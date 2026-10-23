// MEMORY VERBS: REMEMBER, EDIT, FORGET AND LIST FACTS, SEARCH THEM, THE PERSONA AND PROFILE, AND EXPORT OR WIPE EVERYTHING.
// Rules that hold for every writer (the person, the assistant, the extractor job):
// - A fact is never overwritten. A changed fact ends the old row (valid_to) and adds a new one; the old one stays as history.
// - What the person wrote or edited (source "user") is never ended by the extractor. If the extractor disagrees, the new fact waits
//   as a conflict and the person chooses.
// - A deleted fact leaves a tombstone: its hash, so it is not learned again, and no text. Older versions of it go with it, and any digest
//   that cited it is removed.
// - Account, card and phone numbers are taken out of a fact before it is stored.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Plain } from './shared';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, desc, eq, inArray, isNull, like, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	account,
	allocationRule,
	balanceSnapshot,
	bill,
	billPayment,
	chat,
	chatTurn,
	goal,
	incomeSchedule,
	job,
	ledgerTxn,
	memoryFact,
	memoryProfile,
	memorySummary,
	splitPlan
} from '../db/schema';
import {
	memoryEditInput,
	memoryFactIdInput,
	memoryListInput,
	memoryRememberInput,
	memoryResolveInput,
	memorySearchInput,
	profileSetInput,
	wipeInput
} from '../db/zod';
import { activeEmbedder } from '../memory/embed';
import { hashFact, normalizeFact, redactSecrets } from '../memory/pure';
import { queryVector, searchFacts } from '../memory/retrieve';
import { OpsError, run, runWrite } from './context';
import { enqueue } from '../jobs/queue';
import { mapped, parse, plain, requirePerson } from './shared';

// -- TYPES -- //

type FactRow = typeof memoryFact.$inferSelect;
type FactKind = FactRow['kind'];

/** A fact as the app sees it: no vectors, no search column. */
export type FactView = Plain<Omit<FactRow, 'embedding' | 'searchText'>>;

export type FactInput = {
	text: string;
	subject?: string | null;
	kind?: FactKind;
	importance?: number;
	source: FactRow['source'];
	confidence?: number;
	turnId?: string | null;
	/** The fact this one replaces, when the writer knows it. */
	replaces?: string | null;
};

export type WriteResult =
	| { status: 'created'; id: string; supersededId?: string }
	| { status: 'conflict'; id: string; againstId: string }
	| { status: 'duplicate' | 'tombstoned' | 'empty' };

// -- CONSTANTS -- //

const MAX_TEXT = 400;
/** Confidence within this many points counts as "similar": the person is asked. */
const SIMILAR_CONFIDENCE = 15;
const CONFIDENT_CHANGE = 60;

// -- FUNCTIONS -- //

const view = (r: FactRow): FactView => {
	const { embedding: _embedding, searchText: _searchText, ...rest } = r;
	return plain(rest);
};

const minuteKey = () => new Date().toISOString().slice(0, 16);

/** Asks for the vectors of new facts to be made, at most once a minute. */
export const queueEmbedding = (tx: Tx, userId: string) =>
	enqueue(tx, { userId, kind: 'memory.embed', key: minuteKey() });

/**
 * Writes a fact under the rules above. Used by the person's verbs and by the extractor. Runs inside the caller's transaction.
 */
export async function upsertFact(tx: Tx, userId: string, input: FactInput): Promise<WriteResult> {
	const clean = redactSecrets(input.text);
	const text = clean?.slice(0, MAX_TEXT).trim();
	if (!text) return { status: 'empty' };
	const textHash = hashFact(text);
	const person = input.source === 'user';

	const same = await tx
		.select({ id: memoryFact.id, suppressed: memoryFact.suppressed, validTo: memoryFact.validTo })
		.from(memoryFact)
		.where(and(eq(memoryFact.userId, userId), eq(memoryFact.textHash, textHash)));
	const tombstones = same.filter((s) => s.suppressed);
	if (tombstones.length > 0) {
		// The extractor must not bring back what the person deleted. The person may choose to say it again
		if (!person) return { status: 'tombstoned' };
		await tx.delete(memoryFact).where(
			and(
				eq(memoryFact.userId, userId),
				inArray(
					memoryFact.id,
					tombstones.map((t) => t.id)
				)
			)
		);
	}
	if (same.some((s) => !s.suppressed && s.validTo === null)) return { status: 'duplicate' };

	const subject = input.subject ? normalizeFact(input.subject).slice(0, 60) || null : null;
	const confidence = input.confidence ?? (person ? 100 : 80);
	const active = and(
		eq(memoryFact.userId, userId),
		isNull(memoryFact.validTo),
		eq(memoryFact.suppressed, false),
		eq(memoryFact.pending, false)
	);
	let target: FactRow | undefined;
	if (input.replaces) {
		[target] = await tx
			.select()
			.from(memoryFact)
			.where(and(active, eq(memoryFact.id, input.replaces)));
	} else if (subject) {
		[target] = await tx
			.select()
			.from(memoryFact)
			.where(and(active, eq(memoryFact.subject, subject)))
			.orderBy(desc(memoryFact.validFrom))
			.limit(1);
	}

	let mode: 'plain' | 'supersede' | 'conflict' = 'plain';
	if (target) {
		if (person) mode = 'supersede';
		else if (target.source === 'user') mode = 'conflict';
		else if (input.replaces) mode = confidence >= CONFIDENT_CHANGE ? 'supersede' : 'conflict';
		else mode = confidence - target.confidence > SIMILAR_CONFIDENCE ? 'supersede' : 'conflict';
	}

	const [row] = await tx
		.insert(memoryFact)
		.values({
			userId,
			text,
			textHash,
			subject,
			kind: input.kind ?? target?.kind ?? 'fact',
			importance: input.importance ?? target?.importance ?? 3,
			source: input.source,
			confidence,
			turnId: input.turnId ?? null,
			pending: mode === 'conflict'
		})
		.returning({ id: memoryFact.id });
	if (!row) throw new OpsError('CONFLICT', 'The memory could not be saved.');
	if (target && mode === 'supersede')
		await tx
			.update(memoryFact)
			.set({ validTo: sql`now()`, supersededBy: row.id, updatedAt: sql`now()` })
			.where(and(eq(memoryFact.userId, userId), eq(memoryFact.id, target.id)));
	await queueEmbedding(tx, userId);
	if (target && mode === 'conflict')
		return { status: 'conflict', id: row.id, againstId: target.id };
	return {
		status: 'created',
		id: row.id,
		...(target && mode === 'supersede' ? { supersededId: target.id } : {})
	};
}

/** Tombstones a fact and every older version of it, and removes the digests that cited any of them. Returns how many facts. */
export async function tombstone(tx: Tx, userId: string, factId: string): Promise<number> {
	const ids = new Set([factId]);
	for (;;) {
		const older = await tx
			.select({ id: memoryFact.id })
			.from(memoryFact)
			.where(and(eq(memoryFact.userId, userId), inArray(memoryFact.supersededBy, [...ids])));
		const fresh = older.map((o) => o.id).filter((id) => !ids.has(id));
		if (fresh.length === 0) break;
		fresh.forEach((id) => ids.add(id));
	}
	const list = [...ids];
	await tx
		.update(memoryFact)
		.set({
			suppressed: true,
			pending: false,
			text: '[deleted]',
			subject: null,
			// The vector is kept, with no words: the extractor compares new facts to it, so the same thing said in other
			// words is still not learned again. A wipe removes it
			validTo: sql`coalesce(${memoryFact.validTo}, now())`,
			updatedAt: sql`now()`
		})
		.where(and(eq(memoryFact.userId, userId), inArray(memoryFact.id, list)));
	const cited = sql.join(
		list.map((id) => sql`${id}`),
		sql`, `
	);
	await tx.execute(sql`
		delete from memory_summary
		where user_id = ${userId}
		  and exists (select 1 from jsonb_array_elements_text(fact_ids) e where e in (${cited}))`);
	return list.length;
}

// -- VERBS -- //

/** The person (or the assistant, on their word) states a fact. It outranks anything the extractor learned on the same subject. */
export async function rememberFact(ctx: Ctx, raw: unknown) {
	const input = parse(memoryRememberInput, raw);
	return mapped(() =>
		runWrite(ctx, 'memory.remember', input, async (tx, userId) => {
			const r = await upsertFact(tx, userId, { ...input, source: 'user', confidence: 100 });
			if (r.status === 'empty')
				throw new OpsError('INVALID', 'There is nothing to remember in that.');
			return r;
		})
	);
}

/** Changes a fact's words. The old wording is kept as history; the new one is the person's own, so it is protected. */
export async function editFact(ctx: Ctx, raw: unknown) {
	const input = parse(memoryEditInput, raw);
	return mapped(() =>
		runWrite(ctx, 'memory.edit', input, async (tx, userId) => {
			const [old] = await tx
				.select()
				.from(memoryFact)
				.where(
					and(
						eq(memoryFact.userId, userId),
						eq(memoryFact.id, input.factId),
						isNull(memoryFact.validTo),
						eq(memoryFact.suppressed, false)
					)
				);
			if (!old)
				throw new OpsError('NOT_FOUND', 'That memory does not exist, or it was already replaced.');
			const r = await upsertFact(tx, userId, {
				text: input.text,
				subject: old.subject,
				kind: old.kind,
				importance: old.importance,
				source: 'user',
				confidence: 100,
				replaces: old.id
			});
			if (r.status === 'empty')
				throw new OpsError('INVALID', 'There is nothing to remember in that.');
			return r;
		})
	);
}

/** Deletes a fact for good: it is not shown, not used, and not learned again. */
export async function forgetFact(ctx: Ctx, raw: unknown) {
	const input = parse(memoryFactIdInput, raw);
	return mapped(() =>
		runWrite(ctx, 'memory.forget', input, async (tx, userId) => {
			const [row] = await tx
				.select({ id: memoryFact.id, suppressed: memoryFact.suppressed })
				.from(memoryFact)
				.where(and(eq(memoryFact.userId, userId), eq(memoryFact.id, input.factId)));
			if (!row || row.suppressed) throw new OpsError('NOT_FOUND', 'That memory does not exist.');
			return { forgotten: await tombstone(tx, userId, input.factId) };
		})
	);
}

/** Settles two facts that disagree: keep the newer one (the older ends) or the older one (the newer is declined and not learned again). */
export async function resolveConflict(ctx: Ctx, raw: unknown) {
	const input = parse(memoryResolveInput, raw);
	return mapped(() =>
		runWrite(ctx, 'memory.resolve', input, async (tx, userId) => {
			const [p] = await tx
				.select()
				.from(memoryFact)
				.where(
					and(
						eq(memoryFact.userId, userId),
						eq(memoryFact.id, input.factId),
						eq(memoryFact.pending, true),
						eq(memoryFact.suppressed, false)
					)
				);
			if (!p) throw new OpsError('NOT_FOUND', 'There is no waiting question about that memory.');
			if (input.keep === 'old') {
				await tombstone(tx, userId, p.id);
				return { kept: 'old' as const };
			}
			if (p.subject)
				await tx
					.update(memoryFact)
					.set({ validTo: sql`now()`, supersededBy: p.id, updatedAt: sql`now()` })
					.where(
						and(
							eq(memoryFact.userId, userId),
							eq(memoryFact.subject, p.subject),
							isNull(memoryFact.validTo),
							eq(memoryFact.pending, false),
							eq(memoryFact.suppressed, false)
						)
					);
			// The person chose it, so it now counts as theirs and the extractor cannot end it
			await tx
				.update(memoryFact)
				.set({ pending: false, source: 'user', confidence: 100, updatedAt: sql`now()` })
				.where(and(eq(memoryFact.userId, userId), eq(memoryFact.id, p.id)));
			return { kept: 'new' as const };
		})
	);
}

/** The person's memories, newest first. Deleted ones never appear. */
export async function listFacts(ctx: Ctx, raw: unknown = {}) {
	const input = parse(memoryListInput, raw);
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(memoryFact)
			.where(
				and(
					eq(memoryFact.userId, userId),
					eq(memoryFact.suppressed, false),
					input.history ? undefined : isNull(memoryFact.validTo),
					input.pending
						? eq(memoryFact.pending, true)
						: input.history
							? undefined
							: eq(memoryFact.pending, false)
				)
			)
			.orderBy(desc(memoryFact.validFrom))
			.limit(input.limit ?? 100)
	);
	return rows.map(view);
}

/** Memories that match a question, best first. Reads only: nothing is marked as used. */
export async function searchMemory(ctx: Ctx, raw: unknown) {
	const input = parse(memorySearchInput, raw);
	const vector = await queryVector(activeEmbedder(), input.query);
	return run(ctx, (tx, userId) =>
		searchFacts(tx, userId, { query: input.query, queryVector: vector, limit: input.limit ?? 10 })
	);
}

// -- PERSONA AND PROFILE -- //

export async function getProfile(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const [p] = await tx.select().from(memoryProfile).where(eq(memoryProfile.userId, userId));
		return plain({
			persona: p?.persona ?? '',
			about: p?.about ?? '',
			people: Array.isArray(p?.people) ? p.people : [],
			mood: p?.mood ?? 0,
			familiarity: p?.familiarity ?? 0
		});
	});
}

/** Sets how the assistant talks, a few lines about the person, and the names to keep private. Left-out fields stay as they are. */
export async function setProfile(ctx: Ctx, raw: unknown) {
	const input = parse(profileSetInput, raw);
	return mapped(() =>
		runWrite(ctx, 'profile.set', input, async (tx, userId) => {
			const people = input.people ? [...new Set(input.people)] : undefined;
			await tx
				.insert(memoryProfile)
				.values({
					userId,
					persona: input.persona ?? '',
					about: input.about ?? '',
					people: people ?? []
				})
				.onConflictDoUpdate({
					target: memoryProfile.userId,
					set: {
						...(input.persona !== undefined ? { persona: input.persona } : {}),
						...(input.about !== undefined ? { about: input.about } : {}),
						...(people ? { people } : {}),
						updatedAt: sql`now()`
					}
				});
			return { saved: true };
		})
	);
}

// -- EXPORT AND WIPE -- //

/** Everything about the person: memory and finance, as JSON. Never any secret. Only the person can ask. */
export async function exportAll(ctx: Ctx) {
	requirePerson(ctx.actor.kind, 'export your data');
	return run(ctx, async (tx, userId) => {
		const mine = <T extends { userId: unknown }>(t: T) => eq(t.userId as never, userId);
		const profile = await tx.select().from(memoryProfile).where(mine(memoryProfile));
		const facts = await tx
			.select()
			.from(memoryFact)
			.where(and(mine(memoryFact), eq(memoryFact.suppressed, false)));
		const out = {
			exportedAt: new Date().toISOString(),
			profile: profile.map((p) => ({
				persona: p.persona,
				about: p.about,
				people: p.people,
				mood: p.mood,
				familiarity: p.familiarity
			})),
			memory: {
				facts: facts.map(view),
				summaries: await tx.select().from(memorySummary).where(mine(memorySummary)),
				conversations: await tx
					.select({
						clientMessageId: chatTurn.clientMessageId,
						userText: chatTurn.userText,
						reply: chatTurn.reply,
						createdAt: chatTurn.createdAt
					})
					.from(chatTurn)
					// A copy made by a branch is the same conversation again: it is exported once, in the original
					.where(and(mine(chatTurn), isNull(chatTurn.copiedFromTurnId)))
					.orderBy(chatTurn.createdAt)
			},
			finance: {
				accounts: await tx.select().from(account).where(mine(account)),
				incomeSchedules: await tx.select().from(incomeSchedule).where(mine(incomeSchedule)),
				bills: await tx.select().from(bill).where(mine(bill)),
				billPayments: await tx.select().from(billPayment).where(mine(billPayment)),
				goals: await tx.select().from(goal).where(mine(goal)),
				rules: await tx.select().from(allocationRule).where(mine(allocationRule)),
				transactions: await tx
					.select()
					.from(ledgerTxn)
					.where(mine(ledgerTxn))
					.orderBy(ledgerTxn.occurredAt),
				balanceSnapshots: await tx.select().from(balanceSnapshot).where(mine(balanceSnapshot)),
				splits: await tx.select().from(splitPlan).where(mine(splitPlan))
			}
		};
		return plain(out);
	});
}

/**
 * Wipes the assistant's memory of the person: facts (with their vectors and tombstones), digests and the conversation transcripts,
 * and resets the mood. Queued memory jobs are dropped so nothing is rebuilt. Their settings (persona, about, names) and all finance
 * data stay. Only the person can do this.
 */
export async function wipeMemory(ctx: Ctx, raw: unknown) {
	requirePerson(ctx.actor.kind, 'wipe the memory');
	const input = parse(wipeInput, raw);
	return mapped(() =>
		runWrite(ctx, 'memory.wipe', input, async (tx, userId) => {
			const facts = await tx
				.delete(memoryFact)
				.where(eq(memoryFact.userId, userId))
				.returning({ id: memoryFact.id });
			const summaries = await tx
				.delete(memorySummary)
				.where(eq(memorySummary.userId, userId))
				.returning({ id: memorySummary.id });
			const turns = await tx
				.delete(chatTurn)
				.where(eq(chatTurn.userId, userId))
				.returning({ id: chatTurn.id });
			// The conversations (their names can be message text) go with the messages
			await tx.delete(chat).where(eq(chat.userId, userId));
			await tx
				.update(memoryProfile)
				.set({ mood: 0, familiarity: 0, updatedAt: sql`now()` })
				.where(eq(memoryProfile.userId, userId));
			await tx
				.delete(job)
				.where(and(eq(job.userId, userId), like(job.kind, 'memory.%'), eq(job.status, 'queued')));
			return { facts: facts.length, summaries: summaries.length, conversations: turns.length };
		})
	);
}
