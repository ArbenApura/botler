// THE SERVER REFUSES TO RUN REQUESTS AS A ROLE THAT COULD SKIP ROW LEVEL SECURITY, AND ONE MIGRATION RUN AT A TIME IS ENOUGH.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { cpSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createPostgres } from '../../src/lib/server/db/client';
import { MIGRATIONS_DIR, migrateLocked } from '../../src/lib/server/db/migrate';
import { assertRuntimeRole } from '../../src/lib/server/db/tenant';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const ADMIN =
	process.env.TEST_PG_ADMIN_URL ??
	'postgres://postgres:localpostgrespassword@127.0.0.1:5434/postgres';

// -- STATES -- //

let t: TestDb;

// -- FUNCTIONS -- //

const ownerUrl = (database: string) => {
	const url = new URL(ADMIN);
	url.pathname = `/${database}`;
	return url.toString();
};

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('runtime role check', () => {
	it('accepts the app_runtime login', async () => {
		await expect(assertRuntimeRole(t.handle)).resolves.toBeUndefined();
	});

	it('accepts an owner connection that switches to app_runtime for each transaction', async () => {
		const owner = createPostgres({ ownerUrl: ownerUrl(t.name) });
		try {
			await expect(assertRuntimeRole(owner)).resolves.toBeUndefined();
		} finally {
			await owner.close();
		}
	});

	it('refuses a superuser connection that would skip row level security', async () => {
		// switchRole false says "this login is already the runtime role", which is false here: the check must catch it
		const wrong = createPostgres({ ownerUrl: ownerUrl(t.name), switchRole: false });
		try {
			await expect(assertRuntimeRole(wrong)).rejects.toThrow(/must be app_runtime/);
		} finally {
			await wrong.close();
		}
	});
});

describe('migrations', () => {
	it('survive two runs at the same time and apply each migration once', async () => {
		const fresh = await createTestDb();
		try {
			const again = await Promise.all([migrateLocked(fresh.handle), migrateLocked(fresh.handle)]);
			// createTestDb already migrated this database, so both runs have nothing left to apply
			expect(again.flat()).toEqual([]);
			const rows = await fresh.handle.owner.query<{ tag: string }>(
				`select tag from "__botler_migrations"`
			);
			expect(new Set(rows.map((r) => r.tag)).size).toBe(rows.length);
		} finally {
			await fresh.close();
		}
	});

	it('hash the same with Windows line endings', async () => {
		const dir = mkdtempSync(join(tmpdir(), 'botler-mig-'));
		cpSync(MIGRATIONS_DIR, dir, { recursive: true });
		for (const f of readdirSync(dir).filter((n) => n.endsWith('.sql'))) {
			const text = readFileSync(join(dir, f), 'utf8');
			writeFileSync(join(dir, f), text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'));
		}
		// t.handle already ran the LF files; the CRLF copies must not look "changed after they were applied"
		await expect(migrateLocked(t.handle, dir)).resolves.toEqual([]);
	});
});
