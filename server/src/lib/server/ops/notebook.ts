// NOTEBOOK VERBS: READ, SAVE (THE PERSON), EDIT (THE ASSISTANT), LIST THE CHANGES AND RESTORE ONE (THE PERSON), AND MANAGE MANY NOTEBOOKS.
// A person has one MAIN notebook, a Markdown document that is always in the prompt (the main topics and essentials), and up to 40 EXTRA
// notebooks for other information. Extra notebooks are not in the prompt: the main notebook message carries a live index of them (title,
// one-line summary, size) and the assistant reads one on demand. The assistant lists, reads, creates, edits, renames and deletes extra
// notebooks; a delete hides one for 30 days, so it can be restored. A verb names a notebook by id (the app) or by title (the assistant);
// naming none is the main notebook. Rules that hold for every writer:
// - A change never loses text: the replaced text is kept as a revision (newest 50), with who changed it, so the person can restore it.
// - The person's save names the version it was made from; a stale one is refused, so two phones or the assistant never overwrite each other.
// - The assistant edits by exact text only (add under a heading, replace or remove text that appears once). An edit that matches nothing, or
//   several places, is refused with a message it can act on. A line it writes has account, card and phone numbers taken out first.
// - Every notebook has its own version and its own newest 50 revisions.
// - The first read of a person with no notebook makes a draft from the old memory (persona, about lines, live facts) and queues a one-time
//   tidy by the model. A person with no old memory gets the empty template.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, asc, desc, eq, isNotNull, isNull, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	memoryFact,
	memoryProfile,
	notebook,
	notebookRevision,
	NOTEBOOK_MAX_CHARS,
	NOTEBOOK_MAX_EXTRA,
	NOTEBOOK_SUMMARY_MAX,
	NOTEBOOK_TITLE_MAX,
	NOTEBOOK_TRASH_DAYS
} from '../db/schema';
import {
	notebookCreateInput,
	notebookEditInput,
	notebookListInput,
	notebookRestoreInput,
	notebookSaveInput,
	notebookTargetInput,
	notebookUpdateInput
} from '../db/zod';
import { enqueue } from '../jobs/queue';
import { redactSecrets } from '../memory/pure';
import { addLine, buildDraft, EditError, removeOnce, replaceOnce } from '../notebook/text';
import { OpsError, run, runWrite } from './context';
import { parse, requirePerson } from './shared';

// -- TYPES -- //

export type NotebookActor = 'user' | 'agent' | 'seed';

export type NotebookView = {
	id: string;
	kind: 'main' | 'extra';
	title: string;
	summary: string;
	text: string;
	version: number;
	updatedBy: NotebookActor;
	updatedAt: string;
	chars: number;
	maxChars: number;
};

type NotebookRow = typeof notebook.$inferSelect;

/** How a verb names a notebook: by id, by the title of an extra one, or not at all (the main notebook). */
type Target = { notebookId?: string | undefined; notebook?: string | undefined };

/** One line of the index under the main notebook. */
export type NotebookIndexLine = {
	title: string;
	summary: string;
	chars: number;
	updatedAt: string;
};

// -- CONSTANTS -- //

/** The newest revisions kept for each notebook. */
export const REVISIONS_KEPT = 50;

/** The facts read into the first draft. The draft is cut to fit anyway; this only bounds the read. */
const DRAFT_FACTS = 400;

/** The note the assistant reads after an edit: the prompt holds the notebook as it was when the message began. */
const APPLIES_NEXT = 'The change is saved. It applies from the next message.';

// -- FUNCTIONS -- //

const view = (r: NotebookRow): NotebookView => ({
	id: r.id,
	kind: r.kind,
	title: r.title,
	summary: r.summary,
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
	const [found] = await tx
		.select()
		.from(notebook)
		.where(and(eq(notebook.userId, userId), eq(notebook.kind, 'main')));
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
		.values({ userId, text, version: 1, updatedBy: 'seed', kind: 'main' })
		.onConflictDoNothing()
		.returning();
	if (made) {
		// Only a draft that holds old memory is worth a tidy: the empty template is left alone
		if (facts.length > 0 || profile?.persona?.trim() || profile?.about?.trim())
			await enqueue(tx, { userId, kind: 'notebook.seed', key: 'first' });
		return { row: made, created: true };
	}
	// Another request made it first
	const [row] = await tx
		.select()
		.from(notebook)
		.where(and(eq(notebook.userId, userId), eq(notebook.kind, 'main')));
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

/** Lines of free text with account, card and phone numbers taken out, one line at a time so the shape of the text is kept. */
function redactText(text: string): string {
	return text
		.split('\n')
		.map((l) => (l.trim() ? (redactSecrets(l) ?? '') : ''))
		.join('\n');
}

/** The name a title cannot take: the main notebook answers to "main". */
const RESERVED_TITLE = 'main';

/** A title or a summary on one line with its numbers taken out; null when nothing is left. */
const oneLine = (s: string) => redactSecrets(s.replace(/\s+/g, ' '));

/** The live extra notebooks of the person, to name them in a refusal the assistant can act on. */
async function liveTitles(tx: Tx, userId: string): Promise<string[]> {
	const rows = await tx
		.select({ title: notebook.title })
		.from(notebook)
		.where(and(eq(notebook.userId, userId), eq(notebook.kind, 'extra'), isNull(notebook.deletedAt)))
		.orderBy(asc(sql`lower(${notebook.title})`));
	return rows.map((r) => r.title);
}

/**
 * The notebook a verb is about. No name is the main notebook (made on the first read); an id or a title is an extra one, or the main one
 * ("main"). A deleted notebook is found only when `deleted` says so.
 */
async function resolve(
	tx: Tx,
	userId: string,
	target: Target,
	opts: { deleted?: boolean } = {}
): Promise<NotebookRow> {
	if (target.notebookId && target.notebook)
		throw new OpsError('INVALID', 'Name the notebook by its id or by its title, not both.');
	const title = target.notebook?.trim();
	if (!target.notebookId && (!title || title.toLowerCase() === RESERVED_TITLE))
		return (await ensureNotebook(tx, userId)).row;
	const [hit] = target.notebookId
		? await tx
				.select()
				.from(notebook)
				.where(and(eq(notebook.userId, userId), eq(notebook.id, target.notebookId)))
		: await tx
				.select()
				.from(notebook)
				.where(
					and(
						eq(notebook.userId, userId),
						eq(notebook.kind, 'extra'),
						opts.deleted ? isNotNull(notebook.deletedAt) : isNull(notebook.deletedAt),
						sql`lower(${notebook.title}) = lower(${title ?? ''})`
					)
				)
				.orderBy(desc(notebook.deletedAt))
				.limit(1);
	if (hit && hit.kind === 'main') return hit;
	if (hit && (hit.deletedAt !== null) === Boolean(opts.deleted)) return hit;
	if (target.notebookId) throw new OpsError('NOT_FOUND', 'That notebook is gone or was deleted.');
	const names = opts.deleted ? [] : await liveTitles(tx, userId);
	throw new OpsError(
		'NOT_FOUND',
		opts.deleted
			? 'There is no deleted notebook like that.'
			: `There is no notebook called "${title ?? ''}".${names.length ? ` The notebooks are: ${names.map((n) => `"${n}"`).join(', ')}.` : ' There are no other notebooks yet.'}`
	);
}

/** The notebook text for the prompt, and the person's notebook is made on this first read when there is none. */
export async function loadNotebook(ctx: Ctx): Promise<NotebookView> {
	// No lock: the draft is made with ON CONFLICT DO NOTHING, so two first reads at once make one, and a chat message never waits for a job
	return run(ctx, async (tx, userId) => view((await ensureNotebook(tx, userId)).row));
}

/**
 * What a chat message needs: the main notebook text (made on the first read), the index of the other notebooks, and the private names the
 * person listed, for the masker.
 */
export async function loadNotebookContext(
	ctx: Ctx
): Promise<{ text: string; names: string[]; others: NotebookIndexLine[] }> {
	return run(ctx, async (tx, userId) => {
		const { row } = await ensureNotebook(tx, userId);
		const [p] = await tx
			.select({ people: memoryProfile.people })
			.from(memoryProfile)
			.where(eq(memoryProfile.userId, userId));
		const names = Array.isArray(p?.people)
			? (p.people as unknown[]).filter((x): x is string => typeof x === 'string')
			: [];
		const extras = await tx
			.select({
				title: notebook.title,
				summary: notebook.summary,
				chars: sql<number>`length(${notebook.text})`,
				updatedAt: notebook.updatedAt
			})
			.from(notebook)
			.where(
				and(eq(notebook.userId, userId), eq(notebook.kind, 'extra'), isNull(notebook.deletedAt))
			)
			.orderBy(asc(sql`lower(${notebook.title})`))
			.limit(NOTEBOOK_MAX_EXTRA);
		return {
			text: row.text,
			names,
			others: extras.map((e) => ({
				title: e.title,
				summary: e.summary,
				chars: Number(e.chars),
				updatedAt: e.updatedAt.toISOString()
			}))
		};
	});
}

/** A notebook, for the app and for the assistant: the main one when none is named. */
export async function getNotebook(ctx: Ctx, raw: unknown = {}): Promise<NotebookView> {
	const input = parse(notebookTargetInput, raw);
	return run(ctx, async (tx, userId) => view(await resolve(tx, userId, input)));
}

/** The main notebook first, then the live extra ones by title (or, with `deleted`, the deleted ones that can still be restored). */
export async function listNotebooks(ctx: Ctx, raw: unknown = {}) {
	const input = parse(notebookListInput, raw);
	return run(ctx, async (tx, userId) => {
		if (!input.deleted) await ensureNotebook(tx, userId);
		const rows = await tx
			.select({
				id: notebook.id,
				kind: notebook.kind,
				title: notebook.title,
				summary: notebook.summary,
				chars: sql<number>`length(${notebook.text})`,
				version: notebook.version,
				updatedBy: notebook.updatedBy,
				updatedAt: notebook.updatedAt,
				deletedAt: notebook.deletedAt
			})
			.from(notebook)
			.where(
				and(
					eq(notebook.userId, userId),
					input.deleted ? isNotNull(notebook.deletedAt) : isNull(notebook.deletedAt)
				)
			)
			.orderBy(desc(sql`${notebook.kind} = 'main'`), asc(sql`lower(${notebook.title})`));
		return {
			notebooks: rows.map((r) => ({
				id: r.id,
				kind: r.kind,
				title: r.title,
				summary: r.summary,
				chars: Number(r.chars),
				version: r.version,
				updatedBy: r.updatedBy,
				updatedAt: r.updatedAt.toISOString(),
				deletedAt: r.deletedAt?.toISOString() ?? null
			})),
			maxExtra: NOTEBOOK_MAX_EXTRA
		};
	});
}

/** The person saves the whole text, made from the version they opened. A stale version is refused and nothing is lost. */
export async function saveNotebook(
	ctx: Ctx,
	raw: unknown
): Promise<NotebookView & { changed: boolean }> {
	requirePerson(ctx.actor.kind, 'save the notebook');
	const input = parse(notebookSaveInput, raw);
	return runWrite(ctx, 'notebook.save', input, async (tx, userId) => {
		const row = await resolve(tx, userId, input);
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
): Promise<{ notebook: string; version: number; section: string; changed: boolean; note: string }> {
	const input = parse(notebookEditInput, raw);
	return runWrite(ctx, 'notebook.edit', input, async (tx, userId) => {
		const row = await resolve(tx, userId, input);
		const name = row.kind === 'main' ? 'main' : row.title;
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
				notebook: name,
				version: row.version,
				section: result.section,
				changed: false,
				note: 'It was already there.'
			};
		const next = await applyChange(tx, userId, row, result.text, actorOf(ctx), refOf(ctx));
		return {
			notebook: name,
			version: next.version,
			section: result.section,
			changed: true,
			// The main notebook is in the prompt of the next message; an extra one is read on demand, so its change is there at once
			note: row.kind === 'main' ? APPLIES_NEXT : 'The change is saved.'
		};
	});
}

/** The changes made to a notebook, newest first: who, when, and the start of the text each one replaced. */
export async function listRevisions(ctx: Ctx, raw: unknown = {}) {
	requirePerson(ctx.actor.kind, 'see the changes to the notebook');
	const input = parse(notebookTargetInput, raw);
	return run(ctx, async (tx, userId) => {
		const book = await resolve(tx, userId, input);
		const rows = await tx
			.select()
			.from(notebookRevision)
			.where(and(eq(notebookRevision.userId, userId), eq(notebookRevision.notebookId, book.id)))
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
		const [rev] = await tx
			.select()
			.from(notebookRevision)
			.where(and(eq(notebookRevision.userId, userId), eq(notebookRevision.id, input.revisionId)));
		if (!rev) throw new OpsError('NOT_FOUND', 'That change is not there any more.');
		// The revision belongs to one notebook, which must not be deleted
		const row = await resolve(tx, userId, { notebookId: rev.notebookId });
		if (rev.text === row.text) return view(row);
		return view(await applyChange(tx, userId, row, rev.text, 'user', `restore:${rev.version}`));
	});
}

/** A new extra notebook, for other information than the main topics and essentials. At most 40 live ones, each with its own title. */
export async function createNotebook(ctx: Ctx, raw: unknown): Promise<NotebookView> {
	const input = parse(notebookCreateInput, raw);
	return runWrite(ctx, 'notebook.create', input, async (tx, userId) => {
		// Taking numbers out can make a line longer, so the limits are applied to what is stored, before the title is compared
		const title = oneLine(input.title)?.slice(0, NOTEBOOK_TITLE_MAX).trim();
		if (!title || title.toLowerCase() === RESERVED_TITLE)
			throw new OpsError('INVALID', 'Give the notebook a title other than "main".');
		const summary = input.summary
			? (oneLine(input.summary) ?? '').slice(0, NOTEBOOK_SUMMARY_MAX)
			: '';
		const text = redactText(input.text ?? '');
		if (text.length > NOTEBOOK_MAX_CHARS)
			throw new OpsError(
				'INVALID',
				`The text would be longer than ${NOTEBOOK_MAX_CHARS} characters. Make it shorter.`
			);
		const live = await liveTitles(tx, userId);
		if (live.length >= NOTEBOOK_MAX_EXTRA)
			throw new OpsError(
				'INVALID',
				`There are already ${NOTEBOOK_MAX_EXTRA} notebooks. Delete or reuse one first.`
			);
		if (live.some((t) => t.toLowerCase() === title.toLowerCase()))
			throw new OpsError('CONFLICT', `A notebook called "${title}" already exists. Use it.`);
		// The main notebook exists before any other one, so the index always hangs off it
		await ensureNotebook(tx, userId);
		const [made] = await tx
			.insert(notebook)
			.values({
				userId,
				kind: 'extra',
				title,
				summary,
				text,
				version: 1,
				updatedBy: actorOf(ctx)
			})
			.returning();
		if (!made) throw new OpsError('CONFLICT', 'The notebook could not be made. Try again.');
		return view(made);
	});
}

/** Rename an extra notebook or change its summary. The main notebook has neither. */
export async function updateNotebook(ctx: Ctx, raw: unknown): Promise<NotebookView> {
	const input = parse(notebookUpdateInput, raw);
	return runWrite(ctx, 'notebook.update', input, async (tx, userId) => {
		if (input.newTitle === undefined && input.summary === undefined)
			throw new OpsError('INVALID', 'Give the new title or the new summary.');
		const row = await resolve(tx, userId, input);
		if (row.kind === 'main')
			throw new OpsError('INVALID', 'The main notebook has no title or summary. Edit its text.');
		const patch: Partial<typeof notebook.$inferInsert> = {};
		if (input.newTitle !== undefined) {
			const title = oneLine(input.newTitle)?.slice(0, NOTEBOOK_TITLE_MAX).trim();
			if (!title || title.toLowerCase() === RESERVED_TITLE)
				throw new OpsError('INVALID', 'Give the notebook a title other than "main".');
			const clash = (await liveTitles(tx, userId)).some(
				(t) => t.toLowerCase() === title.toLowerCase() && t !== row.title
			);
			if (clash) throw new OpsError('CONFLICT', `A notebook called "${title}" already exists.`);
			patch.title = title;
		}
		if (input.summary !== undefined)
			patch.summary = (oneLine(input.summary) ?? '').slice(0, NOTEBOOK_SUMMARY_MAX);
		const [next] = await tx
			.update(notebook)
			.set({ ...patch, updatedAt: sql`now()` })
			.where(and(eq(notebook.userId, userId), eq(notebook.id, row.id)))
			.returning();
		if (!next) throw new OpsError('NOT_FOUND', 'The notebook is gone.');
		return view(next);
	});
}

/**
 * Deletes an extra notebook: it is hidden, its text and changes are kept, and it can be restored for 30 days. The answer holds the removed
 * notebook, so it can be put back. The main notebook cannot be deleted.
 */
export async function deleteNotebook(ctx: Ctx, raw: unknown) {
	const input = parse(notebookTargetInput, raw);
	return runWrite(ctx, 'notebook.delete', input, async (tx, userId) => {
		const row = await resolve(tx, userId, input);
		if (row.kind === 'main')
			throw new OpsError(
				'INVALID',
				'The main notebook cannot be deleted. Edit its text instead, or ask the person to wipe the memory.'
			);
		await tx
			.update(notebook)
			.set({ deletedAt: sql`now()`, updatedAt: sql`now()` })
			.where(and(eq(notebook.userId, userId), eq(notebook.id, row.id)));
		return {
			removed: view(row),
			note: `The notebook is deleted. It can be restored for ${NOTEBOOK_TRASH_DAYS} days.`
		};
	});
}

/** Puts a deleted notebook back. If its title is taken meanwhile, it comes back as "title (restored)". */
export async function undeleteNotebook(ctx: Ctx, raw: unknown): Promise<NotebookView> {
	const input = parse(notebookTargetInput, raw);
	if (!input.notebookId && !input.notebook)
		throw new OpsError('INVALID', 'Name the deleted notebook to restore.');
	return runWrite(ctx, 'notebook.undelete', input, async (tx, userId) => {
		const row = await resolve(tx, userId, input, { deleted: true });
		if (row.kind === 'main') throw new OpsError('INVALID', 'The main notebook is not deleted.');
		const live = await liveTitles(tx, userId);
		if (live.length >= NOTEBOOK_MAX_EXTRA)
			throw new OpsError(
				'INVALID',
				`There are already ${NOTEBOOK_MAX_EXTRA} notebooks. Delete or reuse one first.`
			);
		const taken = new Set(live.map((t) => t.toLowerCase()));
		let title = row.title;
		for (let n = 1; taken.has(title.toLowerCase()); n++) {
			const tag = n === 1 ? ' (restored)' : ` (restored ${n})`;
			title = `${row.title.slice(0, NOTEBOOK_TITLE_MAX - tag.length)}${tag}`;
		}
		const [next] = await tx
			.update(notebook)
			.set({ deletedAt: null, title, updatedAt: sql`now()` })
			.where(and(eq(notebook.userId, userId), eq(notebook.id, row.id)))
			.returning();
		if (!next) throw new OpsError('NOT_FOUND', 'The notebook is gone.');
		return view(next);
	});
}
