// MIGRATION 0037 (THE NOTEBOOK LIBRARY): EACH EXISTING EXTRA NOTEBOOK, LIVE OR DELETED, BECOMES A PAGE TITLED "Overview" WITH ITS TEXT AND ITS REVISIONS,
// THE MAIN NOTEBOOK IS LEFT ALONE, THE OLD TEXT COLUMN IS EMPTIED ONLY AFTER A CHECK, AND THE ROW LEVEL SECURITY OF THE OLD TABLES IS FORCED AGAIN.
// Run as a plain owner bound by forced row level security (how production runs), where the owner sees none of the old rows unless the migration lifts it.

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

/** The database as it was before this migration: the runner itself, over a copy of the journal that stops at 0036. */
async function applyEarlier(handle: DbHandle) {
	const dir = mkdtempSync(join(tmpdir(), 'botler-mig-'));
	try {
		mkdirSync(join(dir, 'meta'));
		const journal = JSON.parse(
			readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
		) as { entries: { tag: string }[] };
		const earlier = journal.entries.filter((e) => e.tag < '0037_');
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

/** A database owned by a plain role, with the migrations up to 0036 applied, and a superuser connection to plant and read rows. */
async function oldDatabase() {
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
	await applyEarlier(handle);
	const sup = new pg.Client({ connectionString: urlFor(name) });
	await sup.connect();
	return { handle, sup, name };
}

// -- TESTS -- //

describe('migration 0037', () => {
	it('turns each extra notebook, live or deleted, into an Overview page with its text and revisions, and leaves the main notebook alone', async () => {
		const { handle, sup } = await oldDatabase();
		try {
			for (const u of ['u_a', 'u_b'])
				await sup.query(
					`INSERT INTO "user" (id, name, email) VALUES ('${u}', '${u}', '${u}@example.com')`
				);
			const book = async (
				u: string,
				kind: string,
				title: string,
				text: string,
				version: number,
				by: string,
				deleted = false
			) =>
				(
					await sup.query<{ id: string }>(
						`INSERT INTO notebook (user_id, kind, title, summary, text, version, updated_by, deleted_at)
						 VALUES ($1, $2, $3, 'sum', $4, $5, $6, ${deleted ? "now() - interval '3 days'" : 'NULL'}) RETURNING id`,
						[u, kind, title, text, version, by]
					)
				).rows[0]?.id ?? '';
			const revision = (
				u: string,
				notebook: string,
				version: number,
				text: string,
				actor: string
			) =>
				sup.query(
					`INSERT INTO notebook_revision (user_id, notebook_id, version, text, actor, ref) VALUES ($1, $2, $3::int, $4, $5, 'ref-' || $3::text)`,
					[u, notebook, version, text, actor]
				);
			const mainA = await book('u_a', 'main', '', '# About you\n- tea', 4, 'user');
			const trip = await book('u_a', 'extra', 'Trip', 'Flights and hotels ünïcode ✓', 3, 'agent');
			const old = await book('u_a', 'extra', 'Old', 'Deleted but kept', 2, 'user', true);
			const empty = await book('u_a', 'extra', 'Empty', '', 1, 'seed');
			const other = await book('u_b', 'extra', 'Other', 'Not yours', 5, 'user');
			await revision('u_a', mainA, 1, 'main before', 'user');
			await revision('u_a', trip, 1, 'trip v1', 'user');
			await revision('u_a', trip, 2, 'trip v2 longer', 'agent');
			await revision('u_a', old, 1, 'old v1', 'user');
			await revision('u_b', other, 4, 'other v4', 'user');

			await migrateLocked(handle);

			const pages = (
				await sup.query<{
					user_id: string;
					notebook_id: string;
					title: string;
					text: string;
					version: number;
					seen_version: number;
					updated_by: string;
					parent_page_id: string | null;
					deleted_at: Date | null;
				}>(`SELECT * FROM notebook_page ORDER BY user_id, text`)
			).rows;
			expect(pages).toHaveLength(4);
			expect(pages.every((p) => p.title === 'Overview' && p.parent_page_id === null)).toBe(true);
			const of = (id: string) => pages.find((p) => p.notebook_id === id);
			expect(of(trip)).toMatchObject({
				user_id: 'u_a',
				text: 'Flights and hotels ünïcode ✓',
				version: 3,
				seen_version: 3,
				updated_by: 'agent',
				deleted_at: null
			});
			expect(of(old)).toMatchObject({ text: 'Deleted but kept', version: 2 });
			expect(of(empty)).toMatchObject({ text: '', version: 1, updated_by: 'seed' });
			expect(of(other)).toMatchObject({ user_id: 'u_b', text: 'Not yours', version: 5 });
			expect(of(mainA)).toBeUndefined();

			const revs = (
				await sup.query<{
					user_id: string;
					notebook_id: string;
					version: number;
					text: string;
					actor: string;
					ref: string;
				}>(
					`SELECT r.user_id, p.notebook_id, r.version, r.text, r.actor, r.ref
					 FROM notebook_page_revision r JOIN notebook_page p ON p.id = r.page_id ORDER BY r.user_id, p.notebook_id, r.version`
				)
			).rows;
			expect(revs.map((r) => `${r.text}|${r.version}|${r.actor}|${r.ref}`).sort()).toEqual(
				[
					'trip v1|1|user|ref-1',
					'trip v2 longer|2|agent|ref-2',
					'old v1|1|user|ref-1',
					'other v4|4|user|ref-4'
				].sort()
			);
			// The main notebook keeps its text and its revisions; the extras' old text column is emptied, their old revisions are kept
			const books = (
				await sup.query<{ id: string; text: string; kind: string }>(
					`SELECT id, text, kind FROM notebook`
				)
			).rows;
			expect(books.find((b) => b.id === mainA)?.text).toBe('# About you\n- tea');
			expect(books.filter((b) => b.kind === 'extra').every((b) => b.text === '')).toBe(true);
			expect(
				Number((await sup.query(`SELECT count(*)::int AS n FROM notebook_revision`)).rows[0]?.n)
			).toBe(5);
			// The old tables are bound by forced row level security again, and so are the new ones
			const forced = (
				await sup.query<{ relname: string; relforcerowsecurity: boolean }>(
					`SELECT relname, relforcerowsecurity FROM pg_class
					 WHERE relname IN ('notebook', 'notebook_revision', 'notebook_page', 'notebook_page_revision') ORDER BY relname`
				)
			).rows;
			expect(forced.map((f) => f.relforcerowsecurity)).toEqual([true, true, true, true]);
		} finally {
			await sup.end();
			await handle.close();
		}
	});

	it('stops and rolls back when the copy does not match the originals', async () => {
		const { handle, sup } = await oldDatabase();
		try {
			await migrateLocked(handle);
			// The check is one statement in the migration file: run it against a database where an extra notebook has no page
			const file = readFileSync(join(MIGRATIONS_DIR, '0037_notebook_pages.sql'), 'utf8').replaceAll(
				'\r\n',
				'\n'
			);
			const check = /DO \$\$[\s\S]*?END \$\$;/.exec(file)?.[0];
			expect(check).toBeTruthy();
			await sup.query(
				`INSERT INTO "user" (id, name, email) VALUES ('u_c', 'u_c', 'u_c@example.com')`
			);
			await sup.query(
				`INSERT INTO notebook (user_id, kind, title, text) VALUES ('u_c', 'extra', 'Lonely', 'a page is missing')`
			);
			await expect(sup.query(check ?? '')).rejects.toThrow(/does not match/);
			// With a page of the same length the check passes
			await sup.query(
				`INSERT INTO notebook_page (user_id, notebook_id, title, text) SELECT user_id, id, 'Overview', text FROM notebook WHERE title = 'Lonely'`
			);
			await sup.query(`UPDATE notebook SET text = '' WHERE title = 'Lonely'`);
			// The old text is gone, so the sums differ the other way round: the page is longer than the (now empty) original
			await expect(sup.query(check ?? '')).rejects.toThrow(/does not match/);
		} finally {
			await sup.end();
			await handle.close();
		}
	});
});
