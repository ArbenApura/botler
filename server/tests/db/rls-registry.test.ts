// THE REGISTRY GUARD: EVERY TABLE IN THE DATABASE MUST BE REGISTERED, AND EVERY USER TABLE MUST HAVE FORCED ROW LEVEL SECURITY.
// Adding a table without registering it, or registering it as plain by mistake, turns this test red before any data is at risk.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { PLAIN_TABLES, USER_TABLES } from '../../src/lib/server/db/schema';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

/** The migration ledger is bookkeeping of the owner role, not a table of data. */
const BOOKKEEPING = ['__botler_migrations'];

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

describe('row level security registry', () => {
	it('registers every table in the database as plain or user owned', async () => {
		const rows = await t.handle.owner.query<{ relname: string }>(
			`select relname from pg_class where relkind in ('r','p') and relnamespace = 'public'::regnamespace`
		);
		const known = new Set([...PLAIN_TABLES, ...USER_TABLES.map((u) => u.name), ...BOOKKEEPING]);
		const unknown = rows.map((r) => r.relname).filter((n) => !known.has(n));
		expect(unknown, `Unregistered tables: ${unknown.join(', ')}`).toEqual([]);
	});

	it('never registers a table twice or in both lists', () => {
		const names = [...PLAIN_TABLES, ...USER_TABLES.map((u) => u.name)];
		expect(new Set(names).size).toBe(names.length);
	});

	it('forces row level security with a policy on every user table', async () => {
		for (const u of USER_TABLES) {
			const [flags] = await t.handle.owner.query<{ on: boolean; force: boolean }>(
				`select relrowsecurity as on, relforcerowsecurity as force from pg_class where relname = $1 and relnamespace = 'public'::regnamespace`,
				[u.name]
			);
			expect(flags, `${u.name} is missing`).toBeDefined();
			expect(flags?.on, `${u.name} has no RLS`).toBe(true);
			expect(flags?.force, `${u.name} does not force RLS`).toBe(true);
			const policies = await t.handle.owner.query<{ policyname: string }>(
				`select policyname from pg_policies where tablename = $1`,
				[u.name]
			);
			expect(
				policies.map((p) => p.policyname),
				`${u.name} has no policy`
			).toContain('user_isolation');
			const col = await t.handle.owner.query(
				`select 1 from information_schema.columns where table_name = $1 and column_name = $2`,
				[u.name, u.userColumn]
			);
			expect(col, `${u.name} has no ${u.userColumn}`).toHaveLength(1);
		}
	});

	it('keeps plain tables free of user data policies', async () => {
		for (const name of PLAIN_TABLES) {
			const policies = await t.handle.owner.query(
				`select 1 from pg_policies where tablename = $1`,
				[name]
			);
			expect(policies, `${name} is plain but has a policy`).toHaveLength(0);
		}
	});

	it('runs requests as a role that cannot bypass row level security or own tables', async () => {
		const [role] = await t.handle.owner.query<{ super: boolean; bypass: boolean }>(
			`select rolsuper as super, rolbypassrls as bypass from pg_roles where rolname = 'app_runtime'`
		);
		expect(role).toEqual({ super: false, bypass: false });
		const owned = await t.handle.owner.query(
			`select 1 from pg_tables where schemaname = 'public' and tableowner = 'app_runtime'`
		);
		expect(owned).toHaveLength(0);
	});

	it('has pgvector installed by the owner role', async () => {
		const ext = await t.handle.owner.query(`select 1 from pg_extension where extname = 'vector'`);
		expect(ext).toHaveLength(1);
	});
});
