// THE NO_TX JOB CLASS: A JOB THAT WAITS ON THE NETWORK (RATES FEED, FIREBASE) HOLDS NO TRANSACTION, NO CONNECTION AND NO PERSON LOCK WHILE IT WAITS;
// A LONG JOB KEEPS ITS CLAIM (HEARTBEAT); A PUSH THAT NEVER ANSWERS IS CUT OFF; A NUDGE IS CHECKED AGAIN BEFORE IT IS SENT AND ITS TITLE IS MASKED.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { Push, Pusher } from '../../src/lib/server/push/fcm';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createPostgres } from '../../src/lib/server/db/client';
import { job, reminder } from '../../src/lib/server/db/schema';
import { lockPerson, withUser } from '../../src/lib/server/db/tenant';
import { configureFx } from '../../src/lib/server/fx/config';
import { fxHandlers } from '../../src/lib/server/jobs/fx';
import { createPushHandlers } from '../../src/lib/server/jobs/push';
import { claim, enqueue, runBatch, type JobHandler } from '../../src/lib/server/jobs/queue';
import { registerDevice } from '../../src/lib/server/ops/devices';
import { createReminder } from '../../src/lib/server/ops/schedule';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- FUNCTIONS -- //

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const rid = () => `req-ntx-${String(++n).padStart(6, '0')}`;

/** Connections of this test database that sit inside an open transaction doing nothing (a transaction held across a network wait). */
async function idleInTransaction(): Promise<number> {
	const rows = await t.handle.owner.query<{ n: string }>(
		`select count(*)::text as n from pg_stat_activity where datname = current_database() and state like 'idle in transaction%' and pid <> pg_backend_pid()`
	);
	return Number(rows[0]?.n ?? 0);
}

/** Whether the person lock can be taken right now (it is not held by a job that is waiting on the network). */
async function personLockFree(userId: string): Promise<boolean> {
	const done = withUser(t.handle, userId, (tx) => lockPerson(tx, userId)).then(() => true);
	return Promise.race([done, sleep(800).then(() => false)]);
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

afterEach(async () => {
	configureFx(null);
	await t.handle.db.delete(job);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('fx.refresh as a NO_TX job', () => {
	it('five people with a fx job at once, against a feed that never answers: nothing is held while it waits, and every job ends', async () => {
		const people = await Promise.all(Array.from({ length: 5 }, () => seedPerson(t)));
		let hit = 0;
		// A feed that never answers until the request is aborted by its own timeout
		const hang = ((_url: string, init: { signal: AbortSignal }) =>
			new Promise((_resolve, reject) => {
				hit++;
				init.signal.addEventListener('abort', () => reject(new DOMException('t', 'TimeoutError')));
			})) as unknown as typeof fetch;
		configureFx({ url: 'https://rates.test/v6/latest/USD', fetch: hang, timeoutMs: 1500 });
		for (const p of people)
			await withUser(t.handle, p.userId, (tx) =>
				enqueue(tx, { userId: p.userId, kind: 'fx.refresh', key: 'd' })
			);
		const batch = runBatch(t.handle, fxHandlers, { limit: 5 });
		await sleep(500);
		expect(hit).toBeGreaterThan(0);
		// While the feed hangs: no open transaction, and the person can write at once
		expect(await idleInTransaction()).toBe(0);
		for (const p of people) expect(await personLockFree(p.userId)).toBe(true);
		expect(await batch).toBe(5);
		const states = await t.handle.db.select({ status: job.status }).from(job);
		expect(states.map((s) => s.status)).toEqual(Array(5).fill('done'));
	}, 20_000);
});

describe('the claim heartbeat', () => {
	it('keeps a running job from being claimed again after the claim time passed', async () => {
		const f = await seedPerson(t);
		await withUser(t.handle, f.userId, (tx) =>
			enqueue(tx, { userId: f.userId, kind: 'test.slow', key: 'slow' })
		);
		let runs = 0;
		const slow: JobHandler = async () => {
			runs++;
			await sleep(1200);
		};
		// The claim lasts 300 ms; the job runs 1200 ms
		const batch = runBatch(t.handle, { 'test.slow': slow }, { claimMs: 300 });
		await sleep(800);
		expect(await claim(t.handle, new Date(), 5, 300)).toEqual([]);
		await batch;
		expect(runs).toBe(1);
		expect((await t.handle.db.select().from(job))[0]?.status).toBe('done');
	}, 15_000);
});

describe('the push jobs as NO_TX jobs', () => {
	const row = (userId: string, kind: string, payload: Record<string, unknown> = {}) => ({
		id: 'j',
		userId,
		kind,
		key: 'k',
		payload,
		attempts: 1,
		maxAttempts: 5
	});
	const ctxOf = (userId: string): Ctx => ({
		handle: t.handle,
		actor: { userId, kind: 'agent', tool: 'job:push' },
		via: 'job',
		channel: 'job'
	});
	const recorder = () => {
		const sent: Push[] = [];
		const pusher: Pusher = {
			send: async (p) => {
				sent.push(p);
				return 'sent';
			}
		};
		return { pusher, sent };
	};
	/** A reminder whose time has come. */
	const dueReminder = async (userId: string, ctx: Ctx, title: string) => {
		const r = await createReminder(
			{ ...ctx, requestId: rid() },
			{ title, at: new Date(Date.now() + 3_600_000).toISOString() }
		);
		await withUser(t.handle, userId, (tx) =>
			tx
				.update(reminder)
				.set({ remindAt: new Date(Date.now() - 1000) })
				.where(eq(reminder.id, r.id))
		);
		return r;
	};

	it('cuts off a push that never answers, and holds no transaction or lock while it waits', async () => {
		const f = await seedPerson(t);
		await registerDevice({ ...f.ctx, requestId: rid() }, phone(`ntx-token-${n}`));
		const never: Pusher = { send: () => new Promise(() => undefined) };
		const handlers = createPushHandlers({ pusher: () => never, timeoutMs: 700 });
		const started = Date.now();
		const settled = (handlers['push.sync'] as JobHandler)(
			row(f.userId, 'push.sync'),
			undefined as never,
			ctxOf(f.userId)
		).then(
			() => 'ok',
			(e: Error) => e.name
		);
		await sleep(250);
		expect(await idleInTransaction()).toBe(0);
		expect(await personLockFree(f.userId)).toBe(true);
		expect(await settled).toBe('PushTimeout');
		expect(Date.now() - started).toBeLessThan(5000);
	}, 15_000);

	it('sends a masked title, and nothing for a reminder that is cancelled or not yet due', async () => {
		const f = await seedPerson(t);
		await registerDevice({ ...f.ctx, requestId: rid() }, phone(`ntx-token-${n}`));
		const rec = recorder();
		const handlers = createPushHandlers({ pusher: () => rec.pusher });
		const nudge = (id: string) =>
			(handlers['push.nudge'] as JobHandler)(
				row(f.userId, 'push.nudge', { reminderId: id }),
				undefined as never,
				ctxOf(f.userId)
			);

		const due = await dueReminder(f.userId, f.ctx, 'Text 09171234567 about the deposit');
		await nudge(due.id);
		expect(rec.sent).toHaveLength(1);
		const title = (rec.sent[0] as { title: string }).title;
		expect(title).not.toContain('09171234567');
		expect(title).toMatch(/\[PHONE_1\]/);

		const cancelled = await dueReminder(f.userId, f.ctx, 'Cancelled one');
		await withUser(t.handle, f.userId, (tx) =>
			tx.update(reminder).set({ status: 'cancelled' }).where(eq(reminder.id, cancelled.id))
		);
		await nudge(cancelled.id);

		const later = await createReminder(
			{ ...f.ctx, requestId: rid() },
			{ title: 'Later', at: new Date(Date.now() + 3 * 3_600_000).toISOString() }
		);
		await nudge(later.id);
		expect(rec.sent).toHaveLength(1);
	});
});

describe('the pool', () => {
	it('fails loudly when it is full instead of waiting for ever', async () => {
		const url = new URL(
			process.env.TEST_PG_ADMIN_URL ??
				'postgres://postgres:localpostgrespassword@127.0.0.1:5434/postgres'
		);
		url.pathname = `/${t.name}`;
		const h = createPostgres({
			ownerUrl: url.toString(),
			switchRole: false,
			poolMax: 1,
			connectionTimeoutMs: 300
		});
		try {
			const held = h.db.transaction(async () => {
				await sleep(1200);
			});
			await sleep(100);
			await expect(h.db.transaction(async () => undefined)).rejects.toThrow(/timeout/i);
			await held;
		} finally {
			await h.close();
		}
	}, 15_000);
});
