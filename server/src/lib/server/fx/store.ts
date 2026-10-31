// THE STORED RATES AND THE REFRESH: ONE ATOMIC CLAIM, THE FETCH WITH NO TRANSACTION OPEN, THEN ONE SHORT BATCHED WRITE
// Rates are the same for everyone, so a refresh needs no person. The claim stamps the attempt before anything is fetched: only one refresh
// runs per ten minutes across every process, and a failing source is not tried again on every read. A failed or odd answer never removes a
// stored rate; the person sees "rates as of" the date of the last good one.

// -- TYPES -- //
import type { DbHandle, Tx } from '../db/client';
import type { Rates } from '../../finance/fx';
// -- DEP-MODULES -- //
import { eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { movedTooFar } from '../../finance/fx';
import { fxRate, fxRefresh } from '../db/schema';
import { fxConfig } from './config';
import { FxFetchError, fetchRates } from './source';

// -- TYPES -- //

/** What is known about the stored rates, for the app and for the totals. */
export type RatesStatus = {
	/** Units of each currency per US dollar, as decimal text. */
	rates: Rates;
	/** When the newest stored rate was fetched, or null when there are none. */
	asOf: string | null;
	/** When the oldest stored rate was fetched. Differs from asOf when a rate was held back by the sanity check. */
	oldestAt: string | null;
	/** True when there are no rates or they are older than 36 hours. */
	stale: boolean;
	source: string | null;
	attemptedAt: string | null;
	succeededAt: string | null;
	/** A short reason code of the last failure, or null when the last try worked. */
	lastError: string | null;
};

export type RefreshOutcome =
	| { status: 'refreshed'; count: number; held: string[] }
	| { status: 'skipped'; reason: 'recent' | 'not_configured' }
	| { status: 'failed'; reason: string };

// -- CONSTANTS -- //

/** A refresh is not started again within this time, whoever asks. */
export const MIN_REFRESH_INTERVAL_MS = 10 * 60_000;
/** A rate that keeps jumping is held back for at most this long, then the new value is taken. */
const HOLD_BACK_MAX_MS = 7 * 24 * 3_600_000;
/** Rates older than this are stale, and reading a total starts a refresh in the background. A daily feed that is a little late is not yet stale. */
export const STALE_AFTER_MS = 36 * 3_600_000;

// -- FUNCTIONS -- //

/** The stored rates and how the last refresh went. Reads only; works inside any transaction. */
export async function loadRates(
	tx: Tx | DbHandle['db'],
	now: Date = new Date()
): Promise<RatesStatus> {
	const rows = await tx.select().from(fxRate);
	const [state] = await tx.select().from(fxRefresh).where(eq(fxRefresh.id, 'main'));
	const rates: Record<string, string> = {};
	let newest: Date | null = null;
	let oldest: Date | null = null;
	let source: string | null = null;
	for (const r of rows) {
		rates[r.code] = r.rate;
		if (!newest || r.fetchedAt > newest) {
			newest = r.fetchedAt;
			source = r.source;
		}
		if (!oldest || r.fetchedAt < oldest) oldest = r.fetchedAt;
	}
	return {
		rates,
		asOf: newest?.toISOString() ?? null,
		oldestAt: oldest?.toISOString() ?? null,
		stale: !newest || now.getTime() - newest.getTime() > STALE_AFTER_MS,
		source,
		attemptedAt: state?.attemptedAt?.toISOString() ?? null,
		succeededAt: state?.succeededAt?.toISOString() ?? null,
		lastError: state?.lastError ?? null
	};
}

/** Takes the turn to refresh, or says it is not yet time. One statement, so two callers can never both take it. */
async function claimRefresh(handle: DbHandle, now: Date, force: boolean): Promise<boolean> {
	const before = new Date(now.getTime() - MIN_REFRESH_INTERVAL_MS);
	const res = (await handle.db.execute(
		force
			? sql`update fx_refresh set attempted_at = ${now} where id = 'main' returning id`
			: sql`update fx_refresh set attempted_at = ${now} where id = 'main' and (attempted_at is null or attempted_at < ${before}) returning id`
	)) as unknown as { rows: unknown[] };
	return res.rows.length > 0;
}

async function recordFailure(handle: DbHandle, reason: string): Promise<void> {
	await handle.db
		.update(fxRefresh)
		.set({ lastError: reason.slice(0, 60) })
		.where(eq(fxRefresh.id, 'main'));
}

/**
 * Fetches the rates and stores them. Never throws for a bad answer: it records a short reason and keeps what it has. Not configured, or
 * tried within ten minutes, it does nothing. `force` skips the ten minute wait (a person pressed the button; the claim still stamps it).
 */
export async function refreshRates(
	handle: DbHandle,
	options: { now?: Date; force?: boolean } = {}
): Promise<RefreshOutcome> {
	const config = fxConfig();
	if (!config) return { status: 'skipped', reason: 'not_configured' };
	const now = options.now ?? new Date();
	if (!(await claimRefresh(handle, now, options.force ?? false)))
		return { status: 'skipped', reason: 'recent' };
	try {
		// No transaction is open here: a slow source holds no connection and no person's lock
		const fetched = await fetchRates(config);
		// A rate keeps the feed's own timestamp when it gives one, so a feed that stopped updating shows as stale instead of looking fresh
		const stamp = fetched.asOf ?? now;
		const known = new Map((await handle.db.select().from(fxRate)).map((r) => [r.code, r]));
		const held: string[] = [];
		const fresh = Object.entries(fetched.rates).filter(([code, rate]) => {
			const old = known.get(code);
			// A rate that jumped by more than three times is far more likely a bad value than a move: it is held back and the old one stays.
			// But a rate held for a week is taken: a real step (a redenomination, a collapse) must not stay wrong for ever
			if (
				old &&
				now.getTime() - old.fetchedAt.getTime() < HOLD_BACK_MAX_MS &&
				movedTooFar(old.rate, rate)
			) {
				held.push(code);
				return false;
			}
			return true;
		});
		await handle.db.transaction(async (tx) => {
			// Every rate held back leaves nothing to write, and an empty insert is an error
			if (fresh.length > 0)
				await tx
					.insert(fxRate)
					.values(
						fresh.map(([code, rate]) => ({ code, rate, fetchedAt: stamp, source: fetched.source }))
					)
					.onConflictDoUpdate({
						target: fxRate.code,
						set: {
							rate: sql`excluded.rate`,
							fetchedAt: sql`excluded.fetched_at`,
							source: sql`excluded.source`
						}
					});
			await tx
				.update(fxRefresh)
				.set({ succeededAt: now, lastError: held.length > 0 ? `held:${held.length}` : null })
				.where(eq(fxRefresh.id, 'main'));
		});
		return { status: 'refreshed', count: fresh.length, held };
	} catch (e) {
		const reason = e instanceof FxFetchError ? e.reason : 'store_failed';
		// The reason is a short code, never text from the source or the database
		console.warn(JSON.stringify({ event: 'fx_refresh_failed', reason }));
		await recordFailure(handle, reason).catch(() => undefined);
		return { status: 'failed', reason };
	}
}

/** Starts a refresh without waiting for it, when the rates are stale. A read of a total never waits for the network. */
export function refreshInBackground(handle: DbHandle, status: Pick<RatesStatus, 'stale'>): void {
	if (!status.stale || !fxConfig()) return;
	void refreshRates(handle).catch(() => undefined);
}
