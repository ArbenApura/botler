// MIGRATION 0033 (A RULE CAN SAVE FOR A BILL, BTL-20261029-0119): EVERY PERSON'S RULES ARE NUMBERED AGAIN 1, 2, 3 IN THE ORDER THEY HAD, SO TWO RULES
// NEVER SHARE A POSITION, AND DELETING A BILL CLEARS ONLY THE LINK. RUN AS A PLAIN OWNER BOUND BY FORCED ROW LEVEL SECURITY (HOW PRODUCTION RUNS),
// WHERE AN UPDATE WITHOUT THE NO FORCE / FORCE PAIR SILENTLY CHANGES NO ROWS (THE LESSON OF 0027 AND 0028).

// -- TYPES -- //
import type { DbHandle } from '../../src/lib/server/db/client';
// -- DEP-MODULES -- //
import { randomBytes } from 'node:crypto';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createPostgres } from '../../src/lib/server/db/client';
import { MIGRATIONS_DIR, migrateLocked } from '../../src/lib/server/db/migrate';

// -- CONSTANTS -- //

const ADMIN_URL =
	process.env.TEST_PG_ADMIN_URL ??
	'postgres://postgres:localpostgrespassword@127.0.0.1:5434/postgres';

// -- STATES -- //

let admin: pg.Client;
const made: { databases: string[]; roles: string[] } = { databases: [], roles: [] };

// -- LIFECYCLES -- //

beforeAll(async () => {
	admin = new pg.Client({ connectionString: ADMIN_URL });
	await admin.connect();
	admin.on('error', () => undefined);
});

afterAll(async () => {
	for (const name of made.databases)
		if (/^botler_test_[0-9a-f]{12}$/.test(name))
			await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
	for (const role of made.roles)
		if (/^botler_mig_[0-9a-f]{12}$/.test(role)) await admin.query(`DROP ROLE IF EXISTS "${role}"`);
	await admin.end();
});

// -- FUNCTIONS -- //

function urlFor(database: string, user?: string, password?: string): string {
	const u = new URL(ADMIN_URL);
	u.pathname = `/${database}`;
	if (user) u.username = user;
	if (password) u.password = password;
	return u.toString();
}

/** The database as it was before this migration: the runner itself, over a copy of the journal that stops at 0032. */
async function applyEarlier(handle: DbHandle) {
	const dir = mkdtempSync(join(tmpdir(), 'botler-mig-'));
	try {
		mkdirSync(join(dir, 'meta'));
		const journal = JSON.parse(
			readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
		) as { entries: { tag: string }[] };
		const earlier = journal.entries.filter((e) => e.tag < '0033_');
		writeFileSync(
			join(dir, 'meta', '_journal.json'),
			JSON.stringify({ ...journal, entries: earlier })
		);
		for (const { tag } of earlier)
			copyFileSync(join(MIGRATIONS_DIR, `${tag}.sql`), join(dir, `${tag}.sql`));
		await migrateLocked(handle, dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

// -- TESTS -- //

describe('migration 0033', () => {
	it('numbers every person’s rules again in their order under forced row level security, and a bill delete clears only the link', async () => {
		const suffix = randomBytes(6).toString('hex');
		const role = `botler_mig_${suffix}`;
		const name = `botler_test_${suffix}`;
		made.roles.push(role);
		made.databases.push(name);
		await admin.query(`CREATE ROLE "${role}" LOGIN PASSWORD 'migpass' NOSUPERUSER NOBYPASSRLS`);
		await admin.query(`CREATE DATABASE "${name}" OWNER "${role}"`);
		// The vector extension needs a superuser to install; the owner only finds it there
		const setup = new pg.Client({ connectionString: urlFor(name) });
		await setup.connect();
		await setup.query(`CREATE EXTENSION IF NOT EXISTS vector`);
		await setup.end();
		const handle = createPostgres({
			ownerUrl: urlFor(name, role, 'migpass'),
			switchRole: false,
			poolMax: 2
		});
		try {
			await applyEarlier(handle);
			// The rows were written by the app before 0033; the superuser plants them, so row level security does not get in the way
			const planter = new pg.Client({ connectionString: urlFor(name) });
			await planter.connect();
			try {
				for (const u of ['u_a', 'u_b'])
					await planter.query(
						`INSERT INTO "user" (id, name, email) VALUES ('${u}', '${u}', '${u}@example.com')`
					);
				const acct = async (u: string) =>
					(
						await planter.query<{ id: string }>(
							`INSERT INTO account (user_id, name) VALUES ('${u}', 'RCBC') RETURNING id`
						)
					).rows[0]?.id;
				const a = await acct('u_a');
				const b = await acct('u_b');
				// u_a: two rules at position 1 (the older first), one at 3; u_b: already fine
				const rule = (u: string, account: string | undefined, position: number, at: string) =>
					planter.query(
						`INSERT INTO allocation_rule (user_id, position, mode, amount, target_account_id, effective_from, status, created_at, label)
						 VALUES ('${u}', ${position}, 'fixed', 100, '${account}', '2026-11-02', 'active', '${at}', '${u}-${position}-${at}')`
					);
				await rule('u_a', a, 1, '2026-10-01');
				await rule('u_a', a, 1, '2026-10-02');
				await rule('u_a', a, 3, '2026-09-01');
				await rule('u_b', b, 1, '2026-10-01');
				await rule('u_b', b, 2, '2026-10-02');
			} finally {
				await planter.end();
			}
			await migrateLocked(handle);

			// Read as the superuser, so the rows being checked are not hidden
			const reader = new pg.Client({ connectionString: urlFor(name) });
			await reader.connect();
			try {
				const rows = (
					await reader.query<{ user_id: string; position: number; label: string }>(
						`SELECT user_id, position, label FROM allocation_rule ORDER BY user_id, position`
					)
				).rows;
				expect(rows).toEqual([
					{ user_id: 'u_a', position: 1, label: 'u_a-1-2026-10-01' },
					{ user_id: 'u_a', position: 2, label: 'u_a-1-2026-10-02' },
					{ user_id: 'u_a', position: 3, label: 'u_a-3-2026-09-01' },
					{ user_id: 'u_b', position: 1, label: 'u_b-1-2026-10-01' },
					{ user_id: 'u_b', position: 2, label: 'u_b-2-2026-10-02' }
				]);
				const forced = (
					await reader.query(
						`SELECT relforcerowsecurity FROM pg_class WHERE relname = 'allocation_rule'`
					)
				).rows;
				expect(forced).toEqual([{ relforcerowsecurity: true }]);

				// A bill delete clears the link only; the rule keeps its owner
				const a = (
					await reader.query<{ id: string }>(`SELECT id FROM account WHERE user_id = 'u_a'`)
				).rows[0]?.id;
				const bill = (
					await reader.query<{ id: string }>(
						`INSERT INTO bill (user_id, name, account_id, amount, schedule) VALUES ('u_a', 'Parents', '${a}', 700000, '{"kind":"monthly","day":1}') RETURNING id`
					)
				).rows[0]?.id;
				await reader.query(
					`UPDATE allocation_rule SET funds_bill_id = '${bill}' WHERE label = 'u_a-1-2026-10-01'`
				);
				// One rule in force per bill
				await expect(
					reader.query(
						`UPDATE allocation_rule SET funds_bill_id = '${bill}' WHERE label = 'u_a-1-2026-10-02'`
					)
				).rejects.toThrow();
				await reader.query(`DELETE FROM bill WHERE id = '${bill}'`);
				const after = (
					await reader.query(
						`SELECT user_id, funds_bill_id FROM allocation_rule WHERE label = 'u_a-1-2026-10-01'`
					)
				).rows;
				expect(after).toEqual([{ user_id: 'u_a', funds_bill_id: null }]);
			} finally {
				await reader.end();
			}
		} finally {
			await handle.close();
		}
	});
});
