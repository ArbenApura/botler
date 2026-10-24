// THE LEDGER MODEL (P2.7), THE ESTIMATOR (P2.6, P2.9), AMOUNT CONFIRMATION (P2.10) AND THE TEXT READERS (P2.4)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { checkBalanceChange, needsAmountConfirmation } from '../../src/lib/finance/confirm';
import { estimateBill, median } from '../../src/lib/finance/estimator';
import {
	balanceOf,
	driftOf,
	effectOn,
	spendingOf,
	untrackedSpendingOf
} from '../../src/lib/finance/ledger';
import type { Txn } from '../../src/lib/finance/ledger';
import { formatPhp, mulDiv, pesosToCentavos } from '../../src/lib/finance/money';
import { parseExpenseText, parseRuleText } from '../../src/lib/finance/text';

// -- CONSTANTS -- //

const at = (iso: string) => new Date(iso);
const txn = (t: Partial<Txn> & Pick<Txn, 'type' | 'amount'>): Txn => ({
	accountId: 'gcash',
	currency: 'PHP',
	occurredAt: at('2026-10-22T00:00:00Z'),
	...t
});

// -- TESTS -- //

describe('money', () => {
	it('keeps pesos exact in centavos and formats from integers', () => {
		expect(pesosToCentavos(180.1)).toBe(18010);
		expect(pesosToCentavos(0.29)).toBe(29);
		expect(formatPhp(123450)).toBe('₱1,234.50');
		expect(formatPhp(-5)).toBe('-₱0.05');
		expect(mulDiv(100_001, 3333, 10_000)).toBe(33_330);
	});
});

describe('ledger', () => {
	it('adds a snapshot and the signed transactions after it', () => {
		const snap = { amount: 100_000, takenAt: at('2026-10-21T00:00:00Z') };
		const rows = [
			txn({ type: 'income', amount: 50_000 }),
			txn({ type: 'expense', amount: 18_000 }),
			txn({ type: 'refund', amount: 3_000 }),
			// Before the snapshot: already counted in it
			txn({ type: 'expense', amount: 99_999, occurredAt: at('2026-10-20T00:00:00Z') }),
			txn({ type: 'expense', amount: 7_000, voided: true })
		];
		expect(balanceOf('gcash', 'PHP', snap, rows)).toBe(100_000 + 50_000 - 18_000 + 3_000);
	});

	it('moves a transfer between accounts and charges the fee to the source', () => {
		const t = txn({
			type: 'transfer',
			amount: 10_000,
			accountId: 'rcbc',
			toAccountId: 'gcash',
			fee: 1_500
		});
		expect(effectOn(t, 'rcbc', 'PHP')).toBe(-11_500);
		expect(effectOn(t, 'gcash', 'PHP')).toBe(10_000);
		expect(effectOn(t, 'maya', 'PHP')).toBe(0);
		// The same account in another currency is another wallet and sees nothing
		expect(effectOn(t, 'rcbc', 'USD')).toBe(0);
	});

	it('never counts a transfer as spending, but counts its fee and nets refunds', () => {
		const rows = [
			txn({ type: 'expense', amount: 20_000 }),
			txn({
				type: 'transfer',
				amount: 500_000,
				accountId: 'rcbc',
				toAccountId: 'gcash',
				fee: 1_500
			}),
			txn({ type: 'refund', amount: 5_000 }),
			txn({ type: 'income', amount: 900_000 })
		];
		expect(spendingOf(rows, 'PHP')).toBe(20_000 + 1_500 - 5_000);
	});

	it('keeps the wallets of one account apart: pesos and dollars on the same account never mix', () => {
		const rows = [
			txn({ type: 'income', amount: 500_000, accountId: 'wise' }),
			txn({ type: 'income', amount: 10_000, accountId: 'wise', currency: 'USD' }),
			txn({ type: 'expense', amount: 1_250, accountId: 'wise', currency: 'USD' }),
			txn({ type: 'expense', amount: 30_000, accountId: 'wise' })
		];
		expect(balanceOf('wise', 'PHP', null, rows)).toBe(470_000);
		expect(balanceOf('wise', 'USD', null, rows)).toBe(8_750);
		expect(balanceOf('wise', 'EUR', null, rows)).toBe(0);
		// A count of the dollars does not count the pesos
		const usdCount = { amount: 20_000, takenAt: at('2026-10-21T00:00:00Z'), currency: 'USD' };
		expect(balanceOf('wise', 'USD', usdCount, rows)).toBe(20_000 + 10_000 - 1_250);
	});

	it('moves a PHP to USD conversion inside one account by what really arrived', () => {
		// 5,600 pesos became 99.40 dollars (the person's own rate), with a 50 peso fee
		const t = txn({
			type: 'transfer',
			amount: 560_000,
			accountId: 'wise',
			toAccountId: 'wise',
			currency: 'PHP',
			toCurrency: 'USD',
			toAmount: 9_940,
			fee: 5_000
		});
		expect(effectOn(t, 'wise', 'PHP')).toBe(-565_000);
		expect(effectOn(t, 'wise', 'USD')).toBe(9_940);
		expect(effectOn(t, 'wise', 'EUR')).toBe(0);
	});

	it('counts spending of one currency only, so amounts of two currencies are never added', () => {
		const rows = [
			txn({ type: 'expense', amount: 20_000 }),
			txn({ type: 'expense', amount: 999, currency: 'USD' }),
			txn({
				type: 'transfer',
				amount: 100,
				accountId: 'wise',
				toAccountId: 'gcash',
				currency: 'USD',
				fee: 25
			})
		];
		expect(spendingOf(rows, 'PHP')).toBe(20_000);
		expect(spendingOf(rows, 'USD')).toBe(999 + 25);
	});

	it('signs drift and shows untracked spending only when it is negative', () => {
		expect(driftOf(100_000, 92_000)).toBe(-8_000);
		expect(driftOf(100_000, 105_000)).toBe(5_000);
		expect(untrackedSpendingOf([-8_000, 5_000, -2_000])).toBe(10_000);
		expect(untrackedSpendingOf([5_000])).toBe(0);
	});
});

describe('bill estimator', () => {
	it('asks the user on a cold start and flags the bill unknown', () => {
		expect(estimateBill([])).toMatchObject({ amount: null, unknown: true, basis: 'none' });
		expect(estimateBill([200_000, 210_000])).toMatchObject({ unknown: true });
		expect(estimateBill([200_000], 250_000)).toMatchObject({
			amount: 250_000,
			basis: 'user',
			unknown: false
		});
	});

	it('uses the median of the latest six and drops a one off outlier', () => {
		const e = estimateBill([210_000, 200_000, 205_000, 900_000, 195_000, 200_000, 50_000_000]);
		expect(e).toMatchObject({ basis: 'history', dropped: 1, used: 5 });
		expect(e.amount).toBe(200_000);
	});

	it('rounds the median of an even count to the centavo', () => {
		expect(median([100, 101])).toBe(101);
		expect(median([1, 2, 3, 4])).toBe(3);
	});
});

describe('amount confirmation', () => {
	it('always confirms an amount read from a picture', () => {
		expect(needsAmountConfirmation('ocr')).toBe(true);
		expect(needsAmountConfirmation('screenshot')).toBe(true);
		expect(needsAmountConfirmation('chat')).toBe(false);
	});

	it('confirms a big balance change and asks twice for a tenfold one', () => {
		expect(checkBalanceChange(null, 1_000_000)).toBe('ok');
		expect(checkBalanceChange(1_000_000, 1_050_000)).toBe('ok');
		expect(checkBalanceChange(1_000_000, 1_500_000)).toBe('confirm');
		expect(checkBalanceChange(1_000_000, 11_000_000)).toBe('confirm_large');
		expect(checkBalanceChange(1_000_000, 50_000)).toBe('confirm_large');
		// A tenfold jump of a tiny balance is still small money
		expect(checkBalanceChange(1_000, 20_000)).toBe('ok');
	});
});

describe('expense text', () => {
	const accounts = ['RCBC', 'GCash', 'Maya', 'Cash'];

	it('reads the example from the plan', () => {
		expect(parseExpenseText('lunch 180 gcash', accounts)).toMatchObject({
			amount: 18_000,
			note: 'lunch',
			category: 'food',
			accountName: 'GCash',
			ambiguous: false
		});
	});

	it('reads pesos signs, commas, centavos and k', () => {
		expect(parseExpenseText('grab ₱1,250.50 from rcbc', accounts)).toMatchObject({
			amount: 125_050,
			accountName: 'RCBC',
			category: 'transport'
		});
		expect(parseExpenseText('rent 1.5k', accounts).amount).toBe(150_000);
	});

	it('flags two numbers and finds no amount in words', () => {
		expect(parseExpenseText('2 coffee 240', accounts)).toMatchObject({
			amount: 24_000,
			ambiguous: true
		});
		expect(parseExpenseText('hello there', accounts).amount).toBeNull();
	});
});

describe('rule text', () => {
	const targets = [
		{ kind: 'account' as const, id: 'a1', name: 'GCash' },
		{ kind: 'account' as const, id: 'a2', name: 'RCBC' },
		{ kind: 'goal' as const, id: 'g1', name: 'Emergency fund' }
	];

	it('reads an amount, a percentage and the rest', () => {
		expect(parseRuleText('500 to gcash', targets)).toMatchObject({
			ok: true,
			mode: 'fixed',
			amount: 50_000,
			target: { kind: 'account', id: 'a1' }
		});
		expect(parseRuleText('20% to emergency fund', targets)).toMatchObject({
			ok: true,
			mode: 'percent',
			basisPoints: 2000,
			base: 'pay',
			target: { kind: 'goal', id: 'g1' }
		});
		expect(parseRuleText('10 percent of what is left to rcbc', targets)).toMatchObject({
			mode: 'percent',
			basisPoints: 1000,
			base: 'remaining'
		});
		expect(parseRuleText('the rest to rcbc', targets)).toMatchObject({
			ok: true,
			mode: 'rest',
			target: { id: 'a2' }
		});
	});

	it('refuses what it cannot read instead of guessing', () => {
		expect(parseRuleText('500 to the moon', targets)).toMatchObject({ ok: false });
		expect(parseRuleText('some to gcash', targets)).toMatchObject({ ok: false });
		expect(parseRuleText('150% to gcash', targets)).toMatchObject({ ok: false });
	});
});
