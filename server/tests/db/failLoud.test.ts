// FAIL LOUD, NEVER OPEN: THE RATES ADDRESS IS REQUIRED IN PRODUCTION, ACCEPTED RATES KEEP THE FEED'S OWN TIME (STALE AFTER 36 HOURS), A STALE SCHEMA IS REFUSED AT START,
// AND REPLACING A ROW LEVEL SECURITY POLICY NEVER LEAVES A MOMENT WITH NO POLICY (WHICH WOULD DENY EVERY ROW).

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { CURRENCY_CODES } from '../../src/lib/finance/currency';
import { variables } from '../../src/env';
import { fxRate } from '../../src/lib/server/db/schema';
import { MIGRATIONS_DIR, assertMigrated, secure } from '../../src/lib/server/db/migrate';
import { withUser } from '../../src/lib/server/db/tenant';
import { configureFx, fxUrlFromEnv } from '../../src/lib/server/fx/config';
import { loadRates, refreshRates, STALE_AFTER_MS } from '../../src/lib/server/fx/store';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

// -- STATES -- //

let t: TestDb;

// -- FUNCTIONS -- //

function feed(extra: Record<string, unknown> = {}) {
	const rates: Record<string, unknown> = { USD: 1 };
	CURRENCY_CODES.forEach((c, i) => {
		if (c !== 'USD') rates[c] = 2 + i;
	});
	return { result: 'success', base_code: 'USD', rates, ...extra };
}
const serve = (body: unknown) =>
	(async () =>
		new Response(JSON.stringify(body), {
			status: 200,
			headers: { 'content-type': 'application/json' }
		})) as unknown as typeof fetch;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterEach(() => configureFx(null));

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the rates address', () => {
	it('is required in production and may be missing elsewhere', () => {
		expect(() => fxUrlFromEnv(undefined, true)).toThrow(/FX_RATES_URL is required/);
		expect(() => fxUrlFromEnv('   ', true)).toThrow(/required/);
		expect(fxUrlFromEnv(undefined, false)).toBe('');
		expect(fxUrlFromEnv(' https://rates.example.com/x ', true)).toBe('https://rates.example.com/x');
		expect(() => fxUrlFromEnv('http://rates.example.com', false)).toThrow(/https/);
	});

	it('is read by the environment schema with the same rule', () => {
		const schema = variables.FX_RATES_URL.schema as unknown as {
			'~standard': { validate(v: unknown): { value?: unknown } };
		};
		// Vitest runs with NODE_ENV=test, so a missing value is allowed here
		expect(schema['~standard'].validate(undefined).value).toBe('');
	});

	it('reports a manual refresh without a source as not configured', async () => {
		configureFx(null);
		expect(await refreshRates(t.handle)).toEqual({ status: 'skipped', reason: 'not_configured' });
	});
});

describe('the age of the rates', () => {
	it('keeps the feed timestamp when it gives one', async () => {
		const stamp = Math.floor((Date.now() - 20 * 3_600_000) / 1000);
		configureFx({
			url: 'https://rates.test/v6/latest/USD',
			fetch: serve(feed({ time_last_update_unix: stamp }))
		});
		expect(await refreshRates(t.handle, { force: true })).toMatchObject({ status: 'refreshed' });
		const [row] = await t.handle.db.select().from(fxRate).limit(1);
		expect(Math.floor((row?.fetchedAt.getTime() ?? 0) / 1000)).toBe(stamp);
	});

	it('ignores a feed timestamp that is not believable and uses the fetch time', async () => {
		const before = Date.now();
		configureFx({
			url: 'https://rates.test/v6/latest/USD',
			fetch: serve(feed({ time_last_update_unix: Math.floor(Date.now() / 1000) + 10 * 86_400 }))
		});
		await refreshRates(t.handle, { force: true });
		const [row] = await t.handle.db.select().from(fxRate).limit(1);
		expect(row?.fetchedAt.getTime()).toBeGreaterThanOrEqual(before - 1000);
		expect(row?.fetchedAt.getTime()).toBeLessThanOrEqual(Date.now() + 1000);
	});

	it('is stale after 36 hours and not before', async () => {
		expect(STALE_AFTER_MS).toBe(36 * 3_600_000);
		const now = new Date();
		await t.handle.db.update(fxRate).set({ fetchedAt: new Date(now.getTime() - 30 * 3_600_000) });
		expect((await loadRates(t.handle.db, now)).stale).toBe(false);
		await t.handle.db.update(fxRate).set({ fetchedAt: new Date(now.getTime() - 40 * 3_600_000) });
		expect((await loadRates(t.handle.db, now)).stale).toBe(true);
	});
});

describe('the migration check at start', () => {
	it('passes on a migrated database', async () => {
		await expect(assertMigrated(t.handle.owner)).resolves.toBeUndefined();
	});

	it('refuses a database behind the journal, naming what is missing', async () => {
		const dir = mkdtempSync(join(tmpdir(), 'botler-journal-'));
		mkdirSync(join(dir, 'meta'));
		const journal = JSON.parse(
			readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
		) as { entries: { idx: number; tag: string }[] };
		journal.entries.push({ idx: 9999, tag: '9999_not_applied_yet' });
		writeFileSync(join(dir, 'meta', '_journal.json'), JSON.stringify(journal));
		await expect(assertMigrated(t.handle.owner, dir)).rejects.toThrow(/9999_not_applied_yet/);
	});

	it('refuses a database with no migration record at all', async () => {
		const none = {
			exec: async () => undefined,
			query: async () => {
				throw new Error('relation "__botler_migrations" does not exist');
			}
		};
		await expect(assertMigrated(none as never)).rejects.toThrow(/migration record/);
	});
});

describe('replacing the row level security policies', () => {
	it('never leaves a moment where a person sees no rows', async () => {
		const f = await seedPerson(t);
		let stop = false;
		let empty = 0;
		let reads = 0;
		const reader = (async () => {
			while (!stop) {
				const n = await withUser(t.handle, f.userId, async (tx) => {
					const res = await tx.execute(`select count(*)::int as n from account`);
					return (res as unknown as { rows: { n: number }[] }).rows[0]?.n ?? 0;
				});
				reads++;
				if (n === 0) empty++;
			}
		})();
		for (let i = 0; i < 6; i++) await secure(t.handle.owner);
		stop = true;
		await reader;
		expect(reads).toBeGreaterThan(0);
		expect(empty).toBe(0);
		// And every policy is still there under its final name
		const policies = await t.handle.owner.query<{ n: string }>(
			`select count(*)::text as n from pg_policies where schemaname = 'public' and policyname = 'user_isolation_next'`
		);
		expect(policies[0]?.n).toBe('0');
	}, 30_000);
});
