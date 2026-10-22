// RETRIEVAL: WHAT THE ASSISTANT REMEMBERS THAT MATTERS FOR THIS MESSAGE, WITHIN A TOKEN BUDGET.
// Candidates come from two searches (nearest vectors, and keyword matches), are scored together with how recent and how important a
// fact is, and weighed by its fade. The person's own core block (the "about" lines), the latest month and week digests, and the best
// facts are packed in that order until the budget is used. Without an embedder only the keyword half runs. Facts that were deleted,
// ended, or are waiting on a conflict never appear.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Tx } from '../db/client';
import type { Embedder } from './embed';
// -- DEP-MODULES -- //
import { and, desc, eq, inArray, sql } from 'drizzle-orm';
// -- MODULES -- //
import { memoryFact, memoryProfile, memorySummary } from '../db/schema';
import { run } from '../ops/context';
import { estimateTokens, fitBudget, normalizeFact, scoreFact, toneHint } from './pure';

// -- TYPES -- //

export type ScoredFact = {
	id: string;
	text: string;
	kind: string;
	importance: number;
	score: number;
};

export type MemoryContext = {
	/** The persona the person wrote. */
	persona: string;
	/** Tone only, from the mood. */
	tone: string;
	/** The lines for the prompt: core block, digests, facts. Already within the budget. */
	lines: string[];
	factIds: string[];
	tokens: number;
	/** Names to hide from the model. */
	names: string[];
};

type Row = {
	id: string;
	text: string;
	kind: string;
	importance: number;
	valid_from: Date | string;
	fade_weight: number;
	sim?: number | null;
	kw?: number | null;
};

// -- CONSTANTS -- //

export const DEFAULT_BUDGET_TOKENS = 700;
const CANDIDATES = 40;
const MIN_SCORE = 0.22;
const ALWAYS_IMPORTANT = 3;
const DIGEST_CHARS = 600;

// -- FUNCTIONS -- //

/** The rows of a raw query result, which the driver types as unknown. */
export const rowsOf = <T>(result: unknown): T[] => (result as { rows: T[] }).rows;

const live = (userId: string) =>
	sql`user_id = ${userId} and valid_to is null and suppressed = false and pending = false`;

const asVector = (v: readonly number[]) => `[${v.join(',')}]`;

/** Words that appear in nearly every sentence, in English and Filipino, and say nothing about which fact is wanted. */
const STOP_WORDS = new Set(
	[
		'the',
		'and',
		'for',
		'are',
		'was',
		'were',
		'with',
		'that',
		'this',
		'what',
		'when',
		'where',
		'who',
		'whom',
		'how',
		'why',
		'you',
		'your',
		'have',
		'has',
		'had',
		'does',
		'did',
		'about',
		'from',
		'into',
		'any',
		'all',
		'can',
		'will',
		'would',
		'tell',
		'mga',
		'ang',
		'ng',
		'sa',
		'na',
		'ko',
		'ako',
		'mo',
		'ka',
		'ba',
		'ay',
		'ito',
		'yung',
		'yun',
		'kay',
		'para',
		'kung',
		'kapag',
		'kailan',
		'saan',
		'ano',
		'sino',
		'paano',
		'magkano',
		'bakit',
		'may',
		'ang',
		'din',
		'rin',
		'lang',
		'naman',
		'diba',
		'pero',
		'ni',
		'nang',
		'pa',
		'po',
		'ba'
	].filter((w) => w.length >= 3)
);

/** The words of a question that are worth searching for. */
export function keywordsOf(query: string): string[] {
	return [
		...new Set(
			normalizeFact(query)
				.split(' ')
				.filter((w) => w.length >= 3 && !STOP_WORDS.has(w))
		)
	].slice(0, 12);
}

/** The best facts for a question, scored, best first. Reads only. */
export async function searchFacts(
	tx: Tx,
	userId: string,
	opts: { query: string; queryVector?: readonly number[] | null; limit?: number; now?: Date }
): Promise<ScoredFact[]> {
	const now = opts.now ?? new Date();
	const merged = new Map<string, Row & { sim: number | null; kw: number }>();
	const words = keywordsOf(opts.query);
	if (words.length > 0) {
		const q = words.map((w) => `'${w.replaceAll("'", "''")}'`).join(' | ');
		const rows = rowsOf<Row>(
			await tx.execute(sql`
				select id, text, kind, importance, valid_from, fade_weight, ts_rank_cd(search_text, query) as kw
				from memory_fact, to_tsquery('simple', ${q}) query
				where ${live(userId)} and search_text @@ query
				order by kw desc limit ${CANDIDATES}`)
		);
		for (const r of rows) merged.set(r.id, { ...r, sim: null, kw: Number(r.kw ?? 0) });
	}
	if (opts.queryVector) {
		const v = asVector(opts.queryVector);
		const rows = rowsOf<Row>(
			await tx.execute(sql`
				select id, text, kind, importance, valid_from, fade_weight, 1 - (embedding <=> ${v}::vector) as sim
				from memory_fact
				where ${live(userId)} and embedding is not null
				order by embedding <=> ${v}::vector limit ${CANDIDATES}`)
		);
		for (const r of rows) {
			const have = merged.get(r.id);
			if (have) have.sim = Number(r.sim ?? 0);
			else merged.set(r.id, { ...r, sim: Number(r.sim ?? 0), kw: 0 });
		}
	}
	const top = Math.max(0, ...[...merged.values()].map((r) => r.kw));
	const scored = [...merged.values()].map((r) => {
		const parts = {
			similarity: opts.queryVector ? (r.sim ?? 0) : null,
			keyword: top > 0 ? r.kw / top : 0,
			ageDays: (now.getTime() - new Date(r.valid_from).getTime()) / 86_400_000,
			importance: Number(r.importance)
		};
		return {
			id: r.id,
			text: r.text,
			kind: r.kind,
			importance: parts.importance,
			// Whether it matches at all is judged without the fade, so a faded fact that matches strongly can still come back and be
			// restored by use. The fade only moves it down the ranking
			relevant: scoreFact({ ...parts, fadeWeight: 1 }) >= MIN_SCORE,
			score: scoreFact({ ...parts, fadeWeight: Number(r.fade_weight) })
		};
	});
	return scored
		.filter((f) => f.relevant)
		.sort((a, b) => b.score - a.score)
		.slice(0, opts.limit ?? 12)
		.map(({ relevant: _relevant, ...f }) => f);
}

/** Embeds a question, or null when there is no embedder or it fails. Memory still works on keywords alone. */
export async function queryVector(
	embedder: Embedder | null | undefined,
	query: string
): Promise<number[] | null> {
	if (!embedder || !query.trim()) return null;
	try {
		return (await embedder.embed([query], 'query'))[0] ?? null;
	} catch {
		console.error(JSON.stringify({ event: 'embed_unavailable' }));
		return null;
	}
}

/**
 * Everything the prompt needs from memory for one message, within the budget. Marks the facts it returns as used, which
 * brings a faded fact back.
 */
export async function loadMemoryContext(
	ctx: Ctx,
	opts: { query: string; embedder?: Embedder | null; budgetTokens?: number; now?: Date }
): Promise<MemoryContext> {
	const vector = await queryVector(opts.embedder, opts.query);
	return run(ctx, async (tx, userId) => {
		const [profile] = await tx.select().from(memoryProfile).where(eq(memoryProfile.userId, userId));
		const budget = opts.budgetTokens ?? DEFAULT_BUDGET_TOKENS;
		const facts = await searchFacts(tx, userId, {
			query: opts.query,
			queryVector: vector,
			now: opts.now
		});
		// Facts the person marked "never forget" are always considered, a few at most
		const vital = rowsOf<{ id: string; text: string; kind: string; importance: number }>(
			await tx.execute(sql`
				select id, text, kind, importance from memory_fact
				where ${live(userId)} and importance = 5 order by valid_from desc limit ${ALWAYS_IMPORTANT}`)
		);
		const seen = new Set(facts.map((f) => f.id));
		const ordered = [
			...vital.filter((v) => !seen.has(v.id)).map((v) => ({ ...v, score: 1 })),
			...facts
		];

		const digest = async (period: 'month' | 'week') => {
			const [s] = await tx
				.select({ text: memorySummary.text })
				.from(memorySummary)
				.where(and(eq(memorySummary.userId, userId), eq(memorySummary.period, period)))
				.orderBy(desc(memorySummary.periodStart))
				.limit(1);
			return s
				? `${period === 'month' ? 'This month so far' : 'Last week'}: ${s.text.slice(0, DIGEST_CHARS)}`
				: null;
		};
		const core = profile?.about.trim() ? `About the person: ${profile.about.trim()}` : null;
		const candidates = [
			...(core ? [core] : []),
			...[await digest('month'), await digest('week')].filter((x): x is string => x !== null),
			...ordered.map((f) => `- ${f.text}`)
		];
		const lines = fitBudget(candidates, budget);
		const used = ordered.filter((f) => lines.includes(`- ${f.text}`));
		if (used.length > 0)
			await tx
				.update(memoryFact)
				.set({
					lastUsedAt: sql`now()`,
					fadeWeight: sql`least(1, ${memoryFact.fadeWeight} * 2)`
				})
				.where(
					and(
						eq(memoryFact.userId, userId),
						inArray(
							memoryFact.id,
							used.map((f) => f.id)
						)
					)
				);
		const people = Array.isArray(profile?.people)
			? (profile.people as unknown[]).filter((p): p is string => typeof p === 'string')
			: [];
		return {
			persona: profile?.persona.trim() ?? '',
			tone: toneHint(profile?.mood ?? 0),
			lines,
			factIds: used.map((f) => f.id),
			tokens: lines.reduce((n, l) => n + estimateTokens(l) + 1, 0),
			names: people
		};
	});
}
