// WORK HOURS VERBS (BTL-20261105-0015, P2.3 AND P2.4): "I WORK 7 AM TO 6:30 PM", "NO WORK THIS SATURDAY", "WHEN AM I FREE", FROM THE PERSON AND THE ASSISTANT

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- TYPES -- //

type Availability = {
	days: { weekday: number; blocks: { start: string; end: string; kind: string }[] }[];
	changes: { day: string; off: boolean }[];
	awakeFrom: string;
	travelMinutes: number;
};
type Slot = { from: string; to: string; day: string };

// -- CONSTANTS -- //

const ME = 'user_avail_001';
const THU = '2030-11-28';
const SAT = '2030-11-30';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const agent = (): Ctx => ({
	handle: t.handle,
	actor: { userId: ME, kind: 'agent', tool: 'test' },
	requestId: `req-avail-${String(++counter).padStart(6, '0')}`
});
const person = (): Ctx => ({
	handle: t.handle,
	actor: { userId: ME, kind: 'person' },
	requestId: `req-avail-${String(++counter).padStart(6, '0')}`
});
const WORK = {
	days: [
		{ weekdays: [1, 2, 3, 4, 5], blocks: [{ start: '07:00', end: '18:30', kind: 'work' as const }] }
	]
};

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values({ id: ME, name: 'M', email: 'm@example.com' });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('from chat', () => {
	it('classes the writes as free, so the assistant does them itself', () => {
		for (const v of ['availability_set', 'availability_override_set', 'availability_setting_set'])
			expect(verbByName(v)?.kind, v).toBe('free');
		expect(verbByName('free_slots')?.kind).toBe('read');
	});

	it('"I work 7 am to 6:30 pm Monday to Friday"', async () => {
		const a = (await invokeVerb(agent(), 'availability_set', WORK)) as Availability;
		expect(a.days[1]?.blocks).toEqual([
			{ start: '07:00', end: '18:30', kind: 'work', label: null }
		]);
		expect(a.days[6]?.blocks).toEqual([]);
	});

	it('"when am I free" on a work day and on a weekend, in Manila time', async () => {
		const slots = (await invokeVerb(agent(), 'free_slots', { from: THU, to: THU })) as Slot[];
		expect(slots.map((s) => `${s.from}-${s.to}`)).toEqual(['06:00-06:30', '19:00-22:00']);
		const sat = (await invokeVerb(agent(), 'free_slots', { from: SAT, to: SAT })) as Slot[];
		expect(sat.map((s) => `${s.from}-${s.to}`)).toEqual(['06:00-22:00']);
	});

	it('"I have work this Saturday, 9 to 3", then "no work after all"', async () => {
		const a = (await invokeVerb(agent(), 'availability_override_set', {
			day: SAT,
			blocks: [{ start: '09:00', end: '15:00', kind: 'work' }]
		})) as Availability;
		expect(a.changes).toHaveLength(1);
		const sat = (await invokeVerb(agent(), 'free_slots', { from: SAT, to: SAT })) as Slot[];
		expect(sat.map((s) => `${s.from}-${s.to}`)).toEqual(['06:00-08:30', '15:30-22:00']);
		const back = (await invokeVerb(agent(), 'availability_override_set', {
			day: SAT,
			clear: true
		})) as Availability;
		expect(back.changes).toHaveLength(0);
	});

	it('"no work this Thursday" frees the day', async () => {
		await invokeVerb(agent(), 'availability_override_set', { day: THU, off: true });
		const slots = (await invokeVerb(agent(), 'free_slots', { from: THU, to: THU })) as Slot[];
		expect(slots.map((s) => `${s.from}-${s.to}`)).toEqual(['06:00-22:00']);
		await invokeVerb(agent(), 'availability_override_set', { day: THU, clear: true });
	});
});

describe('checks', () => {
	it('refuses overlapping times and says which', async () => {
		await expect(
			invokeVerb(person(), 'availability_set', {
				days: [
					{
						weekdays: [1],
						blocks: [
							{ start: '07:00', end: '18:30', kind: 'work' },
							{ start: '18:00', end: '20:00', kind: 'busy' }
						]
					}
				]
			})
		).rejects.toMatchObject({
			code: 'INVALID',
			message: 'Two times overlap on one day: 07:00 to 18:30 and 18:00 to 20:00.'
		});
	});

	it('refuses an override with nothing to say', async () => {
		await expect(
			invokeVerb(person(), 'availability_override_set', { day: SAT })
		).rejects.toMatchObject({
			code: 'INVALID',
			message: 'Give the times for that day, or say it is off.'
		});
	});

	it('refuses too long a range', async () => {
		await expect(
			invokeVerb(person(), 'free_slots', { from: '2030-01-01', to: '2030-03-01' })
		).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('at most a month')
		});
	});

	it('changes one setting and keeps the others', async () => {
		const a = (await invokeVerb(person(), 'availability_setting_set', {
			travelMinutes: 45
		})) as Availability;
		expect(a.travelMinutes).toBe(45);
		expect(a.awakeFrom).toBe('06:00');
	});
});

describe('replays', () => {
	it('returns a result for a repeated request without saving twice', async () => {
		const c = person();
		await invokeVerb(c, 'availability_set', WORK);
		const again = (await invokeVerb(c, 'availability_set', WORK)) as Availability;
		expect(again.days[1]?.blocks).toHaveLength(1);
	});
});
