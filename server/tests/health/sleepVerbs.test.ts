// SLEEP VERBS AND THE WIND-DOWN REMINDER (BTL-20261105-0015, P7)

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, toManilaDate } from '../../src/lib/finance/dates';
import { reminder, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { reconcileReminders } from '../../src/lib/server/schedule/reminders';
import { windDownFor } from '../../src/lib/schedule/availability';
import { createTestDb } from '../support/testDb';

// -- TYPES -- //

type Entry = {
	id: string;
	minutes: number;
	nap: boolean;
	day: string;
	byAgent: boolean;
	startsAt: string;
};
type Summary = {
	last: Entry | null;
	nights: Entry[];
	naps: Entry[];
	averageMinutes: number | null;
	bedtimeSpreadMinutes: number | null;
	pattern: { shortNightExtraKcal: number } | null;
};

// -- CONSTANTS -- //

const TODAY = toManilaDate(new Date());

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const ctxFor = (id: string, kind: 'person' | 'agent' = 'person'): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind, ...(kind === 'agent' ? { tool: 'test' } : {}) },
	requestId: `req-slp-${String(++counter).padStart(6, '0')}`
});

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values(
			[1, 2, 3, 4].map((n) => ({ id: `user_slp_0000${n}`, name: 'P', email: `s${n}@example.com` }))
		);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('logging sleep', () => {
	const id = 'user_slp_00001';

	it('a night crossing midnight belongs to the day they woke', async () => {
		const s = (await invokeVerb(ctxFor(id, 'agent'), 'sleep_log', {
			from: '23:00',
			to: '06:00'
		})) as Entry;
		expect(s).toMatchObject({ minutes: 420, nap: false, day: TODAY, byAgent: true });
		expect(s.startsAt).toBe(new Date(`${addDays(TODAY, -1)}T15:00:00Z`).toISOString());
	});

	it('a short day sleep is a nap, and does not count as the night', async () => {
		const n = (await invokeVerb(ctxFor(id), 'sleep_log', { from: '13:00', to: '13:40' })) as Entry;
		expect(n).toMatchObject({ minutes: 40, nap: true });
		const sum = (await invokeVerb(ctxFor(id), 'sleep_summary', {})) as Summary;
		expect(sum.last?.minutes).toBe(420);
		expect(sum.averageMinutes).toBe(420);
		expect(sum.naps).toHaveLength(1);
	});

	it('edits one end and keeps the other', async () => {
		const s = (await invokeVerb(ctxFor(id), 'sleep_log', {
			from: '22:30',
			to: '05:30',
			day: addDays(TODAY, -1)
		})) as Entry;
		const e = (await invokeVerb(ctxFor(id), 'sleep_edit', { id: s.id, to: '06:30' })) as Entry;
		expect(e.minutes).toBe(480);
	});

	it('answers what a delete removed', async () => {
		const s = (await invokeVerb(ctxFor(id), 'sleep_log', {
			from: '22:00',
			to: '06:00',
			day: addDays(TODAY, -3)
		})) as Entry;
		const r = await invokeVerb(ctxFor(id, 'agent'), 'sleep_delete', { id: s.id });
		expect(r).toMatchObject({ removed: { id: s.id, minutes: 480 } });
	});

	it('refuses a sleep of more than 20 hours', async () => {
		await expect(
			invokeVerb(ctxFor(id), 'sleep_log', { from: '06:00', to: '05:00' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('gives no score and no stages', async () => {
		const sum = (await invokeVerb(ctxFor(id), 'sleep_summary', {})) as Record<string, unknown>;
		expect(Object.keys(sum).join(' ')).not.toMatch(/score|stage|deep|rem/i);
	});
});

describe('the pattern', () => {
	const id = 'user_slp_00002';

	it('waits for 14 nights, then notices a gap as a pattern', async () => {
		const log = async (back: number, short: boolean) => {
			const day = addDays(TODAY, -back);
			await invokeVerb(ctxFor(id), 'sleep_log', {
				from: short ? '01:00' : '22:30',
				to: '06:00',
				day
			});
			await invokeVerb(ctxFor(id), 'meal_log', {
				day,
				items: [{ manual: { name: 'Food', kcal: short ? 2300 : 1900 } }]
			});
		};
		for (let i = 1; i <= 13; i++) await log(i, i % 3 === 0);
		expect(((await invokeVerb(ctxFor(id), 'sleep_summary', {})) as Summary).pattern).toBeNull();
		await log(14, false);
		const after = (await invokeVerb(ctxFor(id), 'sleep_summary', {})) as Summary;
		expect(after.pattern?.shortNightExtraKcal).toBe(400);
	});
});

describe('the wind-down reminder', () => {
	const id = 'user_slp_00003';
	const scheduled = async (who: string) =>
		(
			await withUser(t.handle, who, (tx) =>
				tx
					.select()
					.from(reminder)
					.where(and(eq(reminder.userId, who), eq(reminder.kind, 'winddown')))
			)
		).filter((r) => r.status === 'scheduled');
	const tomorrow = addDays(TODAY, 1);
	const noon = new Date(`${TODAY}T04:00:00Z`);

	it('works out the time from the first work block', () => {
		const input = {
			weekly: [],
			overrides: [
				{
					day: tomorrow,
					off: false,
					blocks: [{ startMinute: 420, endMinute: 1110, kind: 'work' as const }]
				}
			],
			settings: { wakeStartMinute: 360, wakeEndMinute: 1320, travelMinutes: 30 },
			events: []
		};
		expect(windDownFor(tomorrow, input)).toMatchObject({ time: '22:00', firstAt: '07:00' });
	});

	it('takes no notice of an event that began the day before', () => {
		const input = {
			weekly: [],
			overrides: [],
			settings: { wakeStartMinute: 360, wakeEndMinute: 1320, travelMinutes: 30 },
			events: [
				{
					startsAt: new Date(`${TODAY}T14:00:00Z`),
					endsAt: new Date(`${TODAY}T18:00:00Z`)
				}
			]
		};
		expect(windDownFor(tomorrow, input)).toBeNull();
	});

	it('does nothing while it is off', async () => {
		await invokeVerb(ctxFor(id), 'availability_override_set', {
			day: tomorrow,
			blocks: [{ start: '07:00', end: '18:30', kind: 'work' }]
		});
		await withUser(t.handle, id, (tx) => reconcileReminders(tx, id, noon));
		expect(await scheduled(id)).toHaveLength(0);
	});

	it('is fixed text with no numbers, and keyed by the date', async () => {
		await invokeVerb(ctxFor(id), 'availability_setting_set', { windDown: true });
		await withUser(t.handle, id, (tx) => reconcileReminders(tx, id, noon));
		const [r] = await scheduled(id);
		expect(r?.title).toBe('Time to wind down');
		expect(r?.refKey).toBe(`winddown:${tomorrow}`);
		expect(r?.remindAt.toISOString()).toBe(new Date(`${TODAY}T14:00:00Z`).toISOString());
	});

	it('follows a changed day on the next sync', async () => {
		await invokeVerb(ctxFor(id), 'availability_override_set', {
			day: tomorrow,
			blocks: [{ start: '08:00', end: '18:30', kind: 'work' }]
		});
		await withUser(t.handle, id, (tx) => reconcileReminders(tx, id, noon));
		const [r] = await scheduled(id);
		expect(r?.remindAt.toISOString()).toBe(new Date(`${TODAY}T15:00:00Z`).toISOString());
	});

	it('goes away on a day with no early start', async () => {
		await invokeVerb(ctxFor(id), 'availability_override_set', { day: tomorrow, off: true });
		await withUser(t.handle, id, (tx) => reconcileReminders(tx, id, noon));
		expect(await scheduled(id)).toHaveLength(0);
	});
});
