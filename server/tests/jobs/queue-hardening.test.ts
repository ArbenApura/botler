// THE QUEUE UNDER STRESS: A JOB THAT KEEPS CRASHING STOPS, FINISHED JOBS ARE PURGED, THE DAILY PURGE HANDLER ONLY TOUCHES ITS OWNER, A PAYLOAD STAYS SMALL.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { job, requestLog, undoJournal, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { jobHandlers } from '../../src/lib/server/jobs/handlers';
import {
	claim,
	enqueue,
	purgeFinished,
	runBatch,
	scheduleMaintenance
} from '../../src/lib/server/jobs/queue';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const ANNA = 'user_anna_0001';
const BEN = 'user_ben_00001';

// -- STATES -- //

let t: TestDb;

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

describe('queue hardening', () => {
	it('marks a job failed when its worker died on the last allowed try', async () => {
		await withUser(t.handle, ANNA, (tx) =>
			enqueue(tx, { userId: ANNA, kind: 'k.crash', key: 'a', maxAttempts: 1 })
		);
		const first = new Date(Date.now() + 60_000);
		expect(await claim(t.handle, first, 5)).toHaveLength(1);
		// The claim expires with the job still "running" and all tries used: it must not run again
		const later = new Date(first.getTime() + 6 * 60_000);
		expect(await claim(t.handle, later, 5)).toHaveLength(0);
		const [row] = await t.handle.db.select().from(job);
		expect(row?.status).toBe('failed');
		expect(row?.lastError).toBe('Abandoned');
	});

	it('does not take a job another worker already took', async () => {
		await withUser(t.handle, ANNA, (tx) => enqueue(tx, { userId: ANNA, kind: 'k.one', key: 'a' }));
		const now = new Date(Date.now() + 60_000);
		const results = await Promise.all([1, 2, 3, 4].map(() => claim(t.handle, now, 5)));
		expect(results.flat()).toHaveLength(1);
	});

	it('refuses a payload over 2 KB', async () => {
		await expect(
			withUser(t.handle, ANNA, (tx) =>
				enqueue(tx, { userId: ANNA, kind: 'k.big', key: 'a', payload: { text: 'x'.repeat(5000) } })
			)
		).rejects.toThrow();
	});

	it('purges old finished and failed jobs and keeps recent ones', async () => {
		const now = new Date();
		const old = (days: number) => new Date(now.getTime() - days * 24 * 3_600_000);
		await t.handle.db.insert(job).values([
			{ userId: ANNA, kind: 'k', key: 'old-done', status: 'done', updatedAt: old(8) },
			{ userId: ANNA, kind: 'k', key: 'new-done', status: 'done', updatedAt: old(1) },
			{ userId: ANNA, kind: 'k', key: 'old-failed', status: 'failed', updatedAt: old(31) },
			{ userId: ANNA, kind: 'k', key: 'new-failed', status: 'failed', updatedAt: old(10) },
			{ userId: ANNA, kind: 'k', key: 'queued', status: 'queued', updatedAt: old(40) }
		]);
		await purgeFinished(t.handle, now);
		const keys = (await t.handle.db.select().from(job)).map((r) => r.key).sort();
		expect(keys).toEqual(['new-done', 'new-failed', 'queued']);
	});

	it('queues the daily purge once per person per day', async () => {
		const day = new Date('2026-10-21T10:00:00Z');
		await scheduleMaintenance(t.handle, day);
		await scheduleMaintenance(t.handle, day);
		const rows = await t.handle.db.select().from(job).where(eq(job.kind, 'maintenance.purge'));
		expect(rows.map((r) => r.userId).sort()).toEqual([ANNA, BEN]);
		expect(rows.every((r) => r.key === '2026-10-21')).toBe(true);
	});

	it('runs the purge handler for its owner only', async () => {
		const old = new Date(Date.now() - 100 * 24 * 3_600_000);
		for (const id of [ANNA, BEN]) {
			await withUser(t.handle, id, async (tx) => {
				await tx.insert(requestLog).values({
					userId: id,
					requestId: `req-old-${id}`,
					verb: 'v',
					fingerprint: 'f',
					createdAt: old
				});
				await tx.insert(requestLog).values({
					userId: id,
					requestId: `req-new-${id}`,
					verb: 'v',
					fingerprint: 'f'
				});
				await tx
					.insert(undoJournal)
					.values({ userId: id, verb: 'v', entity: 'device', entityId: '1', createdAt: old });
			});
		}
		await withUser(t.handle, ANNA, (tx) =>
			enqueue(tx, { userId: ANNA, kind: 'maintenance.purge', key: 'today' })
		);
		await runBatch(t.handle, jobHandlers, { now: new Date(Date.now() + 60_000) });
		const annaLog = await withUser(t.handle, ANNA, (tx) => tx.select().from(requestLog));
		const benLog = await withUser(t.handle, BEN, (tx) => tx.select().from(requestLog));
		// Anna's old row is gone and her new one stays; Ben's two rows are untouched because the job ran as Anna
		expect(annaLog.map((r) => r.requestId)).toEqual(['req-new-user_anna_0001']);
		expect(benLog).toHaveLength(2);
		const annaUndo = await withUser(t.handle, ANNA, (tx) => tx.select().from(undoJournal));
		expect(annaUndo).toHaveLength(0);
	});
});
