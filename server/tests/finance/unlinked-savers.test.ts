// A RULE THAT SAVES FOR A BILL BUT IS NOT LINKED TO IT: THE PAY IS ASKED FOR BOTH, SO A PAY LOOKS SHORT WHEN IT IS NOT (BTL-20261106-1502)
// The shape is the owner's plan of 6 Nov 2026: Parents 3,500 and Meralco 3,000 fixed rules into RCBC, and the bills Parents allowance 7,000
// and Meralco 9,000 paid from RCBC; only the Mommy rule was linked to its bill.

// -- TYPES -- //
import type { PlanData } from '../../src/lib/finance/planFlows';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { findUnlinkedSavers } from '../../src/lib/finance/funding';
import { planFlows } from '../../src/lib/finance/planFlows';
import { fundingNotes } from '../../src/lib/server/ops/forecast';
import { plan as base } from './planFixture';

// -- CONSTANTS -- //

const createdOn = '2026-01-01';
const rule = (
	id: string,
	position: number,
	amount: number,
	extra: Partial<PlanData['rules'][number]> = {}
) =>
	({
		id,
		position,
		target: { kind: 'account' as const, id: 'rcbc' },
		mode: 'fixed' as const,
		amount,
		basisPoints: null,
		base: 'pay' as const,
		effectiveFrom: '2025-01-01',
		version: 1,
		createdOn,
		...extra
	}) satisfies PlanData['rules'][number];

const bill = (id: string, name: string, day: number, amount: number) => ({
	id,
	name,
	category: 'family',
	accountId: 'rcbc',
	schedule: { kind: 'monthly' as const, day },
	weekendRule: 'none' as const,
	deferrable: false,
	startsOn: null,
	currency: 'PHP',
	usualAmount: amount,
	createdOn
});

/** The owner's plan: pay 19,000 on the 9th and 23rd, two big bills from RCBC, two saving rules into RCBC, a rest rule. */
function owner(linked: boolean): PlanData {
	const p = base();
	return {
		...p,
		incomes: [
			{
				id: 'pay',
				label: 'Salary',
				accountId: 'rcbc',
				expectedAmount: 1_900_000,
				schedule: { kind: 'semi_monthly', days: [9, 23] },
				weekendRule: 'none',
				createdOn
			}
		],
		bills: [
			bill('parents', 'Parents allowance', 25, 700_000),
			bill('meralco', 'Meralco', 27, 900_000)
		],
		goals: [],
		rules: [
			rule('rp', 1, 350_000, { label: 'Parents', ...(linked ? { fundsBillId: 'parents' } : {}) }),
			rule('rm', 2, 300_000, { label: 'Meralco', ...(linked ? { fundsBillId: 'meralco' } : {}) }),
			{ ...rule('rest', 3, 0), mode: 'rest', amount: null }
		],
		balances: new Map([['rcbc', 1_700_000]])
	};
}

// -- TESTS -- //

describe('findUnlinkedSavers', () => {
	it('names a rule that fills the account paying a bill of its first word, without a link', () => {
		const p = owner(false);
		const found = findUnlinkedSavers(
			p.rules.map((r) => ({
				id: r.id,
				label: r.label ?? null,
				mode: r.mode,
				status: 'active',
				amount: r.amount,
				targetAccountId: r.target.kind === 'account' ? r.target.id : null,
				effectiveFrom: r.effectiveFrom,
				fundsBillId: r.fundsBillId ?? null
			})),
			p.bills.map((b) => ({ ...b, active: true })),
			'PHP'
		);
		expect(found.map((f) => [f.ruleLabel, f.billName, f.perPayday])).toEqual([
			['Parents', 'Parents allowance', 350_000],
			['Meralco', 'Meralco', 300_000]
		]);
	});

	it('says nothing once the rules are linked, and for a rule that fills another account', () => {
		const linked = planFlows(owner(true), {
			mode: 'future',
			from: '2026-11-06',
			to: '2026-11-30',
			today: '2026-11-06'
		});
		expect(linked.unlinkedSavers).toEqual([]);
		const other = owner(false);
		const moved = {
			...other,
			rules: other.rules.map((r) =>
				r.id === 'rp' ? { ...r, target: { kind: 'account' as const, id: 'gcash' } } : r
			)
		};
		const out = planFlows(moved, {
			mode: 'future',
			from: '2026-11-06',
			to: '2026-11-30',
			today: '2026-11-06'
		});
		expect(out.unlinkedSavers?.map((u) => u.ruleLabel)).toEqual(['Meralco']);
	});
});

describe('the forecast of that plan', () => {
	const range = {
		mode: 'future' as const,
		from: '2026-11-06',
		to: '2026-11-30',
		today: '2026-11-06'
	};

	it('reports the unlinked rules and tells how to fix them in the notes', () => {
		const made = planFlows(owner(false), range);
		expect(made.unlinkedSavers).toHaveLength(2);
		const notes = fundingNotes(made.funding ?? [], made.brokenLinks ?? [], made.unlinkedSavers);
		expect(notes.join(' ')).toContain('counted twice');
		expect(notes.join(' ')).toContain('"Parents"');
		expect(notes.join(' ')).toContain('fundsBillId');
	});

	it('is not short by the same money twice once the rules are linked', () => {
		const gap = (p: PlanData) =>
			planFlows(p, range)
				.notes.filter((n) => n.kind === 'shortfall')
				.reduce((s, n) => s + (n.kind === 'shortfall' ? n.gap : 0), 0);
		// Linked, the saving rules are what the bills are paid from: the pay is asked for less than before
		expect(gap(owner(true))).toBeLessThan(gap(owner(false)));
	});
});
