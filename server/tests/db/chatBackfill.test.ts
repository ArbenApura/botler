// MIGRATION 0021 (CONVERSATIONS): EVERY EXISTING TURN GETS A CHAT, ONE PER "NEW CHAT" BATCH PLUS THE LIVE ONE, A TURN LEFT RUNNING JOINS THE BATCH IT PREDATES,
// A PERSON WHOSE LAST ACT WAS "NEW CHAT" OPENS ON AN EMPTY CHAT, AND A PERSON WITH NO TURNS GETS NO CHAT. IT IS RUN TWICE: AS THE POSTGRES SUPERUSER, AND AS A
// PLAIN OWNER THAT IS BOUND BY FORCED ROW LEVEL SECURITY (HOW PRODUCTION RUNS), WHICH IS WHAT THE "NO FORCE" STEP OF THE MIGRATION IS FOR.

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

/** The database as it was before conversations: migrations 0000 to 0020 applied one by one and recorded as the runner records them. */
async function applyEarlier(handle: DbHandle) {
	await handle.owner.exec(
		`CREATE TABLE "__botler_migrations" (tag text PRIMARY KEY, hash text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`
	);
	const journal = JSON.parse(
		readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
	) as { entries: { tag: string }[] };
	for (const { tag } of journal.entries.filter((e) => e.tag < '0021')) {
		const file = readFileSync(join(MIGRATIONS_DIR, `${tag}.sql`), 'utf8');
		for (const st of file
			.split('--> statement-breakpoint')
			.map((x) => x.trim())
			.filter(Boolean))
			await handle.owner.exec(st);
		const hash = createHash('sha256').update(file.replaceAll('\r\n', '\n')).digest('hex');
		await handle.owner.query(`INSERT INTO "__botler_migrations" (tag, hash) VALUES ($1, $2)`, [
			tag,
			hash
		]);
	}
}

/** The state production is in before this migration: row level security forced on the turns, the owner left with its two narrow policies only. */
async function forceLikeProduction(handle: DbHandle) {
	await handle.owner.exec(`ALTER TABLE "chat_turn" ENABLE ROW LEVEL SECURITY`);
	await handle.owner.exec(`ALTER TABLE "chat_turn" FORCE ROW LEVEL SECURITY`);
	for (const [name, command] of [
		['owner_reset_read', 'SELECT'],
		['owner_reset_delete', 'DELETE']
	] as const)
		await handle.owner.exec(
			`DO $$ BEGIN EXECUTE format('CREATE POLICY ${name} ON "chat_turn" FOR ${command} TO %I USING (user_id = nullif(current_setting(''app.user_id'', true), ''''))', current_user); END $$`
		);
}

/** Old-shaped data, in the middle of a history that has been through "new chat" twice. */
async function seedOld(handle: DbHandle) {
	const q = handle.owner.query.bind(handle.owner);
	for (const u of ['u_a', 'u_b', 'u_c', 'u_d', 'u_e'])
		await q(`INSERT INTO "user" (id, name, email) VALUES ($1, $1, $1 || '@example.com')`, [u]);
	const turn = (user: string, id: string, at: string, cleared: string | null, status = 'done') =>
		q(
			`INSERT INTO chat_turn (user_id, client_message_id, user_text, status, created_at, cleared_at) VALUES ($1, $2, $2, $3, $4, $5)`,
			[user, id, status, at, cleared]
		);
	const t1 = '2026-10-01T10:00:00Z';
	const t2 = '2026-10-05T10:00:00Z';
	// A: two batches, a turn left running before the first clear, and live turns
	await turn('u_a', 'a1', '2026-10-01T08:00:00Z', t1);
	await turn('u_a', 'a2', '2026-10-01T08:30:00Z', t1);
	await turn('u_a', 'a3-running', '2026-10-01T09:00:00Z', null, 'running');
	await turn('u_a', 'a4', '2026-10-04T08:00:00Z', t2);
	await turn('u_a', 'a5', '2026-10-06T08:00:00Z', null);
	// B: everything was set aside, nothing said since
	await turn('u_b', 'b1', '2026-10-02T08:00:00Z', t1);
	// D: a single turn that is still running, never set aside
	await turn('u_d', 'd1-running', '2026-10-03T08:00:00Z', null, 'running');
	// E: set aside at the very same moment as A (another person's batch must never mix with it)
	await turn('u_e', 'e1', '2026-10-01T08:10:00Z', t1);
	await turn('u_e', 'e2', '2026-10-06T08:10:00Z', null);
}

/** Reads as the superuser, so forced row level security does not hide the rows being checked. */
async function check(database: string) {
	const reader = new pg.Client({ connectionString: urlFor(database) });
	await reader.connect();
	try {
		await checkWith(reader);
	} finally {
		await reader.end();
	}
}

async function checkWith(reader: pg.Client) {
	const q = async <T extends Record<string, unknown>>(sql: string): Promise<T[]> =>
		(await reader.query(sql)).rows as T[];
	const rows = await q<{ user_id: string; client_message_id: string; chat_id: string }>(
		`SELECT user_id, client_message_id, chat_id FROM chat_turn ORDER BY client_message_id`
	);
	const chatOf = Object.fromEntries(rows.map((r) => [r.client_message_id, r.chat_id]));
	// Every one of the nine seeded turns is seen (an empty read would pass the next line by itself)
	expect(rows).toHaveLength(9);
	expect(rows.every((r) => r.chat_id)).toBe(true);
	expect(chatOf['a1']).toBe(chatOf['a2']);
	expect(chatOf['a3-running']).toBe(chatOf['a1']);
	expect(new Set([chatOf['a1'], chatOf['a4'], chatOf['a5']]).size).toBe(3);
	// The same moment for two people does not put them in one chat
	expect(chatOf['e1']).not.toBe(chatOf['a1']);

	const chats = await q<{ user_id: string; id: string }>(
		`SELECT user_id, id FROM chat ORDER BY last_active_at DESC`
	);
	const of = (u: string) => chats.filter((c) => c.user_id === u);
	expect(of('u_a')).toHaveLength(3);
	expect(of('u_c')).toHaveLength(0);
	// A opens on the live chat; B opens on an empty chat made for it, with its old chat behind it
	expect(of('u_a')[0]?.id).toBe(chatOf['a5']);
	expect(of('u_b')).toHaveLength(2);
	expect(of('u_b')[0]?.id).not.toBe(chatOf['b1']);
	// D: one live chat holding the running turn, and no stray empty chat
	expect(of('u_d')).toHaveLength(1);
	expect(of('u_d')[0]?.id).toBe(chatOf['d1-running']);
	// E has a live chat, so no empty one is added
	expect(of('u_e')).toHaveLength(2);
	// The foreign key now holds a turn to its chat
	await expect(
		q(`UPDATE chat_turn SET chat_id = gen_random_uuid() WHERE client_message_id = 'a1'`)
	).rejects.toThrow();
}

// -- TESTS -- //

describe('migration 0021', () => {
	it('gives every earlier turn a chat and keeps the order of the batches (superuser)', async () => {
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

	it('does the same as a plain owner that forced row level security binds', async () => {
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
			// Production has been through the runner already: rows are secured and the owner is bound by its own narrow policies
			await forceLikeProduction(handle);
			const forced = await handle.owner.query<{ relforcerowsecurity: boolean }>(
				`SELECT relforcerowsecurity FROM pg_class WHERE relname = 'chat_turn'`
			);
			expect(forced[0]?.relforcerowsecurity).toBe(true);
			await migrateLocked(handle);
			await check(name);
			// And it is forced again afterwards
			const after = await handle.owner.query<{ relforcerowsecurity: boolean }>(
				`SELECT relforcerowsecurity FROM pg_class WHERE relname = 'chat_turn'`
			);
			expect(after[0]?.relforcerowsecurity).toBe(true);
		} finally {
			await handle.close();
		}
	});
});
