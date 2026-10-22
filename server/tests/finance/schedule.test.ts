// SCHEDULE SEMANTICS AND MANILA DATES (P2.8): FEBRUARY, THE 31ST, THE 14 DAY ANCHOR OVER A YEAR AND THE MANILA MIDNIGHT BOUNDARY

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	addDays,
	diffDays,
	isDate,
	manilaNoon,
	manilaStart,
	toManilaDate,
	weekday
} from '../../src/lib/finance/dates';
import {
	adjustForWeekend,
	nextOccurrence,
	occurrencesBetween,
	validateSchedule
} from '../../src/lib/finance/schedule';

// -- TESTS -- //

describe('manila dates', () => {
	it('knows real calendar dates only', () => {
		expect(isDate('2028-02-29')).toBe(true);
		expect(isDate('2026-02-29')).toBe(false);
		expect(isDate('2026-13-01')).toBe(false);
		expect(isDate('2026-2-3')).toBe(false);
	});

	it('crosses month, year and leap day boundaries', () => {
		expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
		expect(addDays('2028-02-28', 1)).toBe('2028-02-29');
		expect(addDays('2026-02-28', 1)).toBe('2026-03-01');
		expect(diffDays('2027-01-01', '2026-01-01')).toBe(365);
		expect(weekday('2026-10-21')).toBe(3);
	});

	it('moves the day at Manila midnight, which is 16:00 UTC', () => {
		expect(toManilaDate(new Date('2026-10-21T15:59:59Z'))).toBe('2026-10-21');
		expect(toManilaDate(new Date('2026-10-21T16:00:00Z'))).toBe('2026-10-22');
		expect(manilaStart('2026-10-22').toISOString()).toBe('2026-10-21T16:00:00.000Z');
		expect(toManilaDate(manilaNoon('2026-10-22'))).toBe('2026-10-22');
	});
});

describe('monthly and semi monthly', () => {
	it('clamps a due day of 31 to the last day of a short month', () => {
		const got = occurrencesBetween({ kind: 'monthly', day: 31 }, '2026-01-01', '2026-06-30');
		expect(got).toEqual([
			'2026-01-31',
			'2026-02-28',
			'2026-03-31',
			'2026-04-30',
			'2026-05-31',
			'2026-06-30'
		]);
	});

	it('uses February 29 in a leap year and 28 otherwise', () => {
		expect(occurrencesBetween({ kind: 'monthly', day: 30 }, '2028-02-01', '2028-02-29')).toEqual([
			'2028-02-29'
		]);
		expect(occurrencesBetween({ kind: 'monthly', day: 30 }, '2027-02-01', '2027-02-28')).toEqual([
			'2027-02-28'
		]);
	});

	it('gives two paydays a month and never a repeat when both clamp to the same day', () => {
		const s = { kind: 'semi_monthly', days: [15, 30] } as const;
		expect(occurrencesBetween(s, '2026-02-01', '2026-03-31')).toEqual([
			'2026-02-15',
			'2026-02-28',
			'2026-03-15',
			'2026-03-30'
		]);
		const both = { kind: 'semi_monthly', days: [30, 31] } as const;
		expect(occurrencesBetween(both, '2026-02-01', '2026-02-28')).toEqual(['2026-02-28']);
	});

	it('counts the window ends inclusively', () => {
		expect(occurrencesBetween({ kind: 'monthly', day: 15 }, '2026-10-15', '2026-10-15')).toEqual([
			'2026-10-15'
		]);
	});
});

describe('every n days', () => {
	const s = { kind: 'every_n_days', anchor: '2026-01-02', n: 14 } as const;

	it('keeps a 14 day cycle exactly over a year', () => {
		const got = occurrencesBetween(s, '2026-01-01', '2026-12-31');
		expect(got).toHaveLength(26);
		for (let i = 1; i < got.length; i++)
			expect(diffDays(got[i] as string, got[i - 1] as string)).toBe(14);
		expect(got[0]).toBe('2026-01-02');
		expect(got.at(-1)).toBe('2026-12-18');
	});

	it('reaches dates before the anchor and finds the next one', () => {
		expect(occurrencesBetween(s, '2025-12-01', '2025-12-31')).toEqual(['2025-12-05', '2025-12-19']);
		expect(nextOccurrence(s, '2026-10-21')).toBe('2026-10-23');
		expect(nextOccurrence(s, '2026-10-23')).toBe('2026-11-06');
	});
});

describe('weekend and holiday rule', () => {
	it('moves off a weekend before or after', () => {
		// 2026-10-31 is a Saturday
		expect(adjustForWeekend('2026-10-31', 'before')).toBe('2026-10-30');
		expect(adjustForWeekend('2026-10-31', 'after')).toBe('2026-11-02');
		expect(adjustForWeekend('2026-10-31', 'none')).toBe('2026-10-31');
	});

	it('skips a holiday next to a weekend', () => {
		expect(adjustForWeekend('2026-10-31', 'after', ['2026-11-02'])).toBe('2026-11-03');
	});

	it('counts a payday moved into the window and not one moved out of it', () => {
		const s = { kind: 'monthly', day: 31 } as const;
		expect(occurrencesBetween(s, '2026-10-01', '2026-10-30', { weekend: 'before' })).toEqual([
			'2026-10-30'
		]);
		expect(occurrencesBetween(s, '2026-10-31', '2026-10-31', { weekend: 'before' })).toEqual([]);
	});
});

describe('validation', () => {
	it('names the problem in plain words', () => {
		expect(validateSchedule({ kind: 'monthly', day: 0 })).toMatch(/1 to 31/);
		expect(validateSchedule({ kind: 'semi_monthly', days: [15, 15] })).toMatch(/different/);
		expect(validateSchedule({ kind: 'every_n_days', anchor: '2026-02-30', n: 14 })).toMatch(/date/);
		expect(validateSchedule({ kind: 'every_n_days', anchor: '2026-02-01', n: 0 })).toMatch(/366/);
		expect(validateSchedule({ kind: 'monthly', day: 15 })).toBeNull();
	});

	it('refuses to generate dates from an invalid schedule', () => {
		expect(() =>
			occurrencesBetween({ kind: 'monthly', day: 40 }, '2026-01-01', '2026-02-01')
		).toThrow();
	});
});
