// PUSH (P5.3): THE FIREBASE SENDER, AND THE RULE THAT A PUSH NEVER GOES TO A PHONE THAT NOW BELONGS TO SOMEONE ELSE

// -- TYPES -- //
import type { Push, Pusher, PushResult } from '../../src/lib/server/push/fcm';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { createVerify, generateKeyPairSync } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { device, pushTokenOwner, reminder } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createPushHandlers } from '../../src/lib/server/jobs/push';
import { listDevices, registerDevice, unregisterDevice } from '../../src/lib/server/ops/devices';
import { createReminder } from '../../src/lib/server/ops/schedule';
import { createFcmPusher, parseServiceAccount } from '../../src/lib/server/push/fcm';
import { hashToken, pushToUser } from '../../src/lib/server/push/send';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- FUNCTIONS -- //

const rid = () => `req-push-${String(++n).padStart(6, '0')}`;

/** A pusher that records what it was asked to send and answers as told. */
function recorder(answer: PushResult = 'sent') {
	const sent: Push[] = [];
	const pusher: Pusher = {
		send: async (p) => {
			sent.push(p);
			return answer;
		}
	};
	return { pusher, sent };
}

const phone = (token: string) => ({
	platform: 'android' as const,
	pushToken: token,
	label: 'Phone'
});

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the Firebase sender', () => {
	const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
	const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();

	function fakeFcm(onSend: (body: unknown) => { status: number; body: string }) {
		const calls: { url: string; init: RequestInit }[] = [];
		const fetchFn = (async (url: string, init: RequestInit) => {
			calls.push({ url, init });
			if (url === 'https://oauth2.googleapis.com/token')
				return new Response(JSON.stringify({ access_token: 'ya29.test', expires_in: 3600 }), {
					status: 200
				});
			const r = onSend(JSON.parse(String(init.body)));
			return new Response(r.body, { status: r.status });
		}) as unknown as typeof fetch;
		return { calls, fetchFn };
	}

	it('signs a proper token request, caches the access token, and sends a silent sync and a notice', async () => {
		const f = fakeFcm(() => ({ status: 200, body: '{"name":"projects/p/messages/1"}' }));
		const pusher = createFcmPusher({
			projectId: 'proj',
			clientEmail: 'svc@proj.iam.gserviceaccount.com',
			privateKey: pem,
			fetch: f.fetchFn
		});
		expect(await pusher.send({ token: 'tok-a', kind: 'sync' })).toBe('sent');
		expect(
			await pusher.send({
				token: 'tok-a',
				kind: 'notice',
				title: 'Rent is due tomorrow',
				key: 'bill:1'
			})
		).toBe('sent');

		const tokenCalls = f.calls.filter((c) => c.url.includes('oauth2'));
		expect(tokenCalls).toHaveLength(1);
		const assertion = new URLSearchParams(String(tokenCalls[0]?.init.body)).get('assertion') ?? '';
		const [header, claims, signature] = assertion.split('.');
		expect(JSON.parse(Buffer.from(header ?? '', 'base64url').toString())).toEqual({
			alg: 'RS256',
			typ: 'JWT'
		});
		expect(JSON.parse(Buffer.from(claims ?? '', 'base64url').toString())).toMatchObject({
			iss: 'svc@proj.iam.gserviceaccount.com',
			scope: 'https://www.googleapis.com/auth/firebase.messaging',
			aud: 'https://oauth2.googleapis.com/token'
		});
		const ok = createVerify('RSA-SHA256')
			.update(`${header}.${claims}`)
			.verify(publicKey, Buffer.from(signature ?? '', 'base64url'));
		expect(ok).toBe(true);

		const sends = f.calls.filter((c) => c.url.includes('fcm.googleapis.com'));
		expect(sends[0]?.url).toBe('https://fcm.googleapis.com/v1/projects/proj/messages:send');
		expect(new Headers(sends[0]?.init.headers).get('authorization')).toBe('Bearer ya29.test');
		expect(JSON.parse(String(sends[0]?.init.body)).message).toEqual({
			token: 'tok-a',
			data: { type: 'sync' },
			android: { priority: 'high' }
		});
		expect(JSON.parse(String(sends[1]?.init.body)).message).toMatchObject({
			notification: { title: 'Rent is due tomorrow' },
			data: { type: 'notice', key: 'bill:1' },
			android: { priority: 'high', notification: { channel_id: 'botler_reminders_v2' } }
		});
	});

	it('tells a dead token from a temporary failure', async () => {
		const dead = fakeFcm(() => ({
			status: 404,
			body: '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'
		}));
		const flaky = fakeFcm(() => ({ status: 503, body: 'try later' }));
		const bad = fakeFcm(() => ({
			status: 400,
			body: '{"error":{"status":"INVALID_ARGUMENT","message":"The registration token is not a valid FCM registration token"}}'
		}));
		const make = (f: ReturnType<typeof fakeFcm>) =>
			createFcmPusher({ projectId: 'p', clientEmail: 'e', privateKey: pem, fetch: f.fetchFn });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		expect(await make(dead).send({ token: 'x', kind: 'sync' })).toBe('unregistered');
		// INVALID_ARGUMENT can be our own message that is wrong: the phone is kept
		expect(await make(bad).send({ token: 'x', kind: 'sync' })).toBe('failed');
		expect(await make(flaky).send({ token: 'x', kind: 'sync' })).toBe('failed');
		spy.mockRestore();
	});

	it('fails quietly when Firebase cannot be reached, without leaking the key', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const down = createFcmPusher({
			projectId: 'p',
			clientEmail: 'e',
			privateKey: pem,
			fetch: (async () => {
				throw new Error('offline');
			}) as unknown as typeof fetch
		});
		expect(await down.send({ token: 'x', kind: 'sync' })).toBe('failed');
		expect(JSON.stringify(spy.mock.calls)).not.toContain('PRIVATE KEY');
		spy.mockRestore();
	});

	it('reads the service account file and refuses a bad one', () => {
		const file = Buffer.from(
			JSON.stringify({ client_email: 'a@b.c', private_key: 'KEY' })
		).toString('base64');
		expect(parseServiceAccount(file)).toEqual({ clientEmail: 'a@b.c', privateKey: 'KEY' });
		expect(() => parseServiceAccount('not base64 json')).toThrow(/base64/);
		expect(() => parseServiceAccount(Buffer.from('{}').toString('base64'))).toThrow(/client_email/);
	});
});

describe('who owns a phone', () => {
	it("sends a person's push only to phones that are theirs, and drops a stale registration of a shared phone", async () => {
		const anna = await seedPerson(t);
		const ben = await seedPerson(t);
		const token = `shared-phone-token-${n}`;
		await registerDevice({ ...anna.ctx, requestId: rid() }, phone(token));
		await registerDevice({ ...ben.ctx, requestId: rid() }, phone(token));
		const owner = await t.handle.db
			.select()
			.from(pushTokenOwner)
			.where(eq(pushTokenOwner.tokenHash, hashToken(token)));
		expect(owner.map((o) => o.userId)).toEqual([ben.userId]);

		// A push for Anna must not reach the phone, which now belongs to Ben. Her leftover row is deleted
		const a = recorder();
		expect(await pushToUser(anna.ctx, a.pusher, { kind: 'sync' })).toEqual({
			sent: 0,
			removed: 1,
			failed: 0
		});
		expect(a.sent).toHaveLength(0);
		expect(await listDevices(anna.ctx)).toHaveLength(0);

		const b = recorder();
		expect(await pushToUser(ben.ctx, b.pusher, { kind: 'notice', title: 'Hi Ben' })).toEqual({
			sent: 1,
			removed: 0,
			failed: 0
		});
		expect(b.sent).toEqual([{ kind: 'notice', title: 'Hi Ben', token }]);
	});

	it('gives the phone back to whoever registers it last', async () => {
		const anna = await seedPerson(t);
		const ben = await seedPerson(t);
		const token = `swap-phone-token-${n}`;
		await registerDevice({ ...ben.ctx, requestId: rid() }, phone(token));
		await registerDevice({ ...anna.ctx, requestId: rid() }, phone(token));
		const r = recorder();
		expect(await pushToUser(ben.ctx, r.pusher, { kind: 'sync' })).toMatchObject({
			sent: 0,
			removed: 1
		});
		expect(await pushToUser(anna.ctx, r.pusher, { kind: 'sync' })).toMatchObject({ sent: 1 });
		expect(r.sent).toHaveLength(1);
	});

	it('forgets a token Firebase says is dead, and signing out gives the token up only if it is still yours', async () => {
		const anna = await seedPerson(t);
		const token = `dead-phone-token-${n}`;
		await registerDevice({ ...anna.ctx, requestId: rid() }, phone(token));
		const dead = recorder('unregistered');
		expect(await pushToUser(anna.ctx, dead.pusher, { kind: 'sync' })).toMatchObject({ removed: 1 });
		expect(await listDevices(anna.ctx)).toHaveLength(0);
		expect(
			await t.handle.db
				.select()
				.from(pushTokenOwner)
				.where(eq(pushTokenOwner.tokenHash, hashToken(token)))
		).toHaveLength(0);

		// Anna signs out of a phone Ben has already taken: Ben keeps the token
		const ben = await seedPerson(t);
		const shared = `signout-token-${n}`;
		const mine = await registerDevice({ ...anna.ctx, requestId: rid() }, phone(shared));
		await registerDevice({ ...ben.ctx, requestId: rid() }, phone(shared));
		await unregisterDevice({ ...anna.ctx, requestId: rid() }, { deviceId: mine.id });
		const owner = await t.handle.db
			.select()
			.from(pushTokenOwner)
			.where(eq(pushTokenOwner.tokenHash, hashToken(shared)));
		expect(owner.map((o) => o.userId)).toEqual([ben.userId]);
	});

	it('keeps a push token out of every answer', async () => {
		const anna = await seedPerson(t);
		await registerDevice({ ...anna.ctx, requestId: rid() }, phone(`secret-token-value-${n}`));
		expect(JSON.stringify(await listDevices(anna.ctx))).not.toContain('secret-token-value');
		const rows = await withUser(t.handle, anna.userId, (tx) => tx.select().from(device));
		expect(rows).toHaveLength(1);
	});
});

describe('the push jobs', () => {
	const jobRow = (userId: string, kind: string, payload: Record<string, unknown> = {}) => ({
		id: 'j',
		userId,
		kind,
		key: 'k',
		payload,
		attempts: 1,
		maxAttempts: 5
	});

	it('does nothing for a silent sync when push is not set up, and fails loudly for a visible notice', async () => {
		const f = await seedPerson(t);
		const handlers = createPushHandlers({ pusher: () => null });
		const run = (kind: string, payload = {}) =>
			withUser(t.handle, f.userId, (tx) =>
				(handlers[kind] as NonNullable<(typeof handlers)[string]>)(
					jobRow(f.userId, kind, payload),
					tx,
					{ handle: t.handle, actor: { userId: f.userId, kind: 'agent' } }
				)
			);
		await expect(run('push.sync')).resolves.toBeUndefined();
		await expect(run('push.nudge', { reminderId: crypto.randomUUID() })).rejects.toThrow(
			'PushNotConfigured'
		);
	});

	it("sends the reminder's own title as the notice, and nothing for one that was cancelled meanwhile", async () => {
		const f = await seedPerson(t);
		const nudgeToken = `nudge-token-${n}`;
		await registerDevice({ ...f.ctx, requestId: rid() }, phone(nudgeToken));
		const r = await createReminder(
			{ ...f.ctx, requestId: rid() },
			{ title: 'Call the landlord', at: new Date(Date.now() + 3_600_000).toISOString() }
		);
		// The nudge is queued to run at the reminder's time, so by then it is due
		await withUser(t.handle, f.userId, (tx) =>
			tx
				.update(reminder)
				.set({ remindAt: new Date(Date.now() - 1000) })
				.where(eq(reminder.id, r.id))
		);
		const rec = recorder();
		const handlers = createPushHandlers({ pusher: () => rec.pusher });
		const ctx = { handle: t.handle, actor: { userId: f.userId, kind: 'agent' as const } };
		const run = () =>
			withUser(t.handle, f.userId, (tx) =>
				(handlers['push.nudge'] as NonNullable<(typeof handlers)[string]>)(
					jobRow(f.userId, 'push.nudge', { reminderId: r.id }),
					tx,
					ctx
				)
			);
		await run();
		expect(rec.sent).toEqual([
			{
				kind: 'notice',
				title: 'Call the landlord',
				key: expect.stringMatching(/^custom:/),
				token: nudgeToken
			}
		]);
		await withUser(t.handle, f.userId, (tx) =>
			tx.update(reminder).set({ status: 'cancelled' }).where(eq(reminder.id, r.id))
		);
		await run();
		expect(rec.sent).toHaveLength(1);
	});
});
