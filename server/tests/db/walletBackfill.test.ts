// MIGRATION 0025 (ACCOUNT WALLETS): EVERY OLD ROW GETS THE CURRENCY ITS PERSON HAD SET (PESOS WHEN NONE), AN OLD TRANSFER LANDS IN THE CURRENCY IT LEFT IN, AND EVERY ACCOUNT
// GETS A WALLET FOR EACH CURRENCY IT ALREADY HOLDS. IT IS RUN AS A PLAIN OWNER THAT FORCED ROW LEVEL SECURITY BINDS (HOW PRODUCTION RUNS): THERE A PLAIN UPDATE CHANGES
// NOTHING AND READS NOTHING, WHICH IS WHAT THE "NO FORCE" STEP OF THE MIGRATION IS FOR. A PERSON WITH A NON PESO CURRENCY MUST NOT FALL BACK TO PESOS.

// -- TYPES -- //
import type { DbHandle } from '../../src/lib/server/db/client';
// -- DEP-MODULES -- //
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
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
/** The tables the migration reads or writes, forced like production. */
const FORCED = [
	'user_setting',
	'account',
	'ledger_txn',
	'balance_snapshot',
	'bill',
	'bill_payment'
];

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

/** The database as it was before wallets: migrations 0000 to 0024 applied one by one and recorded as the runner records them. */
async function applyEarlier(handle: DbHandle) {
	await handle.owner.exec(
		`CREATE TABLE "__botler_migrations" (tag text PRIMARY KEY, hash text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`
	);
	const journal = JSON.parse(
		readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
	) as { entries: { tag: string }[] };
	for (const { tag } of journal.entries.filter((e) => e.tag < '0025')) {
		const file = readFileSync(join(MIGRATIONS_DIR, `${tag}.sql`), 'utf8');
		// One query holds the whole file, so it runs in one transaction as the runner runs it (a temp table lives to the end of it)
		await handle.owner.exec(file.replaceAll('--> statement-breakpoint', ''));
		const hash = createHash('sha256').update(file.replaceAll('\r\n', '\n')).digest('hex');
		await handle.owner.query(`INSERT INTO "__botler_migrations" (tag, hash) VALUES ($1, $2)`, [
			tag,
			hash
		]);
	}
}

/** Old shaped data: a peso person with no settings row, a yen person with one, and a dollar person with a transfer between two accounts. */
async function seedOld(handle: DbHandle) {
	const q = handle.owner.query.bind(handle.owner);
	for (const u of ['u_php', 'u_jpy', 'u_usd'])
		await q(`INSERT INTO "user" (id, name, email) VALUES ($1, $1, $1 || '@example.com')`, [u]);
	await q(`INSERT INTO user_setting (user_id, currency) VALUES ('u_jpy', 'JPY'), ('u_usd', 'USD')`);
	for (const [u, n] of [
		['u_php', 'RCBC'],
		['u_jpy', 'Cash'],
		['u_usd', 'Wise'],
		['u_usd', 'Chase']
	] as const)
		await q(`INSERT INTO account (id, user_id, name) VALUES (gen_random_uuid(), $1, $2)`, [u, n]);
	const acct = async (u: string, n: string) =>
		(await q<{ id: string }>(`SELECT id FROM account WHERE user_id = $1 AND name = $2`, [u, n]))[0]
			?.id as string;
	await q(
		`INSERT INTO ledger_txn (user_id, type, account_id, amount) VALUES ('u_php', 'expense', $1, 18000)`,
		[await acct('u_php', 'RCBC')]
	);
	await q(
		`INSERT INTO ledger_txn (user_id, type, account_id, amount) VALUES ('u_jpy', 'income', $1, 5000)`,
		[await acct('u_jpy', 'Cash')]
	);
	await q(
		`INSERT INTO ledger_txn (user_id, type, account_id, to_account_id, amount, fee) VALUES ('u_usd', 'transfer', $1, $2, 2500, 25)`,
		[await acct('u_usd', 'Wise'), await acct('u_usd', 'Chase')]
	);
	await q(`INSERT INTO balance_snapshot (user_id, account_id, amount) VALUES ('u_usd', $1, 9999)`, [
		await acct('u_usd', 'Wise')
	]);
	await q(
		`INSERT INTO bill (id, user_id, name, account_id, kind, amount, schedule) VALUES (gen_random_uuid(), 'u_jpy', 'Rent', $1, 'fixed', 80000, '{}'::jsonb)`,
		[await acct('u_jpy', 'Cash')]
	);
	await q(
		`INSERT INTO bill_payment (user_id, bill_id, due_date, amount) SELECT 'u_jpy', id, '2026-10-01', 80000 FROM bill WHERE user_id = 'u_jpy'`
	);
}

/** The state production is in before this migration: row level security forced, the owner left with no policy on these tables. */
async function forceLikeProduction(handle: DbHandle) {
	for (const t of FORCED) {
		await handle.owner.exec(`ALTER TABLE "${t}" ENABLE ROW LEVEL SECURITY`);
		await handle.owner.exec(`ALTER TABLE "${t}" FORCE ROW LEVEL SECURITY`);
	}
}

/** Reads as the superuser, so forced row level security does not hide the rows being checked. */
async function check(database: string) {
	const reader = new pg.Client({ connectionString: urlFor(database) });
	await reader.connect();
	try {
		const q = async <T extends Record<string, unknown>>(sql: string): Promise<T[]> =>
			(await reader.query(sql)).rows as T[];
		const currencies = async (table: string, user: string) =>
			(
				await q<{ currency: string }>(`SELECT currency FROM ${table} WHERE user_id = '${user}'`)
			).map((r) => r.currency);
		// Every seeded row is seen first, so an empty read cannot pass the lines below by itself
		expect(await q(`SELECT 1 FROM account`)).toHaveLength(4);
		expect(await currencies('account', 'u_php')).toEqual(['PHP']);
		expect(await currencies('account', 'u_jpy')).toEqual(['JPY']);
		expect(await currencies('account', 'u_usd')).toEqual(['USD', 'USD']);
		expect(await currencies('ledger_txn', 'u_php')).toEqual(['PHP']);
		expect(await currencies('ledger_txn', 'u_jpy')).toEqual(['JPY']);
		expect(await currencies('ledger_txn', 'u_usd')).toEqual(['USD']);
		expect(await currencies('balance_snapshot', 'u_usd')).toEqual(['USD']);
		expect(await currencies('bill', 'u_jpy')).toEqual(['JPY']);
		expect(await currencies('bill_payment', 'u_jpy')).toEqual(['JPY']);
		expect(await q(`SELECT 1 FROM account WHERE currency IS NULL`)).toHaveLength(0);
		// The old transfer lands in the currency it left in, with no separate amount
		const transfer = await q<{ to_currency: string; to_amount: string | null }>(
			`SELECT to_currency, to_amount FROM ledger_txn WHERE type = 'transfer'`
		);
		expect(transfer).toEqual([{ to_currency: 'USD', to_amount: null }]);
		// Amounts are untouched
		expect(
			(await q<{ amount: string }>(`SELECT amount FROM ledger_txn ORDER BY amount`)).map((r) =>
				Number(r.amount)
			)
		).toEqual([2500, 5000, 18000]);
		// One wallet for each account and currency it holds
		const wallets = await q<{ user_id: string; currency: string }>(
			`SELECT user_id, currency FROM account_wallet ORDER BY user_id, currency`
		);
		expect(wallets).toEqual([
			{ user_id: 'u_jpy', currency: 'JPY' },
			{ user_id: 'u_php', currency: 'PHP' },
			{ user_id: 'u_usd', currency: 'USD' },
			{ user_id: 'u_usd', currency: 'USD' }
		]);
		// The wallet table is now bound by row level security like the others
		const forced = await q<{ relname: string; relforcerowsecurity: boolean }>(
			`SELECT relname, relforcerowsecurity FROM pg_class WHERE relname = ANY ($$${'{'}${[...FORCED, 'account_wallet'].join(',')}${'}'}$$::text[]) ORDER BY relname`
		);
		for (const r of forced) expect(r.relforcerowsecurity, r.relname).toBe(true);
		expect(forced).toHaveLength(FORCED.length + 1);
	} finally {
		await reader.end();
	}
}

// -- TESTS -- //

describe('migration 0025', () => {
	it('gives every old row its person currency, never pesos by default, under forced row level security (plain owner)', async () => {
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
			await seedOld(handle);
			await forceLikeProduction(handle);
			await migrateLocked(handle);
			await check(name);
		} finally {
			await handle.close();
		}
	});

	it('does the same as the postgres superuser', async () => {
		const name = `botler_test_${randomBytes(6).toString('hex')}`;
		made.databases.push(name);
		await admin.query(`CREATE DATABASE "${name}"`);
		const handle = createPostgres({ ownerUrl: urlFor(name), switchRole: false, poolMax: 2 });
		try {
			await applyEarlier(handle);
			await seedOld(handle);
			await migrateLocked(handle);
			await check(name);
		} finally {
			await handle.close();
		}
	});
});
