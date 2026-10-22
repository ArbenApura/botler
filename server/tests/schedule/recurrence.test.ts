// RECURRENCE (P5.5): DAILY, WEEKLY, MONTHLY AND EVERY-N-DAYS RULES AT A MANILA CLOCK TIME, INCLUDING THE DAY BOUNDARY AND SHORT MONTHS

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	atManilaTime,
	nextOccurrence,
	recurrenceOccurrences,
	validateRecurrence
} from '../../src/lib/schedule/recurrence';

// -- CONSTANTS -- //

const at = (iso: string) => new Date(iso);
const iso = (ds: Date[]) => ds.map((d) => d.toISOString());

// -- TESTS -- //

describe('clock times in Manila', () => {
	it('puts 06:30 Manila at 22:30 UTC the evening before', () => {
		expect(atManilaTime('2026-10-22', '06:30').toISOString()).toBe('2026-10-21T22:30:00.000Z');
		expect(atManilaTime('2026-10-22', '00:00').toISOString()).toBe('2026-10-21T16:00:00.000Z');
		expect(atManilaTime('2026-10-22', '23:59').toISOString()).toBe('2026-10-22T15:59:00.000Z');
	});

	it('refuses a time that is not a clock time', () => {
		for (const bad of ['6:30', '24:00', '12:60', 'noon', ''])
			expect(validateRecurrence({ freq: 'daily', time: bad })).toMatch(/06:30/);
	});
});

describe('daily and weekly', () => {
	it('fires every day at the time, in order, without a repeat', () => {
		const got = recurrenceOccurrences(
			{ freq: 'daily', time: '07:00' },
			at('2026-10-20T00:00:00Z'),
			at('2026-10-23T00:00:00Z')
		);
		expect(iso(got)).toEqual([
			'2026-10-20T23:00:00.000Z',
			'2026-10-21T23:00:00.000Z',
			'2026-10-22T23:00:00.000Z'
		]);
	});

	it('uses the Manila weekday, not the UTC one', () => {
		// 2026-10-26 is a Monday in Manila; 01:00 Manila is still Sunday evening in UTC
		const got = recurrenceOccurrences(
			{ freq: 'weekly', days: [1], time: '01:00' },
			at('2026-10-20T00:00:00Z'),
			at('2026-11-05T00:00:00Z')
		);
		expect(iso(got)).toEqual(['2026-10-25T17:00:00.000Z', '2026-11-01T17:00:00.000Z']);
	});

	it('does the gym on Monday, Wednesday and Friday', () => {
		const got = recurrenceOccurrences(
			{ freq: 'weekly', days: [1, 3, 5], time: '06:00' },
			at('2026-10-25T00:00:00Z'),
			at('2026-11-01T00:00:00Z')
		);
		expect(got).toHaveLength(3);
		expect(iso(got)[0]).toBe('2026-10-25T22:00:00.000Z');
	});
});

describe('monthly and every n days', () => {
	it('clamps the 31st to the last day of a short month', () => {
		const got = recurrenceOccurrences(
			{ freq: 'monthly', day: 31, time: '09:00' },
			at('2026-01-01T00:00:00Z'),
			at('2026-05-01T00:00:00Z')
		);
		expect(iso(got)).toEqual([
			'2026-01-31T01:00:00.000Z',
			'2026-02-28T01:00:00.000Z',
			'2026-03-31T01:00:00.000Z',
			'2026-04-30T01:00:00.000Z'
		]);
	});

	it('keeps a 14 day cycle exactly', () => {
		const got = recurrenceOccurrences(
			{ freq: 'every_n_days', anchor: '2026-01-02', n: 14, time: '08:00' },
			at('2026-01-01T00:00:00Z'),
			at('2026-12-31T00:00:00Z')
		);
		expect(got).toHaveLength(26);
		for (let i = 1; i < got.length; i++)
			expect((got[i] as Date).getTime() - (got[i - 1] as Date).getTime()).toBe(14 * 86_400_000);
	});
});

describe('windows and next', () => {
	it('includes both ends of the window and nothing outside', () => {
		const rule = { freq: 'daily', time: '12:00' } as const;
		const noon = atManilaTime('2026-10-21', '12:00');
		expect(recurrenceOccurrences(rule, noon, noon)).toHaveLength(1);
		expect(
			recurrenceOccurrences(
				rule,
				new Date(noon.getTime() + 1),
				new Date(noon.getTime() + 3_600_000)
			)
		).toHaveLength(0);
	});

	it('finds the next moment strictly after now', () => {
		const rule = { freq: 'weekly', days: [3], time: '09:00' } as const;
		// 2026-10-21 is a Wednesday. At 09:00 Manila sharp the next is a week later
		const now = atManilaTime('2026-10-21', '09:00');
		expect(nextOccurrence(rule, now)?.toISOString()).toBe(
			atManilaTime('2026-10-28', '09:00').toISOString()
		);
		expect(nextOccurrence(rule, new Date(now.getTime() - 1))?.toISOString()).toBe(
			now.toISOString()
		);
	});

	it('refuses invalid rules', () => {
		expect(validateRecurrence({ freq: 'weekly', days: [], time: '09:00' })).toMatch(/days/);
		expect(validateRecurrence({ freq: 'weekly', days: [7], time: '09:00' })).toMatch(/days/);
		expect(validateRecurrence({ freq: 'monthly', day: 0, time: '09:00' })).toMatch(/1 to 31/);
		expect(
			validateRecurrence({ freq: 'every_n_days', anchor: '2026-01-01', n: 0, time: '09:00' })
		).toMatch(/366/);
		expect(() =>
			recurrenceOccurrences({ freq: 'weekly', days: [], time: '09:00' }, new Date(), new Date())
		).toThrow();
	});
});

describe('routines on the flexible schedules (BTL-20261022-0218, S.5)', () => {
	it('fires on the 1st Wednesday of the month at the clock time', () => {
		const r = {
			freq: 'schedule',
			schedule: { kind: 'nth_weekday', n: 1, weekday: 3 },
			time: '07:30'
		} as const;
		expect(validateRecurrence(r)).toBeNull();
		// 07:30 Manila is 23:30 UTC the evening before
		expect(
			iso(recurrenceOccurrences(r, at('2026-10-01T00:00:00Z'), at('2026-12-31T00:00:00Z')))
		).toEqual(['2026-10-06T23:30:00.000Z', '2026-11-03T23:30:00.000Z', '2026-12-01T23:30:00.000Z']);
	});

	it('fires a week window on its first day, and finds it from inside the window', () => {
		const r = {
			freq: 'schedule',
			schedule: { kind: 'week_of_month', n: 1, basis: 'days', pick: 'window' },
			time: '09:00'
		} as const;
		expect(
			iso(recurrenceOccurrences(r, at('2026-10-01T00:00:00Z'), at('2026-11-30T00:00:00Z')))
		).toEqual(['2026-10-01T01:00:00.000Z', '2026-11-01T01:00:00.000Z']);
		// A range that starts in the middle of the window does not fire it again
		expect(
			recurrenceOccurrences(r, at('2026-10-03T00:00:00Z'), at('2026-10-20T00:00:00Z'))
		).toEqual([]);
	});

	it('refuses a bad schedule or time in words, and finds the next moment', () => {
		expect(
			validateRecurrence({
				freq: 'schedule',
				schedule: { kind: 'nth_weekday', n: 9, weekday: 3 },
				time: '07:30'
			})
		).toMatch(/1st to the 5th/);
		expect(
			validateRecurrence({
				freq: 'schedule',
				schedule: { kind: 'nth_weekday', n: 1, weekday: 3 },
				time: '7:30'
			})
		).toMatch(/06:30/);
		const next = nextOccurrence(
			{ freq: 'schedule', schedule: { kind: 'day_range', from: 5, to: 10 }, time: '08:00' },
			at('2026-10-05T01:00:00Z')
		);
		expect(next?.toISOString()).toBe('2026-11-05T00:00:00.000Z');
	});
});
