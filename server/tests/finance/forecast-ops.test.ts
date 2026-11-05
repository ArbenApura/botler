// THE cashflow_forecast VERB OVER A REAL PERSON: TODAY'S BALANCES, THE PAYDAYS, THE UNPAID BILLS WITH THEIR CHANGED DATES, THE APPROVED RULES AS
// MOVES, NOTHING OF ANYONE ELSE, AND THE SAME NUMBERS EVERY TIME

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildTools } from '../../src/lib/server/agent/tools';
import { addDays, toLocalDate } from '../../src/lib/finance/dates';
import { occurrencesBetween } from '../../src/lib/finance/schedule';
import {
	createBill,
	listDueBills,
	markBillPaid,
	updateBillOccurrence
} from '../../src/lib/server/ops/bills';
import { cashflowForecast, type ForecastView } from '../../src/lib/server/ops/forecast';
import { recordIncome, recordSnapshot } from '../../src/lib/server/ops/ledger';
import { createIncome, updateGoal } from '../../src/lib/server/ops/planning';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { approveRule, proposeRule } from '../../src/lib/server/ops/rules';
import { seedPerson } from '../agent/support';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let f: Fixture;
let other: Fixture;
let rids = 0;

const today = toLocalDate(new Date());
const to = addDays(today, 120);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	f = await seedPerson(t);
	other = await seedPerson(t);
	await recordSnapshot(w(f), { accountId: f.rcbc, amount: 1_000_000 });
	await recordSnapshot(w(f), { accountId: f.gcash, amount: 200_000 });
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

function w(who: Fixture) {
	return { ...who.ctx, requestId: `fc-req-${String(++rids).padStart(8, '0')}` };
}

const forecastTo = (end = to, group: 'day' | 'week' | 'month' = 'week', who = f) =>
	cashflowForecast(who.ctx, { to: end, group });

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);

const allOuts = (out: ForecastView) => out.periods.flatMap((p) => p.outs);
const allIns = (out: ForecastView) => out.periods.flatMap((p) => p.ins);

// -- TESTS -- //

describe('the forecast of a person', () => {
	it('starts from the balances of today and adds the paydays and subtracts the unpaid bills, week by week', async () => {
		const out = await forecastTo();
		expect(out).toMatchObject({ today, from: today, to, group: 'week', currency: 'PHP' });
		expect(out.startTotal).toBe(1_200_000);
		// The periods cover every day once
		expect(out.periods[0]?.from).toBe(today);
		expect(out.periods.at(-1)?.to).toBe(to);
		for (let i = 1; i < out.periods.length; i++) {
			expect(out.periods[i]?.from).toBe(addDays(out.periods[i - 1]?.to ?? '', 1));
			expect(out.periods[i]?.startTotal).toBe(out.periods[i - 1]?.endTotal);
		}
		// The paydays: semi-monthly on the 15th and 30th, before a weekend
		const paydays = occurrencesBetween({ kind: 'semi_monthly', days: [15, 30] }, today, to, {
			weekend: 'before'
		});
		expect(allIns(out).map((x) => x.date)).toEqual(paydays);
		expect(sum(allIns(out).map((x) => x.amount))).toBe(paydays.length * 2_500_000);
		// The bills: the same unpaid occurrences the bills verb lists
		const due = (await listDueBills(f.ctx, today, to)).filter((b) => !b.paid);
		expect(sum(allOuts(out).map((x) => x.amount))).toBe(sum(due.map((b) => b.amount ?? 0)));
		expect(
			allOuts(out)
				.map((x) => x.date)
				.sort()
		).toEqual(due.map((b) => b.dueDate).sort());
		// And the end is the start plus what came in less what went out, in whole pesos' smallest unit
		expect(out.endTotal).toBe(
			out.startTotal +
				sum(out.periods.map((p) => p.inTotal)) -
				sum(out.periods.map((p) => p.outTotal))
		);
		// The accounts at the end add up to the total
		expect(sum(out.endWallets.map((x) => x.endMain ?? 0))).toBe(out.endTotal);
	});

	it('gives the same numbers whatever the grouping, and the same answer twice', async () => {
		const [week, month, again] = await Promise.all([
			forecastTo(),
			forecastTo(to, 'month'),
			forecastTo()
		]);
		expect(week.endTotal).toBe(month.endTotal);
		expect(week.endWallets).toEqual(month.endWallets);
		expect(JSON.stringify(week)).toBe(JSON.stringify(again));
		const short = await forecastTo(addDays(today, 20), 'day');
		expect(short.periods).toHaveLength(21);
	});

	it('leaves out a bill that is paid, and counts a changed amount and a moved date for one date', async () => {
		const g = await seedPerson(t);
		await recordSnapshot(w(g), { accountId: g.rcbc, amount: 5_000_000 });
		const before = (await listDueBills(g.ctx, today, to)).filter((b) => b.billId === g.rentBillId);
		expect(before.length).toBeGreaterThan(2);
		const [first, second, third] = before;
		await markBillPaid(w(g), { billId: g.rentBillId, dueDate: first?.dueDate ?? '' });
		await updateBillOccurrence(w(g), {
			billId: g.rentBillId,
			dueDate: second?.dueDate ?? '',
			amount: 111_100
		});
		await updateBillOccurrence(w(g), {
			billId: g.rentBillId,
			dueDate: third?.dueDate ?? '',
			newDueDate: addDays(third?.dueDate ?? '', 3)
		});
		const out = await cashflowForecast(g.ctx, { to, group: 'week' });
		const rent = allOuts(out).filter((x) => x.label === 'Rent');
		const dates = rent.map((x) => x.date);
		expect(dates).not.toContain(first?.dueDate);
		expect(rent.find((x) => x.date === second?.dueDate)?.amount).toBe(111_100);
		expect(dates).not.toContain(third?.dueDate);
		expect(dates).toContain(addDays(third?.dueDate ?? '', 3));
	});

	it('does not count the pay again when it was already recorded today', async () => {
		const day = Number(today.slice(8));
		const mk = async (who: Fixture) =>
			createIncome(w(who), {
				label: 'Today pay',
				accountId: who.rcbc,
				expectedAmount: 1_000_000,
				schedule: { kind: 'monthly', day },
				weekendRule: 'none'
			});
		const waiting = await seedPerson(t);
		const received = await seedPerson(t);
		await mk(waiting);
		await mk(received);
		await recordIncome(w(received), { accountId: received.rcbc, amount: 1_000_000 });
		const a = (await cashflowForecast(waiting.ctx, { to: addDays(today, 5), group: 'day' }))
			.periods;
		const b = (await cashflowForecast(received.ctx, { to: addDays(today, 5), group: 'day' }))
			.periods;
		// Waiting: the pay of today is still to come. Received: it is in the balance already
		expect(a[0]?.ins.map((x) => x.label)).toContain('Today pay');
		expect(b[0]?.ins.map((x) => x.label)).not.toContain('Today pay');
		expect(a[0]?.endTotal).toBe(1_000_000);
		expect(b[0]?.endTotal).toBe(1_000_000);
	});

	it('lists a bill and a pay with no amount yet, never counts them, and says so', async () => {
		const g = await seedPerson(t);
		await createBill(w(g), {
			name: 'Gas',
			category: 'bills',
			accountId: g.rcbc,
			kind: 'variable',
			amount: null,
			schedule: { kind: 'monthly', day: 12 },
			weekendRule: 'none',
			deferrable: false
		});
		await createIncome(w(g), {
			label: 'Freelance',
			accountId: g.rcbc,
			expectedAmount: null,
			schedule: { kind: 'monthly', day: 20 },
			weekendRule: 'none'
		});
		const out = await cashflowForecast(g.ctx, { to, group: 'month' });
		expect(out.unknown.filter((u) => u.label === 'Gas').length).toBeGreaterThan(0);
		expect(out.unknown.filter((u) => u.label === 'Freelance').length).toBeGreaterThan(0);
		expect(allOuts(out).some((x) => x.label === 'Gas')).toBe(false);
		expect(out.notes.join(' ')).toMatch(/no amount yet/);
	});

	it('shows no rule moves without an approved rule, and a move to the rule target with one, the total never changing', async () => {
		const g = await seedPerson(t);
		await recordSnapshot(w(g), { accountId: g.rcbc, amount: 3_000_000 });
		const plain = await cashflowForecast(g.ctx, { to, group: 'week' });
		// Bills and goals paid from other accounts still move with no rules: the moves are the commitments
		const moved = (v: ForecastView) => sum(v.periods.flatMap((p) => p.moves).map((m) => m.amount));
		const plainMoved = moved(plain);
		const proposed = await proposeRule(w(g), {
			mode: 'fixed',
			amount: 500_000,
			targetAccountId: g.maya
		});
		// A proposed rule changes nothing: only one in force does
		expect(moved(await cashflowForecast(g.ctx, { to, group: 'week' }))).toBe(plainMoved);
		await approveRule(w(g), { ruleId: proposed.id });
		const ruled = await cashflowForecast(g.ctx, { to, group: 'week' });
		const moves = ruled.periods.flatMap((p) => p.moves);
		expect(moved(ruled)).toBeGreaterThan(plainMoved);
		expect(moves.every((m) => m.kind === 'move' && m.accountId === g.rcbc)).toBe(true);
		// The move to Maya is the rule's 5,000 or more (what no rule claims goes to the first rule), on the payday
		const toMaya = moves.filter((m) => m.toAccountId === g.maya);
		expect(toMaya.every((m) => m.amount >= 500_000)).toBe(true);
		expect(toMaya.map((m) => m.date)).toEqual(allIns(ruled).map((x) => x.date));
		// Moves change the accounts and never the total
		expect(ruled.periods.map((p) => p.endTotal)).toEqual(plain.periods.map((p) => p.endTotal));
		expect(ruled.endTotal).toBe(plain.endTotal);
		const maya = ruled.endWallets.find((x) => x.accountId === g.maya);
		expect(maya?.end).toBe(sum(toMaya.map((m) => m.amount)));
	});

	it('leaves a rule on a switched-off goal out of the moves, as the split does, and keeps the others', async () => {
		const g = await seedPerson(t);
		await recordSnapshot(w(g), { accountId: g.rcbc, amount: 3_000_000 });
		const onGoal = await proposeRule(w(g), {
			mode: 'fixed',
			amount: 200_000,
			targetGoalId: g.goalId
		});
		await approveRule(w(g), { ruleId: onGoal.id });
		const toMaya = await proposeRule(w(g), {
			mode: 'fixed',
			amount: 500_000,
			targetAccountId: g.maya
		});
		await approveRule(w(g), { ruleId: toMaya.id });
		await updateGoal(w(g), { goalId: g.goalId, active: false });
		const out = await cashflowForecast(g.ctx, { to, group: 'week' });
		expect(out.notes.join(' ')).not.toMatch(/could not be worked out/);
		const moves = out.periods.flatMap((p) => p.moves);
		expect(moves.length).toBeGreaterThan(0);
		expect(moves.some((m) => m.toAccountId === g.maya)).toBe(true);
	});

	it('still moves what a short pay can fund, in the split order, and says it is short', async () => {
		const g = await seedPerson(t);
		// The money sits in Maya, which holds a goal: it never pays a bill, so the bills come from the pay (BTL-20261029-0119)
		await recordSnapshot(w(g), { accountId: g.maya, amount: 3_000_000 });
		for (const day of [5, 20])
			await createBill(w(g), {
				name: `Rent ${day}`,
				category: 'bills',
				accountId: g.rcbc,
				kind: 'fixed',
				amount: 500_000,
				schedule: { kind: 'monthly', day },
				weekendRule: 'none',
				deferrable: false
			});
		for (const [amount, targetAccountId] of [
			[1_500_000, g.maya],
			[900_000, g.gcash]
		] as const) {
			const r = await proposeRule(w(g), { mode: 'fixed', amount, targetAccountId });
			await approveRule(w(g), { ruleId: r.id });
		}
		const soon = addDays(today, 30);
		const out = await cashflowForecast(g.ctx, { to: soon, group: 'week' });
		expect(out.notes.join(' ')).toMatch(/is short by/);
		const moves = out.periods.flatMap((p) => p.moves);
		// Pay 25,000: the 5,000 bill stays in the income account, Maya's rule is whole, GCash gets the 5,000 left of its 9,000
		// Maya's 15,000 rule is funded in full and the moves of one payday never add up to more than the 25,000 pay
		expect(moves.some((m) => m.toAccountId === g.maya && m.amount >= 1_500_000)).toBe(true);
		const byDate = new Map<string, number>();
		for (const m of moves) byDate.set(m.date, (byDate.get(m.date) ?? 0) + m.amount);
		expect(byDate.size).toBeGreaterThan(0);
		for (const total of byDate.values()) expect(total).toBeLessThanOrEqual(2_500_000);
		expect(out.itemsOmitted).toBeUndefined();
	});

	it('names a payday whose split cannot be worked out instead of guessing', async () => {
		const g = await seedPerson(t);
		await createBill(w(g), {
			name: 'Water',
			category: 'bills',
			accountId: g.rcbc,
			kind: 'variable',
			amount: null,
			schedule: { kind: 'monthly', day: 10 },
			weekendRule: 'none',
			deferrable: false
		});
		const proposed = await proposeRule(w(g), {
			mode: 'fixed',
			amount: 500_000,
			targetAccountId: g.maya
		});
		await approveRule(w(g), { ruleId: proposed.id });
		const out = await cashflowForecast(g.ctx, { to, group: 'month' });
		expect(out.notes.join(' ')).toMatch(/split of \d{4}-\d{2}-\d{2} is not in the moves/);
		// Only the paydays whose period has the Water bill are left without moves
		const paydays = allIns(out).map((x) => x.date);
		const moved = new Set(out.periods.flatMap((p) => p.moves).map((m) => m.date));
		expect(moved.size).toBeLessThan(paydays.length);
		for (const d of moved) expect(paydays).toContain(d);
	});

	it('is about this person only', async () => {
		const mine = JSON.stringify(await forecastTo());
		expect(mine).not.toContain(other.userId);
		await createBill(w(other), {
			name: 'Secret hobby',
			category: 'fun',
			accountId: other.rcbc,
			kind: 'fixed',
			amount: 77_700,
			schedule: { kind: 'monthly', day: 9 },
			weekendRule: 'none',
			deferrable: false
		});
		expect(JSON.stringify(await forecastTo())).not.toContain('Secret hobby');
		// 60 days, so the answer keeps its lists (at 120 days it sits right at the length cut)
		expect(JSON.stringify(await forecastTo(addDays(today, 60), 'week', other))).toContain(
			'Secret hobby'
		);
	});

	it('shortens an answer that would be too long to the totals and wallets, and says so', async () => {
		const g = await seedPerson(t);
		for (let i = 0; i < 40; i++)
			await createBill(w(g), {
				name: `Weekly thing number ${i} with a long name to take room`,
				category: 'bills',
				accountId: g.rcbc,
				kind: 'fixed',
				amount: 1_000 + i,
				schedule: { kind: 'weekly', days: [i % 7] },
				weekendRule: 'none',
				deferrable: false
			});
		const out = await cashflowForecast(g.ctx, { to: addDays(today, 200), group: 'week' });
		expect(out.itemsOmitted).toBe(true);
		expect(out.periods.every((p) => p.outs.length === 0)).toBe(true);
		expect(out.periods.some((p) => p.outTotal > 0)).toBe(true);
		expect(out.notes.join(' ')).toMatch(/Too long to list every payment/);
		expect(JSON.stringify(out).length).toBeLessThan(16_000);
	});
});

describe('what it refuses', () => {
	it('refuses a date before today, past 366 days, a day grouping past 62 days, and a key it does not know', async () => {
		await expect(cashflowForecast(f.ctx, { to: addDays(today, -1) })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(cashflowForecast(f.ctx, { to: addDays(today, 366) })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(
			cashflowForecast(f.ctx, { to: addDays(today, 70), group: 'day' })
		).rejects.toMatchObject({
			code: 'INVALID'
		});
		// The verb is strict about its keys: a user id in the arguments is refused, never read
		await expect(invokeVerb(f.ctx, 'cashflow_forecast', { to, userId: 'x' })).rejects.toMatchObject(
			{
				code: 'INVALID'
			}
		);
		await expect(cashflowForecast(f.ctx, { to: 'soon' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(
			cashflowForecast(f.ctx, { to: addDays(today, 365), group: 'month' })
		).resolves.toBeDefined();
	});
});

describe('the verb', () => {
	it('is a read verb the assistant may call, whose schema holds no user id', () => {
		expect(verbByName('cashflow_forecast')).toMatchObject({ kind: 'read', agent: true });
		const tool = buildTools().find((x) => x.name === 'cashflow_forecast');
		expect(tool).toMatchObject({ kind: 'read', taints: false });
		expect(JSON.stringify(tool?.parameters)).not.toMatch(/user_?id/i);
		expect(verbByName('cashflow_forecast')?.description).toMatch(/never bills_due added by hand/);
	});
});
