// MIGRATION 0029 (THE MODEL SERVER CHOICE): OLD user_setting ROWS ARE KEPT AND START ON THE SERVER DEFAULT (NULL), THE CHECK ACCEPTS ONLY THE TWO SELECTABLE
// PROVIDERS, AND THE AUDIT TRIGGER NOW COPIES THE CHOICE. RUN AS A PLAIN OWNER BOUND BY FORCED ROW LEVEL SECURITY, ON A DATABASE BUILT UP TO 0028 FIRST.

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

/** The database as it was before this migration: the runner itself, over a copy of the journal that stops at 0028. */
async function applyEarlier(handle: DbHandle) {
	const dir = mkdtempSync(join(tmpdir(), 'botler-mig-'));
	try {
		mkdirSync(join(dir, 'meta'));
		const journal = JSON.parse(
			readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
		) as { entries: { tag: string }[] };
		const earlier = journal.entries.filter((e) => e.tag < '0029_');
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

describe('migration 0029', () => {
	it('keeps old settings rows on the server default, limits the choice and audits it', async () => {
		const suffix = randomBytes(6).toString('hex');
		const role = `botler_mig_${suffix}`;
		const name = `botler_test_${suffix}`;
		made.roles.push(role);
		made.databases.push(name);
		await admin.query(`CREATE ROLE "${role}" LOGIN PASSWORD 'migpass' NOSUPERUSER NOBYPASSRLS`);
		await admin.query(`CREATE DATABASE "${name}" OWNER "${role}"`);
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
			// An old row, planted by the owner with the wall lifted only for that insert
			await q(`ALTER TABLE user_setting NO FORCE ROW LEVEL SECURITY`);
			await q(`INSERT INTO "user" (id, name, email) VALUES ('u_old', 'Old', 'old@example.com')`);
			await q(
				`INSERT INTO user_setting (user_id, currency, language) VALUES ('u_old', 'USD', 'fil')`
			);
			await q(`ALTER TABLE user_setting FORCE ROW LEVEL SECURITY`);
			await migrateLocked(handle);

			const reader = new pg.Client({ connectionString: urlFor(name) });
			await reader.connect();
			try {
				const rows = (
					await reader.query(`SELECT currency, language, model_provider FROM user_setting`)
				).rows;
				expect(rows).toEqual([{ currency: 'USD', language: 'fil', model_provider: null }]);
				// Only the two selectable hosts pass; unknown is for usage rows and is not a choice
				await reader.query(`UPDATE user_setting SET model_provider = 'deepseek'`);
				await reader.query(`UPDATE user_setting SET model_provider = NULL`);
				for (const bad of ['unknown', 'gpt'])
					await expect(
						reader.query(`UPDATE user_setting SET model_provider = '${bad}'`)
					).rejects.toThrow();
				// The trigger now copies the choice, and the table is still bound by row level security
				const trigger = (
					await reader.query(
						`SELECT pg_get_triggerdef(oid) AS def FROM pg_trigger WHERE tgname = 'audit_user_setting'`
					)
				).rows;
				expect(trigger).toHaveLength(1);
				expect(trigger[0].def).toContain('model_provider');
				const forced = (
					await reader.query(
						`SELECT relforcerowsecurity FROM pg_class WHERE relname = 'user_setting'`
					)
				).rows;
				expect(forced).toEqual([{ relforcerowsecurity: true }]);
			} finally {
				await reader.end();
			}
		} finally {
			await handle.close();
		}
	});
});
