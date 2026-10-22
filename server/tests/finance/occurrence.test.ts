// THE DUE DATES OF A BILL AFTER ITS OVERRIDES (BTL-20261022-0650): MOVED IN AND OUT OF A RANGE, SKIPPED, AND A STALE OVERRIDE IGNORED

// -- TYPES -- //
import type { OverrideLike } from '../../src/lib/finance/occurrence';
import type { Schedule } from '../../src/lib/finance/schedule';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { effectiveOccurrences, occurrenceOn } from '../../src/lib/finance/occurrence';

// -- CONSTANTS -- //

const MONTHLY_10: Schedule = { kind: 'monthly', day: 10 };

const override = (o: Partial<OverrideLike> & { originalDueDate: string }): OverrideLike => ({
	newDueDate: null,
	amount: null,
	accountId: null,
	skipped: false,
	...o
});

const ends = (list: { end: string }[]) => list.map((o) => o.end);

// -- TESTS -- //

describe('effective due dates', () => {
	it('is the schedule when there are no overrides', () => {
		const list = effectiveOccurrences(MONTHLY_10, '2026-11-01', '2027-01-31', {}, []);
		expect(ends(list)).toEqual(['2026-11-10', '2026-12-10', '2027-01-10']);
		expect(list.every((o) => o.override === null && o.original === o.end)).toBe(true);
	});

	it('moves one date and leaves the others', () => {
		const list = effectiveOccurrences(MONTHLY_10, '2026-11-01', '2026-12-31', {}, [
			override({ originalDueDate: '2026-11-10', newDueDate: '2026-11-14' })
		]);
		expect(ends(list)).toEqual(['2026-11-14', '2026-12-10']);
		expect(list[0]).toMatchObject({ original: '2026-11-10', start: '2026-11-14' });
	});

	it('finds a date moved into the range from outside it, and drops one moved out of it', () => {
		const moved = [override({ originalDueDate: '2026-11-10', newDueDate: '2026-11-14' })];
		// The schedule date (the 10th) is before the range, the moved date (the 14th) is inside
		expect(ends(effectiveOccurrences(MONTHLY_10, '2026-11-12', '2026-11-30', {}, moved))).toEqual([
			'2026-11-14'
		]);
		// The schedule date is inside the range, the moved date is after it
		expect(ends(effectiveOccurrences(MONTHLY_10, '2026-11-01', '2026-11-12', {}, moved))).toEqual(
			[]
		);
	});

	it('moves a date backwards across a month end', () => {
		const list = effectiveOccurrences(MONTHLY_10, '2026-10-25', '2026-10-31', {}, [
			override({ originalDueDate: '2026-11-10', newDueDate: '2026-10-28' })
		]);
		expect(ends(list)).toEqual(['2026-10-28']);
	});

	it('hides a skipped date', () => {
		const list = effectiveOccurrences(MONTHLY_10, '2026-11-01', '2026-12-31', {}, [
			override({ originalDueDate: '2026-11-10', skipped: true })
		]);
		expect(ends(list)).toEqual(['2026-12-10']);
	});

	it('carries the amount and the account of one date', () => {
		const [first] = effectiveOccurrences(MONTHLY_10, '2026-11-01', '2026-11-30', {}, [
			override({ originalDueDate: '2026-11-10', amount: 5_000, accountId: 'acc-1' })
		]);
		expect(first?.override).toMatchObject({ amount: 5_000, accountId: 'acc-1' });
		expect(first?.end).toBe('2026-11-10');
	});

	it('ignores an override that matches no date of the schedule', () => {
		const list = effectiveOccurrences(MONTHLY_10, '2026-11-01', '2026-11-30', {}, [
			override({ originalDueDate: '2026-11-11', skipped: true })
		]);
		expect(ends(list)).toEqual(['2026-11-10']);
	});

	it('keys an override by the date after the weekend rule', () => {
		// 2026-11-10 is a Tuesday; the 14th is a Saturday, so "before" moves it to Friday the 13th
		const sat: Schedule = { kind: 'monthly', day: 14 };
		const list = effectiveOccurrences(sat, '2026-11-01', '2026-11-30', { weekend: 'before' }, [
			override({ originalDueDate: '2026-11-13', newDueDate: '2026-11-16' })
		]);
		expect(ends(list)).toEqual(['2026-11-16']);
	});
});

describe('which date a day points at', () => {
	const list = effectiveOccurrences(MONTHLY_10, '2026-11-01', '2026-12-31', {}, [
		override({ originalDueDate: '2026-11-10', newDueDate: '2026-11-14' })
	]);

	it('knows a date by the day the schedule gave it or the day it was moved to', () => {
		expect(occurrenceOn(list, '2026-11-10')?.end).toBe('2026-11-14');
		expect(occurrenceOn(list, '2026-11-14')?.original).toBe('2026-11-10');
	});

	it('is null for a day that is no date of the bill', () => {
		expect(occurrenceOn(list, '2026-11-20')).toBeNull();
	});
});
