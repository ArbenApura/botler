// MIGRATION 0040 (COMPOSITE REFERENCES): DANGLING ids ARE CLEARED BEFORE THE KEYS ARE ADDED, A DELETED TARGET CLEARS ONLY ITS OWN COLUMN, AND NO NEW BARE ID APPEARS BETWEEN TENANT TABLES.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createStagedDb, type StagedDb } from '../support/stagedDb';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

/**
 * Columns that hold an id of another tenant table WITHOUT a reference, on purpose. A new entry needs a reason.
 */
const INTENTIONAL_BARE_IDS: Record<string, string> = {
	'audit_event.account_id':
		'The trail is append-only and outlives the account it names; a reference would block deleting the account or force the trail to change.',
	'chat.forked_from_chat_id':
		'A fork must survive the erasure of the chat it came from (plain id by design, see the chat table).',
	'chat.forked_at_turn_id': 'The same: the turn of the source chat the fork was cut at.',
	'chat.summary_through_turn_id':
		'A plain id so that erasing a turn never blocks; history carries every message after it.',
	'chat_turn.copied_from_turn_id':
		'A marker that the turn was copied into a fork; memory and export skip such turns, so it must survive its source.'
};

const ACCOUNT = '11111111-1111-4111-8111-111111111111';
const SPLIT = '33333333-3333-4333-8333-333333333333';
const NOWHERE = '99999999-9999-4999-8999-999999999999';

// -- STATES -- //

let t: TestDb;
const opened: StagedDb[] = [];

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
	for (const d of opened) await d.close();
});

// -- TESTS -- //

describe('no bare ids between tenant tables', () => {
	it('every uuid column named *_id of a tenant table is a reference, or is on the written list', async () => {
		const bare = await t.handle.owner.query<{ table_name: string; column_name: string }>(`
			SELECT c.table_name, c.column_name FROM information_schema.columns c
			WHERE c.table_schema = 'public' AND c.data_type = 'uuid' AND c.column_name LIKE '%\\_id' ESCAPE '\\' AND c.column_name <> 'id'
			  AND EXISTS (SELECT 1 FROM information_schema.columns u WHERE u.table_schema = 'public' AND u.table_name = c.table_name AND u.column_name = 'user_id')
			  AND NOT EXISTS (
				SELECT 1 FROM pg_constraint k JOIN pg_class r ON r.oid = k.conrelid JOIN pg_namespace n ON n.oid = r.relnamespace
				JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)
				WHERE k.contype = 'f' AND n.nspname = 'public' AND r.relname = c.table_name AND a.attname = c.column_name)
			ORDER BY 1, 2`);
		const found = bare.map((b) => `${b.table_name}.${b.column_name}`);
		expect(found.filter((f) => !(f in INTENTIONAL_BARE_IDS))).toEqual([]);
		// And the list holds nothing that is no longer true
		expect(Object.keys(INTENTIONAL_BARE_IDS).filter((k) => !found.includes(k))).toEqual([]);
	});

	it('keeps the new references as composite keys on the person and the id', async () => {
		const keys = await t.handle.owner.query<{ conname: string; def: string }>(
			`SELECT conname, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname IN ('ledger_txn_split_fk', 'memory_fact_superseded_fk') ORDER BY conname`
		);
		expect(keys).toHaveLength(2);
		for (const k of keys) {
			expect(k.def).toMatch(/FOREIGN KEY \(user_id, /);
			expect(k.def).toMatch(/ON DELETE SET NULL \(/);
		}
	});
});

describe('migration 0040', () => {
	it('clears ids that point at nothing, keeps real ones, and puts forced row level security back (plain owner)', async () => {
		const db = await createStagedDb({ before: '0040', plainOwner: true });
		opened.push(db);
		const q = db.handle.owner.query.bind(db.handle.owner);
		await q(`INSERT INTO "user" (id, name, email) VALUES ('u_ref_00001', 'R', 'r@example.com')`);
		await q(`INSERT INTO account (id, user_id, name) VALUES ($1, 'u_ref_00001', 'RCBC')`, [
			ACCOUNT
		]);
		await q(
			`INSERT INTO split_plan (id, user_id, payday, pay, status, result) VALUES ($1, 'u_ref_00001', '2026-03-15', 100000, 'approved', '{}'::jsonb)`,
			[SPLIT]
		);
		const txn = (id: string, split: string | null) =>
			q(
				`INSERT INTO ledger_txn (id, user_id, type, account_id, amount, split_id) VALUES ($1, 'u_ref_00001', 'income', $3, 100, $2)`,
				[id, split, ACCOUNT]
			);
		await txn('44444444-4444-4444-8444-444444444441', SPLIT);
		await txn('44444444-4444-4444-8444-444444444442', NOWHERE);
		await txn('44444444-4444-4444-8444-444444444443', null);
		const fact = (id: string, hash: string, by: string | null) =>
			q(
				`INSERT INTO memory_fact (id, user_id, text, text_hash, superseded_by) VALUES ($1, 'u_ref_00001', 'a fact', $2, $3)`,
				[id, hash, by]
			);
		await fact('55555555-5555-4555-8555-555555555551', 'h1', null);
		await fact(
			'55555555-5555-4555-8555-555555555552',
			'h2',
			'55555555-5555-4555-8555-555555555551'
		);
		await fact('55555555-5555-4555-8555-555555555553', 'h3', NOWHERE);
		await db.lockDown();

		expect(await db.finish()).toContain('0040_composite_references');

		const reader = await db.reader();
		try {
			const txns = await reader.query<{ id: string; split_id: string | null }>(
				`SELECT id, split_id FROM ledger_txn ORDER BY id`
			);
			expect(txns.rows.map((r) => r.split_id)).toEqual([SPLIT, null, null]);
			const facts = await reader.query<{ id: string; superseded_by: string | null }>(
				`SELECT id, superseded_by FROM memory_fact ORDER BY id`
			);
			expect(facts.rows.map((r) => r.superseded_by)).toEqual([
				null,
				'55555555-5555-4555-8555-555555555551',
				null
			]);
			const valid = await reader.query<{ conname: string; convalidated: boolean }>(
				`SELECT conname, convalidated FROM pg_constraint WHERE conname IN ('ledger_txn_split_fk', 'memory_fact_superseded_fk')`
			);
			expect(valid.rows).toHaveLength(2);
			for (const v of valid.rows) expect(v.convalidated, v.conname).toBe(true);
			const forced = await reader.query<{ relname: string; relforcerowsecurity: boolean }>(
				`SELECT relname, relforcerowsecurity FROM pg_class WHERE relname IN ('ledger_txn', 'split_plan', 'memory_fact')`
			);
			expect(forced.rows).toHaveLength(3);
			for (const r of forced.rows) expect(r.relforcerowsecurity, r.relname).toBe(true);

			// Deleting the split clears only the one column: the entry stays, still the person's
			await reader.query(`DELETE FROM split_plan`);
			const after = await reader.query<{ user_id: string; split_id: string | null }>(
				`SELECT user_id, split_id FROM ledger_txn ORDER BY id`
			);
			expect(after.rows.map((r) => [r.user_id, r.split_id])).toEqual([
				['u_ref_00001', null],
				['u_ref_00001', null],
				['u_ref_00001', null]
			]);
			// A new dangling id is refused now
			await expect(
				reader.query(
					`UPDATE ledger_txn SET split_id = '99999999-9999-4999-8999-999999999998' WHERE id = '44444444-4444-4444-8444-444444444443'`
				)
			).rejects.toThrow(/ledger_txn_split_fk/);
		} finally {
			await reader.end();
		}
	}, 60_000);
});
