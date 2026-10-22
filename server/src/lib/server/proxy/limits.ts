// LIMITS FOR MODEL CALLS: A PER PERSON RATE LIMIT, A MONTHLY TOKEN CAP PER PERSON AND BUCKET, AND A GLOBAL MONTHLY CAP.
// The chat and memory buckets have separate caps, so background memory work can never starve the chat, and the chat can never
// starve the memory jobs. Reaching a cap stops model calls only: expenses, bills and the schedule keep working without the model.

// -- TYPES -- //
import type { Tx } from '../db/client';
// -- DEP-MODULES -- //
import { and, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { modelSpend, modelUsage, type BUCKETS } from '../db/schema';
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

export type Usage = { promptTokens: number; completionTokens: number };

// -- CONSTANTS -- //

export const DEFAULT_LIMITS: Limits = {
	chatTokenCap: 8_000_000,
	memoryTokenCap: 2_000_000,
	globalTokenCap: 12_000_000,
	ratePerMinute: 20
};

// -- FUNCTIONS -- //

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

/** Throws LIMIT when the person or the whole service has used its tokens for the month. Runs inside the person's transaction. */
export async function assertBudget(
	tx: Tx,
	userId: string,
	bucket: Bucket,
	limits: Limits,
	now: Date = new Date()
): Promise<void> {
	const month = monthKey(now);
	const [mine] = await tx
		.select({
			tokens: sql<number>`coalesce(${modelUsage.promptTokens} + ${modelUsage.completionTokens}, 0)`
		})
		.from(modelUsage)
		.where(
			and(eq(modelUsage.userId, userId), eq(modelUsage.bucket, bucket), eq(modelUsage.month, month))
		);
	const cap = bucket === 'chat' ? limits.chatTokenCap : limits.memoryTokenCap;
	if (Number(mine?.tokens ?? 0) >= cap)
		throw new OpsError('LIMIT', 'The monthly model limit for this account has been reached.');
	const [all] = await tx
		.select({ tokens: sql<number>`coalesce(sum(${modelSpend.tokens}), 0)` })
		.from(modelSpend)
		.where(eq(modelSpend.month, month));
	if (Number(all?.tokens ?? 0) >= limits.globalTokenCap)
		throw new OpsError('LIMIT', 'The monthly model limit for the whole service has been reached.');
}

/** Adds one call and its tokens to the person's usage and to the global total. Atomic upserts, safe under concurrency. */
export async function recordUsage(
	tx: Tx,
	userId: string,
	bucket: Bucket,
	usage: Usage,
	now: Date = new Date()
): Promise<void> {
	const month = monthKey(now);
	const prompt = Math.max(0, Math.trunc(usage.promptTokens));
	const completion = Math.max(0, Math.trunc(usage.completionTokens));
	await tx
		.insert(modelUsage)
		.values({ userId, bucket, month, calls: 1, promptTokens: prompt, completionTokens: completion })
		.onConflictDoUpdate({
			target: [modelUsage.userId, modelUsage.bucket, modelUsage.month],
			set: {
				calls: sql`${modelUsage.calls} + 1`,
				promptTokens: sql`${modelUsage.promptTokens} + ${prompt}`,
				completionTokens: sql`${modelUsage.completionTokens} + ${completion}`,
				updatedAt: sql`now()`
			}
		});
	await tx
		.insert(modelSpend)
		.values({ month, bucket, calls: 1, tokens: prompt + completion })
		.onConflictDoUpdate({
			target: [modelSpend.month, modelSpend.bucket],
			set: {
				calls: sql`${modelSpend.calls} + 1`,
				tokens: sql`${modelSpend.tokens} + ${prompt + completion}`
			}
		});
}
