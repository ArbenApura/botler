// FLEXIBLE SCHEDULES (BTL-20261022-0218, S.1 TO S.4): NTH WEEKDAYS, WEEKS OF THE MONTH, DAY RANGES, EVERY K MONTHS, WINDOWS AND THE WEEKEND RULE

// -- TYPES -- //
import type { Schedule } from '../../src/lib/finance/schedule';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, weekday } from '../../src/lib/finance/dates';
import {
	describeSchedule,
	nextOccurrence,
	occurrencesBetween,
	previewOccurrences,
	validateSchedule,
	windowsBetween
} from '../../src/lib/finance/schedule';
import { scheduleInput } from '../../src/lib/server/db/zod';

// -- FUNCTIONS -- //

const ends = (s: Schedule, from: string, to: string, weekend?: 'none' | 'before' | 'after') =>
	windowsBetween(s, from, to, weekend ? { weekend } : {}).map((w) => w.end);

// -- TESTS -- //

describe('nth weekday of the month', () => {
	it('lists every 1st Wednesday, matching a wall calendar', () => {
		const s: Schedule = { kind: 'nth_weekday', n: 1, weekday: 3 };
		expect(ends(s, '2026-10-01', '2027-03-31')).toEqual([
			'2026-10-07',
			'2026-11-04',
			'2026-12-02',
			'2027-01-06',
			'2027-02-03',
			'2027-03-03'
		]);
	});

	it('skips a month that has no 5th such weekday', () => {
		const s: Schedule = { kind: 'nth_weekday', n: 5, weekday: 5 };
		// Only October 2026 and January 2027 have five Fridays in this stretch
		expect(ends(s, '2026-10-01', '2027-03-31')).toEqual(['2026-10-30', '2027-01-29']);
	});

	it('finds the last weekday, including a leap February', () => {
		const last: Schedule = { kind: 'nth_weekday', n: -1, weekday: 0 };
		expect(ends(last, '2028-02-01', '2028-02-29')).toEqual(['2028-02-27']);
		expect(ends(last, '2026-02-01', '2026-02-28')).toEqual(['2026-02-22']);
		const friday: Schedule = { kind: 'nth_weekday', n: -1, weekday: 5 };
		expect(ends(friday, '2026-10-01', '2026-12-31')).toEqual([
			'2026-10-30',
			'2026-11-27',
			'2026-12-25'
		]);
	});

	it('holds when the 1st of the month is itself the weekday', () => {
		// 2026-04-01 is a Wednesday
		const s: Schedule = { kind: 'nth_weekday', n: 1, weekday: 3 };
		expect(ends(s, '2026-04-01', '2026-04-30')).toEqual(['2026-04-01']);
	});
});

describe('week of the month', () => {
	it('keeps the whole week as a payment window, days 1 to 7', () => {
		const s: Schedule = { kind: 'week_of_month', n: 1, basis: 'days', pick: 'window' };
		expect(windowsBetween(s, '2026-10-01', '2026-11-30')).toEqual([
			{ start: '2026-10-01', end: '2026-10-07' },
			{ start: '2026-11-01', end: '2026-11-07' }
		]);
	});

	it('has a 5th week only when the month is long enough, and a last week of 7 days', () => {
		const fifth: Schedule = { kind: 'week_of_month', n: 5, basis: 'days', pick: 'window' };
		// February 2026 has 28 days: no 5th week. A leap February has one day in it
		expect(windowsBetween(fifth, '2026-02-01', '2026-02-28')).toEqual([]);
		expect(windowsBetween(fifth, '2028-02-01', '2028-02-29')).toEqual([
			{ start: '2028-02-29', end: '2028-02-29' }
		]);
		const last: Schedule = { kind: 'week_of_month', n: -1, basis: 'days', pick: 'window' };
		expect(windowsBetween(last, '2026-02-01', '2026-02-28')).toEqual([
			{ start: '2026-02-22', end: '2026-02-28' }
		]);
	});

	it('clips a calendar week at the month edge, for Monday and Sunday weeks', () => {
		const monday: Schedule = { kind: 'week_of_month', n: 1, basis: 'calendar', pick: 'window' };
		// October 2026 begins on a Thursday, November begins on a Sunday
		expect(windowsBetween(monday, '2026-10-01', '2026-11-30')).toEqual([
			{ start: '2026-10-01', end: '2026-10-04' },
			{ start: '2026-11-01', end: '2026-11-01' }
		]);
		const sunday: Schedule = {
			kind: 'week_of_month',
			n: 1,
			basis: 'calendar',
			weekStartsOn: 0,
			pick: 'window'
		};
		expect(windowsBetween(sunday, '2026-10-01', '2026-10-31')).toEqual([
			{ start: '2026-10-01', end: '2026-10-03' }
		]);
		const second: Schedule = { kind: 'week_of_month', n: 2, basis: 'calendar', pick: 'window' };
		expect(windowsBetween(second, '2026-10-01', '2026-10-31')).toEqual([
			{ start: '2026-10-05', end: '2026-10-11' }
		]);
	});

	it('picks one weekday of the first week and skips a month where it is outside the week', () => {
		const wed: Schedule = {
			kind: 'week_of_month',
			n: 1,
			basis: 'calendar',
			pick: 'weekday',
			weekday: 3
		};
		// Oct 2026: the first calendar week is Thu 1 to Sun 4, no Wednesday. Dec 2026: Tue 1 to Sun 6 holds Wed 2
		expect(ends(wed, '2026-10-01', '2026-12-31')).toEqual(['2026-12-02']);
		const days: Schedule = {
			kind: 'week_of_month',
			n: 1,
			basis: 'days',
			pick: 'weekday',
			weekday: 3
		};
		// Days 1 to 7 hold every weekday once
		expect(ends(days, '2026-10-01', '2026-12-31')).toEqual([
			'2026-10-07',
			'2026-11-04',
			'2026-12-02'
		]);
	});
});

describe('day range', () => {
	it('is a window from the first to the last day, clamped to a short month', () => {
		const s: Schedule = { kind: 'day_range', from: 5, to: 10 };
		expect(windowsBetween(s, '2026-10-01', '2026-10-31')).toEqual([
			{ start: '2026-10-05', end: '2026-10-10' }
		]);
		const late: Schedule = { kind: 'day_range', from: 29, to: 31 };
		expect(windowsBetween(late, '2026-02-01', '2026-02-28')).toEqual([
			{ start: '2026-02-28', end: '2026-02-28' }
		]);
		expect(windowsBetween(late, '2028-02-01', '2028-02-29')).toEqual([
			{ start: '2028-02-29', end: '2028-02-29' }
		]);
	});

	it('can run to the last day of the month', () => {
		const s: Schedule = { kind: 'day_range', from: 25, to: -1 };
		expect(windowsBetween(s, '2026-10-31', '2026-10-31')).toEqual([
			{ start: '2026-10-25', end: '2026-10-31' }
		]);
	});
});

describe('every few months, weeks and years', () => {
	it('never drifts over three years when counting every 3 months from an anchor month', () => {
		const s: Schedule = { kind: 'monthly', day: 15, everyMonths: 3, anchorMonth: '2026-01' };
		const got = ends(s, '2026-01-01', '2028-12-31');
		expect(got).toHaveLength(12);
		expect(got[0]).toBe('2026-01-15');
		expect(got[11]).toBe('2028-10-15');
		// The same cycle seen from a window that starts before the anchor
		expect(ends(s, '2025-01-01', '2025-12-31')).toEqual([
			'2025-01-15',
			'2025-04-15',
			'2025-07-15',
			'2025-10-15'
		]);
	});

	it('counts every 2 months and ends on the last day', () => {
		const s: Schedule = { kind: 'monthly', day: -1, everyMonths: 2, anchorMonth: '2026-10' };
		expect(ends(s, '2026-10-01', '2027-03-31')).toEqual(['2026-10-31', '2026-12-31', '2027-02-28']);
	});

	it('repeats weekly on chosen days, and every 2 weeks from an anchor', () => {
		const mwf: Schedule = { kind: 'weekly', days: [1, 3, 5] };
		expect(ends(mwf, '2026-10-19', '2026-10-25')).toEqual([
			'2026-10-19',
			'2026-10-21',
			'2026-10-23'
		]);
		const biweekly: Schedule = { kind: 'weekly', days: [5], everyWeeks: 2, anchor: '2026-10-02' };
		expect(ends(biweekly, '2026-10-01', '2026-11-30')).toEqual([
			'2026-10-02',
			'2026-10-16',
			'2026-10-30',
			'2026-11-13',
			'2026-11-27'
		]);
		// An anchor after the window keeps the same alignment
		const later: Schedule = { kind: 'weekly', days: [5], everyWeeks: 2, anchor: '2026-12-25' };
		expect(ends(later, '2026-10-01', '2026-10-31')).toEqual([
			'2026-10-02',
			'2026-10-16',
			'2026-10-30'
		]);
	});

	it('moves February 29 to the 28th in a common year', () => {
		const s: Schedule = { kind: 'yearly', month: 2, day: 29 };
		expect(ends(s, '2027-01-01', '2028-12-31')).toEqual(['2027-02-28', '2028-02-29']);
	});
});

describe('weekend rule with windows', () => {
	it('moves the end of a window only', () => {
		const s: Schedule = { kind: 'day_range', from: 5, to: 11 };
		// 2026-10-11 is a Sunday
		expect(windowsBetween(s, '2026-10-01', '2026-10-31', { weekend: 'before' })).toEqual([
			{ start: '2026-10-05', end: '2026-10-09' }
		]);
		expect(windowsBetween(s, '2026-10-01', '2026-10-31', { weekend: 'after' })).toEqual([
			{ start: '2026-10-05', end: '2026-10-12' }
		]);
	});

	it('pulls the start back when the moved end would pass it', () => {
		// 2026-11-01 is a Sunday; the first calendar week is that one day
		const s: Schedule = { kind: 'week_of_month', n: 1, basis: 'calendar', pick: 'window' };
		expect(windowsBetween(s, '2026-10-25', '2026-10-31', { weekend: 'before' })).toEqual([
			{ start: '2026-10-30', end: '2026-10-30' }
		]);
	});
});

describe('old shapes and the old functions', () => {
	it('still parses and produces the same dates for every stored shape', () => {
		const shapes: Schedule[] = [
			{ kind: 'monthly', day: 31 },
			{ kind: 'semi_monthly', days: [15, 30] },
			{ kind: 'every_n_days', anchor: '2026-01-02', n: 14 }
		];
		for (const s of shapes) {
			expect(scheduleInput.safeParse(s).success).toBe(true);
			expect(validateSchedule(s)).toBeNull();
		}
		expect(occurrencesBetween({ kind: 'monthly', day: 31 }, '2026-02-01', '2026-04-30')).toEqual([
			'2026-02-28',
			'2026-03-31',
			'2026-04-30'
		]);
		expect(
			occurrencesBetween({ kind: 'semi_monthly', days: [15, 30] }, '2026-02-01', '2026-02-28')
		).toEqual(['2026-02-15', '2026-02-28']);
		expect(nextOccurrence({ kind: 'monthly', day: 5 }, '2026-10-05')).toBe('2026-11-05');
	});

	it('explains a bad schedule in words', () => {
		expect(validateSchedule({ kind: 'nth_weekday', n: 6, weekday: 3 })).toMatch(/1st to the 5th/);
		expect(validateSchedule({ kind: 'weekly', days: [] })).toMatch(/days of the week/);
		expect(validateSchedule({ kind: 'monthly', day: 5, everyMonths: 3 })).toMatch(/anchorMonth/);
		expect(validateSchedule({ kind: 'day_range', from: 10, to: 5 })).toMatch(/not be after/);
		expect(validateSchedule({ kind: 'yearly', month: 2, day: 30 })).toMatch(/not in that month/);
		expect(() =>
			windowsBetween({ kind: 'nth_weekday', n: 9, weekday: 1 }, '2026-01-01', '2026-02-01')
		).toThrow(RangeError);
	});
});

describe('describe and preview', () => {
	it('says what a schedule means in a key plus arguments and in English', () => {
		const first = describeSchedule({ kind: 'nth_weekday', n: 1, weekday: 3 });
		expect(first.text).toBe('Every 1st Wednesday of the month');
		expect(first.key).toBe('schedule.nth_weekday');
		expect(first.args).toEqual({ n: 1, weekday: 3 });
		expect(
			describeSchedule({ kind: 'week_of_month', n: 1, basis: 'days', pick: 'window' }).text
		).toBe('Any day in the 1st week of the month (days 1 to 7)');
		expect(describeSchedule({ kind: 'day_range', from: 5, to: 10 }).text).toBe(
			'Any day between the 5th and the 10th'
		);
		expect(describeSchedule({ kind: 'nth_weekday', n: -1, weekday: 5 }).text).toBe(
			'Every last Friday of the month'
		);
		expect(
			describeSchedule({ kind: 'monthly', day: 15, everyMonths: 2, anchorMonth: '2026-10' }).text
		).toBe('On the 15th of the month every 2 months');
	});

	it('previews the next windows from a date', () => {
		const s: Schedule = { kind: 'nth_weekday', n: 1, weekday: 3 };
		expect(previewOccurrences(s, '2026-10-08', 3).map((w) => w.end)).toEqual([
			'2026-11-04',
			'2026-12-02',
			'2027-01-06'
		]);
		// A cycle of 12 months still finds its next date
		const yearly: Schedule = { kind: 'monthly', day: 10, everyMonths: 12, anchorMonth: '2026-03' };
		expect(previewOccurrences(yearly, '2026-04-01', 1).map((w) => w.end)).toEqual(['2027-03-10']);
	});
});

describe('every schedule keeps its dates ordered, unique and inside the range', () => {
	// A small deterministic generator, so a failure can be reproduced
	let seed = 20261022;
	const rnd = (n: number) => {
		seed = (seed * 1_664_525 + 1_013_904_223) % 4_294_967_296;
		return seed % n;
	};
	const pickSchedule = (): Schedule => {
		const every = [1, 1, 2, 3, 6, 12][rnd(6)] ?? 1;
		const cycle = every > 1 ? { everyMonths: every, anchorMonth: '2026-03' } : {};
		switch (rnd(8)) {
			case 0:
				return { kind: 'monthly', day: rnd(32) === 0 ? -1 : 1 + rnd(31), ...cycle };
			case 1:
				return { kind: 'semi_monthly', days: [1 + rnd(14), 15 + rnd(17)] };
			case 2:
				return { kind: 'every_n_days', anchor: '2026-01-03', n: 1 + rnd(60) };
			case 3:
				return {
					kind: 'weekly',
					days: [rnd(7)],
					...(rnd(2) ? { everyWeeks: 2, anchor: '2026-02-04' } : {})
				};
			case 4:
				return {
					kind: 'nth_weekday',
					n: [1, 2, 3, 4, 5, -1][rnd(6)] ?? 1,
					weekday: rnd(7),
					...cycle
				};
			case 5:
				return {
					kind: 'week_of_month',
					n: [1, 2, 3, 4, 5, -1][rnd(6)] ?? 1,
					basis: rnd(2) ? 'days' : 'calendar',
					weekStartsOn: rnd(2),
					pick: rnd(2) ? 'window' : 'weekday',
					weekday: rnd(7),
					...cycle
				};
			case 6: {
				const from = 1 + rnd(28);
				return {
					kind: 'day_range',
					from,
					to: rnd(5) === 0 ? -1 : from + rnd(31 - from + 1),
					...cycle
				};
			}
			default:
				return { kind: 'yearly', month: 1 + rnd(12), day: 1 + rnd(28) };
		}
	};

	it('holds for 400 random schedules, ranges and weekend rules', () => {
		for (let i = 0; i < 400; i++) {
			const s = pickSchedule();
			expect(validateSchedule(s), JSON.stringify(s)).toBeNull();
			const from = addDays('2026-01-01', rnd(900));
			const to = addDays(from, rnd(400));
			const rule = (['none', 'before', 'after'] as const)[rnd(3)] ?? 'none';
			const windows = windowsBetween(s, from, to, { weekend: rule });
			let previous = '';
			for (const w of windows) {
				expect(w.start <= w.end, JSON.stringify([s, w])).toBe(true);
				expect(w.end >= from && w.end <= to, JSON.stringify([s, w, from, to])).toBe(true);
				expect(w.end > previous, JSON.stringify([s, windows])).toBe(true);
				previous = w.end;
				if (rule !== 'none') expect([0, 6]).not.toContain(weekday(w.end));
			}
			// The old function agrees with the new one
			expect(occurrencesBetween(s, from, to, { weekend: rule })).toEqual(windows.map((w) => w.end));
		}
	});
});
