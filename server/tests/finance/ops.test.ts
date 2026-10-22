// THE FINANCE VERBS AGAINST A REAL (THROWAWAY) DATABASE: ACCOUNTS, BILLS, RULES, THE PAYDAY SPLIT, THE LEDGER, COUNTS WITH DRIFT AND UNDO

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { bill, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import {
	createAccount,
	archiveAccount,
	listAccounts,
	updateAccount
} from '../../src/lib/server/ops/accounts';
import { createBill, listBills, listDueBills, markBillPaid } from '../../src/lib/server/ops/bills';
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
import { createGoal, createIncome, nextPaydays } from '../../src/lib/server/ops/planning';
import {
	approveRule,
	listRules,
	proposeRule,
	proposeRuleFromText
} from '../../src/lib/server/ops/rules';
import { approveSplit, markTransferSent, proposeSplitPlan } from '../../src/lib/server/ops/split';
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
		{ id: 'user_carl_0001', name: 'Carl', email: 'carl@example.com' }
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
		const plan = await proposeSplitPlan(as(ben()), {
			incomeScheduleId: incomeId,
			payday: '2026-11-30',
			pay: 1_000_000
		});
		if (plan.status === 'needs_amounts') throw new Error('unexpected');
		expect(plan.status).toBe('shortfall');
		expect(plan.gap).toBe(1_350_000 + 200_000 - 1_000_000);
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
