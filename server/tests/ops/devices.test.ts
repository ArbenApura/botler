// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { device, user } from '../../src/lib/server/db/schema';
import { OpsError } from '../../src/lib/server/ops/context';
import { listDevices, registerDevice, unregisterDevice } from '../../src/lib/server/ops/devices';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let anna: Ctx;
let ben: Ctx;
let counter = 0;

// -- FUNCTIONS -- //

/** The same person with a fresh request id, as the app sends one per write. */
const w = (ctx: Ctx): Ctx => ({ ...ctx, requestId: `req-device-${++counter}-0000` });

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_anna_0001', name: 'Anna', email: 'anna@example.com' },
		{ id: 'user_ben_00001', name: 'Ben', email: 'ben@example.com' }
	]);
	anna = { handle: t.handle, actor: { userId: 'user_anna_0001', kind: 'person' } };
	ben = { handle: t.handle, actor: { userId: 'user_ben_00001', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('device verbs', () => {
	it('registers a phone and never returns the push token', async () => {
		const row = await registerDevice(w(anna), {
			platform: 'android',
			pushToken: 'token-anna-0123456789',
			label: 'Anna phone'
		});
		expect(row.label).toBe('Anna phone');
		expect(Object.keys(row)).not.toContain('pushToken');
	});

	it('refreshes the same token instead of adding a second row', async () => {
		await registerDevice(w(anna), {
			platform: 'android',
			pushToken: 'token-anna-0123456789',
			label: 'Anna new name'
		});
		const rows = await listDevices(anna);
		expect(rows).toHaveLength(1);
		expect(rows[0]?.label).toBe('Anna new name');
	});

	it("keeps one person from seeing or removing another person's phone", async () => {
		expect(await listDevices(ben)).toHaveLength(0);
		const [annaPhone] = await listDevices(anna);
		await expect(unregisterDevice(w(ben), { deviceId: annaPhone!.id })).rejects.toBeInstanceOf(
			OpsError
		);
		expect(await listDevices(anna)).toHaveLength(1);
	});

	it('hides rows from the runtime role without a user context', async () => {
		// Runs as app_runtime with no app.user_id set, so row level security hides every row
		const [res] = await t.handle.db.select({ n: sql<number>`count(*)::int` }).from(device);
		expect(res?.n).toBe(0);
	});

	it('refuses a write that has no request id', async () => {
		await expect(
			registerDevice(anna, { platform: 'android', pushToken: 'token-anna-0123456789', label: 'x' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('removes a phone on sign out and refuses a bad input', async () => {
		const [annaPhone] = await listDevices(anna);
		await unregisterDevice(w(anna), { deviceId: annaPhone!.id });
		expect(await listDevices(anna)).toHaveLength(0);
		await expect(
			registerDevice(w(anna), { platform: 'android', pushToken: 'short', label: '' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});
