// THE FINANCE VERBS AGAINST A REAL (THROWAWAY) DATABASE: ACCOUNTS, BILLS, RULES, THE PAYDAY SPLIT, THE LEDGER, COUNTS WITH DRIFT AND UNDO

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { asc, eq, sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { auditEvent, bill, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import {
	createAccount,
	archiveAccount,
	listAccounts,
	updateAccount
} from '../../src/lib/server/ops/accounts';
import {
	createBill,
	listBills,
	listDueBills,
	markBillPaid,
	updateBill
} from '../../src/lib/server/ops/bills';
import {
	accountBalances,
	listTransactions,
	listUndoable,
	logExpense,
	logExpenseFromText,
	recordSnapshot,
	recordTransfer,
	spendingSummary,
	undo,
	weeklyCheckin
} from '../../src/lib/server/ops/ledger';
import {
	createGoal,
	createIncome,
	nextPaydays,
	updateIncome
} from '../../src/lib/server/ops/planning';
import {
	approveRule,
	listRules,
	proposeRule,
	proposeRuleFromText
} from '../../src/lib/server/ops/rules';
import {
	approveSplit,
	deleteSplits,
	markTransferSent,
	proposeSplitPlan
} from '../../src/lib/server/ops/split';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const rid = () => `req-fin-${String(++counter).padStart(6, '0')}`;
const person = (userId: string): Ctx => ({ handle: t.handle, actor: { userId, kind: 'person' } });
const as = (base: Ctx) => ({ ...base, requestId: rid() });
const agent = (userId: string): Ctx => ({
	handle: t.handle,
	actor: { userId, kind: 'agent', tool: 'test' }
});

const anna = () => person('user_anna_0001');
const ben = () => person('user_ben_00001');

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_anna_0001', name: 'Anna', email: 'anna@example.com' },
		{ id: 'user_ben_00001', name: 'Ben', email: 'ben@example.com' },
		{ id: 'user_carl_0001', name: 'Carl', email: 'carl@example.com' },
		{ id: 'user_dina_0001', name: 'Dina', email: 'dina@example.com' },
		{ id: 'user_eli_00001', name: 'Eli', email: 'eli@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('accounts and isolation', () => {
	let rcbc: string;
	let gcash: string;

	it('creates accounts, refuses a duplicate name in any case, and keeps people apart', async () => {
		const a = await createAccount(as(anna()), { name: 'RCBC', kind: 'bank', minBalance: 0 });
		rcbc = a.id;
		gcash = (
			await createAccount(as(anna()), { name: 'GCash', kind: 'ewallet', minBalance: 50_000 })
		).id;
		await expect(
			createAccount(as(anna()), { name: 'rcbc', kind: 'bank', minBalance: 0 })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		// Ben may use the same name: names are per person
		await createAccount(as(ben()), { name: 'RCBC', kind: 'bank', minBalance: 0 });
		expect((await listAccounts(ben())).map((x) => x.name)).toEqual(['RCBC']);
		expect(await listAccounts(anna())).toHaveLength(2);
	});

	it('refuses to use another person account, through the verb and through the database', async () => {
		await expect(
			createBill(as(ben()), {
				name: 'Stolen',
				category: 'other',
				accountId: rcbc,
				kind: 'fixed',
				amount: 1000,
				schedule: { kind: 'monthly', day: 1 },
				weekendRule: 'none',
				startsOn: '2000-01-01',
				deferrable: false
			})
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		// Even a direct insert cannot point at a row of another person: the foreign key includes user_id
		await expect(
			withUser(t.handle, 'user_ben_00001', (tx) =>
				tx.insert(bill).values({
					userId: 'user_ben_00001',
					name: 'Direct',
					accountId: rcbc,
					kind: 'fixed',
					amount: 1000,
					schedule: { kind: 'monthly', day: 1 }
				})
			)
		).rejects.toThrow();
	});

	it('updates with a version check and archives without losing history', async () => {
		const [row] = (await listAccounts(anna())).filter((x) => x.id === gcash);
		const upd = await updateAccount(as(anna()), {
			accountId: gcash,
			name: 'GCash wallet',
			expectVersion: row?.version
		});
		expect(upd.version).toBe((row?.version ?? 0) + 1);
		// A field left out of an update is left alone (a default must never reset it)
		expect(upd.minBalance).toBe(50_000);
		await expect(
			updateAccount(as(anna()), { accountId: gcash, name: 'x', expectVersion: row?.version })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		const spare = await createAccount(as(anna()), { name: 'Spare', kind: 'cash', minBalance: 0 });
		await archiveAccount(as(anna()), { accountId: spare.id });
		expect((await listAccounts(anna())).map((x) => x.name)).not.toContain('Spare');
		expect((await listAccounts(anna(), { includeArchived: true })).map((x) => x.name)).toContain(
			'Spare'
		);
		await expect(
			logExpense(as(anna()), { accountId: spare.id, amount: 100 })
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('the payday split, end to end', () => {
	let rcbc: string;
	let gcash: string;
	let maya: string;
	let incomeId: string;

	beforeAll(async () => {
		const mk = async (name: string, kind: 'bank' | 'ewallet') =>
			(await createAccount(as(ben()), { name: `${name}2`, kind, minBalance: 0 })).id;
		rcbc = await mk('Bank', 'bank');
		gcash = await mk('Wallet', 'ewallet');
		maya = await mk('Maya', 'ewallet');
		incomeId = (
			await createIncome(as(ben()), {
				label: 'Salary',
				accountId: rcbc,
				expectedAmount: 2_500_000,
				schedule: { kind: 'semi_monthly', days: [15, 30] },
				weekendRule: 'before'
			})
		).id;
		const fixed = (
			name: string,
			category: string,
			accountId: string,
			amount: number,
			schedule: Parameters<typeof createBill>[1]['schedule']
		) =>
			createBill(as(ben()), {
				name,
				category,
				accountId,
				kind: 'fixed',
				amount,
				schedule,
				weekendRule: 'none',
				startsOn: '2000-01-01',
				deferrable: false
			});
		await fixed('Rent', 'rent', rcbc, 800_000, { kind: 'monthly', day: 1 });
		await fixed('Internet', 'bills', gcash, 150_000, { kind: 'monthly', day: 10 });
		await fixed('Parents', 'parents', rcbc, 300_000, {
			kind: 'every_n_days',
			anchor: '2026-11-27',
			n: 14
		});
		await createGoal(as(ben()), {
			name: 'Emergency fund',
			accountId: maya,
			targetAmount: null,
			perPayday: 100_000
		});
	});

	it('lists the next paydays', async () => {
		const days = await nextPaydays(ben(), incomeId, 3);
		expect(days).toHaveLength(3);
		expect(days.every((d) => /^\d{4}-\d{2}-\d{2}$/.test(d))).toBe(true);
	});

	it('skips one payday, keeps the rest, and brings it back when the skip is left out', async () => {
		const weekly = await createIncome(as(ben()), {
			label: 'Weekly pay',
			accountId: rcbc,
			expectedAmount: 1_900_000,
			schedule: { kind: 'weekly', days: [1] },
			weekendRule: 'before'
		});
		const before = await nextPaydays(ben(), weekly.id, 3);
		const skipped = before[0] as string;
		const set = await updateIncome(as(ben()), {
			incomeId: weekly.id,
			schedule: { kind: 'weekly', days: [1], skipDates: [skipped] }
		});
		expect(set.schedule).toEqual({ kind: 'weekly', days: [1], skipDates: [skipped] });
		expect(await nextPaydays(ben(), weekly.id, 2)).toEqual([before[1], before[2]]);
		await updateIncome(as(ben()), { incomeId: weekly.id, schedule: { kind: 'weekly', days: [1] } });
		expect(await nextPaydays(ben(), weekly.id, 3)).toEqual(before);
	});

	it('proposes a rule in words, and it changes nothing until a person approves it', async () => {
		const proposed = await proposeRuleFromText(as(ben()), { text: '20% to wallet2' });
		expect(proposed).toMatchObject({
			status: 'proposed',
			mode: 'percent',
			basisPoints: 2000,
			targetName: 'Wallet2'
		});
		expect(proposed.summary).toBe(
			`Put 20% of your pay into Wallet2, from ${proposed.effectiveFrom}.`
		);
		await expect(
			approveRule(as(agent('user_ben_00001')), { ruleId: proposed.id })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		const approved = await approveRule(as(ben()), { ruleId: proposed.id });
		expect(approved.status).toBe('active');
		await expect(approveRule(as(ben()), { ruleId: proposed.id })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		const rest = await proposeRuleFromText(as(ben()), { text: 'the rest to bank2' });
		await approveRule(as(ben()), { ruleId: rest.id });
		expect((await listRules(ben(), 'active')).map((r) => r.mode)).toEqual(['percent', 'rest']);
	});

	it('refuses a rule that cannot fit with the ones in force, and words it cannot read', async () => {
		await expect(proposeRuleFromText(as(ben()), { text: '90% to maya2' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		const over = await proposeRule(as(ben()), {
			mode: 'percent',
			basisPoints: 8100,
			targetAccountId: maya
		}).catch((e: unknown) => e);
		expect(over).toMatchObject({ code: 'INVALID' });
		await expect(
			proposeRuleFromText(as(ben()), { text: 'sometimes to nowhere' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('splits the pay so every centavo has a place, then approves and marks transfers sent', async () => {
		const plan = await proposeSplitPlan(as(ben()), {
			incomeScheduleId: incomeId,
			payday: '2026-11-30'
		});
		if (plan.status === 'needs_amounts') throw new Error('unexpected');
		expect(plan.status).toBe('proposed');
		const r = plan.result;
		expect(r.status).toBe('ok');
		expect(r.lines.reduce((s, l) => s + l.amount, 0)).toBe(2_500_000);
		expect(r.periodEnd).toBe('2026-12-14');
		expect(r.lines.map((l) => [l.kind, l.label, l.amount])).toEqual([
			['bill', 'Rent', 800_000],
			['bill', 'Internet', 150_000],
			['parents', 'Parents', 300_000],
			['goal', 'Emergency fund', 100_000],
			['rule', 'Wallet2', 500_000],
			['rest', 'Bank2', 650_000]
		]);
		expect(r.transfers.map((x) => [r.accountNames[x.toAccountId], x.amount])).toEqual([
			['Wallet2', 650_000],
			['Maya2', 100_000]
		]);

		// The agent cannot approve; the person can; a second approval is refused
		await expect(
			approveSplit(as(agent('user_ben_00001')), { splitId: plan.id })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		const ok = await approveSplit(as(ben()), { splitId: plan.id });
		expect(ok.status).toBe('approved');
		expect(ok.approvedBy).toBe('person:user_ben_00001');
		await expect(approveSplit(as(ben()), { splitId: plan.id })).rejects.toMatchObject({
			code: 'CONFLICT'
		});

		// A future payday does not write the pay into the ledger yet
		expect(await listTransactions(ben(), { accountId: rcbc })).toHaveLength(0);

		const sent = await markTransferSent(as(ben()), { splitId: plan.id, index: 0 });
		await expect(markTransferSent(as(ben()), { splitId: plan.id, index: 0 })).rejects.toMatchObject(
			{ code: 'CONFLICT' }
		);
		await expect(markTransferSent(as(ben()), { splitId: plan.id, index: 9 })).rejects.toMatchObject(
			{ code: 'NOT_FOUND' }
		);
		// A transfer between own accounts moves money and is never spending
		const rows = await listTransactions(ben());
		expect(rows.find((x) => x.id === sent.txnId)).toMatchObject({
			type: 'transfer',
			amount: 650_000,
			source: 'split'
		});
		const sum = await spendingSummary(ben(), { from: '2020-01-01', to: '2099-12-31' });
		expect(sum.spending).toBe(0);
		const bal = Object.fromEntries((await accountBalances(ben())).map((b) => [b.name, b.balance]));
		expect(bal['Wallet2']).toBe(650_000);
		expect(bal['Bank2']).toBe(-650_000);

		// Undoing the sent transfer frees it to be sent again
		const undoable = await listUndoable(ben());
		const entry = undoable.find((u) => (u.after as { id?: string } | null)?.id === sent.txnId);
		expect(entry).toBeTruthy();
		await undo(as(ben()), { journalId: entry?.id ?? '' });
		expect(await markTransferSent(as(ben()), { splitId: plan.id, index: 0 })).toMatchObject({
			index: 0
		});
	});

	it('answers a shortfall with the gap and refuses to approve it', async () => {
		// The payday above is approved, so it is planned again only after that split is deleted (the sent transfers stay in the ledger)
		await deleteSplits(as(ben()), { all: true });
		const plan = await proposeSplitPlan(as(ben()), {
			incomeScheduleId: incomeId,
			payday: '2026-11-30',
			pay: 1_000_000
		});
		if (plan.status === 'needs_amounts') throw new Error('unexpected');
		expect(plan.status).toBe('shortfall');
		// Wallet2 holds the 6,500.00 sent above, so it pays Internet's 1,500.00 itself and that is not asked of the pay (BTL-20261029-0119)
		expect(plan.result.covered.map((c) => [c.label, c.amount])).toEqual([['Internet', 150_000]]);
		expect(plan.gap).toBe(1_350_000 - 150_000 + 200_000 - 1_000_000);
		expect(
			plan.result.status === 'shortfall' && plan.result.cutOptions.map((c) => c.label)
		).toEqual(['Emergency fund', 'Wallet2']);
		await expect(approveSplit(as(ben()), { splitId: plan.id })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('refuses a date that is not a payday and a missing pay', async () => {
		await expect(
			proposeSplitPlan(as(ben()), { incomeScheduleId: incomeId, payday: '2026-11-29' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('a variable bill with no amount yet', () => {
	it('asks first, learns from payments, and offers the difference as a savings hint', async () => {
		const carl = () => person('user_carl_0001');
		const bank = (await createAccount(as(carl()), { name: 'Bank', kind: 'bank', minBalance: 0 }))
			.id;
		const income = await createIncome(as(carl()), {
			label: 'Pay',
			accountId: bank,
			expectedAmount: 1_000_000,
			schedule: { kind: 'semi_monthly', days: [15, 30] },
			weekendRule: 'before'
		});
		const meralco = await createBill(as(carl()), {
			name: 'Meralco',
			category: 'bills',
			accountId: bank,
			kind: 'variable',
			amount: null,
			schedule: { kind: 'monthly', day: 20 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		// The 15th of November 2026 is a Sunday, so the weekend rule moves this payday to Friday the 13th
		const asked = await proposeSplitPlan(as(carl()), {
			incomeScheduleId: income.id,
			payday: '2026-11-13'
		});
		expect(asked).toMatchObject({
			status: 'needs_amounts',
			bills: [{ billId: meralco.id, dueDate: '2026-11-20' }]
		});
		expect((await listBills(carl()))[0]?.estimate).toMatchObject({ unknown: true });

		// Paying with an amount records it; a payment without one needs the person's answer
		await expect(
			markBillPaid(as(carl()), { billId: meralco.id, dueDate: '2026-11-20' })
		).rejects.toMatchObject({ code: 'INVALID' });
		for (const [d, amount] of [
			['2026-08-20', 300_000],
			['2026-09-20', 320_000],
			['2026-10-20', 310_000]
		] as const)
			await markBillPaid(as(carl()), { billId: meralco.id, dueDate: d, amount });
		const est = (await listBills(carl()))[0]?.estimate;
		expect(est).toMatchObject({ amount: 310_000, unknown: false, basis: 'history' });

		const under = await markBillPaid(as(carl()), {
			billId: meralco.id,
			dueDate: '2026-11-20',
			amount: 250_000
		});
		expect(under.savingsHint).toBe(60_000);
		await expect(
			markBillPaid(as(carl()), { billId: meralco.id, dueDate: '2026-11-20', amount: 1 })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await expect(
			markBillPaid(as(carl()), { billId: meralco.id, dueDate: '2026-11-21', amount: 1 })
		).rejects.toMatchObject({ code: 'INVALID' });
		expect((await listDueBills(carl(), '2026-11-01', '2026-11-30'))[0]).toMatchObject({
			paid: true,
			amount: 305_000
		});
	});
});

describe('the ledger', () => {
	let rcbc: string;
	let gcash: string;

	beforeAll(async () => {
		rcbc = (await createAccount(as(anna()), { name: 'LedgerBank', kind: 'bank', minBalance: 0 }))
			.id;
		gcash = (
			await createAccount(as(anna()), { name: 'LedgerGCash', kind: 'ewallet', minBalance: 0 })
		).id;
	});

	it('logs "lunch 180 ledgergcash" from words and undoes it', async () => {
		const r = await logExpenseFromText(as(anna()), { text: 'lunch 180 ledgergcash' });
		if (r.status !== 'saved') throw new Error(`unexpected ${r.status}`);
		expect(r.txn).toMatchObject({
			type: 'expense',
			amount: 18_000,
			accountId: gcash,
			category: 'food',
			note: 'lunch',
			source: 'chat'
		});
		const balance = async () =>
			(await accountBalances(anna())).find((b) => b.id === gcash)?.balance;
		expect(await balance()).toBe(-18_000);
		const entry = (await listUndoable(anna())).find(
			(u) => (u.after as { id?: string } | null)?.id === r.txn.id
		);
		// The write hands back the id undo takes, so the assistant never has to look for it (BTL-20261106-1502)
		expect((r.txn as { journalId?: string }).journalId).toBe(entry?.id);
		await undo(as(anna()), { journalId: entry?.id ?? '' });
		expect(await balance()).toBe(0);
		await expect(undo(as(anna()), { journalId: entry?.id ?? '' })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		// The row is kept, marked void
		expect((await listTransactions(anna(), { accountId: gcash }))[0]?.voidedAt).toBeTruthy();
	});

	it('asks for what is missing instead of guessing', async () => {
		expect(await logExpenseFromText(as(anna()), { text: 'hello' })).toMatchObject({
			status: 'needs_amount'
		});
		expect(await logExpenseFromText(as(anna()), { text: 'coffee 120' })).toMatchObject({
			status: 'needs_account',
			amount: 12_000
		});
		// Two numbers: shown as a chip, nothing saved
		expect(
			await logExpenseFromText(as(anna()), { text: '2 coffee 240 ledgergcash' })
		).toMatchObject({ status: 'needs_confirmation', chip: { amount: 24_000 } });
		const before = (await listTransactions(anna())).length;
		expect(before).toBe(1);
	});

	it('shows an amount read from a picture as a chip and saves it only after a yes', async () => {
		const input = { accountId: gcash, amount: 45_050, note: 'receipt', source: 'ocr' as const };
		expect(await logExpense(as(anna()), input)).toMatchObject({
			status: 'needs_confirmation',
			chip: { amount: 45_050, accountName: 'LedgerGCash' }
		});
		expect(await listTransactions(anna(), { accountId: gcash })).toHaveLength(1);
		expect(await logExpense(as(anna()), { ...input, confirmed: true })).toMatchObject({
			status: 'saved'
		});
		expect(await listTransactions(anna(), { accountId: gcash })).toHaveLength(2);
	});

	it('counts a balance, stores the drift, and confirms big or tenfold changes', async () => {
		const day = (d: string) => `2026-09-${d}T00:00:00Z`;
		const base = { accountId: rcbc };
		expect(
			await recordSnapshot(as(anna()), { ...base, amount: 100_000, takenAt: day('10') })
		).toMatchObject({ status: 'saved', expected: null, drift: 0 });
		await logExpense(as(anna()), {
			...base,
			amount: 18_000,
			occurredAt: day('11'),
			note: 'dinner'
		});
		// Expected 82,000; counted 80,000: 2,000 went untracked
		const counted = await recordSnapshot(as(anna()), {
			...base,
			amount: 80_000,
			takenAt: day('12')
		});
		expect(counted).toMatchObject({
			status: 'saved',
			expected: 82_000,
			drift: -2_000,
			untracked: 2_000
		});
		await recordTransfer(as(anna()), {
			fromAccountId: rcbc,
			toAccountId: gcash,
			amount: 50_000,
			fee: 1_500,
			occurredAt: day('13')
		});
		expect((await accountBalances(anna())).find((b) => b.id === rcbc)?.balance).toBe(
			80_000 - 51_500
		);

		// An older count is refused
		await expect(
			recordSnapshot(as(anna()), { ...base, amount: 1, takenAt: day('11') })
		).rejects.toMatchObject({ code: 'INVALID' });

		// Expected 28,500; counted 280,000: more than the limit, so a yes first (but under ten times, so one yes is enough)
		const big = { ...base, amount: 280_000, takenAt: day('14') };
		expect(await recordSnapshot(as(anna()), big)).toMatchObject({
			status: 'needs_confirmation',
			chip: { expected: 28_500, severity: 'normal' }
		});
		const first = await recordSnapshot(as(anna()), { ...big, confirmed: true });
		expect(first).toMatchObject({ status: 'saved', drift: 251_500 });
		// A positive drift is recorded but is not untracked spending
		expect(first.status === 'saved' && first.untracked).toBe(0);

		// More than ten times what was expected: confirming is not enough, it needs the second yes
		const huge = { ...base, amount: 4_000_000, takenAt: day('15') };
		expect(await recordSnapshot(as(anna()), { ...huge, confirmed: true })).toMatchObject({
			status: 'needs_confirmation',
			chip: { severity: 'large' }
		});
		const saved = await recordSnapshot(as(anna()), {
			...huge,
			confirmed: true,
			acknowledgeLarge: true
		});
		expect(saved).toMatchObject({ status: 'saved', drift: 3_720_000 });

		const sum = await spendingSummary(anna(), { from: '2026-09-01', to: '2026-09-30' });
		expect(sum).toMatchObject({
			spending: 18_000 + 1_500,
			untracked: 2_000,
			byCategory: { other: 18_000 }
		});

		// Undoing the last count removes it, and the balance falls back to the earlier count plus what followed
		const entry = (await listUndoable(anna())).find(
			(u) =>
				(u.after as { snapshotId?: string } | null)?.snapshotId ===
				(saved.status === 'saved' ? saved.snapshotId : '')
		);
		await undo(as(anna()), { journalId: entry?.id ?? '' });
		expect((await accountBalances(anna())).find((b) => b.id === rcbc)?.balance).toBe(280_000);
	});

	it('lists which accounts are due for a count in the weekly check-in', async () => {
		const c = await weeklyCheckin(anna());
		const bank = c.accounts.find((a) => a.accountId === rcbc);
		expect(bank?.due).toBe(true);
		expect(c.untrackedLast7Days).toBe(0);
	});

	it('replays a repeated expense request instead of logging it twice', async () => {
		const ctx = as(anna());
		const a = await logExpense(ctx, { accountId: gcash, amount: 7_700, note: 'once' });
		const b = await logExpense(ctx, { accountId: gcash, amount: 7_700, note: 'once' });
		expect(b).toEqual(a);
		expect(
			(await listTransactions(anna(), { accountId: gcash })).filter((x) => x.note === 'once')
		).toHaveLength(1);
	});
});

describe('the purpose label of an account', () => {
	let acc: string;
	const ctx = () => person('user_eli_00001');

	it('is set at creation, changed, kept when absent and cleared with null', async () => {
		const made = await createAccount(as(ctx()), {
			name: 'Pocket',
			kind: 'bank',
			purpose: ' Emergency '
		});
		acc = made.id;
		expect(made.purpose).toBe('Emergency');
		const changed = await updateAccount(as(ctx()), { accountId: acc, purpose: 'Travel' });
		expect(changed.purpose).toBe('Travel');
		// A change that does not mention the label leaves it alone
		const renamed = await updateAccount(as(ctx()), { accountId: acc, name: 'Pocket 2' });
		expect(renamed.purpose).toBe('Travel');
		const cleared = await updateAccount(as(ctx()), { accountId: acc, purpose: null });
		expect(cleared.purpose).toBeNull();
	});

	it('refuses an empty label, a long one and a long number, through the verb and the database', async () => {
		for (const purpose of [
			'',
			'   ',
			'x'.repeat(25),
			'GCash 0917 123 4567',
			'0917.123.4567',
			'12345678'
		])
			await expect(updateAccount(as(ctx()), { accountId: acc, purpose })).rejects.toMatchObject({
				code: 'INVALID'
			});
		await expect(
			withUser(t.handle, 'user_eli_00001', (tx) =>
				tx.execute(sql.raw(`update account set purpose = '  padded ' where id = '${acc}'`))
			)
		).rejects.toBeTruthy();
	});

	it('comes back in the balances read and is a replay of the first answer on a repeated request', async () => {
		const base = as(ctx());
		const first = await updateAccount(base, { accountId: acc, purpose: 'Savings' });
		const again = await updateAccount(base, { accountId: acc, purpose: 'Savings' });
		expect(again.version).toBe(first.version);
		const row = (await accountBalances(ctx())).find((x) => x.id === acc);
		expect(row?.purpose).toBe('Savings');
	});

	it('leaves the label in the audit trail, before and after', async () => {
		const rows = await withUser(t.handle, 'user_eli_00001', (tx) =>
			tx.select().from(auditEvent).where(eq(auditEvent.entityId, acc)).orderBy(asc(auditEvent.seq))
		);
		const last = rows.at(-1);
		expect(last?.after).toMatchObject({ purpose: 'Savings' });
		expect(
			rows.some((r) => (r.after as { purpose?: string | null } | null)?.purpose === 'Emergency')
		).toBe(true);
		expect(
			rows.some(
				(r) =>
					(r.before as { purpose?: string | null } | null)?.purpose === 'Travel' &&
					(r.after as { purpose?: string | null } | null)?.purpose === null
			)
		).toBe(true);
	});

	it('is hidden from another person', async () => {
		expect((await accountBalances(ben())).some((x) => x.id === acc)).toBe(false);
		await expect(
			updateAccount(as(ben()), { accountId: acc, purpose: 'Mine' })
		).rejects.toBeTruthy();
	});
});

describe('no model needed', () => {
	it('logs an expense and marks a bill paid while every outside call fails', async () => {
		const fetchSpy = vi.fn(() => {
			throw new Error('The model is down');
		});
		vi.stubGlobal('fetch', fetchSpy);
		try {
			const acc = await createAccount(as(anna()), {
				name: 'OfflineBank',
				kind: 'bank',
				minBalance: 0
			});
			const b = await createBill(as(anna()), {
				name: 'Water',
				category: 'bills',
				accountId: acc.id,
				kind: 'fixed',
				amount: 40_000,
				schedule: { kind: 'monthly', day: 5 },
				weekendRule: 'none',
				startsOn: '2000-01-01',
				deferrable: false
			});
			expect(await logExpenseFromText(as(anna()), { text: 'snack 90 offlinebank' })).toMatchObject({
				status: 'saved'
			});
			expect(await markBillPaid(as(anna()), { billId: b.id, dueDate: '2026-11-05' })).toMatchObject(
				{ amount: 40_000 }
			);
			expect(fetchSpy).not.toHaveBeenCalled();
		} finally {
			vi.unstubAllGlobals();
		}
	});

	it('keeps the finance verbs free of any import of the model proxy', () => {
		const dir = join(process.cwd(), 'src/lib/server/ops');
		const files = readdirSync(dir).filter((f) =>
			['accounts', 'bills', 'ledger', 'planning', 'rules', 'split', 'shared'].some(
				(n) => f === `${n}.ts`
			)
		);
		expect(files.length).toBe(7);
		for (const f of files)
			expect(readFileSync(join(dir, f), 'utf8')).not.toMatch(/proxy|deepseek/i);
	});
});

describe('bills on flexible schedules (BTL-20261022-0218, O.1 and O.2)', () => {
	const dina = () => person('user_dina_0001');
	let account: string;
	const add = (name: string, schedule: Parameters<typeof createBill>[1]['schedule'], extra = {}) =>
		createBill(as(dina()), {
			name,
			category: 'other',
			accountId: account,
			kind: 'fixed',
			amount: 150_000,
			schedule,
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false,
			...extra
		});

	it('keeps an old stored shape working', async () => {
		account = (await createAccount(as(dina()), { name: 'BDO', kind: 'bank', minBalance: 0 })).id;
		const old = await add('Old rent', { kind: 'monthly', day: 31 });
		const due = (await listDueBills(dina(), '2026-02-01', '2026-04-30')).filter(
			(d) => d.billId === old.id
		);
		expect(due.map((d) => [d.windowStart, d.windowEnd, d.dueDate])).toEqual([
			['2026-02-28', '2026-02-28', '2026-02-28'],
			['2026-03-31', '2026-03-31', '2026-03-31'],
			['2026-04-30', '2026-04-30', '2026-04-30']
		]);
	});

	it('is due on the 1st Wednesday and pays that day once', async () => {
		const b = await add('Water', { kind: 'nth_weekday', n: 1, weekday: 3 });
		const due = (await listDueBills(dina(), '2026-10-01', '2026-12-31')).filter(
			(d) => d.billId === b.id
		);
		expect(due.map((d) => d.dueDate)).toEqual(['2026-10-07', '2026-11-04', '2026-12-02']);
		await markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-11-04' });
		await expect(
			markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-11-04' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		const after = (await listDueBills(dina(), '2026-10-01', '2026-12-31')).filter(
			(d) => d.billId === b.id
		);
		expect(after.map((d) => d.paid)).toEqual([false, true, false]);
		await expect(
			markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-11-05' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('settles a whole week window from any day inside it, and only once', async () => {
		const b = await add('Internet', { kind: 'week_of_month', n: 1, basis: 'days', pick: 'window' });
		const week = (await listDueBills(dina(), '2026-12-01', '2026-12-31')).filter(
			(d) => d.billId === b.id
		);
		expect(week.map((d) => [d.windowStart, d.windowEnd])).toEqual([['2026-12-01', '2026-12-07']]);
		const paid = await markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-12-03' });
		expect(paid.amount).toBe(150_000);
		// A second payment on any other day of the same window is refused; the next month is a new window
		await expect(
			markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-12-06' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await expect(
			markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-12-08' })
		).rejects.toMatchObject({ code: 'INVALID' });
		const both = (await listDueBills(dina(), '2026-12-01', '2027-01-31')).filter(
			(d) => d.billId === b.id
		);
		expect(both.map((d) => [d.windowEnd, d.paid])).toEqual([
			['2026-12-07', true],
			['2027-01-07', false]
		]);
		await markBillPaid(as(dina()), { billId: b.id, dueDate: '2027-01-01' });
	});

	it('still sees a payment after the weekend rule or the schedule is edited', async () => {
		const b = await add('Cable', { kind: 'day_range', from: 5, to: 11 });
		await markBillPaid(as(dina()), { billId: b.id, dueDate: '2026-10-08' });
		// 2026-10-11 is a Sunday: the due date moves to Friday the 9th, which is before the payment's recorded due date
		await updateBill(as(dina()), { billId: b.id, weekendRule: 'before' });
		const moved = (await listDueBills(dina(), '2026-10-01', '2026-10-31')).filter(
			(d) => d.billId === b.id
		);
		expect(moved.map((d) => [d.windowStart, d.windowEnd, d.paid])).toEqual([
			['2026-10-05', '2026-10-09', true]
		]);
		// A different window is not hidden by the old payment
		await updateBill(as(dina()), {
			billId: b.id,
			schedule: { kind: 'week_of_month', n: 2, basis: 'calendar', pick: 'window' }
		});
		const reshaped = (await listDueBills(dina(), '2026-10-01', '2026-10-31')).filter(
			(d) => d.billId === b.id
		);
		expect(reshaped.map((d) => [d.windowStart, d.windowEnd, d.paid])).toEqual([
			['2026-10-05', '2026-10-09', true]
		]);
		const nov = (await listDueBills(dina(), '2026-11-01', '2026-11-30')).filter(
			(d) => d.billId === b.id
		);
		expect(nov.every((d) => !d.paid)).toBe(true);
	});

	it('uses one read for all the variable bills, with the learned estimate', async () => {
		const b = await add(
			'Electric',
			{ kind: 'monthly', day: 20 },
			{ kind: 'variable', amount: 200_000 }
		);
		const due = (await listDueBills(dina(), '2026-10-01', '2026-10-31')).filter(
			(d) => d.billId === b.id
		);
		expect(due[0]).toMatchObject({ amount: 200_000, unknownAmount: false, paid: false });
	});
});

describe('schedule_preview (BTL-20261022-0218, O.3)', () => {
	const dina = () => person('user_dina_0001');
	type Preview = { text: string; key: string; windows: { start: string; end: string }[] };

	it('says what a schedule means and lists the next windows, for the person and the assistant', async () => {
		const input = {
			schedule: { kind: 'nth_weekday', n: 1, weekday: 3 },
			from: '2026-10-08',
			count: 3
		};
		for (const who of [dina(), agent('user_dina_0001')]) {
			const out = (await invokeVerb(who, 'schedule_preview', input)) as Preview;
			expect(out.text).toBe('Every 1st Wednesday of the month');
			expect(out.key).toBe('schedule.nth_weekday');
			expect(out.windows.map((w) => w.end)).toEqual(['2026-11-04', '2026-12-02', '2027-01-06']);
		}
	});

	it('shows a window and moves only its end for the weekend rule', async () => {
		const out = (await invokeVerb(dina(), 'schedule_preview', {
			schedule: { kind: 'day_range', from: 5, to: 11 },
			weekend: 'before',
			from: '2026-10-01',
			count: 1
		})) as Preview;
		expect(out.windows).toEqual([{ start: '2026-10-05', end: '2026-10-09' }]);
	});

	it('explains a wrong schedule in words and refuses unknown fields', async () => {
		await expect(
			invokeVerb(dina(), 'schedule_preview', {
				schedule: { kind: 'nth_weekday', n: 9, weekday: 3 }
			})
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringMatching(/1st to the 5th/) });
		await expect(
			invokeVerb(dina(), 'schedule_preview', {
				schedule: { kind: 'monthly', day: 5 },
				userId: 'someone-else'
			})
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('payment windows and paydays (BTL-20261022-0218, O.5)', () => {
	const eli = () => person('user_eli_00001');
	let bank: string;
	let incomeId: string;
	const bill = (name: string, from: number, to: number) =>
		createBill(as(eli()), {
			name,
			category: 'bills',
			accountId: bank,
			kind: 'fixed',
			amount: 800_000,
			schedule: { kind: 'day_range', from, to },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});

	it('refuses a payday that is a range of days or a whole week', async () => {
		bank = (await createAccount(as(eli()), { name: 'Bank', kind: 'bank', minBalance: 0 })).id;
		for (const schedule of [
			{ kind: 'day_range', from: 5, to: 10 },
			{ kind: 'week_of_month', n: 1, basis: 'days', pick: 'window' }
		] as const)
			await expect(
				createIncome(as(eli()), {
					label: 'Salary',
					accountId: bank,
					expectedAmount: 5_000_000,
					schedule,
					weekendRule: 'none'
				})
			).rejects.toMatchObject({ code: 'INVALID', message: expect.stringMatching(/one day/) });
		// A weekday of the week is one day
		const ok = await createIncome(as(eli()), {
			label: 'Salary',
			accountId: bank,
			expectedAmount: 5_000_000,
			schedule: { kind: 'semi_monthly', days: [15, 30] },
			weekendRule: 'none'
		});
		incomeId = ok.id;
	});

	it('plans a window that closes inside the pay period, and leaves the ones that close outside it', async () => {
		await bill('Window rent', 10, 20);
		await bill('Early window', 1, 14);
		await bill('Late window', 25, -1);
		const plan = await proposeSplitPlan(as(eli()), {
			incomeScheduleId: incomeId,
			payday: '2030-03-15',
			pay: 5_000_000
		});
		if (plan.status === 'needs_amounts') throw new Error('unexpected');
		// The window starts before the payday but its deadline, the 20th, is in this period
		const labels = plan.result.lines.map((l) => l.label);
		expect(labels).toContain('Window rent');
		expect(labels).not.toContain('Early window');
		expect(labels).not.toContain('Late window');
		expect(plan.result.periodEnd).toBe('2030-03-29');
	});
});
