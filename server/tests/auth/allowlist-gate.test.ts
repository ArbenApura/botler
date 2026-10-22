// THE ALLOW-LIST GATE INSIDE BETTER AUTH: A NON-LISTED ADDRESS NEVER GETS A USER ROW, AND A PERSON REMOVED FROM THE LIST CANNOT START A SESSION.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { parseAllowList } from '../../src/lib/server/auth/allowlist';
import { createAuth } from '../../src/lib/server/auth/auth';
import { user } from '../../src/lib/server/db/schema';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

// The adapter takes an optional request context as its second argument; tests have none
const NO_CTX = undefined as never;

// -- STATES -- //

let t: TestDb;
let allowed: Awaited<ReturnType<typeof makeAuth>>;

// -- FUNCTIONS -- //

function makeAuth(handle: TestDb['handle'], list: string) {
	return createAuth({
		handle,
		config: {
			secret: 'x'.repeat(40),
			baseUrl: 'http://localhost:5280',
			google: { clientId: 'id', clientSecret: 'secret' },
			allow: parseAllowList(list),
			disableRateLimit: true
		}
	}).$context.then((ctx) => ctx.internalAdapter);
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	allowed = await makeAuth(t.handle, 'arben@example.com');
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('closed registration', () => {
	it('creates a user for a listed address, in any case', async () => {
		const created = await allowed.createUser({ email: 'Arben@Example.com', name: 'Arben' }, NO_CTX);
		expect(created.email.toLowerCase()).toBe('arben@example.com');
	});

	it('refuses a stranger before any row exists', async () => {
		await expect(
			allowed.createUser({ email: 'stranger@example.com', name: 'S' }, NO_CTX)
		).rejects.toThrow();
		const rows = await t.handle.db.select().from(user);
		expect(rows.map((r) => r.email.toLowerCase())).toEqual(['arben@example.com']);
	});

	it('refuses a session for a person who is no longer on the list', async () => {
		await t.handle.db
			.insert(user)
			.values({ id: 'user_old_000001', name: 'Old', email: 'old@example.com' });
		await expect(allowed.createSession('user_old_000001')).rejects.toThrow();
	});

	it('still lets a listed person start a session', async () => {
		const [arben] = await t.handle.db.select().from(user);
		const session = await allowed.createSession(arben!.id);
		expect(session.userId).toBe(arben!.id);
	});
});
