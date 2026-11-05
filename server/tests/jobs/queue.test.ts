// THE JOB QUEUE: ONE JOB PER KEY, ONE RUNNING JOB PER PERSON, NO DOUBLE CLAIM, RETRY WITH BACKOFF, RECLAIM, AND USER CONTEXT FOR EVERY HANDLER.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { device, job, user, userSetting } from '../../src/lib/server/db/schema';
import { toLocalDate } from '../../src/lib/finance/dates';
import { withUser } from '../../src/lib/server/db/tenant';
import {
	backoffMs,
	claim,
	enqueue,
	runBatch,
	type JobHandler
} from '../../src/lib/server/jobs/queue';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const ANNA = 'user_anna_0001';
const BEN = 'user_ben_00001';
// Jobs are enqueued with the real clock, so the test clock starts a minute after it
const T0 = new Date(Date.now() + 60_000);

// -- STATES -- //

let t: TestDb;

// -- FUNCTIONS -- //

const add = (
	userId: string,
	kind: string,
	key: string,
	extra: { runAfter?: Date; maxAttempts?: number } = {}
) => withUser(t.handle, userId, (tx) => enqueue(tx, { userId, kind, key, ...extra }));

const rows = () => t.handle.db.select().from(job);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: ANNA, name: 'Anna', email: 'anna@example.com' },
		{ id: BEN, name: 'Ben', email: 'ben@example.com' }
	]);
});

beforeEach(async () => {
	await t.handle.db.delete(job);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('job queue', () => {
	it('adds a job once per person, kind and key', async () => {
		expect(await add(ANNA, 'memory.night', '2026-10-21')).toBe(true);
		expect(await add(ANNA, 'memory.night', '2026-10-21')).toBe(false);
		expect(await add(ANNA, 'memory.night', '2026-10-22')).toBe(true);
		expect(await add(BEN, 'memory.night', '2026-10-21')).toBe(true);
		expect(await rows()).toHaveLength(3);
	});

	it("runs a handler inside its owner's context and nobody else's", async () => {
		await add(ANNA, 'test.touch', 'a');
		await withUser(t.handle, BEN, (tx) =>
			tx
				.insert(device)
				.values({ userId: BEN, label: 'Ben phone', pushToken: 'token-ben-0123456789' })
		);
		let seen = -1;
		const handlers: Record<string, JobHandler> = {
			'test.touch': async (row, tx) => {
				await tx
					.insert(device)
					.values({ userId: row.userId, label: 'made by job', pushToken: 'token-job-0123456789' });
				seen = (await tx.select().from(device)).length;
			}
		};
		expect(await runBatch(t.handle, handlers, { now: T0 })).toBe(1);
		// The job saw only Anna's own row, not Ben's
		expect(seen).toBe(1);
		const [done] = await rows();
		expect(done?.status).toBe('done');
		expect(await withUser(t.handle, BEN, (tx) => tx.select().from(device))).toHaveLength(1);
	});

	it("runs a handler in its owner's time zone, so the job's today is the person's day", async () => {
		await withUser(t.handle, ANNA, (tx) =>
			tx.insert(userSetting).values({ userId: ANNA, timeZone: 'Pacific/Kiritimati' })
		);
		await add(ANNA, 'test.zone', 'a');
		await add(BEN, 'test.zone', 'b');
		const seen: Record<string, string> = {};
		const instant = new Date('2026-11-05T20:00:00Z');
		const handlers: Record<string, JobHandler> = {
			'test.zone': async (row) => {
				seen[row.userId] = toLocalDate(instant);
			}
		};
		await runBatch(t.handle, handlers, { now: T0 });
		await runBatch(t.handle, handlers, { now: T0 });
		// Kiritimati is 14 hours ahead and Ben has no choice, so he is on Manila
		expect(seen[ANNA]).toBe('2026-11-06');
		expect(seen[BEN]).toBe('2026-11-06');
		await withUser(t.handle, ANNA, (tx) =>
			tx.update(userSetting).set({ timeZone: 'America/New_York' })
		);
		await add(ANNA, 'test.zone', 'c');
		await runBatch(t.handle, handlers, { now: T0 });
		expect(seen[ANNA]).toBe('2026-11-05');
	});

	it("refuses to write another person's row from a job", async () => {
		await add(ANNA, 'test.cross', 'a', { maxAttempts: 1 });
		const handlers: Record<string, JobHandler> = {
			'test.cross': async (_row, tx) => {
				await tx
					.insert(device)
					.values({ userId: BEN, label: 'x', pushToken: 'token-cross-0123456789' });
			}
		};
		await runBatch(t.handle, handlers, { now: T0 });
		const [row] = await rows();
		expect(row?.status).toBe('failed');
		const benRows = await withUser(t.handle, BEN, (tx) => tx.select().from(device));
		// Only the phone made earlier in this file; the job's attempt to add one for Ben was refused
		expect(benRows.map((r) => r.label)).toEqual(['Ben phone']);
	});

	it('claims one job per person at a time and never claims a job twice', async () => {
		await add(ANNA, 'k.one', 'a');
		await add(ANNA, 'k.two', 'b');
		await add(BEN, 'k.one', 'a');
		const [first, second] = await Promise.all([claim(t.handle, T0, 10), claim(t.handle, T0, 10)]);
		const ids = [...first, ...second].map((r) => r.id);
		expect(new Set(ids).size).toBe(ids.length);
		// Anna has two queued jobs, but only one may run; Ben's runs alongside
		expect([...first, ...second].filter((r) => r.userId === ANNA)).toHaveLength(1);
		expect([...first, ...second].filter((r) => r.userId === BEN)).toHaveLength(1);
		// While Anna's job is running, her second job is not claimed
		expect(await claim(t.handle, T0, 10)).toHaveLength(0);
	});

	it('retries a failing job with a growing backoff and stores only the error class', async () => {
		await add(ANNA, 'test.boom', 'a', { maxAttempts: 3 });
		const handlers: Record<string, JobHandler> = {
			'test.boom': async () => {
				throw new RangeError('a private sentence about rent');
			}
		};
		await runBatch(t.handle, handlers, { now: T0 });
		let [row] = await rows();
		expect(row?.status).toBe('queued');
		expect(row?.attempts).toBe(1);
		expect(row?.lastError).toBe('RangeError');
		expect(row?.runAfter.getTime()).toBe(T0.getTime() + backoffMs(1));
		// Not due yet: nothing runs
		expect(await runBatch(t.handle, handlers, { now: new Date(T0.getTime() + 1000) })).toBe(0);
		// Due: runs again, backoff doubles
		const t1 = new Date(T0.getTime() + backoffMs(1) + 1);
		await runBatch(t.handle, handlers, { now: t1 });
		[row] = await rows();
		expect(row?.attempts).toBe(2);
		expect(row?.runAfter.getTime()).toBe(t1.getTime() + backoffMs(2));
		// Third failure uses the last try
		await runBatch(t.handle, handlers, { now: new Date(t1.getTime() + backoffMs(2) + 1) });
		[row] = await rows();
		expect(row?.status).toBe('failed');
		expect(JSON.stringify(row)).not.toContain('private');
	});

	it('reclaims a job whose worker died', async () => {
		await add(ANNA, 'test.touch', 'a');
		const [claimed] = await claim(t.handle, T0, 5);
		expect(claimed?.attempts).toBe(1);
		// Still held: not claimable
		expect(await claim(t.handle, new Date(T0.getTime() + 60_000), 5)).toHaveLength(0);
		// The claim expired: another worker picks it up
		const later = new Date(T0.getTime() + 6 * 60_000);
		const [again] = await claim(t.handle, later, 5);
		expect(again?.id).toBe(claimed?.id);
		expect(again?.attempts).toBe(2);
	});

	it('fails a job with no handler instead of looping forever', async () => {
		await add(ANNA, 'test.unknown', 'a', { maxAttempts: 1 });
		await runBatch(t.handle, {}, { now: T0 });
		const [row] = await rows();
		expect(row?.status).toBe('failed');
		expect(row?.lastError).toBe('Error');
	});

	it('backs off from 30 seconds up to one hour', () => {
		expect(backoffMs(1)).toBe(30_000);
		expect(backoffMs(2)).toBe(60_000);
		expect(backoffMs(20)).toBe(3_600_000);
	});
});
