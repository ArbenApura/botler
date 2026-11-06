// A NEGATIVE WALLET AND AN OVERDUE BILL ARE EXPLAINED IN THE FORECAST'S OWN NOTES (BTL-20261106-1502)
// The case is the owner's GCash of 6 Nov 2026: 272.73 today, 250.00 put in on each of two paydays, then the Mommy allowance of 1,000.00 on the 25th.

// -- TYPES -- //
import type { ForecastFlow, ForecastWallet, Warning } from '../../src/lib/finance/forecast';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { overdueNotes, warningNotes } from '../../src/lib/server/ops/forecast';

// -- CONSTANTS -- //

const wallets: ForecastWallet[] = [
	{ accountId: 'gcash', accountName: 'GCash', currency: 'PHP', balance: 27_273 },
	{ accountId: 'rcbc', accountName: 'RCBC', currency: 'PHP', balance: 1_000_000 }
];
const move = (date: string): ForecastFlow => ({
	kind: 'move',
	date,
	label: 'GCash',
	accountId: 'rcbc',
	accountName: 'RCBC',
	toAccountId: 'gcash',
	toAccountName: 'GCash',
	currency: 'PHP',
	amount: 25_000
});
const flows: ForecastFlow[] = [
	move('2026-11-09'),
	move('2026-11-16'),
	{
		kind: 'out',
		date: '2026-11-25',
		label: 'Mommy allowance',
		accountId: 'gcash',
		accountName: 'GCash',
		currency: 'PHP',
		amount: 100_000
	}
];
const warning: Warning = {
	date: '2026-11-25',
	accountId: 'gcash',
	accountName: 'GCash',
	currency: 'PHP',
	balance: -22_727,
	already: false
};

// -- TESTS -- //

describe('warningNotes', () => {
	it('names the bill that empties the wallet and what came in before it', () => {
		const [note] = warningNotes([warning], flows, wallets, '2026-11-06');
		expect(note).toContain('GCash goes below zero on 2026-11-25');
		expect(note).toContain('Mommy allowance 100000');
		expect(note).toContain('50000 was put in on 2 paydays before it (2026-11-09, 2026-11-16)');
		expect(note).toContain('held 27273 today');
	});
	it('says so when nothing is put in before it, and when a wallet starts below zero', () => {
		const [none] = warningNotes([warning], flows.slice(2), wallets, '2026-11-06');
		expect(none).toContain('nothing is put in before it');
		const [already] = warningNotes([{ ...warning, already: true }], [], wallets, '2026-11-06');
		expect(already).toContain('already below zero today');
	});
});

describe('overdueNotes', () => {
	it('names a late bill as overdue and unpaid', () => {
		const late: ForecastFlow = {
			kind: 'out',
			date: '2026-11-06',
			label: 'Meralco part 2/3 (late, was due 2026-11-02)',
			accountId: 'rcbc',
			accountName: 'RCBC',
			currency: 'PHP',
			amount: 300_000
		};
		const [note] = overdueNotes([late, flows[2]!]);
		expect(note).toContain('OVERDUE and still unpaid');
		expect(note).toContain('Meralco part 2/3');
		expect(note).not.toContain('Mommy');
	});
	it('says nothing when no bill is late', () => {
		expect(overdueNotes(flows)).toEqual([]);
	});
});
