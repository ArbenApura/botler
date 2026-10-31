// MIGRATION 0039 REPAIRS 0023: ITS UPDATE NEVER REACHED A ROW (THE OWNER IS BOUND BY FORCED ROW LEVEL SECURITY), SO OLD BILLS KEPT starts_on = NULL.
// RUN AS A PLAIN OWNER ON A DATABASE AT 0038 WITH OLD ROWS, THE WAY PRODUCTION RUNS.

// -- DEP-MODULES -- //
import { afterAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createStagedDb, type StagedDb } from '../support/stagedDb';

// -- STATES -- //

const open: StagedDb[] = [];

// -- LIFECYCLES -- //

afterAll(async () => {
	for (const d of open) await d.close();
});

// -- TESTS -- //

describe('migration 0039 (bill starts_on repair)', () => {
	it('gives every bill without a start the Manila day it was added (or its earliest payment), under forced row level security, and can run again', async () => {
		const db = await createStagedDb({ before: '0039', plainOwner: true });
		open.push(db);
		const q = db.handle.owner.query.bind(db.handle.owner);
		await q(`INSERT INTO "user" (id, name, email) VALUES ('u_bill_0001', 'B', 'b@example.com')`);
		await q(
			`INSERT INTO account (id, user_id, name) VALUES ('11111111-1111-4111-8111-111111111111', 'u_bill_0001', 'RCBC')`
		);
		const bill = (id: string, name: string, createdAt: string, startsOn: string | null) =>
			q(
				`INSERT INTO bill (id, user_id, name, account_id, kind, amount, schedule, created_at, starts_on) VALUES ($1, 'u_bill_0001', $2, '11111111-1111-4111-8111-111111111111', 'fixed', 1000, '{}'::jsonb, $3, $4)`,
				[id, name, createdAt, startsOn]
			);
		// 16:30 UTC on the 14th is already the 15th in Manila
		await bill('22222222-2222-4222-8222-222222222221', 'Water', '2026-03-14T16:30:00Z', null);
		// Added on 2026-03-20 but paid for 2026-03-01: the payment is never before the start
		await bill('22222222-2222-4222-8222-222222222222', 'Rent', '2026-03-20T02:00:00Z', null);
		await q(
			`INSERT INTO bill_payment (user_id, bill_id, due_date, amount) VALUES ('u_bill_0001', '22222222-2222-4222-8222-222222222222', '2026-03-01', 1000)`
		);
		// A bill that already has a start keeps it
		await bill(
			'22222222-2222-4222-8222-222222222223',
			'Power',
			'2026-03-20T02:00:00Z',
			'2026-01-05'
		);
		await db.lockDown();

		const applied = await db.finish();
		expect(applied).toContain('0039_bill_starts_on_repair');

		const reader = await db.reader();
		try {
			const rows = await reader.query<{ name: string; starts_on: string }>(
				`SELECT name, to_char(starts_on, 'YYYY-MM-DD') AS starts_on FROM bill ORDER BY name`
			);
			expect(rows.rows).toEqual([
				{ name: 'Power', starts_on: '2026-01-05' },
				{ name: 'Rent', starts_on: '2026-03-01' },
				{ name: 'Water', starts_on: '2026-03-15' }
			]);
			const forced = await reader.query<{ relname: string; relforcerowsecurity: boolean }>(
				`SELECT relname, relforcerowsecurity FROM pg_class WHERE relname IN ('bill', 'bill_payment')`
			);
			expect(forced.rows).toHaveLength(2);
			for (const r of forced.rows) expect(r.relforcerowsecurity, r.relname).toBe(true);

			// Run again: nothing is left at NULL, so nothing changes, and row level security stays forced
			await reader.query(`UPDATE bill SET starts_on = NULL WHERE name = 'Power'`);
			await reader.query(
				`DELETE FROM "__botler_migrations" WHERE tag = '0039_bill_starts_on_repair'`
			);
			expect(await db.finish()).toContain('0039_bill_starts_on_repair');
			const again = await reader.query<{ name: string; starts_on: string }>(
				`SELECT name, to_char(starts_on, 'YYYY-MM-DD') AS starts_on FROM bill ORDER BY name`
			);
			// The re-run fills the one set back to NULL (from its added day) and leaves the others
			expect(again.rows.map((r) => r.starts_on)).toEqual([
				'2026-03-20',
				'2026-03-01',
				'2026-03-15'
			]);
			const forced2 = await reader.query<{ relforcerowsecurity: boolean }>(
				`SELECT relforcerowsecurity FROM pg_class WHERE relname IN ('bill', 'bill_payment')`
			);
			for (const r of forced2.rows) expect(r.relforcerowsecurity).toBe(true);
		} finally {
			await reader.end();
		}
	}, 60_000);
});
