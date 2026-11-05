// WORK HOURS AND FREE TIME (BTL-20261105-0015, P2.1): THE OWNER'S WEEK, A WORKING SATURDAY, AN OVERNIGHT SHIFT AND NEVER A SLOT AT 3 AM

// -- TYPES -- //
import type {
	AvailabilityInput,
	Block,
	FreeSlot,
	WeeklyBlock
} from '../../src/lib/schedule/availability';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	blocksProblem,
	DEFAULT_AVAILABILITY,
	freeSlots,
	freeSlotsOn,
	minuteOf,
	timeOf
} from '../../src/lib/schedule/availability';

// -- CONSTANTS -- //

const WORK: WeeklyBlock[] = [1, 2, 3, 4, 5].map((weekday) => ({
	weekday,
	startMinute: 420,
	endMinute: 1110,
	kind: 'work' as const
}));
const THU = '2026-11-26';
const SAT = '2026-11-28';

// -- FUNCTIONS -- //

const input = (over: Partial<AvailabilityInput> = {}): AvailabilityInput => ({
	weekly: WORK,
	overrides: [],
	settings: DEFAULT_AVAILABILITY,
	events: [],
	...over
});
const times = (slots: FreeSlot[]) =>
	slots.map((s) => `${timeOf(s.startMinute)}-${timeOf(s.endMinute)}`);

// -- TESTS -- //

describe('the owner week', () => {
	it('a work day has free time only before the trip and after it', () => {
		expect(times(freeSlotsOn(THU, input()))).toEqual(['06:00-06:30', '19:00-22:00']);
	});

	it('a weekend with no blocks is free inside the waking hours', () => {
		expect(times(freeSlotsOn(SAT, input()))).toEqual(['06:00-22:00']);
	});

	it('gives Manila instants', () => {
		const [, evening] = freeSlotsOn(THU, input());
		expect(evening?.startsAt).toBe('2026-11-26T11:00:00.000Z');
		expect(evening?.minutes).toBe(180);
	});

	it('never offers a slot outside the waking hours', () => {
		for (const s of freeSlots('2026-11-23', '2026-11-29', input())) {
			expect(s.startMinute).toBeGreaterThanOrEqual(360);
			expect(s.endMinute).toBeLessThanOrEqual(1320);
		}
	});

	it('filters by length', () => {
		expect(times(freeSlots(THU, THU, input(), 60))).toEqual(['19:00-22:00']);
	});
});

describe('one-date changes', () => {
	const working: Block = { startMinute: 540, endMinute: 900, kind: 'work' };

	it('a suddenly working Saturday loses those hours', () => {
		const i = input({ overrides: [{ day: SAT, off: false, blocks: [working] }] });
		expect(times(freeSlotsOn(SAT, i))).toEqual(['06:00-08:30', '15:30-22:00']);
	});

	it('a day off removes the work', () => {
		const i = input({ overrides: [{ day: THU, off: true, blocks: [] }] });
		expect(times(freeSlotsOn(THU, i))).toEqual(['06:00-22:00']);
	});
});

describe('blocks across midnight', () => {
	const night: WeeklyBlock = { weekday: 4, startMinute: 1320, endMinute: 360, kind: 'work' };

	it('takes the start of the next day too', () => {
		const i = input({ weekly: [night] });
		expect(times(freeSlotsOn('2026-11-27', i))).toEqual(['06:30-22:00']);
	});

	it('the tail still applies when the next date has its own change', () => {
		const i = input({
			weekly: [night],
			overrides: [{ day: '2026-11-27', off: true, blocks: [] }]
		});
		expect(times(freeSlotsOn('2026-11-27', i))).toEqual(['06:30-22:00']);
	});

	it('a late finish spills the trip home into the next day', () => {
		const late: WeeklyBlock = { weekday: 4, startMinute: 900, endMinute: 1430, kind: 'work' };
		const noWake = { wakeStartMinute: 0, wakeEndMinute: 120, travelMinutes: 30 };
		const i = input({ weekly: [late], settings: noWake });
		expect(times(freeSlotsOn('2026-11-27', i))).toEqual(['00:20-02:00']);
	});
});

describe('free blocks and the calendar', () => {
	it('uses named free time, and work wins over it', () => {
		const i = input({
			weekly: [
				{ weekday: 6, startMinute: 480, endMinute: 720, kind: 'free' },
				{ weekday: 6, startMinute: 600, endMinute: 660, kind: 'busy' }
			]
		});
		expect(times(freeSlotsOn(SAT, i))).toEqual(['08:00-10:00', '11:00-12:00']);
	});

	it('takes calendar events out', () => {
		const i = input({
			events: [
				{
					startsAt: new Date('2026-11-26T12:00:00Z'),
					endsAt: new Date('2026-11-26T13:00:00Z')
				}
			]
		});
		expect(times(freeSlotsOn(THU, i))).toEqual(['06:00-06:30', '19:00-20:00', '21:00-22:00']);
	});
});

describe('checks', () => {
	it('names an overlap', () => {
		expect(
			blocksProblem([
				{ startMinute: 420, endMinute: 1110, kind: 'work' },
				{ startMinute: 1000, endMinute: 1200, kind: 'free' }
			])
		).toBe('Two times overlap on one day: 07:00 to 18:30 and 16:40 to 20:00.');
		expect(blocksProblem([{ startMinute: 420, endMinute: 1110, kind: 'work' }])).toBeNull();
	});

	it('reads and writes clock times', () => {
		expect(minuteOf('18:30')).toBe(1110);
		expect(timeOf(1110)).toBe('18:30');
	});
});
