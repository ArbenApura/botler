// THE EXCHANGE RATE TABLES (BTL-20261023-1407, M3.2): ALWAYS READABLE AND UPDATABLE BY THE APP ROLE, NEVER DELETABLE, AND ONLY WELL FORMED RATES GET IN

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the rate tables', () => {
	it('lets the app role read, add and change rates but never delete or empty them', async () => {
		for (const table of ['fx_rate', 'fx_refresh']) {
			const [p] = await t.handle.owner.query<Record<string, boolean>>(
				`select has_table_privilege('app_runtime', $1, 'SELECT') as sel, has_table_privilege('app_runtime', $1, 'INSERT') as ins,
					has_table_privilege('app_runtime', $1, 'UPDATE') as upd, has_table_privilege('app_runtime', $1, 'DELETE') as del,
					has_table_privilege('app_runtime', $1, 'TRUNCATE') as trunc`,
				[table]
			);
			expect(p, table).toEqual({ sel: true, ins: true, upd: true, del: false, trunc: false });
		}
	});

	it('keeps the grant after the security statements run again', async () => {
		const { securityStatements } = await import('../../src/lib/server/db/security');
		for (const s of securityStatements()) await t.handle.owner.exec(s);
		const [p] = await t.handle.owner.query<{ del: boolean }>(
			`select has_table_privilege('app_runtime', 'fx_rate', 'DELETE') as del`
		);
		expect(p?.del).toBe(false);
	});

	it('has the one refresh row from the start', async () => {
		const rows = await t.handle.owner.query(`select id, attempted_at from fx_refresh`);
		expect(rows).toEqual([{ id: 'main', attempted_at: null }]);
	});

	it('refuses a rate that is not a positive plain decimal, and a code that is not three capitals', async () => {
		const add = (code: string, rate: string) =>
			t.handle.owner.exec(
				`insert into fx_rate (code, rate, fetched_at, source) values ('${code}', '${rate}', now(), 'test')`
			);
		for (const rate of ['0', '0.0', '-1', '1e3', 'abc', '', '1,5', '5x12', '.5'])
			await expect(add('PHP', rate), rate).rejects.toThrow();
		await expect(add('php', '56')).rejects.toThrow();
		await expect(add('PHPP', '56')).rejects.toThrow();
		await add('PHP', '56.123456789012345678');
		await expect(add('PHP', '57')).rejects.toThrow();
	});
});
