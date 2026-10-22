// A THROWAWAY DATABASE FOR TESTS. IT LIVES IN BOTLER'S OWN LOCAL POSTGRES (docker compose up -d, port 5434), NEVER IN AFB'S (5433) OR ON THE VPS.
// Each call creates a new database with a random name, migrates it, and drops it again in close().

// -- TYPES -- //
import type { DbHandle } from '../../src/lib/server/db/client';
// -- DEP-MODULES -- //
import { randomBytes } from 'node:crypto';
import pg from 'pg';
// -- MODULES -- //
import { createPostgres } from '../../src/lib/server/db/client';
import { migrateLocked } from '../../src/lib/server/db/migrate';

// -- CONSTANTS -- //

const ADMIN_URL =
	process.env.TEST_PG_ADMIN_URL ??
	'postgres://postgres:localpostgrespassword@127.0.0.1:5434/postgres';
const RUNTIME_PASSWORD = process.env.TEST_PG_RUNTIME_PASSWORD ?? 'localruntimepassword';

// -- TYPES -- //

export type TestDb = {
	handle: DbHandle;
	name: string;
	/** Closes the pools and drops the database. */
	close(): Promise<void>;
};

// -- FUNCTIONS -- //

function withDatabase(url: string, name: string, user?: string, password?: string): string {
	const u = new URL(url);
	u.pathname = `/${name}`;
	if (user) u.username = user;
	if (password) u.password = password;
	return u.toString();
}

/** Creates a migrated throwaway database. The app connects as app_runtime, as in production. */
export async function createTestDb(): Promise<TestDb> {
	const name = `botler_test_${randomBytes(6).toString('hex')}`;
	const admin = new pg.Client({ connectionString: ADMIN_URL });
	try {
		await admin.connect();
	} catch (e) {
		throw new Error(
			`The test Postgres is not reachable. Start Botler's own one with "docker compose up -d" in the repo root (port 5434). ${e instanceof Error ? e.message : ''}`,
			{ cause: e }
		);
	}
	// A connection the server drops (for example when the test database is dropped with FORCE) must not become an unhandled error
	admin.on('error', () => undefined);
	await admin.query(`CREATE DATABASE "${name}"`);
	const handle = createPostgres({
		ownerUrl: withDatabase(ADMIN_URL, name),
		runtimeUrl: withDatabase(ADMIN_URL, name, 'app_runtime', RUNTIME_PASSWORD),
		switchRole: false,
		poolMax: 4
	});
	await migrateLocked(handle);
	return {
		handle,
		name,
		close: async () => {
			await handle.close();
			// Only a database this call created, named with the random prefix, is ever dropped
			if (/^botler_test_[0-9a-f]{12}$/.test(name))
				await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
			await admin.end();
		}
	};
}
