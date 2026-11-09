// THE BALANCE TIMELINE: RECORDED, REPLAYED, SIMULATED AND MISSED, EVERY CASE THE PLAN ALLOWS, WITH NO DATABASE

// -- TYPES -- //
import type { PlanData } from '../../src/lib/finance/planFlows';
import type { RecordedSnapshot, RecordedTxn, SimulateInput } from '../../src/lib/finance/simulate';
import type { SimulationView } from '../../src/lib/server/ops/simulate';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { dayNoon, toLocalDate } from '../../src/lib/finance/dates';
import { convert } from '../../src/lib/finance/fx';
import { planFlows } from '../../src/lib/finance/planFlows';
import { applyScenario } from '../../src/lib/finance/scenario';
import { MAX_ENTRIES, simulate } from '../../src/lib/finance/simulate';
import { forAgent, MAX_AGENT_CHARS } from '../../src/lib/server/ops/simulate';
import { GOAL_PER_PAY, NET, PAY, plan, RENT } from './planFixture';

// -- CONSTANTS -- //

const TODAY = '2026-06-10';
const NOW = dayNoon(TODAY);

const SNAPSHOTS: RecordedSnapshot[] = [
	{ accountId: 'rcbc', currency: 'PHP', amount: 1_000_000, takenAt: dayNoon('2026-01-02') },
	{ accountId: 'gcash', currency: 'PHP', amount: 300_000, takenAt: dayNoon('2026-01-02') }
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
			occurredAt: dayNoon(d),
			label: 'Salary'
		})
	),
	...RENT_DAYS.map((d) =>
		txn({
			type: 'expense',
			accountId: 'gcash',
			amount: RENT,
			occurredAt: dayNoon(d),
			label: 'Rent'
		})
	),
	...PAY_DAYS.map((d) =>
		txn({
			type: 'transfer',
			accountId: 'rcbc',
			toAccountId: 'gcash',
			amount: 2_000_000,
			occurredAt: dayNoon(d),
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
				(t) => `${t.accountId}|${toLocalDate(t.occurredAt)}`
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
			{ accountId: 'old', currency: 'PHP', amount: 77_700, takenAt: dayNoon('2026-01-02') }
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
					{ accountId: 'save', currency: 'EUR', amount: 5_000, takenAt: dayNoon('2026-01-02') }
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

	it('gives each wallet its main-currency figure at the stored rate, and null (never zero) for a currency with no rate', () => {
		const out = sim({
			snapshots: [
				...SNAPSHOTS,
				{ accountId: 'save', currency: 'USD', amount: 5_000, takenAt: dayNoon('2026-01-02') },
				{ accountId: 'jar', currency: 'EUR', amount: 5_000, takenAt: dayNoon('2026-01-02') }
			],
			wallets: [
				...WALLETS,
				{ accountId: 'save', currency: 'USD' },
				{ accountId: 'jar', currency: 'EUR' }
			]
		});
		const wallets = month(out, '2026-03').wallets;
		const php = wallets.find((w) => w.accountId === 'rcbc');
		const usd = wallets.find((w) => w.currency === 'USD');
		const eur = wallets.find((w) => w.currency === 'EUR');
		// A main-currency wallet is its own figure
		expect(php?.recordedMain).toBe(php?.recorded);
		// 50.00 USD comes to exactly what the stored rate converts it to, a whole number of centavos
		const usdInMain = convert(5_000, 'USD', 'PHP', realPlan().rates);
		expect(usd?.recorded).toBe(5_000);
		expect(usd?.recordedMain).toBe(usdInMain);
		expect(Number.isInteger(usdInMain)).toBe(true);
		expect(usdInMain).toBeGreaterThan(5_000);
		// After today the simulated figure is converted the same way
		expect(month(out, '2026-12').wallets.find((w) => w.currency === 'USD')?.simulatedMain).toBe(
			usdInMain
		);
		// EUR has no rate: the balance is there, its main figure is null and the currency is named
		expect(eur?.recorded).toBe(5_000);
		expect(eur?.recordedMain).toBeNull();
		expect(out.missing).toContain('EUR');
		// The replay balance has no rate either; and a source the period has nothing for stays null on both sides
		expect(eur?.replayMain).toBeNull();
		expect(
			month(out, '2026-12').wallets.find((w) => w.currency === 'USD')?.recordedMain
		).toBeNull();
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

describe('spent and received per period', () => {
	/** A quiet March: only these rows are recorded, so the sums are easy to read. */
	const MARCH: RecordedTxn[] = [
		txn({
			type: 'expense',
			accountId: 'gcash',
			amount: 100_000,
			occurredAt: dayNoon('2026-03-04'),
			label: 'Lunch',
			category: 'Food'
		}),
		txn({
			type: 'expense',
			accountId: 'gcash',
			amount: 40_000,
			occurredAt: dayNoon('2026-03-06'),
			label: 'Dinner',
			category: ' food '
		}),
		txn({
			type: 'refund',
			accountId: 'gcash',
			amount: 20_000,
			occurredAt: dayNoon('2026-03-07'),
			label: 'Refund',
			category: 'Food'
		}),
		txn({
			type: 'income',
			accountId: 'rcbc',
			amount: 500_000,
			occurredAt: dayNoon('2026-03-10'),
			label: 'Salary'
		}),
		txn({
			type: 'transfer',
			accountId: 'rcbc',
			toAccountId: 'gcash',
			amount: 300_000,
			fee: 5_000,
			occurredAt: dayNoon('2026-03-11'),
			label: 'Top up'
		}),
		txn({
			type: 'adjustment',
			accountId: 'gcash',
			amount: -30_000,
			occurredAt: dayNoon('2026-03-12'),
			label: 'Balance count'
		}),
		txn({
			type: 'adjustment',
			accountId: 'gcash',
			amount: 10_000,
			occurredAt: dayNoon('2026-03-13'),
			label: 'Balance count'
		})
	];
	const march = (extra: RecordedTxn[] = [], over: Partial<SimulateInput> = {}) =>
		sim({ txns: [...MARCH, ...extra], ...over });

	it('counts expenses plus transfer fees minus refunds as spent, income as received, a negative count as untracked, and a plain transfer as nothing', () => {
		const p = month(march(), '2026-03');
		// 1,000 + 400 - 200 spending, plus the 50 fee; the 3,000 moved between own accounts is not spending
		expect(p.recordedSpent).toBe(100_000 + 40_000 - 20_000 + 5_000);
		expect(p.recordedReceived).toBe(500_000);
		expect(p.recordedUntracked).toBe(30_000);
		expect(p.leftOut).toEqual([]);
	});

	it('does not count a balance reset as untracked or as spent', () => {
		const reset = txn({
			type: 'adjustment',
			accountId: 'gcash',
			amount: -80_000,
			occurredAt: dayNoon('2026-03-20'),
			label: 'Balance reset: lost the wallet',
			category: 'reset'
		});
		const p = month(march([reset]), '2026-03');
		expect(p.recordedUntracked).toBe(30_000);
		expect(p.recordedSpent).toBe(100_000 + 40_000 - 20_000 + 5_000);
	});

	it('gives the fee its own entry, marks a refund, and every counting entry adds up to the period and to its group', () => {
		const out = march([], { from: '2026-03-01', to: '2026-03-31', detail: true });
		const recorded = (out.entries ?? []).filter((e) => e.source === 'recorded');
		const fee = recorded.find((e) => e.id.endsWith(':fee'));
		expect(fee).toMatchObject({ kind: 'out', amount: 5_000, groupKey: 'other', spentMain: 5_000 });
		const refund = recorded.find((e) => e.refund);
		expect(refund).toMatchObject({ kind: 'in', spentMain: -20_000 });
		expect(refund?.receivedMain).toBeUndefined();
		const p = month(out, '2026-03');
		expect(recorded.reduce((a, e) => a + (e.spentMain ?? 0), 0)).toBe(p.recordedSpent);
		expect(recorded.reduce((a, e) => a + (e.receivedMain ?? 0), 0)).toBe(p.recordedReceived);
		// Food and food with spaces are one group; the fee is other
		const groups = out.breakdown?.recorded.groups ?? [];
		expect(groups.find((g) => g.key === 'cat:food')).toMatchObject({
			amount: 100_000 + 40_000 - 20_000,
			count: 3,
			kind: 'category',
			label: 'Food'
		});
		expect(groups.find((g) => g.key === 'other')?.amount).toBe(5_000);
		const listed = groups.reduce((a, g) => a + g.amount, 0);
		expect(listed + (out.breakdown?.recorded.more?.amount ?? 0)).toBe(p.recordedSpent);
		// Money counts as untracked only for a negative count, and never as spent
		expect(recorded.filter((e) => e.untrackedMain !== undefined)).toHaveLength(1);
	});

	it('groups a bill payment under its bill, named from the plan or from the names it is given', () => {
		const paid = txn({
			type: 'expense',
			accountId: 'gcash',
			amount: RENT,
			occurredAt: dayNoon('2026-03-05'),
			label: 'Rent paid',
			billId: 'rent'
		});
		const gone = txn({
			type: 'expense',
			accountId: 'gcash',
			amount: 70_000,
			occurredAt: dayNoon('2026-03-08'),
			label: 'Old gym',
			billId: 'old-gym'
		});
		const out = march([paid, gone], {
			from: '2026-03-01',
			to: '2026-03-31',
			detail: true,
			billNames: new Map([['old-gym', 'Gym']])
		});
		const groups = out.breakdown?.recorded.groups ?? [];
		expect(groups.find((g) => g.key === 'bill:rent')).toMatchObject({
			label: 'Rent',
			kind: 'bill',
			amount: RENT
		});
		expect(groups.find((g) => g.key === 'bill:old-gym')).toMatchObject({
			label: 'Gym',
			kind: 'bill'
		});
		// The biggest group is listed first
		expect(groups[0]?.key).toBe('bill:rent');
	});

	it('converts each row at the stored rate, and names a currency with no rate instead of counting it as zero', () => {
		const usd = txn({
			type: 'expense',
			accountId: 'gcash',
			amount: 1_500,
			currency: 'USD',
			occurredAt: dayNoon('2026-03-14'),
			label: 'Hosting'
		});
		const eur = txn({
			type: 'expense',
			accountId: 'gcash',
			amount: 900,
			currency: 'EUR',
			occurredAt: dayNoon('2026-03-15'),
			label: 'Coffee'
		});
		const rates = realPlan().rates;
		const p = month(march([usd, eur]), '2026-03');
		expect(p.recordedSpent).toBe(
			100_000 + 40_000 - 20_000 + 5_000 + convert(1_500, 'USD', 'PHP', rates)
		);
		expect(p.leftOut).toEqual(['EUR']);
	});

	it('counts the plan money out and in for the replay and the simulation, never its moves', () => {
		const out = sim({ from: '2026-05-01', to: '2026-07-31', detail: true });
		const may = month(out, '2026-05');
		const jul = month(out, '2026-07');
		const sum = (source: 'replay' | 'simulated', field: 'spentMain' | 'receivedMain') =>
			(out.entries ?? [])
				.filter((e) => e.source === source)
				.reduce((a, e) => a + (e[field] ?? 0), 0);
		// The replay of May is all of May's rent, internet and two paydays
		expect(may.replaySpent).toBe(RENT + NET);
		expect(may.replayReceived).toBe(2 * PAY);
		// The simulation counts July's too and nothing else: the split's moves are in no total
		expect(jul.simulatedSpent).toBe(RENT + NET);
		expect(jul.simulatedReceived).toBe(2 * PAY);
		expect(jul.recordedSpent).toBeNull();
		expect(may.simulatedSpent).toBeNull();
		expect(sum('replay', 'spentMain')).toBe(may.replaySpent);
		expect(sum('simulated', 'receivedMain')).toBe(
			(month(out, '2026-06').simulatedReceived ?? 0) + (jul.simulatedReceived ?? 0)
		);
	});

	it('keeps what was recorded so far and what is still to come apart in the period of today', () => {
		const out = sim({ from: '2026-06-01', to: '2026-06-30' });
		const june = month(out, '2026-06');
		expect(june.part).toBe('mixed');
		// Rent was paid on the 5th (recorded); the internet bill of the 20th, and an unpaid one still within its late window, are still to come
		expect(june.recordedSpent).toBe(RENT);
		expect(june.simulatedSpent).toBeGreaterThanOrEqual(NET);
		expect((june.simulatedSpent ?? 0) % NET).toBe(0);
		expect(june.replaySpent).toBeNull();
	});

	it('adds up: the days of a month are the month, and the months are the year', () => {
		const all = [...TXNS, ...MARCH];
		const days = sim({ group: 'day', from: '2026-03-01', to: '2026-03-31', txns: all });
		const monthly = sim({ from: '2026-03-01', to: '2026-03-31', txns: all });
		const m = monthly.periods[0];
		const total = (f: 'recordedSpent' | 'recordedReceived' | 'recordedUntracked') =>
			days.periods.reduce((a, d) => a + (d[f] ?? 0), 0);
		expect(total('recordedSpent')).toBe(m?.recordedSpent);
		expect(total('recordedReceived')).toBe(m?.recordedReceived);
		expect(total('recordedUntracked')).toBe(m?.recordedUntracked);
		const year = sim({ group: 'year', from: '2026-01-01', to: '2026-12-31' });
		const months = sim({ from: '2026-01-01', to: '2026-12-31' });
		const y = year.periods[0];
		for (const f of [
			'recordedSpent',
			'recordedReceived',
			'simulatedSpent',
			'simulatedReceived'
		] as const)
			expect(months.periods.reduce((a, p) => a + (p[f] ?? 0), 0)).toBe(y?.[f]);
	});
});

describe('the running total from a period to today', () => {
	const recordedSum = (out: ReturnType<typeof sim>, f: 'recordedSpent' | 'recordedReceived') =>
		out.periods.reduce((a, p) => a + (p[f] ?? 0), 0);

	it('gives a past period the total from its start to today, even when the window ends before today', () => {
		const short = sim({ from: '2026-03-01', to: '2026-03-31' });
		const long = sim({ from: '2026-03-01', to: '2026-12-31' });
		const m = month(short, '2026-03');
		expect(m.spanFrom).toBe('2026-03-01');
		expect(m.spanTo).toBe(TODAY);
		expect(m.spanSource).toBe('recorded');
		// March, April, May and the recorded part of June
		const upToJune = { periods: long.periods.filter((p) => p.from <= TODAY) } as typeof long;
		expect(m.spanSpent).toBe(recordedSum(upToJune, 'recordedSpent'));
		expect(m.spanReceived).toBe(recordedSum(upToJune, 'recordedReceived'));
		// The same whatever window it was asked in, and the period's own figures are unchanged by the span
		expect(month(long, '2026-03').spanSpent).toBe(m.spanSpent);
		expect(m.recordedSpent).toBe(month(long, '2026-03').recordedSpent);
		expect(m.spanSpent).toBeGreaterThan(m.recordedSpent ?? 0);
	});

	it('follows the period rule: expenses and fees less refunds, income only, transfers and counts apart', () => {
		const MARCH = [
			txn({
				type: 'expense',
				accountId: 'gcash',
				amount: 100_000,
				occurredAt: dayNoon('2026-03-04')
			}),
			txn({
				type: 'refund',
				accountId: 'gcash',
				amount: 20_000,
				occurredAt: dayNoon('2026-03-07')
			}),
			txn({
				type: 'income',
				accountId: 'rcbc',
				amount: 500_000,
				occurredAt: dayNoon('2026-03-10')
			}),
			txn({
				type: 'transfer',
				accountId: 'rcbc',
				toAccountId: 'gcash',
				amount: 300_000,
				fee: 5_000,
				occurredAt: dayNoon('2026-03-11')
			}),
			txn({
				type: 'adjustment',
				accountId: 'gcash',
				amount: -30_000,
				occurredAt: dayNoon('2026-03-12')
			}),
			txn({
				type: 'adjustment',
				accountId: 'gcash',
				amount: -80_000,
				occurredAt: dayNoon('2026-03-20'),
				category: 'reset'
			})
		];
		const m = month(sim({ from: '2026-03-01', to: '2026-03-31', txns: MARCH }), '2026-03');
		expect(m.spanSpent).toBe(100_000 - 20_000 + 5_000);
		expect(m.spanReceived).toBe(500_000);
		expect(m.spanSpent).toBe(m.recordedSpent);
		expect(m.spanReceived).toBe(m.recordedReceived);
	});

	it('gives a future period the simulated total from today to its end', () => {
		const out = sim({ from: '2026-06-01', to: '2026-07-31' });
		const june = month(out, '2026-06');
		const jul = month(out, '2026-07');
		expect(jul.spanFrom).toBe(TODAY);
		expect(jul.spanTo).toBe('2026-07-31');
		expect(jul.spanSource).toBe('simulated');
		expect(jul.spanSpent).toBe((june.simulatedSpent ?? 0) + (jul.simulatedSpent ?? 0));
		expect(jul.spanReceived).toBe((june.simulatedReceived ?? 0) + (jul.simulatedReceived ?? 0));
	});

	it('has none for the period of today, for a period before the first record, or for a day window with nothing past', () => {
		const june = month(sim({ from: '2026-06-01', to: '2026-06-30' }), '2026-06');
		expect(june.part).toBe('mixed');
		expect(june.spanSpent).toBeNull();
		expect(june.spanFrom).toBeNull();
		expect(june.spanLeftOut).toEqual([]);
		const early = month(sim({ from: '2025-11-01', to: '2026-01-31' }), '2025-12');
		expect(early.beforeFirstRecord).toBe(true);
		expect(early.spanSpent).toBeNull();
	});

	it('names a currency with no rate in the span only, and leaves the period as it was', () => {
		const eur = txn({
			type: 'expense',
			accountId: 'gcash',
			amount: 900,
			currency: 'EUR',
			occurredAt: dayNoon('2026-04-15'),
			label: 'Coffee'
		});
		const out = sim({ from: '2026-03-01', to: '2026-03-31', txns: [...TXNS, eur] });
		const m = month(out, '2026-03');
		expect(m.leftOut).toEqual([]);
		expect(m.spanLeftOut).toEqual(['EUR']);
	});

	it('keeps the entries to the window when it ends before today', () => {
		const out = sim({ from: '2026-03-01', to: '2026-03-31', detail: true });
		for (const e of out.entries ?? []) {
			expect(e.date >= '2026-03-01' && e.date <= '2026-03-31').toBe(true);
		}
	});

	it('is left out of the assistant answer, which would quote it as the period', () => {
		const out = sim({ from: '2026-03-01', to: '2026-03-31' });
		const view: SimulationView = {
			...out,
			view: 'overview',
			notes: [],
			rates: { asOf: null, stale: false }
		};
		const cut = forAgent(view);
		expect(month(out, '2026-03').spanSpent).not.toBeNull();
		expect(JSON.stringify(cut)).not.toContain('span');
	});
});

describe('entries in one order, and in bulk', () => {
	const many = (n: number): RecordedTxn[] =>
		Array.from({ length: n }, (_, i) =>
			txn({
				type: 'expense',
				accountId: 'gcash',
				amount: 100 + (i % 37),
				occurredAt: dayNoon(`2026-03-${String(1 + (i % 28)).padStart(2, '0')}`),
				label: `Row ${i}`,
				category: i % 3 === 0 ? 'Food' : i % 3 === 1 ? 'Fun' : null
			})
		);

	it('gives the same pages whatever order the rows were read in', () => {
		const rows = many(240);
		const ask = (txns: RecordedTxn[], offset: number) =>
			sim({
				from: '2026-03-01',
				to: '2026-03-31',
				detail: true,
				txns,
				page: { offset, limit: 100 }
			}).entries?.map((e) => e.id);
		const shuffled = [...rows].sort((a, b) => (a.id < b.id ? 1 : -1));
		for (const offset of [0, 100, 200]) expect(ask(shuffled, offset)).toEqual(ask(rows, offset));
	});

	it('answers a few thousand rows in a second or two, and the breakdown still adds up to spent', () => {
		const rows = many(4_000);
		const started = Date.now();
		const out = sim({ from: '2026-03-01', to: '2026-03-31', detail: true, txns: rows });
		expect(Date.now() - started).toBeLessThan(3_000);
		const p = month(out, '2026-03');
		const b = out.breakdown?.recorded;
		const total = (b?.groups ?? []).reduce((a, g) => a + g.amount, 0) + (b?.more?.amount ?? 0);
		expect(total).toBe(p.recordedSpent);
		expect(out.entries).toHaveLength(500);
		expect(out.entriesOmitted).toBeGreaterThanOrEqual(4_000 - 500);
	});
});

// -- NET AT THE END OF A SIMULATED PERIOD (BTL-20261109-0230) -- //

describe('net of the simulated balance', () => {
	const walletOf = (p: ReturnType<typeof month>, id: string) =>
		p.wallets.find((w) => w.accountId === id);
	const whatIf = (over: Partial<NonNullable<PlanData['whatIf']>> = {}) => ({
		skip: new Set<string>(),
		billAmounts: new Map<string, number>(),
		delayDays: 0,
		deferDeferrable: false,
		extra: [],
		...over
	});

	it('gives a simulated or mixed period a net and leaves a past period without one', () => {
		const out = sim();
		expect(month(out, '2026-03').simulatedNetEnd).toBeUndefined();
		expect(walletOf(month(out, '2026-03'), 'gcash')?.simulatedNet).toBeUndefined();
		for (const ym of ['2026-06', '2026-07', '2026-12']) {
			const p = month(out, ym);
			expect(typeof p.simulatedNetEnd).toBe('number');
			expect(p.simulatedNetEnd).toBeLessThanOrEqual(p.simulatedEnd ?? 0);
		}
		expect(out.net).toEqual({ failed: false, unmatched: [], broken: [] });
	});

	it('holds the bills due before the next payday out of the balance at the end of the month', () => {
		// 31 July: the next payday is 14 August, and the rent of 5 August falls before it; the internet bill of the 20th does not
		const out = sim({ from: '2026-07-01', to: '2026-07-31', detail: true });
		const july = month(out, '2026-07');
		const gcash = walletOf(july, 'gcash');
		expect(gcash?.simulatedHolds).toEqual(
			expect.arrayContaining([{ kind: 'bill', label: 'Rent', amount: RENT, dueDate: '2026-08-05' }])
		);
		expect(gcash?.simulatedHolds?.some((h) => h.label === 'Internet')).toBe(false);
		const balance = gcash?.simulated ?? 0;
		expect(gcash?.simulatedNet).toBe(Math.max(0, balance - (gcash?.simulatedHeld ?? 0)));
		// Only the rent is due before the payday, so only it can be short
		expect(gcash?.simulatedShortfall).toBe(Math.max(0, RENT - Math.max(balance, 0)));
	});

	it('keeps a goal wallet whole and adds the wallets net to the period total to the last unit', () => {
		const july = month(sim(), '2026-07');
		const goal = walletOf(july, 'save');
		expect(goal?.simulatedNet).toBe(0);
		expect(goal?.simulatedHeld).toBe(Math.max(goal?.simulated ?? 0, 0));
		const sum = july.wallets.reduce((n, w) => n + (w.simulatedNetMain ?? 0), 0);
		expect(july.simulatedNetEnd).toBe(sum);
		const short = july.wallets.reduce((n, w) => n + (w.simulatedShortfall ?? 0), 0);
		expect(july.simulatedShortfallEnd).toBe(short);
	});

	it('follows the what-if: a delay moves the rent past the payday, so it is not held at the end of July', () => {
		const base = month(sim({ from: '2026-07-01', to: '2026-07-31' }), '2026-07');
		const delayed = month(
			sim(
				{ from: '2026-07-01', to: '2026-07-31' },
				realPlan({ whatIf: whatIf({ delayDays: 12 }) })
			),
			'2026-07'
		);
		// 5 August is held at 31 July; 12 days late it is the 17th, after the payday of the 14th
		expect(walletOf(base, 'gcash')?.simulatedHeld).toBeGreaterThanOrEqual(RENT);
		expect(walletOf(delayed, 'gcash')?.simulatedHeld).toBeLessThan(RENT);
	});

	it('leaves a currency with no rate out of the net total and names it, never counting it as zero', () => {
		const eur = { accountId: 'save', currency: 'EUR' };
		const out = sim({
			wallets: [...WALLETS, eur],
			snapshots: [
				...SNAPSHOTS,
				{ accountId: 'save', currency: 'EUR', amount: 10_000, takenAt: dayNoon('2026-01-02') }
			]
		});
		const july = month(out, '2026-07');
		const w = july.wallets.find((x) => x.currency === 'EUR');
		expect(w?.simulatedNet).toBe(10_000);
		expect(w?.simulatedNetMain).toBeNull();
		expect(out.missing).toContain('EUR');
		const sum = july.wallets.reduce((n, x) => n + (x.simulatedNetMain ?? 0), 0);
		expect(july.simulatedNetEnd).toBe(sum);
	});

	it('holds no bill and no set-aside for an archived account', () => {
		const base = realPlan();
		const p = {
			...base,
			accounts: base.accounts.map((a) => (a.id === 'gcash' ? { ...a, archived: true } : a))
		};
		const july = month(sim({}, p), '2026-07');
		expect(walletOf(july, 'gcash')?.simulatedHeld ?? 0).toBe(0);
	});

	it('answers a 62-day range by day and a two-year range by week, each period with its net', () => {
		const daily = sim({ from: '2026-06-10', to: '2026-08-10', group: 'day' });
		expect(daily.periods).toHaveLength(62);
		expect(daily.periods.every((p) => typeof p.simulatedNetEnd === 'number')).toBe(true);
		const started = Date.now();
		const weekly = sim({ from: '2026-06-10', to: '2028-06-09', group: 'week' });
		expect(weekly.periods.length).toBeGreaterThan(100);
		expect(weekly.periods.every((p) => typeof p.simulatedNetEnd === 'number')).toBe(true);
		expect(Date.now() - started).toBeLessThan(5_000);
	});

	it('cuts the assistant summary so the net stays while it fits and goes, with every net note, when it does not', () => {
		const out = sim({ from: '2026-06-10', to: '2026-12-31', group: 'week' });
		const view = (pad: number) =>
			({
				...out,
				view: 'overview',
				rates: { asOf: null, stale: false },
				notes: [
					'Only recorded numbers are real.',
					'Net (simulatedNetEnd, and simulatedNet on a wallet) is what is left.',
					"Net: no wallet holds Rent in the bill's currency, so it is in no net.",
					'x'.repeat(pad)
				]
			}) as unknown as SimulationView;
		const answers: SimulationView[] = [];
		for (let pad = 0; pad <= 16_000; pad += 40) {
			try {
				answers.push(forAgent(view(pad)));
			} catch {
				// Too much padding even for the bare summary: the cut has nothing left to drop
				break;
			}
		}
		const withNet = answers.filter((r) => r.summary?.some((p) => p.net !== undefined));
		const without = answers.filter((r) => r.summary?.every((p) => p.net === undefined));
		expect(withNet.length).toBeGreaterThan(0);
		expect(without.length).toBeGreaterThan(0);
		for (const r of answers) expect(JSON.stringify(r).length).toBeLessThanOrEqual(MAX_AGENT_CHARS);
		for (const r of withNet)
			expect(r.notes.some((n) => n.startsWith('Net (simulatedNetEnd'))).toBe(true);
		for (const r of without) {
			expect(r.net).toBeUndefined();
			// Every net note went with the net; at most the one short sentence saying so is left
			expect(
				r.notes.filter(
					(n) => n.startsWith('Net') && !n.includes('left out here to keep the answer short')
				)
			).toEqual([]);
		}
	});
});
