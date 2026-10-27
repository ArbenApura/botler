// NOTEBOOK VERBS: READ IT, SAVE IT (THE PERSON), EDIT IT (THE ASSISTANT), LIST ITS CHANGES AND RESTORE ONE (THE PERSON).
// Botler's Notebook is one Markdown document per person that is always in the prompt. Rules that hold for every writer:
// - A change never loses text: the replaced text is kept as a revision (newest 50), with who changed it, so the person can restore it.
// - The person's save names the version it was made from; a stale one is refused, so two phones or the assistant never overwrite each other.
// - The assistant edits by exact text only (add under a heading, replace or remove text that appears once). An edit that matches nothing, or
//   several places, is refused with a message it can act on. A line it writes has account, card and phone numbers taken out first.
// - The first read of a person with no notebook makes a draft from the old memory (persona, about lines, live facts) and queues a one-time
//   tidy by the model. A person with no old memory gets the empty template.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, desc, eq, isNull, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	memoryFact,
	memoryProfile,
	notebook,
	notebookRevision,
	NOTEBOOK_MAX_CHARS
} from '../db/schema';
import { notebookEditInput, notebookRestoreInput, notebookSaveInput } from '../db/zod';
import { enqueue } from '../jobs/queue';
import { redactSecrets } from '../memory/pure';
import { addLine, buildDraft, EditError, removeOnce, replaceOnce } from '../notebook/text';
import { OpsError, run, runWrite } from './context';
import { parse, requirePerson } from './shared';

// -- TYPES -- //

export type NotebookActor = 'user' | 'agent' | 'seed';

export type NotebookView = {
	text: string;
	version: number;
	updatedBy: NotebookActor;
	updatedAt: string;
	chars: number;
	maxChars: number;
};

type NotebookRow = typeof notebook.$inferSelect;

// -- CONSTANTS -- //

/** The newest revisions kept for each notebook. */
export const REVISIONS_KEPT = 50;

/** The facts read into the first draft. The draft is cut to fit anyway; this only bounds the read. */
const DRAFT_FACTS = 400;

/** The note the assistant reads after an edit: the prompt holds the notebook as it was when the message began. */
const APPLIES_NEXT = 'The change is saved. It applies from the next message.';

// -- FUNCTIONS -- //

const view = (r: NotebookRow): NotebookView => ({
	text: r.text,
	version: r.version,
	updatedBy: r.updatedBy,
	updatedAt: r.updatedAt.toISOString(),
	chars: r.text.length,
	maxChars: NOTEBOOK_MAX_CHARS
});

/** An edit the person approved on a card is still the assistant's: the changes list says so. */
const actorOf = (ctx: Ctx): NotebookActor =>
	ctx.actor.kind === 'agent' || ctx.onBehalfOf === 'agent' ? 'agent' : 'user';

/** Where a change came from, short and never text: the chat message of an assistant edit, or the request. */
const refOf = (ctx: Ctx) => (ctx.turnId ?? ctx.requestId ?? null)?.slice(0, 80) ?? null;

/** The notebook row of the person, made from the old memory when there is none. Safe to call from two places at once. */
export async function ensureNotebook(
	tx: Tx,
	userId: string
): Promise<{ row: NotebookRow; created: boolean }> {
	const [found] = await tx.select().from(notebook).where(eq(notebook.userId, userId));
	if (found) return { row: found, created: false };
	const [profile] = await tx
		.select({ persona: memoryProfile.persona, about: memoryProfile.about })
		.from(memoryProfile)
		.where(eq(memoryProfile.userId, userId));
	const facts = await tx
		.select({ text: memoryFact.text, kind: memoryFact.kind, source: memoryFact.source })
		.from(memoryFact)
		.where(
			and(
				eq(memoryFact.userId, userId),
				eq(memoryFact.suppressed, false),
				eq(memoryFact.pending, false),
				isNull(memoryFact.validTo)
			)
		)
		.orderBy(desc(memoryFact.importance), desc(memoryFact.createdAt))
		.limit(DRAFT_FACTS);
	const text = buildDraft(
		{ persona: profile?.persona ?? '', about: profile?.about ?? '', facts },
		NOTEBOOK_MAX_CHARS
	);
	const [made] = await tx
		.insert(notebook)
		.values({ userId, text, version: 1, updatedBy: 'seed' })
		.onConflictDoNothing()
		.returning();
	if (made) {
		// Only a draft that holds old memory is worth a tidy: the empty template is left alone
		if (facts.length > 0 || profile?.persona?.trim() || profile?.about?.trim())
			await enqueue(tx, { userId, kind: 'notebook.seed', key: 'first' });
		return { row: made, created: true };
	}
	// Another request made it first
	const [row] = await tx.select().from(notebook).where(eq(notebook.userId, userId));
	if (!row) throw new OpsError('CONFLICT', 'The notebook could not be opened. Try again.');
	return { row, created: false };
}

/**
 * Replaces the text and keeps the old text as a revision, then drops the revisions past the newest 50. Runs inside the caller's
 * transaction, with the person already locked.
 */
export async function applyChange(
	tx: Tx,
	userId: string,
	row: NotebookRow,
	text: string,
	actor: NotebookActor,
	ref: string | null
): Promise<NotebookRow> {
	await tx.insert(notebookRevision).values({
		userId,
		notebookId: row.id,
		version: row.version,
		text: row.text,
		actor,
		ref
	});
	const [next] = await tx
		.update(notebook)
		.set({ text, version: row.version + 1, updatedBy: actor, updatedAt: sql`now()` })
		.where(and(eq(notebook.userId, userId), eq(notebook.id, row.id)))
		.returning();
	if (!next) throw new OpsError('NOT_FOUND', 'The notebook is gone.');
	await tx.execute(sql`
		delete from notebook_revision
		where user_id = ${userId} and notebook_id = ${row.id}
		  and id not in (
			select id from notebook_revision
			where user_id = ${userId} and notebook_id = ${row.id}
			order by version desc limit ${REVISIONS_KEPT})`);
	return next;
}

/** The notebook text for the prompt, and the person's notebook is made on this first read when there is none. */
export async function loadNotebook(ctx: Ctx): Promise<NotebookView> {
	// No lock: the draft is made with ON CONFLICT DO NOTHING, so two first reads at once make one, and a chat message never waits for a job
	return run(ctx, async (tx, userId) => view((await ensureNotebook(tx, userId)).row));
}

/** What a chat message needs: the notebook text (made on the first read) and the private names the person listed, for the masker. */
export async function loadNotebookContext(ctx: Ctx): Promise<{ text: string; names: string[] }> {
	return run(ctx, async (tx, userId) => {
		const { row } = await ensureNotebook(tx, userId);
		const [p] = await tx
			.select({ people: memoryProfile.people })
			.from(memoryProfile)
			.where(eq(memoryProfile.userId, userId));
		const names = Array.isArray(p?.people)
			? (p.people as unknown[]).filter((x): x is string => typeof x === 'string')
			: [];
		return { text: row.text, names };
	});
}

/** The notebook, for the app. */
export async function getNotebook(ctx: Ctx): Promise<NotebookView> {
	return loadNotebook(ctx);
}

/** The person saves the whole text, made from the version they opened. A stale version is refused and nothing is lost. */
export async function saveNotebook(
	ctx: Ctx,
	raw: unknown
): Promise<NotebookView & { changed: boolean }> {
	requirePerson(ctx.actor.kind, 'save the notebook');
	const input = parse(notebookSaveInput, raw);
	return runWrite(ctx, 'notebook.save', input, async (tx, userId) => {
		const { row } = await ensureNotebook(tx, userId);
		if (input.expectVersion !== row.version)
			throw new OpsError(
				'CONFLICT',
				'The notebook changed since you opened it. Open it again to see the new version.'
			);
		if (input.text === row.text) return { ...view(row), changed: false };
		return {
			...view(await applyChange(tx, userId, row, input.text, 'user', refOf(ctx))),
			changed: true
		};
	});
}

/** One edit by exact text, for the assistant (and for the person's approval of a card made from it). */
export async function editNotebook(
	ctx: Ctx,
	raw: unknown
): Promise<{ version: number; section: string; changed: boolean; note: string }> {
	const input = parse(notebookEditInput, raw);
	return runWrite(ctx, 'notebook.edit', input, async (tx, userId) => {
		const { row } = await ensureNotebook(tx, userId);
		let result: { text: string; section: string; changed?: boolean };
		try {
			if (input.op === 'add') {
				if (!input.heading || !input.line)
					throw new OpsError('INVALID', 'To add a line give the heading and the line.');
				// Account, card and phone numbers never go into the notebook
				const line = redactSecrets(input.line);
				if (!line) throw new OpsError('INVALID', 'The line is empty.');
				// The heading is one line and has its numbers taken out too, like the line
				const heading = redactSecrets(input.heading.replace(/\s+/g, ' '));
				if (!heading) throw new OpsError('INVALID', 'The heading is empty.');
				result = addLine(row.text, heading, line, NOTEBOOK_MAX_CHARS);
			} else if (input.op === 'replace') {
				if (!input.find || input.replacement === undefined)
					throw new OpsError('INVALID', 'To replace text give the exact text and its replacement.');
				const replacement = input.replacement ? redactSecrets(input.replacement) : '';
				if (replacement === null) throw new OpsError('INVALID', 'The replacement is empty.');
				result = replaceOnce(row.text, input.find, replacement, NOTEBOOK_MAX_CHARS);
			} else {
				if (!input.find) throw new OpsError('INVALID', 'To remove text give the exact text.');
				result = removeOnce(row.text, input.find);
			}
		} catch (e) {
			// A refused edit reads as a plain message the assistant can act on
			if (e instanceof EditError) throw new OpsError('INVALID', e.message);
			throw e;
		}
		if (result.changed === false || result.text === row.text)
			return {
				version: row.version,
				section: result.section,
				changed: false,
				note: 'It was already there.'
			};
		const next = await applyChange(tx, userId, row, result.text, actorOf(ctx), refOf(ctx));
		return { version: next.version, section: result.section, changed: true, note: APPLIES_NEXT };
	});
}

/** The changes made to the notebook, newest first: who, when, and the start of the text each one replaced. */
export async function listRevisions(ctx: Ctx) {
	requirePerson(ctx.actor.kind, 'see the changes to the notebook');
	return run(ctx, async (tx, userId) => {
		const rows = await tx
			.select()
			.from(notebookRevision)
			.where(eq(notebookRevision.userId, userId))
			.orderBy(desc(notebookRevision.version))
			.limit(REVISIONS_KEPT);
		return {
			revisions: rows.map((r) => ({
				id: r.id,
				version: r.version,
				actor: r.actor,
				at: r.createdAt.toISOString(),
				chars: r.text.length,
				preview: r.text.slice(0, 160)
			}))
		};
	});
}

/** The person puts an earlier text back. The text it replaces is kept as a revision of its own, so a restore can be undone the same way. */
export async function restoreRevision(ctx: Ctx, raw: unknown): Promise<NotebookView> {
	requirePerson(ctx.actor.kind, 'restore the notebook');
	const input = parse(notebookRestoreInput, raw);
	return runWrite(ctx, 'notebook.restore', input, async (tx, userId) => {
		const { row } = await ensureNotebook(tx, userId);
		const [rev] = await tx
			.select()
			.from(notebookRevision)
			.where(and(eq(notebookRevision.userId, userId), eq(notebookRevision.id, input.revisionId)));
		if (!rev) throw new OpsError('NOT_FOUND', 'That change is not there any more.');
		if (rev.text === row.text) return view(row);
		return view(await applyChange(tx, userId, row, rev.text, 'user', `restore:${rev.version}`));
	});
}
