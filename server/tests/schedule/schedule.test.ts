// SCHEDULING AGAINST A REAL (THROWAWAY) DATABASE: TASKS, EVENTS, ROUTINES, REMINDERS THAT FOLLOW WHAT NEEDS ACTION, ALARMS, AND THE SYNC CONTRACT

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, toLocalDate } from '../../src/lib/finance/dates';
import { atLocalTime } from '../../src/lib/schedule/recurrence';
import { job, reminder } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { markBillPaid } from '../../src/lib/server/ops/bills';
import { OpsError } from '../../src/lib/server/ops/context';
import { recordIncome } from '../../src/lib/server/ops/ledger';
import { createBill } from '../../src/lib/server/ops/bills';
import { createIncome } from '../../src/lib/server/ops/planning';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import {
	closeReminder,
	completeTask,
	createAlarm,
	createEvent,
	createReminder,
	createRoutine,
	createTask,
	createTimer,
	deleteEvent,
	listReminders,
	listTasks,
	updateRoutine
} from '../../src/lib/server/ops/schedule';
import { approveSplit, proposeSplitPlan } from '../../src/lib/server/ops/split';
import { setSettings } from '../../src/lib/server/ops/settings';
import { syncGet } from '../../src/lib/server/ops/sync';
import { reconcileReminders } from '../../src/lib/server/schedule/reminders';
import { createTestDb } from '../support/testDb';
import { seedPerson, type Fixture } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- FUNCTIONS -- //

const rid = () => `req-sch-${String(++n).padStart(6, '0')}`;
const as = (c: Ctx): Ctx => ({ ...c, requestId: rid() });
const today = () => toLocalDate(new Date());
const inDays = (d: number) => addDays(today(), d);
const hours = (h: number) => new Date(Date.now() + h * 3_600_000);

const rows = (f: Fixture) =>
	withUser(t.handle, f.userId, (tx) =>
		tx.select().from(reminder).where(eq(reminder.userId, f.userId))
	);
const byPrefix = async (f: Fixture, prefix: string) =>
	(await rows(f)).filter((r) => r.refKey.startsWith(prefix));
const reconcile = (f: Fixture, now = new Date()) =>
	withUser(t.handle, f.userId, (tx) => reconcileReminders(tx, f.userId, now));

/** A bill that falls due on a given Manila date. */
const billDue = (f: Fixture, date: string, name = 'Water') =>
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

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('reminders follow what needs action', () => {
	it('reminds of a bill until it is paid, with no amount in the words', async () => {
		const f = await seedPerson(t);
		const due = inDays(2);
		const bill = await billDue(f, due);
		await reconcile(f);
		const [r] = await byPrefix(f, `bill:${bill.id}`);
		expect(r).toMatchObject({
			status: 'scheduled',
			kind: 'bill',
			origin: 'system',
			title: 'Water is due tomorrow'
		});
		expect(r?.remindAt.toISOString()).toBe(atLocalTime(addDays(due, -1), '18:00').toISOString());
		expect(r?.title).not.toMatch(/\d{3}|₱/);

		await markBillPaid(as(f.ctx), { billId: bill.id, dueDate: due });
		const result = await reconcile(f);
		expect(result.cancelled).toBeGreaterThanOrEqual(1);
		expect((await byPrefix(f, `bill:${bill.id}`))[0]?.status).toBe('cancelled');
	});

	it('reminds when a payment window opens and two days before it closes, and drops both once paid', async () => {
		const f = await seedPerson(t);
		const bill = await createBill(as(f.ctx), {
			name: 'Internet',
			category: 'bills',
			accountId: f.rcbc,
			kind: 'fixed',
			amount: 120_000,
			schedule: { kind: 'day_range', from: 5, to: 11 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		// 10:00 in Manila on 2030-03-03; the window is the 5th to the 11th
		await reconcile(f, new Date('2030-03-03T02:00:00Z'));
		const all = await byPrefix(f, `bill:${bill.id}`);
		const open = all.find((r) => r.refKey.endsWith(':open'));
		const soon = all.find((r) => r.refKey.endsWith(':soon'));
		expect(open?.remindAt.toISOString()).toBe(atLocalTime('2030-03-05', '08:00').toISOString());
		expect(open?.title).toBe('Internet can be paid from today until 2030-03-11');
		expect(soon?.remindAt.toISOString()).toBe(atLocalTime('2030-03-09', '09:00').toISOString());
		expect(soon?.title).toBe('Internet is due in 2 days');
		// No amount in the words (the date is fine)
		for (const r of all) expect(r.title).not.toMatch(/1200|1,200|120000|₱/);

		// Paying on any day inside the window settles it: every reminder of that window goes
		await markBillPaid(as(f.ctx), { billId: bill.id, dueDate: '2030-03-07' });
		await reconcile(f, new Date('2030-03-03T02:00:00Z'));
		const left = (await byPrefix(f, `bill:${bill.id}:2030-03-11`)).filter(
			(r) => r.status === 'scheduled'
		);
		expect(left).toEqual([]);
	});

	it('nudges about an overdue unpaid bill at the next 9 in the morning', async () => {
		const f = await seedPerson(t);
		const overdue = inDays(-2);
		const bill = await billDue(f, overdue, 'Gas');
		await reconcile(f);
		const [r] = await byPrefix(f, `bill:${bill.id}:${overdue}`);
		expect(r?.title).toBe('Gas is overdue');
		expect(toLocalDate(r?.remindAt ?? new Date(0)) >= today()).toBe(true);
		const hourInManila = Number(
			new Intl.DateTimeFormat('en-GB', {
				hour: '2-digit',
				hour12: false,
				timeZone: 'Asia/Manila'
			}).format(r?.remindAt)
		);
		expect(hourInManila).toBe(9);
	});

	it('reminds of a payday until the split is approved', async () => {
		const f = await seedPerson(t);
		const d = inDays(3);
		const income = await createIncome(as(f.ctx), {
			label: 'Side pay',
			accountId: f.rcbc,
			expectedAmount: 500_000,
			schedule: { kind: 'monthly', day: Number(d.slice(8)) },
			weekendRule: 'none'
		});
		await reconcile(f);
		const [r] = await byPrefix(f, `payday:${income.id}`);
		expect(r).toMatchObject({ kind: 'payday', status: 'scheduled' });
		expect(r?.remindAt.toISOString()).toBe(atLocalTime(d, '08:00').toISOString());

		const plan = await proposeSplitPlan(as(f.ctx), {
			incomeScheduleId: income.id,
			payday: d,
			pay: 5_000_000
		});
		if (plan.status === 'needs_amounts') throw new Error('unexpected');
		await approveSplit(as(f.ctx), { splitId: plan.id });
		await reconcile(f);
		expect((await byPrefix(f, `payday:${income.id}:${d}`))[0]?.status).toBe('cancelled');
	});

	it('reminds of a task before it is due, stops when it is done, and brings an overdue one back each morning', async () => {
		const f = await seedPerson(t);
		const task = await createTask(as(f.ctx), {
			title: 'Renew license',
			dueAt: hours(5).toISOString()
		});
		const [r] = await byPrefix(f, `task:${task.id}`);
		expect(r?.title).toBe('Renew license');
		expect(Math.abs((r?.remindAt.getTime() ?? 0) - hours(4).getTime())).toBeLessThan(60_000);

		await completeTask(as(f.ctx), { taskId: task.id });
		expect((await byPrefix(f, `task:${task.id}`))[0]?.status).toBe('cancelled');

		const old = await createTask(as(f.ctx), {
			title: 'Call the bank',
			dueAt: hours(-30).toISOString()
		});
		const [nag] = await byPrefix(f, `task:${old.id}`);
		expect(nag?.status).toBe('scheduled');
		expect(nag?.remindAt.getTime()).toBeGreaterThan(Date.now());
		// It rang and was sent; a day later, still open, it comes again
		await withUser(t.handle, f.userId, (tx) =>
			tx
				.update(reminder)
				.set({ status: 'sent' })
				.where(eq(reminder.id, nag?.id ?? ''))
		);
		await reconcile(f, new Date(Date.now() + 26 * 3_600_000));
		expect((await byPrefix(f, `task:${old.id}`))[0]?.status).toBe('scheduled');
	});

	it('reminds before an event, at 8 for an all-day one, and drops it when the event is deleted', async () => {
		const f = await seedPerson(t);
		const start = hours(6);
		const ev = await createEvent(as(f.ctx), { title: 'Dentist', startsAt: start.toISOString() });
		const [r] = await byPrefix(f, `event:${ev.id}`);
		expect(r?.remindAt.getTime()).toBe(start.getTime() - 30 * 60_000);
		expect(r?.title).toMatch(/^Dentist at \d{1,2}:\d{2}/);
		await deleteEvent(as(f.ctx), { eventId: ev.id });
		expect((await byPrefix(f, `event:${ev.id}`))[0]?.status).toBe('cancelled');

		const tomorrow = inDays(1);
		const allDay = await createEvent(as(f.ctx), {
			title: 'Holiday',
			startsAt: atLocalTime(tomorrow, '00:00').toISOString(),
			allDay: true
		});
		expect((await byPrefix(f, `event:${allDay.id}`))[0]?.remindAt.toISOString()).toBe(
			atLocalTime(tomorrow, '08:00').toISOString()
		);
	});

	it('still reminds an event made less than 30 minutes before it starts', async () => {
		const f = await seedPerson(t);
		const near = await createEvent(as(f.ctx), {
			title: 'Call',
			startsAt: new Date(Date.now() + 20 * 60_000).toISOString()
		});
		const [a] = await byPrefix(f, `event:${near.id}`);
		expect(a?.remindAt.getTime()).toBe(Date.parse(near.startsAt) - 10 * 60_000);
		const soon = await createEvent(as(f.ctx), {
			title: 'Door',
			startsAt: new Date(Date.now() + 5 * 60_000).toISOString()
		});
		const [b] = await byPrefix(f, `event:${soon.id}`);
		expect(b?.remindAt.getTime()).toBe(Date.parse(soon.startsAt));
	});

	it('plans each occurrence of a routine ahead of its time, and cancels them when it is switched off', async () => {
		const f = await seedPerson(t);
		const r = await createRoutine(as(f.ctx), {
			title: 'Take vitamins',
			recurrence: { freq: 'daily', time: '07:00' },
			leadMinutes: 10
		});
		const mine = await byPrefix(f, `routine:${r.id}`);
		expect(mine.length).toBeGreaterThanOrEqual(13);
		expect(mine.every((x) => x.status === 'scheduled' && x.title === 'Take vitamins')).toBe(true);
		for (const x of mine)
			expect(
				new Intl.DateTimeFormat('en-GB', {
					hour: '2-digit',
					minute: '2-digit',
					hour12: false,
					timeZone: 'Asia/Manila'
				}).format(x.remindAt)
			).toBe('06:50');
		await updateRoutine(as(f.ctx), { routineId: r.id, active: false });
		expect((await byPrefix(f, `routine:${r.id}`)).every((x) => x.status === 'cancelled')).toBe(
			true
		);
	});

	it('makes no duplicates however often it runs', async () => {
		const f = await seedPerson(t);
		await billDue(f, inDays(2));
		await createTask(as(f.ctx), { title: 'One', dueAt: hours(8).toISOString() });
		await reconcile(f);
		const first = (await rows(f)).length;
		const again = await reconcile(f);
		await reconcile(f);
		expect((await rows(f)).length).toBe(first);
		expect(again).toEqual({ created: 0, moved: 0, cancelled: 0 });
	});

	it('keeps a dismissed reminder dismissed', async () => {
		const f = await seedPerson(t);
		const task = await createTask(as(f.ctx), {
			title: 'Water the plants',
			dueAt: hours(5).toISOString()
		});
		const [r] = await byPrefix(f, `task:${task.id}`);
		await closeReminder(as(f.ctx), { reminderId: r?.id }, 'dismissed');
		await reconcile(f, new Date(Date.now() + 3_600_000));
		expect((await byPrefix(f, `task:${task.id}`))[0]?.status).toBe('dismissed');
	});
});

describe('a change of time zone', () => {
	it('moves the hours of the reminders at once, in the settings write, with no copy left behind', async () => {
		const f = await seedPerson(t);
		await billDue(f, inDays(6), 'Zone water');
		await reconcile(f);
		const before = (await byPrefix(f, 'bill:')).filter((r) => r.title.includes('Zone water'));
		expect(before.length).toBeGreaterThan(0);
		await setSettings(as(f.ctx), { timeZone: 'Asia/Tokyo' });
		const after = (await byPrefix(f, 'bill:')).filter((r) => r.title.includes('Zone water'));
		// Same reminders, no duplicate; Tokyo is an hour ahead of Manila, so 8 in the morning there comes an hour sooner
		expect(after.map((r) => r.refKey).sort()).toEqual(before.map((r) => r.refKey).sort());
		for (const r of after) {
			const was = before.find((b) => b.refKey === r.refKey);
			expect((was?.remindAt.getTime() ?? 0) - r.remindAt.getTime()).toBe(3_600_000);
		}
	});
});

describe('reminders, alarms and timers', () => {
	it('sets a reminder, an alarm and a timer, and cancels them', async () => {
		const f = await seedPerson(t);
		const r = await createReminder(as(f.ctx), { title: 'Call mama', at: hours(2).toISOString() });
		const a = await createAlarm(as(f.ctx), { title: 'Wake up', at: hours(10).toISOString() });
		const tm = await createTimer(as(f.ctx), { minutes: 15 });
		expect([r.kind, a.kind, tm.kind]).toEqual(['custom', 'alarm', 'timer']);
		expect(tm.title).toBe('15 minute timer');
		expect(Math.abs(new Date(tm.remindAt).getTime() - (Date.now() + 15 * 60_000))).toBeLessThan(
			5_000
		);
		const made = async () =>
			(await listReminders(f.ctx))
				.filter((x) => x.origin !== 'system')
				.map((x) => x.kind)
				.sort();
		expect(await made()).toEqual(['alarm', 'custom', 'timer']);
		await closeReminder(as(f.ctx), { reminderId: r.id });
		await expect(closeReminder(as(f.ctx), { reminderId: r.id })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		// The recompute leaves what the person made on purpose alone
		await reconcile(f);
		expect(await made()).toEqual(['alarm', 'timer']);
	});

	it('refuses a time that has passed', async () => {
		const f = await seedPerson(t);
		await expect(
			createAlarm(as(f.ctx), { title: 'Late', at: hours(-3).toISOString() })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('hands a reminder made just now to the phone, and one up to ten minutes late, but not older', async () => {
		const f = await seedPerson(t);
		const soon = await createReminder(as(f.ctx), {
			title: 'In a minute',
			at: new Date(Date.now() + 60_000).toISOString()
		});
		const late = (min: number, title: string) =>
			withUser(t.handle, f.userId, (tx) =>
				tx.insert(reminder).values({
					userId: f.userId,
					kind: 'custom',
					refKey: `custom:${title}`,
					title,
					remindAt: new Date(Date.now() - min * 60_000),
					origin: 'user'
				})
			);
		await late(5, 'Five late');
		await late(11, 'Eleven late');
		const listed = ((await syncGet(f.ctx)).reminders ?? []).map((r) => r.title);
		expect(listed).toContain('In a minute');
		expect(listed).toContain('Five late');
		expect(listed).not.toContain('Eleven late');
		expect(soon.status).toBe('scheduled');
	});

	it('tells the assistant what time it is when the time it gave has passed', async () => {
		const f = await seedPerson(t);
		await expect(
			createReminder(as(f.ctx), { title: 'Late', at: hours(-3).toISOString() })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('It is now') });
	});

	it('queues a visible push for a reminder the assistant made, and a silent sync for any change', async () => {
		const f = await seedPerson(t);
		const agent: Ctx = {
			handle: t.handle,
			actor: { userId: f.userId, kind: 'agent' },
			requestId: rid()
		};
		const r = await invokeVerb(agent, 'reminder_create', {
			title: 'Pay the rent',
			at: hours(3).toISOString()
		});
		const id = (r as { id: string }).id;
		const jobs = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(job).where(eq(job.userId, f.userId))
		);
		const nudge = jobs.find((j) => j.kind === 'push.nudge');
		expect(nudge?.key).toBe(id);
		expect(nudge?.payload).toEqual({ reminderId: id });
		expect(jobs.some((j) => j.kind === 'push.sync')).toBe(true);
		expect((await listReminders(f.ctx))[0]?.origin).toBe('agent');
	});
});

describe('tasks', () => {
	it('lists open tasks soonest first and the others on request', async () => {
		const f = await seedPerson(t);
		const later = await createTask(as(f.ctx), { title: 'Later', dueAt: hours(48).toISOString() });
		await createTask(as(f.ctx), { title: 'No date' });
		const soon = await createTask(as(f.ctx), { title: 'Soon', dueAt: hours(5).toISOString() });
		expect((await listTasks(f.ctx)).map((x) => x.title)).toEqual(['Soon', 'Later', 'No date']);
		await completeTask(as(f.ctx), { taskId: soon.id });
		expect((await listTasks(f.ctx, { status: 'done' })).map((x) => x.title)).toEqual(['Soon']);
		expect(later.status).toBe('open');
	});

	it('refuses a stale update and a task of someone else', async () => {
		const f = await seedPerson(t);
		const other = await seedPerson(t);
		const task = await createTask(as(f.ctx), { title: 'Mine' });
		const { updateTask } = await import('../../src/lib/server/ops/schedule');
		await updateTask(as(f.ctx), { taskId: task.id, title: 'Mine v2' });
		await expect(
			updateTask(as(f.ctx), { taskId: task.id, title: 'x', expectVersion: task.version })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await expect(
			updateTask(as(other.ctx), { taskId: task.id, title: 'stolen' })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
	});
});

describe('the sync contract', () => {
	it('hands over the reminders, then only a cursor until something changes', async () => {
		const f = await seedPerson(t);
		await billDue(f, inDays(2));
		const first = await syncGet(f.ctx);
		expect(first.changed).toBe(true);
		expect(first.reminders?.length).toBeGreaterThanOrEqual(1);
		const same = await syncGet(f.ctx, { cursor: first.cursor });
		expect(same.changed).toBe(false);
		expect(same.reminders).toBeUndefined();
		expect(same.cursor).toBe(first.cursor);
		await createTask(as(f.ctx), { title: 'New thing', dueAt: hours(5).toISOString() });
		const next = await syncGet(f.ctx, { cursor: first.cursor });
		expect(next.changed).toBe(true);
		expect(next.reminders?.some((r) => r.title === 'New thing')).toBe(true);
		for (const r of next.reminders ?? [])
			expect(r).toEqual({
				key: expect.any(String),
				id: expect.any(String),
				kind: expect.any(String),
				title: expect.any(String),
				at: expect.any(String),
				version: expect.any(Number)
			});
	});

	it('stops listing a reminder once its bill is paid, so the phone drops the alarm', async () => {
		const f = await seedPerson(t);
		const due = inDays(2);
		const bill = await billDue(f, due, 'Cable');
		const before = await syncGet(f.ctx);
		expect(before.reminders?.some((r) => r.key === `bill:${bill.id}:${due}`)).toBe(true);
		await markBillPaid(as(f.ctx), { billId: bill.id, dueDate: due });
		const after = await syncGet(f.ctx, { cursor: before.cursor });
		expect(after.changed).toBe(true);
		expect(after.reminders?.some((r) => r.key === `bill:${bill.id}:${due}`)).toBe(false);
	});

	it('carries the summary card: the total, the next bill, the first event today', async () => {
		const f = await seedPerson(t);
		await recordIncome(as(f.ctx), { accountId: f.gcash, amount: 123_400 });
		await recordIncome(as(f.ctx), { accountId: f.maya, amount: 1_000 });
		const due = inDays(1);
		await billDue(f, due, 'Internet');
		const soon = new Date(Date.now() + 60_000);
		await createEvent(as(f.ctx), { title: 'Standup', startsAt: soon.toISOString() });
		const s = (await syncGet(f.ctx)).summary;
		expect(s.total).toBe(124_400);
		expect(s.nextBill).toEqual({
			name: expect.any(String),
			dueDate: expect.any(String),
			windowStart: expect.any(String),
			windowEnd: expect.any(String)
		});
		// A single day opens and closes on its due date
		expect(s.nextBill?.windowStart).toBe(s.nextBill?.dueDate);
		expect(s.firstEventToday?.title).toBe('Standup');
	});

	it("keeps one person's reminders out of another's sync", async () => {
		const f = await seedPerson(t);
		const other = await seedPerson(t);
		await createTask(as(f.ctx), { title: 'Private errand', dueAt: hours(5).toISOString() });
		expect(JSON.stringify(await syncGet(other.ctx))).not.toContain('Private errand');
		expect((await rows(other)).map((r) => r.title)).not.toContain('Private errand');
	});
});

describe('who may do what', () => {
	it('refuses unknown fields, and has no calendar sync switch', async () => {
		const f = await seedPerson(t);
		await expect(
			invokeVerb(as(f.ctx), 'task_create', { title: 'x', userId: 'other' })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(invokeVerb(as(f.ctx), 'calendar_enable', {})).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect(new OpsError('INVALID', 'x').code).toBe('INVALID');
	});

	it('refuses an event that ends before it starts and a bad routine', async () => {
		const f = await seedPerson(t);
		await expect(
			createEvent(as(f.ctx), {
				title: 'Backwards',
				startsAt: hours(5).toISOString(),
				endsAt: hours(4).toISOString()
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			createRoutine(as(f.ctx), {
				title: 'x',
				recurrence: { freq: 'weekly', days: [9], time: '07:00' }
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		expect(and).toBeTruthy();
	});
});
