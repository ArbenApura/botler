// A THROWAWAY DATABASE THAT IS MIGRATED IN TWO STAGES, FOR TESTING A MIGRATION AGAINST OLD DATA.
// Stage one applies the journal up to (not including) a tag, exactly as the runner records it; the test then seeds old shaped rows; stage two runs the
// rest through the real runner. It can run as a plain owner (not a superuser) with the security statements applied, which is how production runs.

// -- TYPES -- //
import type { DbHandle } from '../../src/lib/server/db/client';
// -- DEP-MODULES -- //
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import pg from 'pg';
// -- MODULES -- //
import { createPostgres } from '../../src/lib/server/db/client';
import { MIGRATIONS_DIR, migrateLocked, secure } from '../../src/lib/server/db/migrate';
import { assertLocalTestPg } from './testDb';

// -- CONSTANTS -- //

const ADMIN_URL =
	process.env.TEST_PG_ADMIN_URL ??
	'postgres://postgres:localpostgrespassword@127.0.0.1:5434/postgres';
const RUNTIME_PASSWORD = process.env.TEST_PG_RUNTIME_PASSWORD ?? 'localruntimepassword';

// -- TYPES -- //

export type StagedDb = {
	handle: DbHandle;
	name: string;
	/** A superuser connection to this database, so forced row level security does not hide the rows being checked. */
	reader(): Promise<pg.Client>;
	/** Applies the security statements as production has them (forced row level security, the owner left with its narrow policies). Call it after seeding. */
	lockDown(): Promise<void>;
	/** Runs every migration not yet applied, as the real runner does, and returns the tags it applied. */
	finish(): Promise<string[]>;
	close(): Promise<void>;
};

// -- FUNCTIONS -- //

function urlFor(database: string, user?: string, password?: string): string {
	const u = new URL(ADMIN_URL);
	u.pathname = `/${database}`;
	if (user) u.username = user;
	if (password) u.password = password;
	return u.toString();
}

/**
 * Creates the database and applies migrations whose tag sorts before `before`. With `plainOwner` the owner is a role that is not a superuser; lockDown() then applies the security statements.
 */
export async function createStagedDb(options: {
	before: string;
	plainOwner?: boolean;
}): Promise<StagedDb> {
	assertLocalTestPg(ADMIN_URL);
	const suffix = randomBytes(6).toString('hex');
	const name = `botler_test_${suffix}`;
	const role = `botler_mig_${suffix}`;
	const admin = new pg.Client({ connectionString: ADMIN_URL });
	await admin.connect();
	admin.on('error', () => undefined);
	// The runtime role is cluster wide; a plain owner cannot create it, so it exists before the migrations run
	await admin.query(
		`DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_runtime') THEN CREATE ROLE app_runtime NOLOGIN NOSUPERUSER NOBYPASSRLS; END IF; END $$`
	);
	if (options.plainOwner) {
		await admin.query(`CREATE ROLE "${role}" LOGIN PASSWORD 'migpass' NOSUPERUSER NOBYPASSRLS`);
		await admin.query(`CREATE DATABASE "${name}" OWNER "${role}"`);
	} else await admin.query(`CREATE DATABASE "${name}"`);
	// The vector extension needs a superuser to install; the owner only finds it there
	const setup = new pg.Client({ connectionString: urlFor(name) });
	await setup.connect();
	await setup.query(`CREATE EXTENSION IF NOT EXISTS vector`);
	await setup.end();
	const handle = createPostgres({
		ownerUrl: options.plainOwner ? urlFor(name, role, 'migpass') : urlFor(name),
		runtimeUrl: urlFor(name, 'app_runtime', RUNTIME_PASSWORD),
		switchRole: false,
		poolMax: 2
	});
	// Stage one, one migration at a time, recorded as the runner records them
	await handle.owner.exec(
		`CREATE TABLE "__botler_migrations" (tag text PRIMARY KEY, hash text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`
	);
	const journal = JSON.parse(
		readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8')
	) as { entries: { tag: string }[] };
	for (const { tag } of journal.entries.filter((e) => e.tag < options.before)) {
		const file = readFileSync(join(MIGRATIONS_DIR, `${tag}.sql`), 'utf8');
		await handle.owner.exec(file.replaceAll('--> statement-breakpoint', ''));
		const hash = createHash('sha256').update(file.replaceAll('\r\n', '\n')).digest('hex');
		await handle.owner.query(`INSERT INTO "__botler_migrations" (tag, hash) VALUES ($1, $2)`, [
			tag,
			hash
		]);
	}
	return {
		handle,
		name,
		lockDown: () => secure(handle.owner, true),
		reader: async () => {
			const c = new pg.Client({ connectionString: urlFor(name) });
			await c.connect();
			return c;
		},
		finish: () => migrateLocked(handle),
		close: async () => {
			await handle.close();
			if (/^botler_test_[0-9a-f]{12}$/.test(name))
				await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
			if (options.plainOwner && /^botler_mig_[0-9a-f]{12}$/.test(role))
				await admin.query(`DROP ROLE IF EXISTS "${role}"`);
			await admin.end();
		}
	};
}
