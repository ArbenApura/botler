// THE DUE DATES OF BILLS FROM LOADED ROWS: WINDOWS, A MOVED OR CHANGED DATE, THE PAID OVERLAP AND THE AMOUNT, WITH NO DATABASE

// -- TYPES -- //
import type { BillLike } from '../../src/lib/finance/billWindows';
import type { OverrideLike } from '../../src/lib/finance/occurrence';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { billOccurrences } from '../../src/lib/finance/billWindows';

// -- CONSTANTS -- //

const RENT: BillLike = {
	id: 'rent',
	name: 'Rent',
	category: 'rent',
	accountId: 'rcbc',
	schedule: { kind: 'monthly', day: 5 },
	weekendRule: 'none',
	deferrable: false,
	startsOn: null,
	currency: 'PHP'
};

const NET: BillLike = {
	...RENT,
	id: 'net',
	name: 'Internet',
	schedule: { kind: 'monthly', day: 20 }
};

// -- TESTS -- //

describe('billOccurrences', () => {
	it('lists every date in the range, sorted, with the amount and the paid overlap', () => {
		const out = billOccurrences<OverrideLike>(
			[RENT, NET],
			'2026-01-01',
			'2026-02-28',
			new Map(),
			new Map([['rent', [{ start: '2026-01-05', end: '2026-01-05' }]]]),
			new Map([
				['rent', 1_500_000],
				['net', null]
			])
		);
		expect(out.map((b) => `${b.dueDate} ${b.billId}`)).toEqual([
			'2026-01-05 rent',
			'2026-01-20 net',
			'2026-02-05 rent',
			'2026-02-20 net'
		]);
		expect(out.map((b) => b.paid)).toEqual([true, false, false, false]);
		expect(out[0]?.amount).toBe(1_500_000);
		expect(out[1]).toMatchObject({ amount: null, unknownAmount: true });
	});

	it('takes a changed amount, account and date from the override of one date', () => {
		const override: OverrideLike = {
			originalDueDate: '2026-02-05',
			newDueDate: '2026-02-09',
			amount: 99_900,
			accountId: 'gcash',
			skipped: false
		};
		const out = billOccurrences(
			[RENT],
			'2026-02-01',
			'2026-02-28',
			new Map([['rent', [override]]]),
			new Map(),
			new Map([['rent', 1_500_000]])
		);
		expect(out).toHaveLength(1);
		expect(out[0]).toMatchObject({
			dueDate: '2026-02-09',
			originalDueDate: '2026-02-05',
			overridden: true,
			amount: 99_900,
			accountId: 'gcash'
		});
	});
});
