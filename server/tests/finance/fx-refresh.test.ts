// FETCHING AND STORING EXCHANGE RATES (BTL-20261023-1407, M3.3 TO M3.5): A CHECKED FEED, ONE REFRESH AT A TIME, A BAD ANSWER NEVER REPLACES A GOOD RATE, READING NEVER WAITS

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { CURRENCY_CODES } from '../../src/lib/finance/currency';
import { fxRate, fxRefresh, user } from '../../src/lib/server/db/schema';
import { configureFx, fxConfig } from '../../src/lib/server/fx/config';
import { fetchRates, FxFetchError } from '../../src/lib/server/fx/source';
import { loadRates, MIN_REFRESH_INTERVAL_MS, refreshRates } from '../../src/lib/server/fx/store';
import { fxRefreshJob } from '../../src/lib/server/jobs/fx';
import { fxRates, fxRatesRefresh } from '../../src/lib/server/ops/fx';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const URL = 'https://rates.test/v6/latest/USD';

/** A feed for every currency of the catalogue: PHP is 56 to the dollar, the rest a number that is easy to check. */
function feed(overrides: Record<string, unknown> = {}, extra: Record<string, unknown> = {}) {
	const rates: Record<string, unknown> = { USD: 1 };
	CURRENCY_CODES.forEach((c, i) => {
		if (c !== 'USD') rates[c] = 2 + i;
	});
	rates.PHP = 56;
	rates.JPY = 157.2;
	rates.KWD = 0.0000643;
	return { result: 'success', base_code: 'USD', rates: { ...rates, ...overrides }, ...extra };
}

const answer = (body: unknown, init: ResponseInit = {}, type = 'application/json') =>
	new Response(typeof body === 'string' ? body : JSON.stringify(body), {
		status: 200,
		headers: { 'content-type': type },
		...init
	});

// -- STATES -- //

let t: TestDb;
let calls = 0;
let next: () => Promise<Response> = async () => answer(feed());
const stub = (async () => {
	calls++;
	return next();
}) as unknown as typeof fetch;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const stored = (code: string) =>
	t.handle.db
		.select()
		.from(fxRate)
		.where(eq(fxRate.code, code))
		.then((r) => r[0]);
/** Lets the refresh be tried again: the claim of the last one is moved back past the wait. */
const reopen = () =>
	t.handle.db
		.update(fxRefresh)
		.set({ attemptedAt: new Date(Date.now() - MIN_REFRESH_INTERVAL_MS - 1000) })
		.where(eq(fxRefresh.id, 'main'));

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values([{ id: 'user_fx_0001', name: 'F', email: 'fx@example.com' }]);
});

afterEach(() => {
	calls = 0;
	next = async () => answer(feed());
});

afterAll(async () => {
	configureFx(null);
	await t.close();
});

// -- TESTS -- //

describe('the address', () => {
	it('must be a plain https address', () => {
		for (const bad of ['http://x.test/a', 'ftp://x.test', 'nonsense', 'https://u:p@x.test/'])
			expect(() => configureFx({ url: bad }), bad).toThrow();
		configureFx({ url: URL, fetch: stub });
		expect(fxConfig()?.url).toBe(URL);
	});
});

describe('reading the feed', () => {
	const cfg = () => ({ url: URL, fetch: stub });

	it('keeps a rate for every currency of the catalogue as exact decimal text', async () => {
		const got = await fetchRates(cfg());
		expect(got.source).toBe('rates.test');
		expect(got.rates.PHP).toBe('56');
		expect(got.rates.JPY).toBe('157.2');
		// A tiny number is written out, never as 6.43e-5
		expect(got.rates.KWD).toBe('0.0000643');
		expect(got.rates.USD).toBeUndefined();
		expect(Object.keys(got.rates)).toHaveLength(CURRENCY_CODES.length - 1);
		expect(got.missing).toEqual([]);
	});

	it('leaves out a rate that is zero, negative, text or missing, and names it', async () => {
		next = async () => answer(feed({ PHP: 0, EUR: -3, GBP: '0.8', CAD: null }));
		const got = await fetchRates(cfg());
		expect([...got.missing].sort()).toEqual(['CAD', 'EUR', 'GBP', 'PHP']);
		expect(got.rates.PHP).toBeUndefined();
		expect(got.rates.AUD).toBeDefined();
	});

	it('fails with a short code for every kind of bad answer', async () => {
		const reasons: [string, () => Promise<Response>][] = [
			['http_503', async () => answer('down', { status: 503 })],
			['not_json', async () => answer(feed(), {}, 'text/html')],
			['not_json', async () => answer('{broken')],
			['bad_shape', async () => answer({ result: 'error', rates: {} })],
			['bad_shape', async () => answer(feed({}, { base_code: 'EUR' }))],
			['bad_base', async () => answer(feed({ USD: 2 }))],
			[
				'too_few_rates',
				async () => answer({ result: 'success', base_code: 'USD', rates: { PHP: 56 } })
			],
			['too_large', async () => answer(' '.repeat(1_100_000))],
			[
				'timeout',
				async () => {
					throw new DOMException('slow', 'TimeoutError');
				}
			],
			[
				'network',
				async () => {
					throw new TypeError('fetch failed');
				}
			]
		];
		for (const [reason, make] of reasons) {
			next = make;
			await expect(fetchRates(cfg()), reason).rejects.toMatchObject({
				name: 'FxFetchError',
				reason
			});
		}
		expect(new FxFetchError('x').message).toContain('x');
	});

	it('asks for the fixed address with a redirect refused, and sends nothing about a person', async () => {
		let seen: { url: string; init: RequestInit } | null = null;
		const spy = (async (url: string, init: RequestInit) => {
			seen = { url, init };
			return answer(feed());
		}) as unknown as typeof fetch;
		await fetchRates({ url: URL, fetch: spy });
		const call = seen as unknown as { url: string; init: RequestInit };
		expect(call.url).toBe(URL);
		expect(call.init.redirect).toBe('error');
		expect(call.init.method).toBe('GET');
		expect(call.init.body).toBeUndefined();
		expect(call.init.signal).toBeInstanceOf(AbortSignal);
	});
});

describe('storing the rates', () => {
	it('does nothing without a configured source', async () => {
		configureFx(null);
		expect(await refreshRates(t.handle)).toEqual({ status: 'skipped', reason: 'not_configured' });
		await expect(fxRatesRefresh(person('user_fx_0001'))).rejects.toMatchObject({
			code: 'UNAVAILABLE'
		});
		expect(calls).toBe(0);
	});

	it('stores every rate on the first refresh, and the second one within ten minutes fetches nothing', async () => {
		configureFx({ url: URL, fetch: stub });
		const first = await refreshRates(t.handle);
		expect(first).toMatchObject({ status: 'refreshed', held: [] });
		expect(calls).toBe(1);
		expect((await stored('PHP'))?.rate).toBe('56');
		expect((await stored('JPY'))?.source).toBe('rates.test');
		const again = await refreshRates(t.handle);
		expect(again).toEqual({ status: 'skipped', reason: 'recent' });
		expect(calls).toBe(1);
		const status = await loadRates(t.handle.db);
		expect(status.stale).toBe(false);
		expect(status.lastError).toBeNull();
		expect(status.succeededAt).not.toBeNull();
	});

	it('lets only one of several refreshes at once fetch', async () => {
		await reopen();
		const results = await Promise.all([1, 2, 3, 4].map(() => refreshRates(t.handle)));
		expect(results.filter((r) => r.status === 'refreshed')).toHaveLength(1);
		expect(results.filter((r) => r.status === 'skipped')).toHaveLength(3);
		expect(calls).toBe(1);
	});

	it('holds back a rate that jumped more than three times and keeps the old one, storing the rest', async () => {
		await reopen();
		// JPY would be 100 times lower, PHP moves a little
		next = async () => answer(feed({ JPY: 1.5, PHP: 57.5 }));
		const out = await refreshRates(t.handle);
		expect(out).toMatchObject({ status: 'refreshed', held: ['JPY'] });
		expect((await stored('JPY'))?.rate).toBe('157.2');
		expect((await stored('PHP'))?.rate).toBe('57.5');
		expect((await loadRates(t.handle.db)).lastError).toBe('held:1');
	});

	it('takes a held rate after a week, and an all-held batch is not a store failure', async () => {
		await reopen();
		// Every rate jumps at once: all are held, and that is a refresh that stored nothing, not an error
		next = async () =>
			answer(
				feed(Object.fromEntries(CURRENCY_CODES.filter((c) => c !== 'USD').map((c) => [c, 1e9])))
			);
		const all = await refreshRates(t.handle);
		expect(all).toMatchObject({ status: 'refreshed', count: 0 });
		expect((await loadRates(t.handle.db)).lastError).toMatch(/^held:/);
		// A rate that has been held for more than a week is taken: a real step must not stay wrong for ever
		await t.handle.db.update(fxRate).set({ fetchedAt: new Date(Date.now() - 8 * 86_400_000) });
		await reopen();
		next = async () => answer(feed({ JPY: 1.5 }));
		const out = await refreshRates(t.handle);
		expect(out).toMatchObject({ status: 'refreshed' });
		expect((await stored('JPY'))?.rate).toBe('1.5');
		// Back to the numbers the later tests expect
		await reopen();
		next = async () => answer(feed({ JPY: 157.2, PHP: 57.5 }));
		await t.handle.db.update(fxRate).set({ fetchedAt: new Date(Date.now() - 9 * 86_400_000) });
		await refreshRates(t.handle);
		expect((await stored('JPY'))?.rate).toBe('157.2');
	});

	it('keeps every stored rate when the source fails, records a short reason, and is not tried again on every read', async () => {
		await reopen();
		next = async () => answer('down', { status: 500 });
		const out = await refreshRates(t.handle);
		expect(out).toEqual({ status: 'failed', reason: 'http_500' });
		expect((await stored('PHP'))?.rate).toBe('57.5');
		const status = await loadRates(t.handle.db);
		expect(status.lastError).toBe('http_500');
		// The failed try counts as a try
		expect(await refreshRates(t.handle)).toEqual({ status: 'skipped', reason: 'recent' });
		await reopen();
		expect(await refreshRates(t.handle)).toMatchObject({ status: 'failed' });
	});

	it('records the next good refresh and clears the error', async () => {
		await reopen();
		next = async () => answer(feed({ PHP: 58 }));
		expect(await refreshRates(t.handle)).toMatchObject({ status: 'refreshed' });
		const status = await loadRates(t.handle.db);
		expect(status.lastError).toBeNull();
		expect((await stored('PHP'))?.rate).toBe('58');
	});
});

describe('the verbs', () => {
	const id = 'user_fx_0001';

	it('reads the stored rates for a live person, with their date and whether they are stale', async () => {
		const view = await fxRates(person(id));
		expect(view.configured).toBe(true);
		expect(view.rates.PHP).toBe('58');
		expect(view.stale).toBe(false);
		expect(view.asOf).not.toBeNull();
		expect(view.source).toBe('rates.test');
	});

	it('starts a refresh in the background when the rates are stale, and still answers at once', async () => {
		await t.handle.db.update(fxRate).set({ fetchedAt: new Date(Date.now() - 3 * 86_400_000) });
		await reopen();
		next = async () => {
			await new Promise((r) => setTimeout(r, 150));
			return answer(feed({ PHP: 60 }));
		};
		const view = await fxRates(person(id));
		// The answer is the stored rates, not the ones being fetched
		expect(view.stale).toBe(true);
		expect(view.rates.PHP).toBe('58');
		await new Promise((r) => setTimeout(r, 600));
		expect((await stored('PHP'))?.rate).toBe('60');
		expect((await fxRates(person(id))).stale).toBe(false);
	});

	it('refreshes on request for a person and is not offered to the assistant', async () => {
		await reopen();
		next = async () => answer(feed({ PHP: 61 }));
		const out = await fxRatesRefresh(person(id));
		expect(out.outcome).toMatchObject({ status: 'refreshed' });
		expect(out.view.rates.PHP).toBe('61');
		const agent: Ctx = { handle: t.handle, actor: { userId: id, kind: 'agent', tool: 't' } };
		await expect(invokeVerb(agent, 'fx_rates_refresh', {})).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
		await expect(invokeVerb(agent, 'fx_rates', {})).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await expect(invokeVerb(person(id), 'fx_rates', { extra: 1 })).rejects.toBeTruthy();
	});

	it('runs from the nightly job without throwing when the source fails', async () => {
		await reopen();
		next = async () => answer('down', { status: 502 });
		const ctx: Ctx = {
			handle: t.handle,
			actor: { userId: id, kind: 'agent', tool: 'job:fx.refresh' },
			via: 'job',
			channel: 'job'
		};
		await expect(
			fxRefreshJob(
				{
					id: 'j',
					userId: id,
					kind: 'fx.refresh',
					key: 'k',
					payload: {},
					attempts: 1,
					maxAttempts: 5
				},
				undefined as never,
				ctx
			)
		).resolves.toBeUndefined();
		expect((await loadRates(t.handle.db)).lastError).toBe('http_502');
	});
});

describe('the nightly job', () => {
	it('is queued once a day for each person by the maintenance schedule', async () => {
		const { scheduleMaintenance } = await import('../../src/lib/server/jobs/queue');
		const { job } = await import('../../src/lib/server/db/schema');
		const day = new Date('2026-10-25T04:00:00Z');
		await scheduleMaintenance(t.handle, day);
		await scheduleMaintenance(t.handle, day);
		const rows = await t.handle.db.select().from(job).where(eq(job.kind, 'fx.refresh'));
		expect(rows.map((r) => [r.userId, r.key])).toEqual([['user_fx_0001', '2026-10-25']]);
	});
});
