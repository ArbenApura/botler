// TRANSACTION LOCAL USER CONTEXT. EVERY REQUEST, AGENT TOOL CALL AND JOB RUNS ITS QUERIES THROUGH withUser.
// The setting lives only inside the transaction (set_config with is_local = true), so a pooled connection can never
// carry one person's context into the next call.

// -- TYPES -- //
import type { DbHandle, Tx } from './client';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import pg from 'pg';
// -- MODULES -- //
import { RUNTIME_ROLE } from './security';

// -- CONSTANTS -- //

const USER_ID = /^[A-Za-z0-9_-]{8,64}$/;

// -- FUNCTIONS -- //

/** Refuses anything that is not a plausible user id before it reaches the database. */
export function assertUserId(userId: string): string {
	if (!USER_ID.test(userId)) throw new Error('userId is not a valid user id');
	return userId;
}

/**
 * Runs `fn` in one transaction with the user set and the runtime role active. Without a user, no user row is visible,
 * so a call that forgot its context reads nothing instead of everything.
 */
export async function withUser<T>(
	handle: DbHandle,
	userId: string,
	fn: (tx: Tx) => Promise<T>
): Promise<T> {
	const id = assertUserId(userId);
	return handle.db.transaction(async (tx) => {
		const role = handle.switchRole ? `SET LOCAL ROLE ${RUNTIME_ROLE}; ` : '';
		await tx.execute(
			sql.raw(`${role}select set_config('app.user_id', ${pg.escapeLiteral(id)}, true)`)
		);
		return fn(tx);
	});
}

/**
 * Checks, as the app will run its queries, that the role is app_runtime and can neither skip row level security nor own the
 * tables. A connection string that points at the owner or a superuser would silently remove tenant isolation, so the server
 * refuses to start instead.
 */
export async function assertRuntimeRole(handle: DbHandle): Promise<void> {
	const role = await handle.db.transaction(async (tx) => {
		if (handle.switchRole) await tx.execute(sql.raw(`SET LOCAL ROLE ${RUNTIME_ROLE}`));
		const res = (await tx.execute(
			sql`select current_user as name, r.rolsuper as super, r.rolbypassrls as bypass
				from pg_roles r where r.rolname = current_user`
		)) as unknown as { rows: { name: string; super: boolean; bypass: boolean }[] };
		return res.rows[0];
	});
	if (!role || role.name !== RUNTIME_ROLE || role.super || role.bypass)
		throw new Error(
			`The database role must be ${RUNTIME_ROLE} without superuser or BYPASSRLS, but requests would run as ${role?.name ?? 'an unknown role'}. Check DATABASE_URL.`
		);
}
