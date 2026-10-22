// THE APP'S DATABASE HANDLE: THE POSTGRESQL SERVER IN DATABASE_URL. THE APP STOPS AT START WITHOUT IT, OR WHEN ITS ROLE COULD BYPASS ROW LEVEL SECURITY.

// -- TYPES -- //
import type { DbHandle } from './client';
// -- ENVS -- //
import { BOTLER_AUTO_MIGRATE, DATABASE_OWNER_URL, DATABASE_URL } from '$app/env/private';
// -- MODULES -- //
import { createPostgres } from './client';
import { migrateLocked } from './migrate';
import { RUNTIME_ROLE } from './security';
import { assertRuntimeRole } from './tenant';

// -- STATES -- //

// Kept on globalThis so a hot reload of this module in development reuses the open connections
const shared = globalThis as typeof globalThis & { __botlerDb?: Promise<DbHandle> };

// -- FUNCTIONS -- //

async function open(): Promise<DbHandle> {
	if (!DATABASE_URL)
		throw new Error(
			'DATABASE_URL is required: the PostgreSQL connection of the app as the app_runtime role (see .env.example).'
		);
	const owner = DATABASE_OWNER_URL ?? DATABASE_URL;
	// Only a login that is exactly app_runtime needs no role switch in each transaction. Anything else switches, and is checked below
	const loginIsRuntime =
		!DATABASE_OWNER_URL && decodeURIComponent(new URL(DATABASE_URL).username) === RUNTIME_ROLE;
	const h = createPostgres({
		runtimeUrl: DATABASE_OWNER_URL ? DATABASE_URL : undefined,
		ownerUrl: owner,
		...(loginIsRuntime ? { switchRole: false, poolMax: 5 } : {})
	});
	try {
		if (BOTLER_AUTO_MIGRATE === '1') await migrateLocked(h);
		// Fails loudly when requests would run as a role that skips row level security (a superuser, the owner, BYPASSRLS)
		await assertRuntimeRole(h);
	} catch (e) {
		await h.close().catch(() => undefined);
		throw e;
	}
	return h;
}

/** One handle per server process, opened on first use. A failed open is forgotten, so the next call tries again. */
export function getDb(): Promise<DbHandle> {
	shared.__botlerDb ??= open().catch((e: unknown) => {
		shared.__botlerDb = undefined;
		throw e;
	});
	return shared.__botlerDb;
}
