// THE BALANCE TIMELINE: RECORDED, REPLAYED, SIMULATED AND MISSED, EVERY CASE THE PLAN ALLOWS, WITH NO DATABASE

// -- TYPES -- //
import type { PlanData } from '../../src/lib/finance/planFlows';
import type { RecordedSnapshot, RecordedTxn, SimulateInput } from '../../src/lib/finance/simulate';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { manilaNoon, toManilaDate } from '../../src/lib/finance/dates';
import { planFlows } from '../../src/lib/finance/planFlows';
import { applyScenario } from '../../src/lib/finance/scenario';
import { MAX_ENTRIES, simulate } from '../../src/lib/finance/simulate';
import { GOAL_PER_PAY, PAY, plan, RENT } from './planFixture';

// -- CONSTANTS -- //

const TODAY = '2026-06-10';
const NOW = manilaNoon(TODAY);

const SNAPSHOTS: RecordedSnapshot[] = [
	{ accountId: 'rcbc', currency: 'PHP', amount: 1_000_000, takenAt: manilaNoon('2026-01-02') },
	{ accountId: 'gcash', currency: 'PHP', amount: 300_000, takenAt: manilaNoon('2026-01-02') }
];

/** The pay was logged on these days: 13 March came in on the 16th, and 15 April never did. */
const PAY_DAYS = [
	'2026-01-15',
	'2026-01-30',
	'2026-02-13',
	'2026-02-27',
	'2026-03-16',
	'2026-03-30',
	'2026-04-30',
	'2026-05-15',
	'2026-05-29'
];
/** Rent was paid on these days; April's (due the 5th) on the 6th, which settles the date it was marked paid for. */
const RENT_DAYS = ['2026-02-05', '2026-03-05', '2026-04-06', '2026-05-05', '2026-06-05'];
const RENT_DUE = ['2026-02-05', '2026-03-05', '2026-04-05', '2026-05-05', '2026-06-05'];

let ids = 0;
const txn = (
	over: Partial<RecordedTxn> & Pick<RecordedTxn, 'type' | 'accountId' | 'amount' | 'occurredAt'>
): RecordedTxn => ({
	id: `t${++ids}`,
	label: over.type,
	currency: 'PHP',
	...over
});

const TXNS: RecordedTxn[] = [
	...PAY_DAYS.map((d) =>
		txn({
			type: 'income',
			accountId: 'rcbc',
			amount: PAY,
			occurredAt: manilaNoon(d),
			label: 'Salary'
		})
	),
	...RENT_DAYS.map((d) =>
		txn({
			type: 'expense',
			accountId: 'gcash',
			amount: RENT,
			occurredAt: manilaNoon(d),
			label: 'Rent'
		})
	),
	...PAY_DAYS.map((d) =>
		txn({
			type: 'transfer',
			accountId: 'rcbc',
			toAccountId: 'gcash',
			amount: 2_000_000,
			occurredAt: manilaNoon(d),
			label: 'Split'
		})
	)
];

const WALLETS = ['rcbc', 'gcash', 'save'].map((accountId) => ({ accountId, currency: 'PHP' }));

// -- FUNCTIONS -- //

/** The plan of the fixture with the recorded pay days and rent payments of these tests. */
function realPlan(over: Partial<PlanData> = {}): PlanData {
	return plan({
		incomeDays: new Set(
			TXNS.filter((t) => t.type === 'income').map(
				(t) => `${t.accountId}|${toManilaDate(t.occurredAt)}`
			)
		),
		settled: new Map([['rent', RENT_DUE.map((d) => ({ start: d, end: d }))]]),
		...over
	});
}

function sim(over: Partial<SimulateInput> = {}, p: PlanData = realPlan()) {
	return simulate({
		from: '2026-01-01',
		to: '2026-12-31',
		group: 'month',
		weekStart: 1,
		today: TODAY,
		now: NOW,
		plan: p,
		basePlan: p,
		wallets: WALLETS,
		snapshots: SNAPSHOTS,
		txns: TXNS,
		detail: false,
		...over
	});
}

const month = (out: ReturnType<typeof sim>, ym: string) => {
	const found = out.periods.find((p) => p.from.startsWith(ym));
	if (!found) throw new Error(`no period ${ym}`);
	return found;
};

// -- TESTS -- //

describe('recorded and replayed past', () => {
	it('gives each past month its recorded start and end, the replay of the plan and the gap', () => {
		const out = sim();
		const march = month(out, '2026-03');
		expect(march.part).toBe('past');
		// January to February: two pays in, one rent out, the transfers stay inside the accounts
		const feb = month(out, '2026-02');
		expect(feb.recordedEnd).toBe((feb.recordedStart ?? 0) + 2 * PAY - RENT);
		expect(march.recordedStart).toBe(feb.recordedEnd);
		// The replay: two paydays and the plan's rent and internet, from the recorded start
		expect(march.replayEnd).toBe((march.recordedStart ?? 0) + 2 * PAY - RENT - 150_000);
		expect(march.gap).toBe((march.recordedEnd ?? 0) - (march.replayEnd ?? 0));
	});

	it('replays every bill date, paid or not, at the plan amount', () => {
		const out = sim({ from: '2026-03-01', to: '2026-03-31', detail: true });
		const replayOuts = (out.entries ?? []).filter((e) => e.source === 'replay' && e.kind === 'out');
		expect(replayOuts.map((e) => e.label).sort()).toEqual(['Internet', 'Rent']);
		expect(replayOuts.find((e) => e.label === 'Rent')?.amount).toBe(RENT);
	});

	it('gives a period the same replay and gap whatever range it was asked in', () => {
		const wide = month(sim(), '2026-04');
		const narrow = month(sim({ from: '2026-04-01', to: '2026-04-30' }), '2026-04');
		const byDay = sim({ from: '2026-04-01', to: '2026-04-30', group: 'day' });
		expect(narrow.replayEnd).toBe(wide.replayEnd);
		expect(narrow.gap).toBe(wide.gap);
		expect(byDay.periods.at(-1)?.recordedEnd).toBe(wide.recordedEnd);
	});

	it('marks a payday missed only when no pay came before the next one, and an unpaid bill date', () => {
		const out = sim({ from: '2026-01-01', to: '2026-05-31', detail: true });
		const missed = (out.entries ?? []).filter((e) => e.source === 'missed');
		const pays = missed.filter((e) => e.kind === 'in').map((e) => e.date);
		// 13 March came in late on the 16th: not missed. 15 April never came.
		expect(pays).toEqual(['2026-04-15']);
		// The rent of January was never paid; every internet bill is unpaid
		expect(missed.filter((e) => e.label === 'Rent').map((e) => e.date)).toEqual(['2026-01-05']);
		expect(missed.filter((e) => e.label === 'Internet')).toHaveLength(5);
		expect(month(out, '2026-04').missed).toBe(2);
	});

	it('shows nothing recorded before the first record', () => {
		const out = sim({ from: '2025-11-01', to: '2026-01-31' });
		expect(out.firstRecord).toBe('2026-01-02');
		expect(out.periods[0]).toMatchObject({
			beforeFirstRecord: true,
			recordedEnd: null,
			replayEnd: null,
			gap: null,
			missed: 0
		});
		expect(out.periods[2]?.recordedEnd).not.toBeNull();
	});

	it('replays the period of the first record from the day after it, so the opening count is not a gap', () => {
		const jan = month(sim(), '2026-01');
		// Counted on 2 January: 10,000 + 3,000. The plan from the 3rd: two pays, the rent of the 5th and the internet of the 20th
		expect(jan.replayEnd).toBe(1_300_000 + 2 * PAY - RENT - 150_000);
		expect(jan.recordedStart).toBe(0);
	});

	it('counts a rule and an account only from the day they were made', () => {
		const base = realPlan();
		const p: PlanData = {
			...base,
			accounts: [
				...base.accounts,
				{ id: 'trip', name: 'Travel', minBalance: 0, archived: false, createdOn: '2026-04-01' }
			],
			rules: [
				{
					id: 'r0',
					position: 0,
					target: { kind: 'account', id: 'trip' },
					mode: 'fixed',
					amount: 100_000,
					basisPoints: null,
					base: 'pay',
					effectiveFrom: '2025-01-01',
					version: 1,
					createdOn: '2026-04-01'
				},
				...base.rules
			]
		};
		const out = simulate({
			from: '2026-03-01',
			to: '2026-04-30',
			group: 'month',
			weekStart: 1,
			today: TODAY,
			now: NOW,
			plan: p,
			basePlan: p,
			wallets: WALLETS,
			snapshots: SNAPSHOTS,
			txns: TXNS,
			detail: true
		});
		const toTrip = (out.entries ?? []).filter(
			(e) => e.source === 'replay' && e.toAccountId === 'trip'
		);
		expect(toTrip.map((e) => e.date)).toEqual(['2026-04-15', '2026-04-30']);
	});

	it('keeps an archived account in the recorded past and out of the future', () => {
		const base = realPlan();
		const p: PlanData = {
			...base,
			accounts: [
				...base.accounts,
				{ id: 'old', name: 'Old bank', minBalance: 0, archived: true, createdOn: '2026-01-01' }
			]
		};
		const snapshots = [
			...SNAPSHOTS,
			{ accountId: 'old', currency: 'PHP', amount: 77_700, takenAt: manilaNoon('2026-01-02') }
		];
		const out = sim({ snapshots, wallets: [...WALLETS, { accountId: 'old', currency: 'PHP' }] }, p);
		const withOld = month(out, '2026-02');
		const without = month(sim(), '2026-02');
		expect((withOld.recordedEnd ?? 0) - (without.recordedEnd ?? 0)).toBe(77_700);
		expect(withOld.wallets.find((w) => w.accountId === 'old')).toMatchObject({
			archived: true,
			recorded: 77_700
		});
		const june = month(out, '2026-06');
		expect(june.simulatedStart).toBe(month(sim(), '2026-06').simulatedStart);
	});
});

describe('the period that holds today and the future', () => {
	it('splits the month of today: recorded up to now, simulated to its end, no replay', () => {
		const june = month(sim(), '2026-06');
		expect(june.part).toBe('mixed');
		expect(june.replayEnd).toBeNull();
		expect(june.simulatedStart).toBe(june.recordedEnd);
		// Two paydays after today (15 and 30 June), the rest of the plan moves inside the accounts; internet of May is late and counts today, June's on the 20th
		expect(june.simulatedEnd).toBe((june.recordedEnd ?? 0) + 2 * PAY - 2 * 150_000);
	});

	it('runs a far-future range from today, never from zero', () => {
		const far = sim({ from: '2028-03-01', to: '2028-03-31' });
		const through = sim({ from: TODAY, to: '2028-03-31' });
		expect(far.periods).toHaveLength(1);
		expect(far.periods[0]?.part).toBe('future');
		expect(far.periods[0]?.simulatedEnd).toBe(through.periods.at(-1)?.simulatedEnd);
		expect(far.periods[0]?.simulatedStart).toBe(through.periods.at(-2)?.simulatedEnd);
	});

	it('moves money inside the accounts on payday: the total changes only by pay in and bills out, and the split is the whole pay', () => {
		const p = realPlan();
		const flows = planFlows(p, {
			mode: 'future',
			from: TODAY,
			to: '2026-07-31',
			today: TODAY
		}).flows;
		for (const payday of ['2026-06-15', '2026-06-30', '2026-07-15', '2026-07-30']) {
			const moves = flows.filter((f) => f.kind === 'move' && f.date === payday);
			// The rule of the rest takes what is left, so nothing stays in the pay account
			expect(moves.reduce((a, b) => a + b.amount, 0)).toBe(PAY);
			expect(moves.every((m) => Number.isInteger(m.amount))).toBe(true);
			expect(moves.some((m) => m.toAccountId === 'save' && m.label.includes('Emergency'))).toBe(
				true
			);
		}
		expect(flows.filter((f) => f.kind === 'in').map((f) => f.date)).toEqual([
			'2026-06-15',
			'2026-06-30',
			'2026-07-15',
			'2026-07-30'
		]);
		const out = sim({ from: '2026-07-01', to: '2026-07-31' });
		const july = out.periods[0];
		expect(july?.simulatedEnd).toBe((july?.simulatedStart ?? 0) + 2 * PAY - RENT - 150_000);
		expect(GOAL_PER_PAY).toBeGreaterThan(0);
	});

	it('moves a payday on a weekend to the Friday before', () => {
		const flows = planFlows(realPlan(), {
			mode: 'future',
			from: TODAY,
			to: '2026-08-31',
			today: TODAY
		}).flows;
		// 15 August 2026 is a Saturday
		expect(flows.some((f) => f.kind === 'in' && f.date === '2026-08-14')).toBe(true);
	});

	it('counts a bill in another currency at the stored rate, rounded up, and a changed amount for one date', () => {
		const base = realPlan();
		const p: PlanData = {
			...base,
			bills: [
				...base.bills,
				{
					...base.bills[0],
					id: 'cloud',
					name: 'Cloud',
					currency: 'USD',
					usualAmount: 1_001,
					schedule: { kind: 'monthly', day: 20 }
				}
			] as PlanData['bills'],
			overrides: new Map([
				[
					'rent',
					[
						{
							originalDueDate: '2026-07-05',
							newDueDate: null,
							amount: 99_900,
							accountId: null,
							skipped: false
						}
					]
				]
			])
		};
		const flows = planFlows(p, {
			mode: 'future',
			from: TODAY,
			to: '2026-07-31',
			today: TODAY
		}).flows;
		expect(flows.find((f) => f.label === 'Rent' && f.date === '2026-07-05')?.amount).toBe(99_900);
		const cloud = flows.find((f) => f.label === 'Cloud');
		expect(cloud).toMatchObject({ currency: 'USD', amount: 1_001 });
		// 10.01 USD at 56 PHP is 560.56 PHP: 56_056 centavos, rounded up from 56_056; the split of 30 June reserves it
		const toGcash = flows.filter(
			(f) => f.kind === 'move' && f.date === '2026-06-30' && f.toAccountId === 'gcash'
		);
		expect(toGcash.reduce((a, b) => a + b.amount, 0)).toBeGreaterThanOrEqual(56_056);
	});

	it('names a currency with no rate and leaves it out, and lists unknown amounts without counting them', () => {
		const base = realPlan();
		const p: PlanData = {
			...base,
			bills: base.bills.map((b) => (b.id === 'net' ? { ...b, usualAmount: null } : b))
		};
		const out = sim(
			{
				snapshots: [
					...SNAPSHOTS,
					{ accountId: 'save', currency: 'EUR', amount: 5_000, takenAt: manilaNoon('2026-01-02') }
				],
				wallets: [...WALLETS, { accountId: 'save', currency: 'EUR' }]
			},
			p
		);
		expect(out.missing).toEqual(['EUR']);
		const net = out.unknown.find((u) => u.label === 'Internet');
		expect(net?.count).toBeGreaterThan(5);
		// A payday split with a bill of no amount is not in the moves and says so
		expect(out.notes.some((n) => n.kind === 'missing_amount' && n.bill === 'Internet')).toBe(true);
	});

	it('works out what a short pay can fund and says it is short', () => {
		const p = realPlan({
			incomes: realPlan().incomes.map((i) => ({ ...i, expectedAmount: 50_000 }))
		});
		const out = planFlows(p, { mode: 'future', from: TODAY, to: '2026-07-31', today: TODAY });
		expect(out.notes.some((n) => n.kind === 'shortfall')).toBe(true);
		for (const d of ['2026-06-15', '2026-06-30'])
			expect(
				out.flows.filter((f) => f.kind === 'move' && f.date === d).reduce((a, b) => a + b.amount, 0)
			).toBeLessThanOrEqual(50_000);
	});

	it('defers a deferrable bill to the next payday and warns when a wallet goes below zero or under its minimum', () => {
		const applied = applyScenario(realPlan(), {
			deferDeferrable: true,
			extra: [
				{
					date: '2026-07-01',
					kind: 'out',
					accountId: 'gcash',
					currency: 'PHP',
					amount: 20_000_000,
					label: 'Car repair'
				}
			]
		});
		const out = sim({ from: '2026-07-01', to: '2026-07-31', detail: true }, applied.plan);
		const net = (out.entries ?? []).find((e) => e.label === 'Internet');
		expect(net?.date).toBe('2026-07-30');
		expect((out.entries ?? []).find((e) => e.label === 'Car repair')).toMatchObject({
			source: 'simulated',
			pretend: true
		});
		expect(
			out.warnings.some(
				(w) => w.kind === 'below_zero' && w.accountId === 'gcash' && w.date === '2026-07-01'
			)
		).toBe(true);
		expect(out.warnings.some((w) => w.kind === 'below_minimum' && w.accountId === 'gcash')).toBe(
			true
		);
		expect(out.periods[0]).toMatchObject({ below: true, low: true });
	});
});

describe('entries and limits', () => {
	it('tags every entry and keeps whole numbers', () => {
		const out = sim({ from: '2026-05-01', to: '2026-06-30', detail: true });
		const sources = new Set((out.entries ?? []).map((e) => e.source));
		expect([...sources].sort()).toEqual(['missed', 'recorded', 'replay', 'simulated']);
		for (const e of out.entries ?? [])
			if (e.amount !== null) expect(Number.isInteger(e.amount)).toBe(true);
		for (const p of out.periods)
			for (const v of [p.recordedEnd, p.replayEnd, p.simulatedEnd])
				if (v !== null) expect(Number.isInteger(v)).toBe(true);
		expect(sim().entries).toBeUndefined();
		expect(MAX_ENTRIES).toBe(500);
	});

	it('refuses a range too long for its grouping', () => {
		expect(() => sim({ group: 'day' })).toThrow(/at most 62/);
		expect(() => sim({ from: '2021-01-01', to: '2026-12-31' })).toThrow(/at most 1827/);
	});
});
