// WHAT A RULE THAT SAVES FOR A BILL HAS SET ASIDE, WHAT AN ACCOUNT CAN STILL GIVE, AND WHICH LINKS COUNT (BTL-20261029-0119)

// -- TYPES -- //
import type { LinkBillLike, LinkRuleLike } from '../../src/lib/finance/funding';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { availableFor, checkLinks, reservedFor } from '../../src/lib/finance/funding';
import { fundingAt } from '../../src/lib/finance/planFlows';
import { plan } from './planFixture';

// -- CONSTANTS -- //

const ruleRow = (over: Partial<LinkRuleLike> = {}): LinkRuleLike => ({
	id: 'r1',
	label: 'Parents',
	mode: 'fixed',
	status: 'active',
	amount: 350_000,
	targetAccountId: 'rcbc',
	effectiveFrom: '2026-11-02',
	fundsBillId: 'b1',
	...over
});
const billRow = (over: Partial<LinkBillLike> = {}): LinkBillLike => ({
	id: 'b1',
	name: 'Parents allowance',
	active: true,
	accountId: 'rcbc',
	currency: 'PHP',
	...over
});
const mondays = ['2026-10-26', '2026-11-02', '2026-11-09', '2026-11-16', '2026-11-23'];

// -- TESTS -- //

describe('checkLinks', () => {
	it('keeps a fixed active rule that fills the account the bill is paid from', () => {
		const { links, broken } = checkLinks([ruleRow()], [billRow()], 'PHP');
		expect(broken).toEqual([]);
		expect(links).toEqual([
			{
				ruleId: 'r1',
				ruleLabel: 'Parents',
				billId: 'b1',
				billName: 'Parents allowance',
				accountId: 'rcbc',
				perPayday: 350_000,
				effectiveFrom: '2026-11-02'
			}
		]);
	});

	it('names every link that cannot count, and skips rules that are not in force', () => {
		const cases: [LinkRuleLike, LinkBillLike[], string][] = [
			[ruleRow(), [billRow({ active: false })], 'switched off'],
			[ruleRow(), [], 'switched off'],
			[ruleRow({ mode: 'percent', amount: null }), [billRow()], 'fixed amount'],
			[ruleRow({ targetAccountId: null }), [billRow()], 'goal'],
			[ruleRow(), [billRow({ currency: 'USD' })], 'USD'],
			[ruleRow(), [billRow({ accountId: 'gcash' })], 'another account']
		];
		for (const [r, bills, words] of cases) {
			const { links, broken } = checkLinks([r], bills, 'PHP');
			expect(links).toEqual([]);
			expect(broken[0]?.reason).toContain(words);
		}
		expect(checkLinks([ruleRow({ status: 'proposed' })], [billRow()], 'PHP')).toEqual({
			links: [],
			broken: []
		});
		expect(checkLinks([ruleRow({ fundsBillId: null })], [billRow()], 'PHP').links).toEqual([]);
	});
});

describe('reservedFor', () => {
	const l = { perPayday: 350_000, effectiveFrom: '2026-11-02' };

	it('counts the paydays after the previous date, from the rule start, before the payday', () => {
		// Parents every 2 Wednesdays: previous 28 Oct, next 11 Nov; on the 9 Nov payday the 2 Nov one is set aside
		expect(reservedFor(l, 700_000, '2026-10-28', mondays, '2026-11-09')).toBe(350_000);
		expect(reservedFor(l, 700_000, '2026-10-28', mondays, '2026-11-02')).toBe(0);
		// Mommy every 4 weeks with 250.00 a payday: 2, 9 and 16 Nov are set aside before 23 Nov
		const mommy = { perPayday: 25_000, effectiveFrom: '2026-11-02' };
		expect(reservedFor(mommy, 100_000, '2026-10-28', mondays, '2026-11-23')).toBe(75_000);
	});

	it('never sets aside more than the bill, nothing once paid, and counts a payday once', () => {
		expect(reservedFor(l, 500_000, null, mondays, '2026-11-23')).toBe(500_000);
		expect(reservedFor(l, 700_000, '2026-10-28', mondays, '2026-11-09', true)).toBe(0);
		expect(reservedFor(l, 700_000, null, ['2026-11-02', '2026-11-02'], '2026-11-09')).toBe(350_000);
	});
});

describe('availableFor', () => {
	const a = (projected: number, minBalance = 0, reserved = 0, holdsGoal = false) =>
		availableFor({ projected, minBalance, reserved, holdsGoal });

	it('is the balance less the minimum and the savings, never below zero, and nothing for a goal account', () => {
		expect(a(150_273)).toBe(150_273);
		expect(a(150_273, 50_000, 25_000)).toBe(75_273);
		expect(a(10_000, 50_000)).toBe(0);
		expect(a(-5)).toBe(0);
		expect(a(900_000, 0, 0, true)).toBe(0);
	});
});

describe('fundingAt: what a payday may take from money already there', () => {
	// GCash holds 20,000.00 with a 2,000.00 minimum; Rent (15,000.00, the 5th) and Internet (1,500.00, the 20th) are paid from it
	const balances = new Map([
		['gcash', 2_000_000],
		['rcbc', 0],
		['save', 900_000]
	]);

	it('takes the bills already late out of a payday today, never money of an account that holds a goal', () => {
		const p = plan({ balances });
		const today = fundingAt(p, [], '2026-03-10', '2026-03-10');
		// Rent of 5 Mar and Internet of 20 Feb are late and unpaid (up to 31 days): they are owed from the same money
		expect(today.available).toEqual({ gcash: 2_000_000 - 1_500_000 - 150_000 - 200_000 });
		// A later payday gets the late bill through the flows before it, so with none given only the minimum comes off
		expect(fundingAt(p, [], '2026-03-13', '2026-03-10').available).toEqual({ gcash: 1_800_000 });
	});

	it('holds back what a linked rule set aside before today, and nothing once that date is paid', () => {
		const rules = plan().rules.map((r) => (r.id === 'r1' ? { ...r, fundsBillId: 'net' } : r));
		const at = fundingAt(plan({ balances, rules }), [], '2026-03-15', '2026-03-01');
		// The 27 Feb payday (28 Feb is a Saturday) is after Internet's 20 Feb date: 5,000.00, at most the 1,500.00 bill
		expect(at.links).toEqual([
			{
				billId: 'net',
				ruleId: 'r1',
				ruleLabel: 'Saving for Internet',
				perPayday: 500_000,
				reserved: 150_000
			}
		]);
		expect(at.available).toEqual({ gcash: 1_650_000 });
		const paid = fundingAt(
			plan({
				balances,
				rules,
				settled: new Map([['net', [{ start: '2026-03-20', end: '2026-03-20' }]]])
			}),
			[],
			'2026-03-15',
			'2026-03-01'
		);
		expect(paid.links[0]?.reserved).toBe(0);
		expect(paid.available).toEqual({ gcash: 1_800_000 });
	});
});
