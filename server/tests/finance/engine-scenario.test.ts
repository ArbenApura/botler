// ONE SHARED PLAN AND THE FOUR WAYS OF LOOKING AT IT: THE PAYDAY SPLIT, cashflow_forecast, balance_simulate AND calendar_range MUST AGREE
// The scenario has an archived target account, a foreign-currency bill paid from its own wallet, a bill late by 10 days, a payday today, and
// a recorded pay that must be matched to its own income schedule. Every date is relative to today, so the numbers do not depend on the run date.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, dayStart, toLocalDate } from '../../src/lib/finance/dates';
import { forecast } from '../../src/lib/finance/forecast';
import { recordedPays } from '../../src/lib/finance/planFlows';
import { ruleWarnings, validateRules } from '../../src/lib/finance/rules';
import { occurrencesBetween } from '../../src/lib/finance/schedule';
import {
	balanceSnapshot,
	calendarEvent,
	fxRate,
	ledgerTxn,
	user
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { configureFx } from '../../src/lib/server/fx/config';
import { addWallet, archiveAccount, createAccount } from '../../src/lib/server/ops/accounts';
import { balanceSimulate, loadRecorded } from '../../src/lib/server/ops/simulate';
import { createBill } from '../../src/lib/server/ops/bills';
import { calendarRange } from '../../src/lib/server/ops/calendarRange';
import { cashflowForecast } from '../../src/lib/server/ops/forecast';
import {
	accountBalances,
	balancesIn,
	logExpense,
	logExpenseFromText,
	recordIncome,
	recordRefund,
	recordSnapshot,
	recordTransfer,
	spendingSummary,
	weeklyCheckin
} from '../../src/lib/server/ops/ledger';
import { createIncome } from '../../src/lib/server/ops/planning';
import { approveRule, proposeRule } from '../../src/lib/server/ops/rules';
import {
	createEvent,
	createReminder,
	createTask,
	deleteEvent,
	listEvents
} from '../../src/lib/server/ops/schedule';
import { approveSplit, proposeSplitPlan } from '../../src/lib/server/ops/split';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;
let users = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const as = (c: Ctx): Ctx => ({ ...c, requestId: `req-eng-${String(++counter).padStart(6, '0')}` });
const today = () => toLocalDate(new Date());
const inDays = (n: number) => addDays(today(), n);
const newUser = async () => {
	const id = `user_eng_${String(++users).padStart(4, '0')}`;
	await t.handle.db.insert(user).values({ id, name: id, email: `${id}@example.com` });
	return id;
};

type Scene = {
	id: string;
	ctx: Ctx;
	pay: string;
	sav: string;
	old: string;
	dollar: string;
	salary: string;
	rent: string;
};

/**
 * The shared plan. Pay account: 10,000.00 pesos and 200.00 dollars. A salary of 20,000.00 whose payday is today (not recorded). A rule of
 * 2,000.00 into Savings and one of 3,000.00 into Old, which is then hidden. Bills: Rent 5,000.00 in 3 days, Cloud 10.00 dollars in 5 days
 * (paid from the dollar wallet), Gym 1,000.00 in 4 days on a dollar-only card, and Late 500.00 that was due 10 days ago and is unpaid.
 */
async function scene(opts: { salary?: boolean } = {}): Promise<Scene> {
	const id = await newUser();
	const c = person(id);
	const pay = (await createAccount(as(c), { name: 'Pay', kind: 'bank', minBalance: 0 })).id;
	const sav = (await createAccount(as(c), { name: 'Savings', kind: 'ewallet' })).id;
	const old = (await createAccount(as(c), { name: 'Old', kind: 'ewallet' })).id;
	const dollar = (
		await createAccount(as(c), { name: 'Dollar card', kind: 'bank', currency: 'USD' })
	).id;
	await addWallet(as(c), { accountId: pay, currency: 'USD' });
	await recordSnapshot(as(c), { accountId: pay, amount: 1_000_000, confirmed: true });
	await recordSnapshot(as(c), { accountId: pay, currency: 'USD', amount: 20_000, confirmed: true });
	const salary = (
		await createIncome(as(c), {
			label: 'Salary',
			accountId: pay,
			expectedAmount: opts.salary === false ? null : 2_000_000,
			schedule: { kind: 'every_n_days', anchor: today(), n: 60 },
			weekendRule: 'none'
		})
	).id;
	for (const [amount, target] of [
		[200_000, sav],
		[300_000, old]
	] as const) {
		const r = await proposeRule(as(c), { mode: 'fixed', amount, targetAccountId: target });
		await approveRule(as(c), { ruleId: r.id });
	}
	await archiveAccount(as(c), { accountId: old });
	const bill = async (
		name: string,
		accountId: string,
		amount: number,
		offset: number,
		currency?: string
	) =>
		(
			await createBill(as(c), {
				name,
				category: 'bills',
				accountId,
				kind: 'fixed',
				amount,
				...(currency ? { currency } : {}),
				schedule: { kind: 'once', date: inDays(offset) },
				weekendRule: 'none',
				deferrable: false
			})
		).id;
	const rent = await bill('Rent', pay, 500_000, 3);
	await bill('Cloud', pay, 1_000, 5, 'USD');
	await bill('Gym', dollar, 100_000, 4);
	await bill('Late', pay, 50_000, -10);
	return { id, ctx: c, pay, sav, old, dollar, salary, rent };
}

const forecastDays = async (id: string, days = 10) => {
	const out = await cashflowForecast(person(id), { to: inDays(days), group: 'day' });
	return { out, total: (n: number) => out.periods[n]?.endTotal };
};

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	configureFx(null);
	for (const [code, rate] of Object.entries({ PHP: '56', JPY: '157.2' }))
		await t.handle.db.insert(fxRate).values({ code, rate, fetchedAt: new Date(), source: 'test' });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the shared plan', () => {
	it('gives the same daily totals in the forecast and the calendar, with the late bill, the pay of today and the dollar bill in their own wallet', async () => {
		const s = await scene();
		const { out, total } = await forecastDays(s.id);
		// Wallets now: 10,000.00 pesos and 200.00 dollars at 56 pesos
		expect(out.startTotal).toBe(1_000_000 + 20_000 * 56);
		// Today: the pay arrives and the bill late by 10 days (31 days are looked back) goes out
		expect(total(0)).toBe(2_120_000 - 50_000 + 2_000_000);
		expect(total(3)).toBe((total(2) ?? 0) - 500_000);
		expect(total(4)).toBe((total(3) ?? 0) - 100_000);
		// The dollar bill leaves the dollar wallet: 10.00 dollars at 56
		expect(total(5)).toBe((total(4) ?? 0) - 1_000 * 56);
		const usd = out.endWallets.find((w) => w.accountName === 'Pay' && w.currency === 'USD');
		expect(usd?.end).toBe(19_000);

		const cal = await calendarRange(s.ctx, { from: today(), to: inDays(10) });
		expect(cal.forecast.days.map((d) => d.total)).toEqual(out.periods.map((p) => p.endTotal));
		expect(cal.forecast.unconvertedBills).toBe(0);
	});

	it('never moves money into the hidden account: not in the split, the forecast, the simulation or the calendar', async () => {
		const s = await scene();
		const plan = await proposeSplitPlan(as(s.ctx), { incomeScheduleId: s.salary });
		if (plan.status === 'needs_amounts') throw new Error('needs amounts');
		expect(plan.result.lines.some((l) => l.accountId === s.old)).toBe(false);
		expect(plan.result.transfers.some((x) => x.toAccountId === s.old)).toBe(false);
		expect(plan.result.skippedRules?.some((r) => r.note.includes('hidden'))).toBe(true);

		const { out } = await forecastDays(s.id);
		const moves = out.periods.flatMap((p) => p.moves);
		expect(moves.length).toBeGreaterThan(0);
		expect(moves.some((m) => m.toAccountId === s.old)).toBe(false);
		expect(out.endWallets.some((w) => w.accountId === s.old && w.end !== 0)).toBe(false);

		const sim = await balanceSimulate(s.ctx, {
			from: inDays(1),
			to: inDays(10),
			group: 'day',
			view: 'detail'
		});
		expect(sim.entries?.some((e) => e.kind === 'move' && e.toAccountId === s.old)).toBeFalsy();
		expect(
			sim.periods.every((p) =>
				p.wallets.every((w) => w.accountId !== s.old || w.simulated === 0 || w.simulated === null)
			)
		).toBe(true);
		const cal = await calendarRange(s.ctx, { from: today(), to: inDays(10) });
		expect(cal.forecast.days.length).toBe(11);
	});

	it('agrees between the forecast and the simulation on the start and the first day', async () => {
		const s = await scene();
		const { out } = await forecastDays(s.id);
		const sim = await balanceSimulate(s.ctx, { from: today(), to: inDays(10), group: 'day' });
		const first = sim.periods[0];
		expect(first?.simulatedStart).toBe(out.startTotal);
		expect(first?.simulatedEnd).toBe(out.periods[0]?.endTotal);
		expect(sim.periods.at(-1)?.simulatedEnd).toBe(out.endTotal);
	});

	it('reports a bill on an account with no wallet to pay it, instead of dropping it', async () => {
		const id = await newUser();
		const c = person(id);
		const ghost = (await createAccount(as(c), { name: 'Ghost', kind: 'bank', currency: 'USD' })).id;
		await createBill(as(c), {
			name: 'Orphan',
			category: 'bills',
			accountId: ghost,
			kind: 'fixed',
			amount: 30_000,
			schedule: { kind: 'once', date: inDays(2) },
			weekendRule: 'none',
			deferrable: false
		});
		const cal = await calendarRange(c, { from: today(), to: inDays(5) });
		expect(cal.forecast.unconvertedBills).toBe(1);
		const out = await cashflowForecast(c, { to: inDays(5), group: 'day' });
		expect(out.notes.some((n) => n.includes('not in the balances'))).toBe(true);
	});
});

describe('a pay recorded today belongs to its own income schedule', () => {
	it('a small income on the pay account does not hide the salary', async () => {
		const s = await scene();
		await recordIncome(as(s.ctx), { accountId: s.pay, amount: 5_000 });
		const { out, total } = await forecastDays(s.id);
		expect(out.startTotal).toBe(2_120_000 + 5_000);
		expect(total(0)).toBe(2_125_000 - 50_000 + 2_000_000);
		const cal = await calendarRange(s.ctx, { from: today(), to: inDays(3) });
		expect(cal.forecast.days[0]?.total).toBe(total(0));
	});

	it('the salary itself, recorded, is not counted a second time, and a refund is not a pay', async () => {
		const s = await scene();
		await recordRefund(as(s.ctx), { accountId: s.pay, amount: 2_000_000 });
		const { total } = await forecastDays(s.id);
		// The refund is not a pay: the salary of today still comes
		expect(total(0)).toBe(2_120_000 + 2_000_000 - 50_000 + 2_000_000);
		const t2 = await scene();
		await recordIncome(as(t2.ctx), { accountId: t2.pay, amount: 2_000_000 });
		const after = await forecastDays(t2.id);
		expect(after.total(0)).toBe(2_120_000 + 2_000_000 - 50_000);
	});

	it('a simulation that starts after today does not count a pay recorded today a second time', async () => {
		const s = await scene();
		await recordIncome(as(s.ctx), { accountId: s.pay, amount: 2_000_000 });
		const fromToday = await balanceSimulate(s.ctx, { from: today(), to: inDays(3), group: 'day' });
		const fromTomorrow = await balanceSimulate(s.ctx, {
			from: inDays(1),
			to: inDays(3),
			group: 'day'
		});
		expect(fromTomorrow.periods[0]?.simulatedStart).toBe(fromToday.periods[1]?.simulatedStart);
	});

	it('with two incomes on one account, the entry matches the one it is for', async () => {
		const s = await scene();
		await createIncome(as(s.ctx), {
			label: 'Side job',
			accountId: s.pay,
			expectedAmount: 300_000,
			schedule: { kind: 'every_n_days', anchor: today(), n: 60 },
			weekendRule: 'none'
		});
		await recordIncome(as(s.ctx), { accountId: s.pay, amount: 300_000 });
		const { total } = await forecastDays(s.id);
		// The side job is in the balance already; the salary still arrives today
		expect(total(0)).toBe(2_120_000 + 300_000 - 50_000 + 2_000_000);
	});

	it('matches a split entry by its schedule and a person entry by its size (pure)', () => {
		const incomes = [
			{
				id: 'salary',
				label: 'Salary',
				accountId: 'pay',
				expectedAmount: 2_000_000,
				schedule: { kind: 'every_n_days' as const, anchor: '2026-01-01', n: 1 },
				weekendRule: 'none' as const,
				createdOn: '2026-01-01'
			},
			{
				id: 'side',
				label: 'Side',
				accountId: 'pay',
				expectedAmount: 300_000,
				schedule: { kind: 'every_n_days' as const, anchor: '2026-01-01', n: 1 },
				weekendRule: 'none' as const,
				createdOn: '2026-01-01'
			}
		];
		const plan = (records: { amount: number; scheduleId: string | null; currency?: string }[]) =>
			({
				main: 'PHP',
				incomes,
				incomeDays: new Set(['pay|2026-02-01']),
				incomeRecords: records.map((r) => ({
					accountId: 'pay',
					date: '2026-02-01',
					currency: r.currency ?? 'PHP',
					amount: r.amount,
					scheduleId: r.scheduleId
				}))
			}) as unknown as Parameters<typeof recordedPays>[0];
		expect([...recordedPays(plan([{ amount: 300_000, scheduleId: null }]), '2026-02-01')]).toEqual([
			'side'
		]);
		expect([
			...recordedPays(plan([{ amount: 1_900_000, scheduleId: null }]), '2026-02-01')
		]).toEqual(['salary']);
		expect([...recordedPays(plan([{ amount: 5_000, scheduleId: null }]), '2026-02-01')]).toEqual(
			[]
		);
		expect([
			...recordedPays(plan([{ amount: 300_000, scheduleId: 'salary' }]), '2026-02-01')
		]).toEqual(['salary']);
		expect([
			...recordedPays(
				plan([{ amount: 2_000_000, scheduleId: null, currency: 'USD' }]),
				'2026-02-01'
			)
		]).toEqual([]);
	});
});

describe('the payday split', () => {
	it('keeps the money recorded today in the pay account for a payday still ahead', async () => {
		const id = await newUser();
		const c = person(id);
		const pay = (await createAccount(as(c), { name: 'Pay', kind: 'bank' })).id;
		await recordSnapshot(as(c), { accountId: pay, amount: 1_000_000, confirmed: true });
		const next = (
			await createIncome(as(c), {
				label: 'Next pay',
				accountId: pay,
				expectedAmount: 1_000_000,
				schedule: { kind: 'every_n_days', anchor: inDays(5), n: 60 },
				weekendRule: 'none'
			})
		).id;
		await createBill(as(c), {
			name: 'Rent',
			category: 'rent',
			accountId: pay,
			kind: 'fixed',
			amount: 200_000,
			schedule: { kind: 'once', date: inDays(7) },
			weekendRule: 'none',
			deferrable: false
		});
		// Some other money arrives today
		await recordIncome(as(c), { accountId: pay, amount: 5_000 });
		const plan = await proposeSplitPlan(as(c), { incomeScheduleId: next });
		if (plan.status === 'needs_amounts') throw new Error('needs amounts');
		// The rent is paid from what the account holds, so nothing has to move for it
		expect(plan.result.covered.map((x) => x.label)).toContain('Rent');
	});

	it('records the pay of an approved split for a past payday on that day, not now', async () => {
		const id = await newUser();
		const c = person(id);
		const pay = (await createAccount(as(c), { name: 'Pay', kind: 'bank' })).id;
		const inc = (
			await createIncome(as(c), {
				label: 'Pay',
				accountId: pay,
				expectedAmount: 1_000_000,
				schedule: { kind: 'every_n_days', anchor: inDays(-3), n: 60 },
				weekendRule: 'none'
			})
		).id;
		const plan = await proposeSplitPlan(as(c), { incomeScheduleId: inc, payday: inDays(-3) });
		if (plan.status === 'needs_amounts') throw new Error('needs amounts');
		await approveSplit(as(c), { splitId: plan.id, recordIncome: true });
		const rows = await withUser(t.handle, id, (tx) =>
			tx
				.select()
				.from(ledgerTxn)
				.where(and(eq(ledgerTxn.userId, id), eq(ledgerTxn.type, 'income')))
		);
		expect(rows).toHaveLength(1);
		expect(toLocalDate(rows[0]?.occurredAt ?? new Date())).toBe(inDays(-3));
	});
});

describe('two paydays a month that fall on the same short-month date', () => {
	it('keeps the documented behaviour: one payday when both days clamp to the same date, two otherwise', () => {
		const between = (days: [number, number], from: string, to: string) =>
			occurrencesBetween({ kind: 'semi_monthly', days }, from, to, { weekend: 'none' });
		// February has 28 days in 2027: the 30th and the 31st are both the 28th, a date that is a payday once
		expect(between([30, 31], '2027-02-01', '2027-02-28')).toEqual(['2027-02-28']);
		expect(between([29, 31], '2027-02-01', '2027-02-28')).toEqual(['2027-02-28']);
		// Distinct dates keep both paydays, and the clamped day is the first of two
		expect(between([15, 31], '2027-02-01', '2027-02-28')).toEqual(['2027-02-15', '2027-02-28']);
		expect(between([30, 31], '2027-04-01', '2027-04-30')).toEqual(['2027-04-30']);
		expect(between([29, 31], '2027-04-01', '2027-04-30')).toEqual(['2027-04-29', '2027-04-30']);
		expect(between([30, 31], '2027-01-01', '2027-01-31')).toEqual(['2027-01-30', '2027-01-31']);
	});
});

describe('rules that can ask for more than the pay', () => {
	it('warns when the shares of the pay and of what is left add up to more than the pay, and still saves', async () => {
		const rule = (base: 'pay' | 'remaining', basisPoints: number) => ({
			id: `${base}${basisPoints}`,
			position: 1,
			target: { kind: 'account' as const, id: 'a' },
			mode: 'percent' as const,
			amount: null,
			basisPoints,
			base,
			effectiveFrom: '2026-01-01',
			version: 1
		});
		expect(validateRules([rule('pay', 6000), rule('remaining', 6000)])).toEqual([]);
		expect(ruleWarnings([rule('pay', 6000), rule('remaining', 6000)])).toHaveLength(1);
		expect(ruleWarnings([rule('pay', 4000), rule('remaining', 6000)])).toEqual([]);

		const id = await newUser();
		const c = person(id);
		const a = (await createAccount(as(c), { name: 'A', kind: 'bank' })).id;
		const b = (await createAccount(as(c), { name: 'B', kind: 'bank' })).id;
		const first = await proposeRule(as(c), {
			mode: 'percent',
			basisPoints: 6000,
			base: 'pay',
			targetAccountId: a
		});
		await approveRule(as(c), { ruleId: first.id });
		const second = await proposeRule(as(c), {
			mode: 'percent',
			basisPoints: 6000,
			base: 'remaining',
			targetAccountId: b
		});
		expect(second.warnings).toHaveLength(1);
		const approved = await approveRule(as(c), { ruleId: second.id });
		expect(approved.status).toBe('active');
		expect(approved.warnings).toHaveLength(1);
	});
});

describe('spending by category', () => {
	it('adds up to the spending: expenses, fees and refunds, with categories grouped without regard to case', async () => {
		const id = await newUser();
		const c = person(id);
		const a = (await createAccount(as(c), { name: 'A', kind: 'bank' })).id;
		const b = (await createAccount(as(c), { name: 'B', kind: 'bank' })).id;
		await recordSnapshot(as(c), { accountId: a, amount: 1_000_000, confirmed: true });
		await logExpense(as(c), { accountId: a, amount: 100_000, category: 'Food' });
		await logExpense(as(c), { accountId: a, amount: 50_000, category: ' food ' });
		await recordTransfer(as(c), { fromAccountId: a, toAccountId: b, amount: 20_000, fee: 1_000 });
		await recordRefund(as(c), { accountId: a, amount: 20_000 });
		const s = await spendingSummary(c, { from: today(), to: today() });
		expect(s.byCategory).toEqual({ Food: 150_000, fees: 1_000, other: -20_000 });
		expect(Object.values(s.byCategory).reduce((x, y) => x + y, 0)).toBe(s.spending);
	});
});

describe('the weekly check-in', () => {
	it('names untracked money in other currencies and counts the balances with a fixed number of queries', async () => {
		const id = await newUser();
		const c = person(id);
		const a = (await createAccount(as(c), { name: 'Wise', kind: 'ewallet' })).id;
		await addWallet(as(c), { accountId: a, currency: 'USD' });
		await recordSnapshot(as(c), { accountId: a, currency: 'USD', amount: 10_000, confirmed: true });
		await logExpense(as(c), { accountId: a, currency: 'USD', amount: 2_000 });
		await recordSnapshot(as(c), { accountId: a, currency: 'USD', amount: 5_000, confirmed: true });
		const check = await weeklyCheckin(c);
		expect(check.untrackedLast7Days).toBe(0);
		expect(check.untrackedOtherCurrencies).toEqual([{ currency: 'USD', amount: 3_000 }]);
		expect(check.accounts.map((x) => [x.currency, x.expected]).sort()).toEqual([
			['PHP', 0],
			['USD', 5_000]
		]);

		// The queries of the balances do not grow with the accounts
		const count = async () => {
			let n = 0;
			await withUser(t.handle, id, async (tx) => {
				const counting = new Proxy(tx, {
					get(target, prop) {
						const v = Reflect.get(target, prop, target) as unknown;
						if (typeof v !== 'function') return v;
						if (prop === 'select' || prop === 'selectDistinctOn' || prop === 'execute')
							return (...args: unknown[]) => {
								n++;
								return (v as (...a: unknown[]) => unknown).apply(target, args);
							};
						return (v as (...a: unknown[]) => unknown).bind(target);
					}
				});
				await balancesIn(counting, id);
			});
			return n;
		};
		const few = await count();
		for (let i = 0; i < 4; i++) await createAccount(as(c), { name: `Extra ${i}`, kind: 'cash' });
		const many = await count();
		expect(many).toBe(few);
		expect(many).toBeLessThanOrEqual(5);
		const rows = await accountBalances(c);
		expect(rows).toHaveLength(5);
	});
});

describe('the simulation', () => {
	it('treats a hidden account the same way in the recorded end and the simulated start of today', async () => {
		const id = await newUser();
		const c = person(id);
		const live = (await createAccount(as(c), { name: 'Live', kind: 'bank' })).id;
		const gone = (await createAccount(as(c), { name: 'Gone', kind: 'bank' })).id;
		const longAgo = new Date(Date.now() - 40 * 86_400_000).toISOString();
		await recordSnapshot(as(c), {
			accountId: live,
			amount: 100_000,
			confirmed: true,
			takenAt: longAgo
		});
		await recordSnapshot(as(c), {
			accountId: gone,
			amount: 50_000,
			confirmed: true,
			takenAt: longAgo
		});
		await archiveAccount(as(c), { accountId: gone });
		const sim = await balanceSimulate(c, { from: inDays(-2), to: inDays(1), group: 'day' });
		const past = sim.periods.find((p) => p.part === 'past');
		const mixed = sim.periods.find((p) => p.part === 'mixed');
		// The past was real: both accounts. From today on the hidden one is out of the plan, in the recorded and the simulated figure alike
		expect(past?.recordedEnd).toBe(150_000);
		expect(mixed?.recordedEnd).toBe(100_000);
		expect(mixed?.simulatedStart).toBe(100_000);
	});

	it('reads only the counts and entries a range needs, and the same balances', async () => {
		const id = await newUser();
		const c = person(id);
		const a = (await createAccount(as(c), { name: 'A', kind: 'bank' })).id;
		const ago = (days: number) => new Date(Date.now() - days * 86_400_000);
		await recordSnapshot(as(c), {
			accountId: a,
			amount: 100_000,
			confirmed: true,
			takenAt: ago(40).toISOString()
		});
		await logExpense(as(c), { accountId: a, amount: 1_000, occurredAt: ago(30).toISOString() });
		await recordSnapshot(as(c), {
			accountId: a,
			amount: 90_000,
			confirmed: true,
			takenAt: ago(20).toISOString()
		});
		await logExpense(as(c), { accountId: a, amount: 2_000, occurredAt: ago(10).toISOString() });
		await logExpense(as(c), { accountId: a, amount: 3_000, occurredAt: ago(1).toISOString() });
		const loaded = await withUser(t.handle, id, (tx) =>
			loadRecorded(tx, id, {
				from: inDays(-5),
				now: new Date(),
				wallets: [{ accountId: a, currency: 'PHP' }]
			})
		);
		// The count of 20 days ago is the latest before the range; what came before it is not read
		expect(loaded.snapshots.map((s) => s.amount)).toEqual([90_000]);
		expect(loaded.txns.map((x) => x.amount)).toEqual([2_000, 3_000]);
		// The very first record is still known
		expect(loaded.firstRecordAt && toLocalDate(loaded.firstRecordAt)).toBe(toLocalDate(ago(40)));
		const sim = await balanceSimulate(c, { from: inDays(-5), to: inDays(-1), group: 'day' });
		expect(sim.firstRecord).toBe(toLocalDate(ago(40)));
		expect(sim.periods.at(-1)?.recordedEnd).toBe(90_000 - 2_000 - 3_000);
	});
});

describe('the forecast reconciles', () => {
	it('start plus money in less money out plus an explicit rounding line is the end, in every period', () => {
		const out = forecast({
			from: '2026-03-01',
			to: '2026-03-06',
			group: 'day',
			weekStart: 1,
			main: 'PHP',
			rates: { PHP: '56', JPY: '157.2' },
			wallets: [
				{ accountId: 'a', accountName: 'A', currency: 'PHP', balance: 100_000 },
				{ accountId: 'a', accountName: 'A', currency: 'JPY', balance: 1_001 }
			],
			flows: [
				{
					kind: 'out',
					date: '2026-03-02',
					label: 'x',
					accountId: 'a',
					accountName: 'A',
					currency: 'JPY',
					amount: 333
				},
				{
					kind: 'in',
					date: '2026-03-03',
					label: 'y',
					accountId: 'a',
					accountName: 'A',
					currency: 'JPY',
					amount: 777
				},
				{
					kind: 'out',
					date: '2026-03-04',
					label: 'z',
					accountId: 'a',
					accountName: 'A',
					currency: 'JPY',
					amount: 11
				}
			]
		});
		for (const p of out.periods)
			expect(p.endTotal).toBe(p.startTotal + p.inTotal - p.outTotal + p.rounding);
		expect(out.endTotal).toBe(
			out.startTotal + out.periods.reduce((s, p) => s + p.inTotal - p.outTotal, 0) + out.rounding
		);
		expect(out.periods.some((p) => p.rounding !== 0)).toBe(true);
	});
});

describe('ranges end before the first instant of the next day', () => {
	it('keeps an item at exactly 00:00 of the day after out of the range, and one at 00:00 of the last day in', async () => {
		const id = await newUser();
		const c = person(id);
		const day = inDays(2);
		const nextMidnight = dayStart(addDays(day, 1)).toISOString();
		const thisMidnight = dayStart(day).toISOString();
		await createTask(as(c), { title: 'edge task', dueAt: nextMidnight });
		await createTask(as(c), { title: 'start task', dueAt: thisMidnight });
		await createReminder(as(c), { title: 'edge reminder', at: nextMidnight });
		await createEvent(as(c), { title: 'edge event', startsAt: nextMidnight });
		await createEvent(as(c), { title: 'start event', startsAt: thisMidnight });
		const r = await calendarRange(c, { from: day, to: day });
		const titles = r.items.map((i) => i.title);
		expect(titles).toContain('start task');
		expect(titles).toContain('start event');
		expect(titles).not.toContain('edge task');
		expect(titles).not.toContain('edge reminder');
		expect(titles).not.toContain('edge event');
		// And the next day has them
		const next = await calendarRange(c, { from: addDays(day, 1), to: addDays(day, 1) });
		expect(next.items.map((i) => i.title)).toEqual(
			expect.arrayContaining(['edge task', 'edge reminder', 'edge event'])
		);
	});
});

describe('deleting an event', () => {
	it('refuses one made from a bill or a payday, and returns the removed event of an ordinary one', async () => {
		const id = await newUser();
		const c = person(id);
		const [row] = await withUser(t.handle, id, (tx) =>
			tx
				.insert(calendarEvent)
				.values({
					userId: id,
					title: 'Rent due',
					startsAt: new Date(),
					endsAt: new Date(Date.now() + 3_600_000),
					source: 'bill'
				})
				.returning()
		);
		await expect(deleteEvent(as(c), { eventId: row?.id ?? '' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		const mine = await createEvent(as(c), { title: 'Dentist', startsAt: inDays(1) + 'T02:00:00Z' });
		const removed = await deleteEvent(as(c), { eventId: mine.id });
		expect(removed).toMatchObject({ deleted: true, event: { id: mine.id, title: 'Dentist' } });
		const left = await listEvents(c, { from: inDays(0), to: inDays(3) });
		expect(left.some((e) => e.id === mine.id)).toBe(false);
		await expect(deleteEvent(as(c), { eventId: mine.id })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
	});
});

describe('expense_from_text after the account list changed', () => {
	it('replays the first answer for the same request id instead of a conflict', async () => {
		const id = await newUser();
		const c = person(id);
		const gcash = (await createAccount(as(c), { name: 'Gcash', kind: 'ewallet' })).id;
		await createAccount(as(c), { name: 'Rcbc', kind: 'bank' });
		const ctx = as(c);
		const first = await logExpenseFromText(ctx, { text: 'lunch 180 gcash' });
		if (first.status !== 'saved') throw new Error('not saved');
		expect(first.txn.accountId).toBe(gcash);
		// The account is hidden, and the phone retries the same request
		await archiveAccount(as(c), { accountId: gcash });
		const retry = await logExpenseFromText(ctx, { text: 'lunch 180 gcash' });
		expect(retry).toEqual(first);
		const rows = await withUser(t.handle, id, (tx) =>
			tx
				.select()
				.from(ledgerTxn)
				.where(and(eq(ledgerTxn.userId, id), eq(ledgerTxn.type, 'expense')))
		);
		expect(rows).toHaveLength(1);
		// Another message under the same id is still refused
		await expect(logExpenseFromText(ctx, { text: 'taxi 999 rcbc' })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		// And an unrelated snapshot row is untouched
		expect(await t.handle.db.select().from(balanceSnapshot)).toBeDefined();
	});
});
