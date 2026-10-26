// MIGRATIONS 0027 AND 0028 (PROVIDER AND CACHE COLUMNS ON THE USAGE TABLES): EVERY OLD ROW IS KEPT, GETS THE PROVIDER 'unknown' AND COUNTS IN FULL AGAINST THE CAP
// (charged tokens = prompt + completion), AND THE KEYS NOW HOLD ONE ROW PER PROVIDER. RUN AS A PLAIN OWNER BOUND BY FORCED ROW LEVEL SECURITY (HOW PRODUCTION RUNS):
// THE FIRST VERSION OF THIS BACKFILL (IN 0027) MATCHED NO ROWS THERE, WHICH 0028 REPAIRS.

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

/** The database as it was before this migration: the runner itself, over a copy of the journal that stops at 0026. */
async function applyEarlier(handle: DbHandle) {
	const dir = mkdtempSync(join(tmpdir(), 'botler-mig-'));
	try {
		mkdirSync(join(dir, 'meta'));
		const journal = JSON.parse(
			readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
		) as { entries: { tag: string }[] };
		const earlier = journal.entries.filter((e) => e.tag < '0027_');
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

describe('migrations 0027 and 0028', () => {
	it('keep the old rows, count them in full under forced row level security, and allow one row per provider', async () => {
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
			const q = handle.owner.query.bind(handle.owner);
			// The old rows were written by the app before 0027; the owner is lifted only to plant them
			await q(`ALTER TABLE model_usage NO FORCE ROW LEVEL SECURITY`);
			await q(`INSERT INTO "user" (id, name, email) VALUES ('u_old', 'Old', 'old@example.com')`);
			await q(
				`INSERT INTO model_usage (user_id, bucket, month, calls, prompt_tokens, completion_tokens) VALUES ('u_old', 'chat', '2026-10', 3, 30000, 900)`
			);
			await q(`ALTER TABLE model_usage FORCE ROW LEVEL SECURITY`);
			await q(
				`INSERT INTO model_spend (month, bucket, calls, tokens) VALUES ('2026-10', 'chat', 3, 30900)`
			);
			await migrateLocked(handle);

			// Read as the superuser, so the rows being checked are not hidden
			const reader = new pg.Client({ connectionString: urlFor(name) });
			await reader.connect();
			try {
				const usage = (
					await reader.query(
						`SELECT provider, prompt_tokens, completion_tokens, cache_read_tokens, cache_write_tokens, charged_tokens FROM model_usage`
					)
				).rows;
				expect(usage).toEqual([
					{
						provider: 'unknown',
						prompt_tokens: '30000',
						completion_tokens: '900',
						cache_read_tokens: '0',
						cache_write_tokens: '0',
						charged_tokens: '30900'
					}
				]);
				const spend = (
					await reader.query(`SELECT provider, tokens, charged_tokens FROM model_spend`)
				).rows;
				expect(spend).toEqual([{ provider: 'unknown', tokens: '30900', charged_tokens: '30900' }]);
				// The table is bound by row level security again
				const forced = (
					await reader.query(
						`SELECT relforcerowsecurity FROM pg_class WHERE relname = 'model_usage'`
					)
				).rows;
				expect(forced).toEqual([{ relforcerowsecurity: true }]);
				// Another provider in the same month is a new row; the same provider twice is refused
				await reader.query(
					`INSERT INTO model_usage (user_id, bucket, month, provider) VALUES ('u_old', 'chat', '2026-10', 'anthropic')`
				);
				await expect(
					reader.query(
						`INSERT INTO model_usage (user_id, bucket, month, provider) VALUES ('u_old', 'chat', '2026-10', 'anthropic')`
					)
				).rejects.toThrow();
				await expect(
					reader.query(
						`INSERT INTO model_usage (user_id, bucket, month, provider) VALUES ('u_old', 'chat', '2026-10', 'other')`
					)
				).rejects.toThrow();
			} finally {
				await reader.end();
			}
		} finally {
			await handle.close();
		}
	});
});
