// WHAT-IFS ON THE PLAN: EACH CHANGE ON ITS OWN, IDS THAT ARE NOT THE PERSON'S, BOUNDS, AND AN EMPTY WHAT-IF THAT CHANGES NOTHING

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { planFlows } from '../../src/lib/finance/planFlows';
import { applyScenario, scenarioChanges, type Scenario } from '../../src/lib/finance/scenario';
import { FIXED_RULE, NET, PAY, plan, RENT } from './planFixture';

// -- CONSTANTS -- //

const RANGE = {
	mode: 'future' as const,
	from: '2026-03-01',
	to: '2026-03-31',
	today: '2026-03-01'
};

// -- FUNCTIONS -- //

function flowsWith(s: Scenario | undefined) {
	const applied = applyScenario(plan(), s);
	return { applied, out: planFlows(applied.plan, RANGE) };
}

// The bills of February are late on the 1st of March and count that day; these tests look at March's own dates
const ofKind = (out: ReturnType<typeof planFlows>, kind: 'in' | 'out' | 'move') =>
	out.flows.filter((f) => f.kind === kind && !f.label.includes('(late'));

const sum = (xs: { amount: number }[]) => xs.reduce((a, b) => a + b.amount, 0);

// -- TESTS -- //

describe('applyScenario', () => {
	it('changes nothing for an empty what-if', () => {
		const base = plan();
		for (const s of [undefined, {}, { off: {}, extra: [] }]) {
			const applied = applyScenario(base, s);
			expect(applied.plan).toBe(base);
			expect(applied.changes).toBe(0);
		}
		expect(JSON.stringify(flowsWith({}).out)).toBe(JSON.stringify(planFlows(base, RANGE)));
	});

	it('switches off a payday, a bill, a rule and a goal', () => {
		const base = flowsWith(undefined).out;
		expect(ofKind(base, 'in')).toHaveLength(2);
		expect(ofKind(flowsWith({ off: { incomes: ['pay'] } }).out, 'in')).toHaveLength(0);
		const noRent = flowsWith({ off: { bills: ['rent'] } }).out;
		expect(ofKind(noRent, 'out').map((f) => f.label)).toEqual(['Internet']);
		const noFixed = flowsWith({ off: { rules: ['r1'] } }).out;
		expect(sum(ofKind(noFixed, 'move'))).toBe(sum(ofKind(base, 'move')) - 0);
		expect(
			ofKind(noFixed, 'move').some((f) => f.label.includes('GCash') && f.amount === FIXED_RULE)
		).toBe(false);
		const noGoal = flowsWith({ off: { goals: ['fund'] } }).applied;
		expect(noGoal.plan.goals).toHaveLength(0);
		expect(noGoal.changes).toBe(1);
	});

	it('changes a pay and a bill amount', () => {
		const out = flowsWith({
			incomeAmounts: [{ id: 'pay', amount: 3_000_000 }],
			billAmounts: [{ id: 'rent', amount: 2_000_000 }]
		}).out;
		expect(ofKind(out, 'in').map((f) => f.amount)).toEqual([3_000_000, 3_000_000]);
		expect(ofKind(out, 'out').find((f) => f.label === 'Rent')?.amount).toBe(2_000_000);
		expect(ofKind(flowsWith(undefined).out, 'out').find((f) => f.label === 'Rent')?.amount).toBe(
			RENT
		);
	});

	it('skips one payday', () => {
		const out = flowsWith({ skipPaydays: [{ incomeId: 'pay', date: '2026-03-13' }] }).out;
		expect(ofKind(out, 'in').map((f) => f.date)).toEqual(['2026-03-30']);
	});

	it('pays every bill late and defers a deferrable bill to the next payday', () => {
		const late = flowsWith({ billDelayDays: 7 }).out;
		expect(ofKind(late, 'out').map((f) => `${f.date} ${f.label}`)).toEqual([
			'2026-03-12 Rent',
			'2026-03-27 Internet'
		]);
		const deferred = flowsWith({ deferDeferrable: true }).out;
		expect(ofKind(deferred, 'out').find((f) => f.label === 'Internet')?.date).toBe('2026-03-30');
		expect(ofKind(deferred, 'out').find((f) => f.label === 'Rent')?.date).toBe('2026-03-05');
	});

	it("adds pretend entries on active accounts only, and names ids that are not the person's", () => {
		const { applied, out } = flowsWith({
			extra: [
				{
					date: '2026-03-10',
					kind: 'out',
					accountId: 'gcash',
					currency: 'PHP',
					amount: 50_000,
					label: 'New phone'
				},
				{
					date: '2026-03-10',
					kind: 'in',
					accountId: 'someone-else',
					currency: 'PHP',
					amount: 1,
					label: 'x'
				}
			],
			off: { bills: ['not-mine'] }
		});
		expect(out.flows.filter((f) => f.origin === 'pretend').map((f) => f.label)).toEqual([
			'New phone'
		]);
		expect(applied.ignored).toEqual(['not-mine', 'someone-else']);
		expect(applied.changes).toBe(3);
	});

	it('keeps a past pretend entry for the replay only', () => {
		const applied = applyScenario(plan(), {
			extra: [
				{
					date: '2026-02-10',
					kind: 'out',
					accountId: 'gcash',
					currency: 'PHP',
					amount: NET,
					label: 'Old'
				}
			]
		});
		expect(planFlows(applied.plan, RANGE).flows.some((f) => f.origin === 'pretend')).toBe(false);
		const replay = planFlows(applied.plan, {
			mode: 'replay',
			from: '2026-02-01',
			to: '2026-02-28',
			today: '2026-03-01'
		});
		expect(replay.flows.some((f) => f.origin === 'pretend')).toBe(true);
	});

	it('refuses an amount or a delay out of bounds', () => {
		expect(() => applyScenario(plan(), { billDelayDays: 61 })).toThrow(RangeError);
		expect(() => applyScenario(plan(), { incomeAmounts: [{ id: 'pay', amount: 0 }] })).toThrow(
			RangeError
		);
		expect(() =>
			applyScenario(plan(), { billAmounts: [{ id: 'rent', amount: 1_000_000_000_001 }] })
		).toThrow(RangeError);
		expect(scenarioChanges({ billDelayDays: 0, deferDeferrable: false })).toBe(0);
		expect(PAY).toBeGreaterThan(0);
	});
});
