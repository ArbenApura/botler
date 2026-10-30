// NET BALANCE (BTL-20261030-0546): WHAT A WALLET HOLDS THAT IS NOT ALREADY OWED TO A BILL OR A GOAL, ON THE SMALL PLAN OF planFixture.ts
// Today is Friday 2026-01-02: the next payday is 2026-01-15, Rent (day 5, GCash) falls before it, Internet (day 20) after it.

// -- TYPES -- //
import type { PlanData, PlanRule } from '../../src/lib/finance/planFlows';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { computeNet, nextPayday } from '../../src/lib/finance/net';
import { NET, RENT, plan as rawPlan } from './planFixture';

// -- CONSTANTS -- //

const TODAY = '2026-01-02';

/** A fixed rule that puts 100 000 into GCash on every payday for the Internet bill. */
const SAVES_FOR_NET: PlanRule = {
	id: 'r3',
	position: 3,
	target: { kind: 'account', id: 'gcash' },
	mode: 'fixed',
	amount: 100_000,
	basisPoints: null,
	base: 'pay',
	effectiveFrom: '2025-12-01',
	version: 1,
	createdOn: '2025-12-01',
	fundsBillId: 'net',
	ownLabel: null
};

// -- FUNCTIONS -- //

/** The fixture with December's rent and internet already paid, so only what is really owed shows. */
const plan = (over: Partial<PlanData> = {}) =>
	rawPlan({
		settled: new Map([
			['rent', [{ start: '2025-12-05', end: '2025-12-05' }]],
			['net', [{ start: '2025-12-20', end: '2025-12-20' }]]
		]),
		...over
	});

const wallet = (accountId: string, balance: number, currency = 'PHP') => ({
	accountId,
	currency,
	balance
});

const of = (p: PlanData, w: ReturnType<typeof wallet>[], today = TODAY) => computeNet(p, w, today);

const gcash = (r: ReturnType<typeof of>) => r.wallets.find((w) => w.accountId === 'gcash');

// -- TESTS -- //

describe('net balance', () => {
	it('finds the next payday: a pay already recorded today is past, one not yet recorded is today, an income with no amount is no payday', () => {
		expect(nextPayday(plan(), TODAY)).toBe('2026-01-15');
		expect(nextPayday(plan(), '2026-01-15')).toBe('2026-01-15');
		expect(nextPayday(plan({ incomeDays: new Set(['rcbc|2026-01-15']) }), '2026-01-15')).toBe(
			'2026-01-30'
		);
		const noAmount = plan();
		expect(
			nextPayday(
				{ ...noAmount, incomes: noAmount.incomes.map((i) => ({ ...i, expectedAmount: null })) },
				TODAY
			)
		).toBeNull();
	});

	it('holds a bill due before the next payday in full, never the one after it', () => {
		const r = of(plan(), [wallet('gcash', 2_000_000)]);
		expect(gcash(r)).toMatchObject({
			held: RENT,
			net: 500_000,
			shortfall: 0,
			holds: [{ kind: 'bill', label: 'Rent', amount: RENT, dueDate: '2026-01-05' }]
		});
		expect(r.until).toBe('2026-01-15');
	});

	it('does not subtract the minimum balance', () => {
		// GCash keeps 200 000 as its minimum: net is balance less the bill only
		expect(gcash(of(plan(), [wallet('gcash', 1_700_000)]))?.net).toBe(200_000);
	});

	it('shows what a due bill still lacks as a shortfall, and net never goes below zero', () => {
		expect(gcash(of(plan(), [wallet('gcash', 1_000_000)]))).toMatchObject({
			net: 0,
			shortfall: 500_000
		});
		// An overdraft is not made worse by the shortfall: the bill is the whole claim
		expect(gcash(of(plan(), [wallet('gcash', -100_000)]))).toMatchObject({
			net: 0,
			shortfall: RENT
		});
	});

	it('holds nothing for a bill that is paid, and names a bill with no amount yet', () => {
		const paid = plan({
			settled: new Map([
				[
					'rent',
					[
						{ start: '2025-12-05', end: '2025-12-05' },
						{ start: '2026-01-05', end: '2026-01-05' }
					]
				],
				['net', [{ start: '2025-12-20', end: '2025-12-20' }]]
			])
		});
		expect(gcash(of(paid, [wallet('gcash', 2_000_000)]))).toMatchObject({
			held: 0,
			net: 2_000_000
		});
		const base = plan();
		const unknown = {
			...base,
			bills: base.bills.map((b) => (b.id === 'rent' ? { ...b, usualAmount: null } : b))
		};
		const r = of(unknown, [wallet('gcash', 2_000_000)]);
		expect(gcash(r)).toMatchObject({ held: 0, net: 2_000_000 });
		expect(r.notes).toContainEqual({
			kind: 'missing_amount',
			accountId: 'gcash',
			bill: 'Rent',
			dueDate: '2026-01-05'
		});
	});

	it('holds a late unpaid bill (up to 31 days) too', () => {
		// Rent of 5 Dec and Internet of 20 Dec were never paid: 28 and 13 days late on 2026-01-02
		const r = of(rawPlan(), [wallet('gcash', 5_000_000)]);
		expect(gcash(r)?.holds.map((h) => h.dueDate)).toEqual([
			'2025-12-05',
			'2025-12-20',
			'2026-01-05'
		]);
		expect(gcash(r)?.held).toBe(RENT * 2 + NET);
	});

	it('holds what a linked rule has set aside for a later bill, lowering net but never raising a shortfall', () => {
		const p = plan({ rules: [...plan().rules, SAVES_FOR_NET] });
		// One payday (30 Dec) since the Internet bill of 20 Dec: 100 000 set aside, on top of the rent due
		const r = of(p, [wallet('gcash', 2_000_000)]);
		expect(gcash(r)).toMatchObject({ held: RENT + 100_000, net: 400_000, shortfall: 0 });
		expect(gcash(r)?.holds.map((h) => h.kind)).toEqual(['bill', 'rule']);
		// With too little money the rule's hold is not a shortfall: the bill is not due yet
		expect(gcash(of(p, [wallet('gcash', RENT)]))).toMatchObject({ net: 0, shortfall: 0 });
		// A rule never holds more than the bill
		const rich = plan({ rules: [...plan().rules, { ...SAVES_FOR_NET, amount: 900_000 }] });
		expect(
			gcash(of(rich, [wallet('gcash', 5_000_000)]))?.holds.find((h) => h.kind === 'rule')?.amount
		).toBe(NET);
	});

	it('does not hold a bill due on the payday itself, and does not hold a due bill a second time through its rule', () => {
		const base = plan();
		// Internet falls on the 15th, the payday: the pay arrives that day, so it is not held before it
		const onPayday = {
			...base,
			bills: base.bills.map((b) =>
				b.id === 'net' ? { ...b, schedule: { kind: 'monthly' as const, day: 15 } } : b
			),
			settled: new Map([
				['rent', [{ start: '2025-12-05', end: '2025-12-05' }]],
				['net', [{ start: '2025-12-15', end: '2025-12-15' }]]
			])
		};
		expect(gcash(of(onPayday, [wallet('gcash', 5_000_000)]))?.holds.map((h) => h.label)).toEqual([
			'Rent'
		]);
		// A rule saving for the rent, which is due before the next payday: only the bill holds, in full
		const p = plan({ rules: [...base.rules, { ...SAVES_FOR_NET, fundsBillId: 'rent' }] });
		const r = gcash(of(p, [wallet('gcash', 5_000_000)]));
		expect(r?.holds.map((h) => h.kind)).toEqual(['bill']);
		expect(r?.held).toBe(RENT);
	});

	it('names a rule that cannot save for its bill and holds nothing for it', () => {
		const p = plan({ rules: [...plan().rules, { ...SAVES_FOR_NET, mode: 'rest', amount: null }] });
		const r = of(p, [wallet('gcash', 2_000_000)]);
		expect(r.notes.some((n) => n.kind === 'broken_link')).toBe(true);
		expect(gcash(r)?.holds.map((h) => h.kind)).toEqual(['bill']);
	});

	it('keeps the whole main wallet of a goal account for the goal and makes a bill due from it a shortfall', () => {
		const r = of(plan(), [wallet('save', 300_000)]);
		expect(r.wallets[0]).toMatchObject({ net: 0, held: 300_000, shortfall: 0 });
		expect(r.wallets[0]?.holds).toEqual([{ kind: 'goal', label: 'Emergency', amount: 300_000 }]);
		// Rent paid from the goal account: the goal's money does not pay it
		const base = plan();
		const p = {
			...base,
			bills: base.bills.map((b) => (b.id === 'rent' ? { ...b, accountId: 'save' } : b))
		};
		expect(of(p, [wallet('save', 300_000)]).wallets[0]).toMatchObject({ net: 0, shortfall: RENT });
	});

	it('holds a foreign bill in the wallet of its own currency, and names one with no wallet', () => {
		const base = plan();
		const usd = {
			...base,
			bills: base.bills.map((b) =>
				b.id === 'rent' ? { ...b, currency: 'USD', usualAmount: 10_000 } : b
			)
		};
		const r = of(usd, [wallet('gcash', 2_000_000), wallet('gcash', 25_000, 'USD')]);
		expect(r.wallets.find((w) => w.currency === 'USD')).toMatchObject({
			held: 10_000,
			net: 15_000
		});
		// The PHP wallet is untouched by a USD bill
		expect(r.wallets.find((w) => w.currency === 'PHP')).toMatchObject({ held: 0, net: 2_000_000 });
		const none = of(usd, [wallet('gcash', 2_000_000)]);
		expect(none.unmatched).toEqual([
			{ accountId: 'gcash', currency: 'USD', label: 'Rent', amount: 10_000, dueDate: '2026-01-05' }
		]);
	});

	it('holds bills for 30 days when no income has an amount and a date', () => {
		const base = plan();
		const p = { ...base, incomes: base.incomes.map((i) => ({ ...i, expectedAmount: null })) };
		const r = of(p, [wallet('gcash', 5_000_000)]);
		expect(r.until).toBe('2026-02-01');
		expect(gcash(r)?.holds.map((h) => h.label)).toEqual(['Rent', 'Internet']);
	});

	it('counts a payday today as the horizon until its pay is recorded', () => {
		const day = '2026-01-15';
		// Pay not recorded: it arrives today, so only what is already late is held (nothing here)
		const day0 = plan({
			settled: new Map([
				[
					'rent',
					[
						{ start: '2025-12-05', end: '2025-12-05' },
						{ start: '2026-01-05', end: '2026-01-05' }
					]
				],
				['net', [{ start: '2025-12-20', end: '2025-12-20' }]]
			])
		});
		expect(gcash(of(day0, [wallet('gcash', 2_000_000)], day))).toMatchObject({ held: 0 });
		// Pay recorded: it is in the balance, and the Internet bill of the 20th is held
		const recorded = { ...day0, incomeDays: new Set(['rcbc|2026-01-15']) };
		expect(gcash(of(recorded, [wallet('gcash', 2_000_000)], day))).toMatchObject({
			held: NET,
			net: 2_000_000 - NET
		});
	});

	it('leaves out the bills of an archived account', () => {
		const base = plan();
		const p = {
			...base,
			accounts: base.accounts.map((a) => (a.id === 'gcash' ? { ...a, archived: true } : a))
		};
		const r = of(p, [wallet('save', 1)]);
		expect(r.unmatched).toEqual([]);
		expect(r.wallets[0]?.holds.some((h) => h.kind === 'bill')).toBe(false);
	});

	it('is never above the balance and the held amount is the sum of its holds', () => {
		const p = plan({ rules: [...plan().rules, SAVES_FOR_NET] });
		for (const balance of [-5, 0, 1, 700_000, 1_500_000, 1_600_000, 9_000_000]) {
			const w = gcash(of(p, [wallet('gcash', balance)]));
			expect(w?.net).toBeGreaterThanOrEqual(0);
			expect(w?.net).toBeLessThanOrEqual(Math.max(balance, 0));
			expect(w?.held).toBe(w?.holds.reduce((n, h) => n + h.amount, 0));
		}
	});
});
