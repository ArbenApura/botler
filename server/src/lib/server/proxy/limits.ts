// LIMITS FOR MODEL CALLS: A PER PERSON RATE LIMIT, A MONTHLY TOKEN CAP PER PERSON AND BUCKET, AND A GLOBAL MONTHLY CAP.
// The chat and memory buckets have separate caps, so background memory work can never starve the chat, and the chat can never
// starve the memory jobs. Reaching a cap stops model calls only: expenses, bills and the schedule keep working without the model.

// -- TYPES -- //
import type { SelectableProvider } from '../../providers';
import type { Tx } from '../db/client';
// -- DEP-MODULES -- //
import { and, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { modelSpend, modelUsage, type BUCKETS, type PROVIDERS } from '../db/schema';
import { OpsError } from '../ops/context';

// -- TYPES -- //

export type Bucket = (typeof BUCKETS)[number];

export type Limits = {
	/** Tokens one person may use per month in the chat bucket. */
	chatTokenCap: number;
	/** Tokens one person may use per month in the memory bucket. */
	memoryTokenCap: number;
	/** Tokens everyone together may use per month, over both buckets. */
	globalTokenCap: number;
	/** Model calls one person may start per minute. */
	ratePerMinute: number;
};

export type Provider = (typeof PROVIDERS)[number];

export type RateLimiter = { take(key: string): boolean };

/**
 * What one call used. promptTokens is the TOTAL input (uncached + cache read + cache write), so every reader of it keeps its meaning.
 * The cache fields default to 0 for a host or a reply that reports none.
 */
export type Usage = {
	promptTokens: number;
	completionTokens: number;
	cacheReadTokens?: number;
	cacheWriteTokens?: number;
	/** The part of cacheWriteTokens written with the 1 hour lifetime, which the host bills at twice the input price. */
	cacheWrite1hTokens?: number;
	/** True when the host reported no usage and promptTokens is our own estimate: the context meter never shows an estimate. */
	estimated?: true;
};

/** Why a call was refused, with the numbers, for the log. Counts only. */
export type LimitDetail = { reason: 'person_cap' | 'global_cap'; used: number; cap: number };

/** A LIMIT error that carries why it was thrown. */
export class BudgetError extends OpsError {
	constructor(
		message: string,
		readonly detail: LimitDetail
	) {
		super('LIMIT', message);
	}
}

// -- TYPES -- //

export type CacheWeights = { read: number; write: number; write1h?: number };

// -- CONSTANTS -- //

/**
 * What a cached token counts for against the cap, in hundredths of an uncached token. A cache read is much cheaper than a fresh token; a
 * host may charge for a cache write (write, and write1h for a longer one). DeepSeek bills a hit at a fraction and a miss at the full price (it has no write fee).
 */
export const CACHE_WEIGHTS: Record<SelectableProvider, CacheWeights> = {
	deepseek: { read: 2, write: 100 }
};

export const DEFAULT_LIMITS: Limits = {
	chatTokenCap: 8_000_000,
	memoryTokenCap: 2_000_000,
	globalTokenCap: 12_000_000,
	ratePerMinute: 20
};

// -- FUNCTIONS -- //

/**
 * The tokens one call counts against the cap: uncached input + output + the weighted cache read and write, rounded up. Output counts 1 for 1.
 * A provider with no weights (unknown) counts everything in full, as before caching existed.
 */
export function chargedTokens(
	usage: Usage,
	provider: Provider,
	weights: Record<SelectableProvider, CacheWeights> = CACHE_WEIGHTS
): number {
	const read = Math.max(0, Math.trunc(usage.cacheReadTokens ?? 0));
	const write = Math.max(0, Math.trunc(usage.cacheWriteTokens ?? 0));
	const prompt = Math.max(0, Math.trunc(usage.promptTokens));
	const completion = Math.max(0, Math.trunc(usage.completionTokens));
	if (provider === 'unknown') return prompt + completion;
	const w = weights[provider];
	const uncached = Math.max(0, prompt - read - write);
	const long = Math.min(write, Math.max(0, Math.trunc(usage.cacheWrite1hTokens ?? 0)));
	const writeCost = (write - long) * w.write + long * (w.write1h ?? w.write);
	return uncached + completion + Math.ceil((read * w.read + writeCost) / 100);
}

const monthFormat = new Intl.DateTimeFormat('en-CA', {
	timeZone: 'Asia/Manila',
	year: 'numeric',
	month: '2-digit'
});

/** The Asia/Manila month of a moment, YYYY-MM. Caps reset on the first of the month in Manila. */
export function monthKey(now: Date = new Date()): string {
	const parts = monthFormat.formatToParts(now);
	const y = parts.find((p) => p.type === 'year')?.value;
	const m = parts.find((p) => p.type === 'month')?.value;
	return `${y}-${m}`;
}

/** A sliding window counter per key, in memory. One server process, so one counter; a restart only forgets the last minute. */
export function createRateLimiter(max: number, windowMs = 60_000, clock: () => number = Date.now) {
	const hits = new Map<string, number[]>();
	return {
		/** True when the call may go on; false when the key already made `max` calls in the window. */
		take(key: string): boolean {
			const now = clock();
			const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
			if (recent.length >= max) {
				hits.set(key, recent);
				return false;
			}
			recent.push(now);
			hits.set(key, recent);
			// Keys that went quiet are dropped now and then, so the map cannot grow without bound
			if (hits.size > 1000)
				for (const [k, v] of hits) if (v.every((t) => now - t >= windowMs)) hits.delete(k);
			return true;
		}
	};
}

/** The limits the server runs with, set once at start by the model client (see configureLimits). Until then the defaults. */
let configured: Limits = DEFAULT_LIMITS;

/** Called once at start with the limits built from the environment, so the ops layer reads the same caps the model calls are held to. */
export function configureLimits(limits: Limits): void {
	configured = limits;
}

/** The limits the model calls are held to. */
export function configuredLimits(): Limits {
	return configured;
}

/** Charged tokens one person used this month in a bucket, over every provider, so switching provider cannot reset the cap. */
export async function monthlyUsed(
	tx: Tx,
	userId: string,
	bucket: Bucket,
	now: Date = new Date()
): Promise<number> {
	const [mine] = await tx
		.select({ tokens: sql<number>`coalesce(sum(${modelUsage.chargedTokens}), 0)` })
		.from(modelUsage)
		.where(
			and(
				eq(modelUsage.userId, userId),
				eq(modelUsage.bucket, bucket),
				eq(modelUsage.month, monthKey(now))
			)
		);
	return Number(mine?.tokens ?? 0);
}

/** Throws LIMIT when the person or the whole service has used its tokens for the month. Runs inside the person's transaction. */
export async function assertBudget(
	tx: Tx,
	userId: string,
	bucket: Bucket,
	limits: Limits,
	now: Date = new Date()
): Promise<void> {
	const month = monthKey(now);
	const cap = bucket === 'chat' ? limits.chatTokenCap : limits.memoryTokenCap;
	const used = await monthlyUsed(tx, userId, bucket, now);
	if (used >= cap)
		throw new BudgetError('The monthly model limit for this account has been reached.', {
			reason: 'person_cap',
			used,
			cap
		});
	const [all] = await tx
		.select({ tokens: sql<number>`coalesce(sum(${modelSpend.chargedTokens}), 0)` })
		.from(modelSpend)
		.where(eq(modelSpend.month, month));
	const everyone = Number(all?.tokens ?? 0);
	if (everyone >= limits.globalTokenCap)
		throw new BudgetError('The monthly model limit for the whole service has been reached.', {
			reason: 'global_cap',
			used: everyone,
			cap: limits.globalTokenCap
		});
}

/** Adds one call and its tokens to the person's usage and to the global total. Atomic upserts, safe under concurrency. */
export async function recordUsage(
	tx: Tx,
	userId: string,
	bucket: Bucket,
	usage: Usage,
	provider: Provider = 'unknown',
	now: Date = new Date()
): Promise<void> {
	const month = monthKey(now);
	const prompt = Math.max(0, Math.trunc(usage.promptTokens));
	const completion = Math.max(0, Math.trunc(usage.completionTokens));
	const read = Math.max(0, Math.trunc(usage.cacheReadTokens ?? 0));
	const write = Math.max(0, Math.trunc(usage.cacheWriteTokens ?? 0));
	const charged = chargedTokens(usage, provider);
	await tx
		.insert(modelUsage)
		.values({
			userId,
			bucket,
			month,
			provider,
			calls: 1,
			promptTokens: prompt,
			completionTokens: completion,
			cacheReadTokens: read,
			cacheWriteTokens: write,
			chargedTokens: charged
		})
		.onConflictDoUpdate({
			target: [modelUsage.userId, modelUsage.bucket, modelUsage.month, modelUsage.provider],
			set: {
				calls: sql`${modelUsage.calls} + 1`,
				promptTokens: sql`${modelUsage.promptTokens} + ${prompt}`,
				completionTokens: sql`${modelUsage.completionTokens} + ${completion}`,
				cacheReadTokens: sql`${modelUsage.cacheReadTokens} + ${read}`,
				cacheWriteTokens: sql`${modelUsage.cacheWriteTokens} + ${write}`,
				chargedTokens: sql`${modelUsage.chargedTokens} + ${charged}`,
				updatedAt: sql`now()`
			}
		});
	await tx
		.insert(modelSpend)
		.values({
			month,
			bucket,
			provider,
			calls: 1,
			tokens: prompt + completion,
			chargedTokens: charged
		})
		.onConflictDoUpdate({
			target: [modelSpend.month, modelSpend.bucket, modelSpend.provider],
			set: {
				calls: sql`${modelSpend.calls} + 1`,
				tokens: sql`${modelSpend.tokens} + ${prompt + completion}`,
				chargedTokens: sql`${modelSpend.chargedTokens} + ${charged}`
			}
		});
}
