// PUSH: ONLY A TOKEN FIREBASE CALLS DEAD (UNREGISTERED, NOT_FOUND) IS FORGOTTEN; A 400 INVALID_ARGUMENT KEEPS THE PHONE AND LOGS NO MESSAGE TEXT

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { generateKeyPairSync } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { listDevices, registerDevice } from '../../src/lib/server/ops/devices';
import { createFcmPusher } from '../../src/lib/server/push/fcm';
import { pushToUser } from '../../src/lib/server/push/send';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();

const fcm = (status: number, body: string) =>
	createFcmPusher({
		projectId: 'p',
		clientEmail: 'e',
		privateKey: pem,
		fetch: (async (url: string) =>
			url === 'https://oauth2.googleapis.com/token'
				? new Response(JSON.stringify({ access_token: 'ya29', expires_in: 3600 }))
				: new Response(body, { status })) as unknown as typeof fetch
	});

async function personWithPhone() {
	const f = await seedPerson(t);
	await registerDevice(
		{ ...f.ctx, requestId: `req-fcm-${String(++n).padStart(6, '0')}` },
		{ platform: 'android', pushToken: `tok-fcm-${n}-${'x'.repeat(20)}`, label: 'Phone' }
	);
	return f;
}

const body400 = (message: string) =>
	JSON.stringify({ error: { code: 400, status: 'INVALID_ARGUMENT', message } });

// -- TESTS -- //

describe('a push Firebase refuses', () => {
	it('keeps the phone on a 400 INVALID_ARGUMENT and logs no message text', async () => {
		const f = await personWithPhone();
		const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const summary = await pushToUser(
			f.ctx,
			fcm(400, body400('Invalid value at message.notification.title: Rent for Maria 123456')),
			{ kind: 'notice', title: 'Rent for Maria 123456 is due' }
		);
		const logged = JSON.stringify(errors.mock.calls);
		errors.mockRestore();
		expect(summary).toEqual({ sent: 0, removed: 0, failed: 1 });
		expect(await listDevices(f.ctx)).toHaveLength(1);
		expect(logged).toContain('push_failed');
		expect(logged).toContain('INVALID_ARGUMENT');
		expect(logged).not.toContain('Maria');
		expect(logged).not.toContain('Rent');
	});

	it('keeps the phone on a 400 that talks about the registration token too', async () => {
		const f = await personWithPhone();
		const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const summary = await pushToUser(
			f.ctx,
			fcm(400, body400('The registration token is not a valid FCM registration token')),
			{ kind: 'sync' }
		);
		errors.mockRestore();
		expect(summary.removed).toBe(0);
		expect(await listDevices(f.ctx)).toHaveLength(1);
	});

	it('forgets the phone when Firebase says UNREGISTERED', async () => {
		const f = await personWithPhone();
		const summary = await pushToUser(
			f.ctx,
			fcm(404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'),
			{ kind: 'sync' }
		);
		expect(summary).toEqual({ sent: 0, removed: 1, failed: 0 });
		expect(await listDevices(f.ctx)).toHaveLength(0);
	});

	it('forgets the phone on a NOT_FOUND status with no detail', async () => {
		const f = await personWithPhone();
		const summary = await pushToUser(f.ctx, fcm(404, '{"error":{"status":"NOT_FOUND"}}'), {
			kind: 'sync'
		});
		expect(summary.removed).toBe(1);
	});

	it('keeps the phone on a server error', async () => {
		const f = await personWithPhone();
		const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const summary = await pushToUser(f.ctx, fcm(503, 'try later'), { kind: 'sync' });
		errors.mockRestore();
		expect(summary).toEqual({ sent: 0, removed: 0, failed: 1 });
		expect(await listDevices(f.ctx)).toHaveLength(1);
	});
});
