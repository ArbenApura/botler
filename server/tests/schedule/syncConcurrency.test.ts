// SYNC_GET SETTLES REMINDERS UNDER THE PERSON LOCK: TWO SYNCS AT ONCE NEVER COLLIDE (23505), A SYNC RACING A WRITE NEVER DEADLOCKS (40P01), A REPEAT
// OF AN UNCHANGED SYNC TOUCHES NOTHING, AND ANY OLD CURSOR STRING (AND NO REQUEST ID) STILL WORKS.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { addDays, toLocalDate } from '../../src/lib/finance/dates';
import { auditEvent, reminder } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createBill, markBillPaid } from '../../src/lib/server/ops/bills';
import { invokeVerb, VERBS } from '../../src/lib/server/ops/registry';
import { createReminder } from '../../src/lib/server/ops/schedule';
import { syncGet } from '../../src/lib/server/ops/sync';
import { createTestDb } from '../support/testDb';
import { seedPerson, type Fixture } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- FUNCTIONS -- //

const rid = () => `req-syn-${String(++n).padStart(6, '0')}`;
const as = (c: Ctx): Ctx => ({ ...c, requestId: rid() });
const inDays = (d: number) => addDays(toLocalDate(new Date()), d);
const rows = (f: Fixture) =>
	withUser(t.handle, f.userId, (tx) =>
		tx.select().from(reminder).where(eq(reminder.userId, f.userId))
	);
const bill = (f: Fixture, date: string, name: string) =>
	createBill(as(f.ctx), {
		name,
		category: 'bills',
		accountId: f.rcbc,
		kind: 'fixed',
		amount: 40_000,
		schedule: { kind: 'monthly', day: Number(date.slice(8)) },
		weekendRule: 'none',
		startsOn: '2000-01-01',
		deferrable: false
	});
/** The caller as the old app sends it: no request id at all. */
const old = (f: Fixture): Ctx => ({ ...f.ctx, requestId: undefined });

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('sync_get under concurrency', () => {
	it('survives many syncs at once without a unique violation', async () => {
		const f = await seedPerson(t);
		await bill(f, inDays(2), 'Water');
		await bill(f, inDays(3), 'Power');
		const answers = await Promise.all(Array.from({ length: 8 }, () => syncGet(old(f), {})));
		expect(new Set(answers.map((a) => a.cursor)).size).toBe(1);
		const keys = (await rows(f)).map((r) => r.refKey);
		expect(new Set(keys).size).toBe(keys.length);
	});

	it('does not deadlock when a sync races a write of the same person', async () => {
		const f = await seedPerson(t);
		const due = inDays(2);
		const b = await bill(f, due, 'Water');
		const jobs: Promise<unknown>[] = [];
		for (let i = 0; i < 4; i++) {
			jobs.push(syncGet(old(f), {}));
			jobs.push(
				bill(f, inDays(4 + i), `Extra ${i}`),
				// the same bill marked paid by several writers: one wins, the others replay or conflict, none may deadlock
				markBillPaid(as(f.ctx), { billId: b.id, dueDate: due }).catch((e: unknown) => {
					if ((e as { code?: string }).code === '40P01') throw e;
				})
			);
		}
		await expect(Promise.all(jobs)).resolves.toBeDefined();
	});

	it('leaves updatedAt, version, the cursor and the audit trail alone when nothing changed', async () => {
		const f = await seedPerson(t);
		await bill(f, inDays(2), 'Water');
		const first = await syncGet(old(f), {});
		const before = await rows(f);
		const auditBefore = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(auditEvent).where(eq(auditEvent.userId, f.userId))
		);
		const second = await syncGet(old(f), { cursor: first.cursor });
		expect(second.cursor).toBe(first.cursor);
		expect(second.changed).toBe(false);
		expect(second.reminders).toBeUndefined();
		const after = await rows(f);
		const pick = (r: (typeof before)[number]) => [r.id, r.version, r.updatedAt.getTime()];
		expect(after.map(pick).sort()).toEqual(before.map(pick).sort());
		const auditAfter = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(auditEvent).where(eq(auditEvent.userId, f.userId))
		);
		expect(auditAfter.length).toBe(auditBefore.length);
	});

	it('changes the cursor when a reminder enters the 14 day window, though no row changed', async () => {
		const f = await seedPerson(t);
		const at = new Date(Date.now() + 15 * 24 * 3_600_000).toISOString();
		await createReminder(as(f.ctx), { title: 'Far away', at });
		const outside = await syncGet(old(f), {});
		expect(outside.reminders?.map((r) => r.title)).not.toContain('Far away');
		// Only the clock of the code moves: two days later the reminder is inside the window
		vi.useFakeTimers({ toFake: ['Date'] });
		try {
			vi.setSystemTime(new Date(Date.now() + 2 * 24 * 3_600_000));
			const inside = await syncGet(old(f), { cursor: outside.cursor });
			expect(inside.cursor).not.toBe(outside.cursor);
			expect(inside.changed).toBe(true);
			expect(inside.reminders?.map((r) => r.title)).toContain('Far away');
		} finally {
			vi.useRealTimers();
		}
	});

	it('accepts any old cursor string and needs no request id', async () => {
		const f = await seedPerson(t);
		await bill(f, inDays(2), 'Water');
		for (const cursor of ['0:0', '3:1793000000000', 'garbage', '']) {
			const a = await syncGet(old(f), { cursor });
			expect(a.changed).toBe(true);
			expect(Array.isArray(a.reminders)).toBe(true);
		}
		const viaVerb = await invokeVerb(old(f), 'sync_get', { cursor: '1:2' });
		expect(viaVerb).toHaveProperty('cursor');
	});

	it('is not offered to the assistant', () => {
		const v = VERBS.find((x) => x.name === 'sync_get');
		expect(v?.kind).toBe('read');
		expect(v?.agent).toBe(false);
	});
});
