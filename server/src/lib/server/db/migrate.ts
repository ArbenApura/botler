// MIGRATION RUNNER. APPLIES THE DRIZZLE SQL FILES IN ORDER AS THE OWNER, THEN THE ROLES, GRANTS AND ROW LEVEL SECURITY.

// -- TYPES -- //
import type { DbHandle } from './client';
import type { SqlExecutor } from './executor';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
// -- MODULES -- //
import { securityStatements } from './security';

// -- CONSTANTS -- //

export const MIGRATIONS_DIR = join(process.cwd(), 'src', 'lib', 'server', 'db', 'migrations');

// -- TYPES -- //

type Journal = { entries: { tag: string; when: number }[] };

// -- FUNCTIONS -- //

/**
 * Runs every migration that has not run yet, each in its own transaction, then the security statements.
 * Returns the tags it applied. A migration file that changed after it ran is refused loudly.
 */
export async function migrate(db: SqlExecutor, dir = MIGRATIONS_DIR): Promise<string[]> {
	await db.exec(
		`CREATE TABLE IF NOT EXISTS "__botler_migrations" (tag text PRIMARY KEY, hash text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`
	);
	const journal = JSON.parse(readFileSync(join(dir, 'meta', '_journal.json'), 'utf8')) as Journal;
	const done = new Map(
		(
			await db.query<{ tag: string; hash: string }>(`SELECT tag, hash FROM "__botler_migrations"`)
		).map((r) => [r.tag, r.hash])
	);
	const applied: string[] = [];
	for (const { tag } of journal.entries) {
		const file = readFileSync(join(dir, `${tag}.sql`), 'utf8');
		// Line endings are normalised, so a checkout on Windows (CRLF) and one on Linux (LF) hash the same
		const hash = createHash('sha256').update(file.replaceAll('\r\n', '\n')).digest('hex');
		const seen = done.get(tag);
		if (seen) {
			if (seen !== hash)
				throw new Error(
					`Migration ${tag} changed after it was applied. Write a new migration instead.`
				);
			continue;
		}
		const statements = file
			.split('--> statement-breakpoint')
			.map((s) => s.trim())
			.filter(Boolean);
		await db.exec('BEGIN');
		try {
			for (const s of statements) await db.exec(s);
			await db.query(`INSERT INTO "__botler_migrations" (tag, hash) VALUES ($1, $2)`, [tag, hash]);
			await db.exec('COMMIT');
		} catch (e) {
			await db.exec('ROLLBACK');
			throw new Error(`Migration ${tag} failed: ${e instanceof Error ? e.message : String(e)}`, {
				cause: e
			});
		}
		applied.push(tag);
	}
	await secure(db);
	return applied;
}

/** Roles, grants and forced row level security. Safe to run again, and run after every migration. */
export async function secure(db: SqlExecutor): Promise<void> {
	for (const s of securityStatements()) await db.exec(s);
}

/** An arbitrary constant: the advisory lock key that serialises migrations of this database. */
const MIGRATION_LOCK = 727274;

/**
 * Migrates on one pinned owner connection under an advisory lock. Two processes started together (a rolling deploy, a second
 * container) wait for each other instead of applying the same migration twice, and each transaction stays on one connection.
 */
export async function migrateLocked(handle: DbHandle, dir = MIGRATIONS_DIR): Promise<string[]> {
	const pinned = await handle.pinOwner();
	try {
		await pinned.exec(`select pg_advisory_lock(${MIGRATION_LOCK})`);
		try {
			return await migrate(pinned, dir);
		} finally {
			await pinned.exec(`select pg_advisory_unlock(${MIGRATION_LOCK})`);
		}
	} finally {
		pinned.release();
	}
}
