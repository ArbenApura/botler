// THE PAYDAY SPLIT AND THE FORECAST WITH MONEY ALREADY IN AN ACCOUNT AND RULES THAT SAVE FOR A BILL (BTL-20261029-0119), ON A COPY OF THE OWNER'S
// SETUP: SALARY EVERY MONDAY INTO RCBC, WIFI PAID FROM GCASH THAT ALREADY HOLDS ENOUGH, PARENTS EVERY OTHER WEDNESDAY AND POCKET MONEY EVERY WEDNESDAY
// FROM RCBC, EACH WITH A RULE THAT SAVES FOR IT. BOTH VERBS MUST MOVE THE SAME MONEY, AND AN OLD APP STILL READS A SPLIT THAT SUMS TO THE PAY.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { SplitPlanView } from '../../src/lib/server/ops/split';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, toLocalDate, weekday } from '../../src/lib/finance/dates';
import { occurrencesBetween } from '../../src/lib/finance/schedule';
import { bestEffortTransfers } from '../../src/lib/finance/split';
import { user } from '../../src/lib/server/db/schema';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { createBill } from '../../src/lib/server/ops/bills';
import { cashflowForecast } from '../../src/lib/server/ops/forecast';
import { recordIncome, recordSnapshot } from '../../src/lib/server/ops/ledger';
import { createIncome } from '../../src/lib/server/ops/planning';
import { describeAction } from '../../src/lib/server/ops/actions';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { approveRule, proposeRule } from '../../src/lib/server/ops/rules';
import { proposeSplitPlan } from '../../src/lib/server/ops/split';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

const today = toLocalDate(new Date());
/** The next Monday from today, today included: the first payday. */
const monday =
	occurrencesBetween({ kind: 'weekly', days: [1] }, today, addDays(today, 7), {
		weekend: 'none'
	})[0] ?? today;

/** The owner's setup, relative to the first payday `p`. */
async function owner() {
	const userId = `user_split_${String(++n).padStart(4, '0')}`;
	await t.handle.db.insert(user).values({ id: userId, name: 'O', email: `${userId}@example.com` });
	let r = 0;
	const ctx = (): Ctx => ({
		handle: t.handle,
		actor: { userId, kind: 'person' },
		requestId: `sf-${userId}-${String(++r).padStart(4, '0')}`
	});
	const acc = async (name: string) =>
		(await createAccount(ctx(), { name, kind: 'bank', minBalance: 0 })).id;
	const rcbc = await acc('RCBC');
	const gcash = await acc('GCash');
	const wise = await acc('Wise');
	await recordSnapshot(ctx(), { accountId: gcash, amount: 150_273 });
	const income = await createIncome(ctx(), {
		label: 'Salary',
		accountId: rcbc,
		expectedAmount: 1_900_000,
		schedule: { kind: 'weekly', days: [1] },
		weekendRule: 'none'
	});
	const bill = (name: string, accountId: string, amount: number, schedule: unknown) =>
		createBill(ctx(), {
			name,
			category: 'bills',
			accountId,
			kind: 'fixed',
			amount,
			schedule: schedule as never,
			weekendRule: 'none',
			deferrable: false
		});
	const p = monday;
	const wifi = await bill('WiFi', gcash, 150_000, { kind: 'once', date: addDays(p, 2) });
	const parents = await bill('Parents', rcbc, 700_000, {
		kind: 'weekly',
		days: [3],
		everyWeeks: 2,
		anchor: addDays(p, 2)
	});
	const pocket = await bill('Pocket money', rcbc, 300_000, { kind: 'weekly', days: [3] });
	const rule = async (label: string, amount: number, targetAccountId: string, billId?: string) => {
		const made = await proposeRule(ctx(), {
			label,
			mode: 'fixed',
			amount,
			targetAccountId,
			effectiveFrom: today,
			...(billId ? { fundsBillId: billId } : {})
		});
		await approveRule(ctx(), { ruleId: made.id });
		return made.id;
	};
	await rule('Parents', 350_000, rcbc, parents.id);
	await rule('Wise savings', 300_000, wise);
	await rule('Mommy', 25_000, gcash);
	await rule('Pocket money', 300_000, rcbc, pocket.id);
	return { userId, ctx, rcbc, gcash, wise, income: income.id, wifi: wifi.id, p };
}

const movesOn = (out: Awaited<ReturnType<typeof cashflowForecast>>, day: string) =>
	out.periods
		.flatMap((x) => x.moves)
		.filter((m) => m.date === day)
		.map((m) => ({ to: m.toAccountId, amount: m.amount }))
		.sort((a, b) => (a.to ?? '').localeCompare(b.to ?? ''));

const transfersOf = (plan: SplitPlanView) =>
	plan.result.transfers
		.map((x) => ({ to: x.toAccountId, amount: x.amount }))
		.sort((a, b) => (a.to ?? '').localeCompare(b.to ?? ''));

// -- TESTS -- //

describe('the owner’s first payday', () => {
	it('pays WiFi from the GCash balance, moves only Mommy’s 250.00 to GCash, and the forecast and the split agree', async () => {
		const o = await owner();
		const out = await cashflowForecast(o.ctx(), { to: addDays(o.p, 20), group: 'week' });
		expect(movesOn(out, o.p)).toEqual(
			[
				{ to: o.gcash, amount: 25_000 },
				{ to: o.wise, amount: 300_000 }
			].sort((a, b) => a.to.localeCompare(b.to))
		);
		const first = out.funding.find((x) => x.payday === o.p);
		expect(first?.covered).toEqual([{ bill: 'WiFi', account: 'GCash', amount: 150_000 }]);
		expect(first?.funded).toContainEqual({
			bill: 'Pocket money',
			rule: 'Pocket money',
			amount: 300_000
		});
		expect(out.notes.join(' ')).toMatch(/^|funding: per payday/);

		const plan = (await proposeSplitPlan(o.ctx(), {
			incomeScheduleId: o.income,
			payday: o.p
		})) as SplitPlanView;
		expect(transfersOf(plan)).toEqual(movesOn(out, o.p));
		expect(plan.result.covered).toEqual([
			{ refId: o.wifi, label: 'WiFi', accountId: o.gcash, amount: 150_000 }
		]);
		expect(plan.result.lines.reduce((s, l) => s + l.amount, 0)).toBe(1_900_000);
	});

	it('takes the part of Parents its rule has not saved yet from the first pay, and nothing on the next Parents payday', async () => {
		const o = await owner();
		const out = await cashflowForecast(o.ctx(), { to: addDays(o.p, 20), group: 'week' });
		const first = out.funding.find((x) => x.payday === o.p);
		// Nothing saved before the first payday: 3,500.00 from this pay's rule, 3,500.00 still needed
		expect(first?.funded).toContainEqual({ bill: 'Parents', rule: 'Parents', amount: 350_000 });
		expect(first?.unfunded).toEqual([{ bill: 'Parents', amount: 350_000 }]);
		// Two weeks on, the rule saved one payday and adds this one: the whole 7,000.00, nothing from the pay
		const third = out.funding.find((x) => x.payday === addDays(o.p, 14));
		expect(third?.funded).toContainEqual({ bill: 'Parents', rule: 'Parents', amount: 700_000 });
		expect(third?.unfunded).toEqual([]);
		// No payday is short: a bill and the rule that saves for it are not counted twice
		expect(out.notes.join(' ')).not.toMatch(/is short by/);
		// The later split agrees with the forecast, from the balances projected to it
		const later = (await proposeSplitPlan(o.ctx(), {
			incomeScheduleId: o.income,
			payday: addDays(o.p, 14)
		})) as SplitPlanView;
		expect(transfersOf(later)).toEqual(movesOn(out, addDays(o.p, 14)));
		expect(later.status).toBe('proposed');
	});

	it('gives the same moves in both verbs with a second income on another account', async () => {
		const o = await owner();
		const side = await createIncome(o.ctx(), {
			label: 'Side job',
			accountId: o.gcash,
			expectedAmount: 200_000,
			schedule: { kind: 'weekly', days: [4] },
			weekendRule: 'none'
		});
		const out = await cashflowForecast(o.ctx(), { to: addDays(o.p, 20), group: 'week' });
		const sideDay =
			occurrencesBetween({ kind: 'weekly', days: [4] }, addDays(o.p, 1), addDays(o.p, 8), {
				weekend: 'none'
			})[0] ?? '';
		const plan = (await proposeSplitPlan(o.ctx(), {
			incomeScheduleId: side.id,
			payday: sideDay
		})) as SplitPlanView;
		// The rules ask more than the side pay: the split is short and moves nothing until the person decides, the forecast moves what
		// the pay can fund in the split's own order
		expect(plan.status).toBe('shortfall');
		if (plan.result.status !== 'shortfall') throw new Error('expected a shortfall');
		const best = bestEffortTransfers(plan.result, o.gcash)
			.map((x) => ({ to: x.toAccountId, amount: x.amount }))
			.sort((a, b) => a.to.localeCompare(b.to));
		expect(best).toEqual(movesOn(out, sideDay));
	});

	it('lets the Mommy rule save for WiFi on GCash, and lists no broken links', async () => {
		const o = await owner();
		const rules = (await invokeVerb(o.ctx(), 'rules_list', {})) as {
			id: string;
			label: string;
		}[];
		const mommy = rules.find((r) => r.label === 'Mommy');
		// A link that could not count is refused when made (rule-funding-ops) and cleared when its bill changes, so none is left
		await expect(
			invokeVerb(o.ctx(), 'rule_update', { ruleId: mommy?.id, fundsBillId: o.wifi })
		).resolves.toMatchObject({ fundsBillId: o.wifi });
		const out = await cashflowForecast(o.ctx(), { to: addDays(o.p, 6), group: 'week' });
		const first = out.funding.find((x) => x.payday === o.p);
		expect(first?.funded).toContainEqual({ bill: 'WiFi', rule: 'Mommy', amount: 25_000 });
		expect(out.brokenLinks).toEqual([]);
	});
});

describe('a payday whose pay is already in the balance', () => {
	it('never pays the split’s own bills from the pay it is splitting', async () => {
		const o = await owner();
		// A second payday today on GCash, its pay already recorded, and a bill paid from GCash tomorrow
		const today2 = await createIncome(o.ctx(), {
			label: 'Bonus',
			accountId: o.gcash,
			expectedAmount: 500_000,
			schedule: { kind: 'weekly', days: [weekday(today)] },
			weekendRule: 'none'
		});
		await recordIncome(o.ctx(), { accountId: o.gcash, amount: 500_000 });
		await createBill(o.ctx(), {
			name: 'Load',
			category: 'bills',
			accountId: o.gcash,
			kind: 'fixed',
			amount: 100_000,
			schedule: { kind: 'once', date: addDays(today, 1) },
			weekendRule: 'none',
			deferrable: false
		});
		const plan = (await proposeSplitPlan(o.ctx(), {
			incomeScheduleId: today2.id,
			payday: today
		})) as SplitPlanView;
		// GCash holds 1,502.73 + 5,000.00 now, but the 5,000.00 is this very pay: nothing of GCash covers Load
		expect(plan.result.covered.filter((c) => c.label === 'Load')).toEqual([]);
		expect(plan.result.lines.find((l) => l.label === 'Load')?.amount).toBe(100_000);
	});
});

describe('the approval card of a rule change after untrusted text', () => {
	it('names the bill a rule will save for, or that it stops', () => {
		const names = new Map([
			['rule-1', 'a fixed amount to RCBC (active)'],
			['bill-1', 'Parents allowance'],
			['acc-1', 'RCBC']
		]);
		expect(describeAction('rule_update', { ruleId: 'rule-1', fundsBillId: 'bill-1' }, names)).toBe(
			'Change the payday rule a fixed amount to RCBC (active): make it save for the bill "Parents allowance", so that bill is paid from what it saved instead of from the pay.'
		);
		expect(describeAction('rule_update', { ruleId: 'rule-1', fundsBillId: null }, names)).toBe(
			'Change the payday rule a fixed amount to RCBC (active): stop it saving for a bill.'
		);
		expect(
			describeAction(
				'rule_propose',
				{ mode: 'fixed', amount: 350_000, targetAccountId: 'acc-1', fundsBillId: 'bill-1' },
				names
			)
		).toBe(
			'Propose a payday rule: ₱3,500.00 to RCBC, saving for the bill "Parents allowance". It still waits for your approval.'
		);
	});
});

describe('an old app reading the new split', () => {
	it('still finds lines that sum to the pay and transfers, with the new lists only beside them', async () => {
		const o = await owner();
		const plan = (await proposeSplitPlan(o.ctx(), {
			incomeScheduleId: o.income,
			payday: o.p
		})) as SplitPlanView;
		const old = JSON.parse(JSON.stringify(plan.result)) as {
			pay: number;
			lines: { amount: number; accountId: string; label: string }[];
			transfers: { amount: number }[];
		};
		expect(old.lines.reduce((s, l) => s + l.amount, 0)).toBe(old.pay);
		expect(old.transfers.length).toBeGreaterThan(0);
		const rules = (await invokeVerb(o.ctx(), 'rules_list', {})) as Record<string, unknown>[];
		for (const r of rules)
			expect(r).toMatchObject({ id: expect.any(String), summary: expect.any(String) });
	});
});
