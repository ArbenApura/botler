// ACCOUNT WALLETS IN THE SERVER VERBS (BTL-20261023-1407, M2): AN ACCOUNT HOLDS SEVERAL CURRENCIES, EACH WALLET HAS ITS OWN BALANCE, COUNT AND HISTORY, A CONVERSION INSIDE ONE
// ACCOUNT MOVES WHAT REALLY ARRIVED, A FOREIGN BILL IS PAID IN THE WALLET THE PERSON CHOOSES, AND A WALLET IN ANOTHER CURRENCY NEVER CHANGES A MONEY PLAN CHECK.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { toManilaDate } from '../../src/lib/finance/dates';
import { accountWallet, billPayment, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import {
	addWallet,
	createAccount,
	listAccounts,
	updateAccount
} from '../../src/lib/server/ops/accounts';
import { accountHistory } from '../../src/lib/server/ops/audit';
import {
	createBill,
	deleteBill,
	listBills,
	markBillPaid,
	updateBill
} from '../../src/lib/server/ops/bills';
import {
	accountBalances,
	logExpense,
	logExpenseFromText,
	recordIncome,
	recordSnapshot,
	recordTransfer,
	spendingSummary,
	weeklyCheckin
} from '../../src/lib/server/ops/ledger';
import { createIncome } from '../../src/lib/server/ops/planning';
import { setSettings } from '../../src/lib/server/ops/settings';
import { approveSplit, proposeSplitPlan } from '../../src/lib/server/ops/split';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const as = (c: Ctx): Ctx => ({ ...c, requestId: `req-wal-${String(++counter).padStart(6, '0')}` });
const wallets = (id: string, accountId: string) =>
	withUser(t.handle, id, (tx) =>
		tx
			.select({ currency: accountWallet.currency })
			.from(accountWallet)
			.where(and(eq(accountWallet.userId, id), eq(accountWallet.accountId, accountId)))
	).then((rows) => rows.map((r) => r.currency).sort());
const walletOf = async (id: string, accountId: string, currency: string) =>
	(await accountBalances(person(id)))
		.find((a) => a.id === accountId)
		?.wallets.find((w) => w.currency === currency);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_wal_0001', name: 'A', email: 'wa@example.com' },
		{ id: 'user_wal_0002', name: 'B', email: 'wb@example.com' },
		{ id: 'user_wal_0003', name: 'C', email: 'wc@example.com' },
		{ id: 'user_wal_0004', name: 'D', email: 'wd@example.com' }
	]);
	await setSettings(as(person('user_wal_0004')), { currency: 'JPY' });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('an account and its wallets', () => {
	const id = 'user_wal_0001';

	it('opens in the main currency with one wallet, and a person in yen gets yen', async () => {
		const wise = await createAccount(as(person(id)), { name: 'Wise', kind: 'ewallet' });
		expect(wise.currency).toBe('PHP');
		expect(await wallets(id, wise.id)).toEqual(['PHP']);
		const yen = await createAccount(as(person('user_wal_0004')), { name: 'Cash', kind: 'cash' });
		expect(yen.currency).toBe('JPY');
		expect(await wallets('user_wal_0004', yen.id)).toEqual(['JPY']);
		const eur = await createAccount(as(person(id)), {
			name: 'Revolut',
			kind: 'bank',
			currency: 'EUR'
		});
		expect(eur.currency).toBe('EUR');
	});

	it('adds a currency once, however often it is asked, and refuses a code that is not one', async () => {
		const wise = (await listAccounts(person(id))).find((a) => a.name === 'Wise');
		if (!wise) throw new Error('no account');
		await addWallet(as(person(id)), { accountId: wise.id, currency: 'USD' });
		const again = await addWallet(as(person(id)), { accountId: wise.id, currency: 'USD' });
		expect(again.currencies).toEqual(['PHP', 'USD']);
		expect(await wallets(id, wise.id)).toEqual(['PHP', 'USD']);
		await expect(
			addWallet(as(person(id)), { accountId: wise.id, currency: 'XXX' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('opens a wallet by itself on the first entry in a currency, even two at once', async () => {
		const acc = await createAccount(as(person(id)), { name: 'PayPal', kind: 'ewallet' });
		await Promise.all([
			logExpense(as(person(id)), { accountId: acc.id, amount: 500, currency: 'USD', note: 'a' }),
			logExpense(as(person(id)), { accountId: acc.id, amount: 700, currency: 'USD', note: 'b' })
		]);
		expect(await wallets(id, acc.id)).toEqual(['PHP', 'USD']);
		expect((await walletOf(id, acc.id, 'USD'))?.balance).toBe(-1_200);
	});

	it('keeps the balance, the count and the history of each wallet apart', async () => {
		const acc = await createAccount(as(person(id)), { name: 'Multi', kind: 'bank' });
		await recordIncome(as(person(id)), { accountId: acc.id, amount: 500_000 });
		await recordIncome(as(person(id)), { accountId: acc.id, amount: 10_000, currency: 'USD' });
		await logExpense(as(person(id)), { accountId: acc.id, amount: 1_250, currency: 'USD' });
		await logExpense(as(person(id)), { accountId: acc.id, amount: 30_000 });
		const row = (await accountBalances(person(id))).find((a) => a.id === acc.id);
		expect(row?.currency).toBe('PHP');
		// balance is the wallet in the account's own currency, which is what an older app reads
		expect(row?.balance).toBe(470_000);
		expect(row?.wallets.map((w) => [w.currency, w.balance])).toEqual([
			['PHP', 470_000],
			['USD', 8_750]
		]);
		// Counting the dollars leaves the pesos alone
		const counted = await recordSnapshot(as(person(id)), {
			accountId: acc.id,
			currency: 'USD',
			amount: 9_000,
			confirmed: true
		});
		expect(counted).toMatchObject({ status: 'saved', counted: 9_000, expected: 8_750, drift: 250 });
		expect((await walletOf(id, acc.id, 'USD'))?.balance).toBe(9_000);
		expect((await walletOf(id, acc.id, 'PHP'))?.balance).toBe(470_000);
		// The history of a wallet lists its own entries and its running balance
		const usd = await accountHistory(person(id), { accountId: acc.id, currency: 'USD' });
		expect(usd.currency).toBe('USD');
		expect(usd.balance).toBe(9_000);
		const ledger = usd.entries.filter((e) => e.currency !== null);
		expect(ledger.every((e) => e.currency === 'USD')).toBe(true);
		expect(ledger[0]?.balanceAfter).toBe(9_000);
		const php = await accountHistory(person(id), { accountId: acc.id });
		expect(php.currency).toBe('PHP');
		expect(php.entries.filter((e) => e.currency !== null).every((e) => e.currency === 'PHP')).toBe(
			true
		);
	});

	it('reads a currency written in the words, and otherwise the currency of the account', async () => {
		const acc = await createAccount(as(person(id)), { name: 'Cashbox', kind: 'cash' });
		const usd = await logExpenseFromText(as(person(id)), { text: 'coffee usd 5 cashbox' });
		expect(usd).toMatchObject({ status: 'saved', txn: { amount: 500, currency: 'USD' } });
		const plain = await logExpenseFromText(as(person(id)), { text: 'lunch 180 cashbox' });
		expect(plain).toMatchObject({ status: 'saved', txn: { amount: 18_000, currency: 'PHP' } });
		expect(await wallets(id, acc.id)).toEqual(['PHP', 'USD']);
	});

	it('takes a number with no symbol in the currency of its account, whatever the main currency is', async () => {
		const acc = await createAccount(as(person(id)), {
			name: 'Tokyo',
			kind: 'bank',
			currency: 'JPY'
		});
		const res = await logExpenseFromText(as(person(id)), { text: 'ramen 900 tokyo' });
		// Yen have no cents: 900 is 900, not 90,000
		expect(res).toMatchObject({
			status: 'saved',
			txn: { amount: 900, currency: 'JPY', accountId: acc.id }
		});
	});

	it('refuses to change the currency of an account that has entries, and allows it on an empty one', async () => {
		const used = await createAccount(as(person(id)), { name: 'Used', kind: 'bank' });
		await logExpense(as(person(id)), { accountId: used.id, amount: 100 });
		await expect(
			updateAccount(as(person(id)), { accountId: used.id, currency: 'USD' })
		).rejects.toMatchObject({ code: 'INVALID' });
		const empty = await createAccount(as(person(id)), { name: 'Empty', kind: 'bank' });
		const changed = await updateAccount(as(person(id)), { accountId: empty.id, currency: 'SGD' });
		expect(changed.currency).toBe('SGD');
		expect(await wallets(id, empty.id)).toEqual(['SGD']);
	});
});

describe('a conversion between wallets', () => {
	const id = 'user_wal_0002';

	it('moves what really arrived, inside one account, and charges the fee in the source currency', async () => {
		const wise = await createAccount(as(person(id)), { name: 'Wise', kind: 'ewallet' });
		await recordIncome(as(person(id)), { accountId: wise.id, amount: 1_000_000 });
		const row = await recordTransfer(as(person(id)), {
			fromAccountId: wise.id,
			toAccountId: wise.id,
			currency: 'PHP',
			toCurrency: 'USD',
			amount: 560_000,
			toAmount: 9_940,
			fee: 5_000
		});
		expect(row).toMatchObject({ currency: 'PHP', toCurrency: 'USD', toAmount: 9_940 });
		expect((await walletOf(id, wise.id, 'PHP'))?.balance).toBe(1_000_000 - 565_000);
		expect((await walletOf(id, wise.id, 'USD'))?.balance).toBe(9_940);
	});

	it('asks what arrived when the currencies differ, and refuses a move to the same wallet', async () => {
		const wise = (await listAccounts(person(id))).find((a) => a.name === 'Wise');
		const other = await createAccount(as(person(id)), { name: 'Maya', kind: 'ewallet' });
		if (!wise) throw new Error('no account');
		await expect(
			recordTransfer(as(person(id)), {
				fromAccountId: wise.id,
				toAccountId: wise.id,
				currency: 'PHP',
				toCurrency: 'USD',
				amount: 100
			})
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('USD arrived') });
		await expect(
			recordTransfer(as(person(id)), { fromAccountId: wise.id, toAccountId: wise.id, amount: 100 })
		).rejects.toMatchObject({ code: 'INVALID' });
		// Two accounts in one currency need no second amount, and one given that differs is refused
		await expect(
			recordTransfer(as(person(id)), {
				fromAccountId: wise.id,
				toAccountId: other.id,
				amount: 100,
				toAmount: 99
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		const ok = await recordTransfer(as(person(id)), {
			fromAccountId: wise.id,
			toAccountId: other.id,
			amount: 100
		});
		expect(ok).toMatchObject({ currency: 'PHP', toCurrency: 'PHP', toAmount: null });
	});

	it('shows a conversion in the history of each wallet it touches', async () => {
		const wise = (await listAccounts(person(id))).find((a) => a.name === 'Wise');
		if (!wise) throw new Error('no account');
		const usd = await accountHistory(person(id), { accountId: wise.id, currency: 'USD' });
		expect(usd.balance).toBe(9_940);
		expect(usd.entries.find((e) => e.entity === 'ledger_txn')?.balanceAfter).toBe(9_940);
		const php = await accountHistory(person(id), { accountId: wise.id, currency: 'PHP' });
		expect(
			php.entries.find((e) => e.entity === 'ledger_txn' && e.action === 'create')
		).toBeTruthy();
	});
});

describe('the money plan stays in the main currency', () => {
	const id = 'user_wal_0003';

	it('does not judge the minimum balance or the check-in by a wallet in another currency', async () => {
		const acc = await createAccount(as(person(id)), {
			name: 'Wise',
			kind: 'ewallet',
			minBalance: 100_000
		});
		await recordIncome(as(person(id)), { accountId: acc.id, amount: 50_000 });
		const before = (await accountBalances(person(id))).find((a) => a.id === acc.id);
		expect(before?.belowMinimum).toBe(true);
		// A large balance in dollars is not pesos: the peso wallet is still below its minimum
		await recordIncome(as(person(id)), { accountId: acc.id, amount: 9_000_000, currency: 'USD' });
		const after = (await accountBalances(person(id))).find((a) => a.id === acc.id);
		expect(after?.belowMinimum).toBe(true);
		expect(after?.wallets).toHaveLength(2);
		// The check-in lists each wallet on its own line
		const checkin = await weeklyCheckin(person(id));
		expect(checkin.accounts.filter((a) => a.accountId === acc.id).map((a) => a.currency)).toEqual([
			'PHP',
			'USD'
		]);
	});

	it('treats an account with no wallet in the main currency as having nothing to judge, not as empty', async () => {
		const usd = await createAccount(as(person(id)), {
			name: 'Dollar jar',
			kind: 'cash',
			currency: 'USD',
			minBalance: 100_000
		});
		const row = (await accountBalances(person(id))).find((a) => a.id === usd.id);
		expect(row?.currency).toBe('USD');
		expect(row?.belowMinimum).toBe(false);
	});

	it('sums spending in the main currency and names the others instead of adding them', async () => {
		const acc = (await listAccounts(person(id))).find((a) => a.name === 'Wise');
		if (!acc) throw new Error('no account');
		await logExpense(as(person(id)), { accountId: acc.id, amount: 20_000, category: 'food' });
		await logExpense(as(person(id)), { accountId: acc.id, amount: 999, currency: 'USD' });
		const today = toManilaDate(new Date());
		const summary = await spendingSummary(person(id), { from: '2020-01-01', to: today });
		expect(summary.currency).toBe('PHP');
		expect(summary.spending).toBe(20_000);
		expect(summary.otherCurrencies).toEqual(['USD']);
		expect(summary.byCategory).toEqual({ food: 20_000 });
	});
});

describe('a bill in another currency', () => {
	const id = 'user_wal_0003';

	it('is in the main currency unless it says another, and keeps its own amounts', async () => {
		const gcash = await createAccount(as(person(id)), { name: 'GCash', kind: 'ewallet' });
		const plain = await createBill(as(person(id)), {
			name: 'Meralco',
			category: 'bills',
			accountId: gcash.id,
			kind: 'fixed',
			amount: 250_000,
			schedule: { kind: 'monthly', day: 15 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		expect(plain.currency).toBe('PHP');
		const usd = await createBill(as(person(id)), {
			name: 'Netflix',
			category: 'subscription',
			accountId: gcash.id,
			kind: 'fixed',
			amount: 1_599,
			currency: 'USD',
			schedule: { kind: 'monthly', day: 20 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		expect(usd.currency).toBe('USD');
	});

	it('is paid in the wallet the person chooses, for what was really charged, and the payment keeps the bill amount', async () => {
		const gcash = (await listAccounts(person(id))).find((a) => a.name === 'GCash');
		if (!gcash) throw new Error('no account');
		const list = await listBills(person(id));
		const nf = list.find((b) => b.name === 'Netflix');
		if (!nf) throw new Error('no bill');
		// A dollar bill paid in pesos: the charged amount is asked for
		await expect(
			markBillPaid(as(person(id)), { billId: nf.id, dueDate: '2026-09-20', paidCurrency: 'PHP' })
		).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('PHP was charged')
		});
		const paid = await markBillPaid(as(person(id)), {
			billId: nf.id,
			dueDate: '2026-09-20',
			paidCurrency: 'PHP',
			paidAmount: 90_100
		});
		expect(paid).toMatchObject({
			amount: 1_599,
			currency: 'USD',
			paidCurrency: 'PHP',
			paidAmount: 90_100
		});
		// The expense left the peso wallet; the dollar wallet was not touched
		expect((await walletOf(id, gcash.id, 'PHP'))?.balance).toBe(-90_100);
		expect(await walletOf(id, gcash.id, 'USD')).toBeUndefined();
		const rows = await withUser(t.handle, id, (tx) =>
			tx.select().from(billPayment).where(eq(billPayment.userId, id))
		);
		expect(rows).toHaveLength(1);
		expect(rows[0]).toMatchObject({
			amount: 1_599,
			currency: 'USD',
			paidCurrency: 'PHP',
			paidAmount: 90_100
		});
	});

	it('pays from the dollar wallet at the bill amount when nothing else is said, and refuses a charge that disagrees', async () => {
		const gcash = (await listAccounts(person(id))).find((a) => a.name === 'GCash');
		const nf = (await listBills(person(id))).find((b) => b.name === 'Netflix');
		if (!gcash || !nf) throw new Error('missing');
		await expect(
			markBillPaid(as(person(id)), {
				billId: nf.id,
				dueDate: '2026-10-20',
				paidCurrency: 'USD',
				paidAmount: 1_700
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		// With no dollar wallet and nothing said, it is not paid into a new negative wallet: the person is asked
		await expect(
			markBillPaid(as(person(id)), { billId: nf.id, dueDate: '2026-10-20' })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('wallet') });
		await addWallet(as(person(id)), { accountId: gcash.id, currency: 'USD' });
		const paid = await markBillPaid(as(person(id)), { billId: nf.id, dueDate: '2026-10-20' });
		expect(paid).toMatchObject({
			amount: 1_599,
			currency: 'USD',
			paidCurrency: null,
			paidAmount: null
		});
		expect((await walletOf(id, gcash.id, 'USD'))?.balance).toBe(-1_599);
	});

	it('cannot change currency once it has payments, and can before', async () => {
		const list = await listBills(person(id));
		const nf = list.find((b) => b.name === 'Netflix');
		const mer = list.find((b) => b.name === 'Meralco');
		if (!nf || !mer) throw new Error('missing');
		await expect(
			updateBill(as(person(id)), { billId: nf.id, currency: 'EUR' })
		).rejects.toMatchObject({ code: 'INVALID' });
		const changed = await updateBill(as(person(id)), { billId: mer.id, currency: 'SGD' });
		expect(changed.currency).toBe('SGD');
	});
});

describe('changing the main currency', () => {
	const id = 'user_wal_0003';

	it('leaves wallets as they are, judges the minimum balance in the new main currency, and posts the pay there', async () => {
		const bank = await createAccount(as(person(id)), {
			name: 'Salary bank',
			kind: 'bank',
			minBalance: 100_000
		});
		await recordIncome(as(person(id)), { accountId: bank.id, amount: 50_000 });
		expect((await accountBalances(person(id))).find((a) => a.id === bank.id)?.belowMinimum).toBe(
			true
		);
		const income = await createIncome(as(person(id)), {
			label: 'Pay',
			accountId: bank.id,
			expectedAmount: 2_000_000,
			schedule: { kind: 'semi_monthly', days: [15, 30] },
			weekendRule: 'before'
		});
		// The Meralco bill an earlier test left in Singapore dollars has no rate here, and the split rightly refuses a bill it cannot count: whether
		// it falls inside the pay period depends on the run date, so this test takes it away and stays about the main currency
		const left = (await listBills(person(id))).find((b) => b.currency === 'SGD');
		if (left) await deleteBill(as(person(id)), { billId: left.id });
		await setSettings(as(person(id)), { currency: 'USD' });
		// The pesos are still there; with no dollar wallet there is nothing to judge, so no warning (and not an "empty" account)
		const after = (await accountBalances(person(id))).find((a) => a.id === bank.id);
		expect(after?.wallets.map((w) => [w.currency, w.balance])).toEqual([['PHP', 50_000]]);
		expect(after?.belowMinimum).toBe(false);
		// The pay of a split lands in the main currency wallet, which opens
		const plan = await proposeSplitPlan(as(person(id)), { incomeScheduleId: income.id });
		if (plan.status === 'needs_amounts') throw new Error('needs amounts');
		await approveSplit(as(person(id)), { splitId: plan.id, recordIncome: true });
		expect(await wallets(id, bank.id)).toEqual(['PHP', 'USD']);
		expect((await walletOf(id, bank.id, 'USD'))?.balance).toBe(2_000_000);
		expect((await walletOf(id, bank.id, 'PHP'))?.balance).toBe(50_000);
		await setSettings(as(person(id)), { currency: 'PHP' });
	});
});

describe('the usual amount of a bill in another currency', () => {
	const id = 'user_wal_0002';

	it('is learned from the bill amounts, never from what was charged in another currency', async () => {
		const acc = await createAccount(as(person(id)), { name: 'Cloud card', kind: 'bank' });
		const hosting = await createBill(as(person(id)), {
			name: 'Hosting',
			category: 'subscription',
			accountId: acc.id,
			kind: 'variable',
			currency: 'USD',
			schedule: { kind: 'monthly', day: 5 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		for (const [due, usd, php] of [
			['2026-05-05', 2_000, 112_000],
			['2026-06-05', 2_200, 125_000],
			['2026-07-05', 2_100, 119_000]
		] as const)
			await markBillPaid(as(person(id)), {
				billId: hosting.id,
				dueDate: due,
				amount: usd,
				paidCurrency: 'PHP',
				paidAmount: php
			});
		const bill = (await listBills(person(id))).find((b) => b.id === hosting.id);
		expect(bill?.currency).toBe('USD');
		// Three payments are enough to learn the usual amount: dollars (about 21.00), not the pesos charged (about 1,190)
		expect(bill?.estimate.amount).toBe(2_100);
	});
});
