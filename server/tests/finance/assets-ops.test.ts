// TOTAL ASSETS IN THE MAIN CURRENCY (BTL-20261023-1407, M4): EVERY WALLET CONVERTED AT THE STORED RATES, A MISSING RATE LEFT OUT AND NAMED, A BILL IN ANOTHER CURRENCY COUNTED AT ITS
// RATE IN THE SPLIT AND THE FORECAST, AND THE ASSISTANT ASKS BEFORE A CURRENCY IT HAS NOT USED ON AN ACCOUNT OPENS A WALLET

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { convertUp } from '../../src/lib/finance/fx';
import { fxRate, user } from '../../src/lib/server/db/schema';
import { configureFx } from '../../src/lib/server/fx/config';
import { createAccount, archiveAccount, listAccounts } from '../../src/lib/server/ops/accounts';
import { createAction } from '../../src/lib/server/ops/actions';
import { assetsSummary } from '../../src/lib/server/ops/assets';
import { createBill, listBills, listDueBills } from '../../src/lib/server/ops/bills';
import { calendarRange } from '../../src/lib/server/ops/calendarRange';
import { fxConvert } from '../../src/lib/server/ops/fx';
import { logExpense, recordIncome } from '../../src/lib/server/ops/ledger';
import { createIncome } from '../../src/lib/server/ops/planning';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { setSettings } from '../../src/lib/server/ops/settings';
import { proposeSplitPlan } from '../../src/lib/server/ops/split';
import { syncGet } from '../../src/lib/server/ops/sync';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const agent = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test_tool' },
	channel: 'chat'
});
const as = (c: Ctx): Ctx => ({ ...c, requestId: `req-ast-${String(++counter).padStart(6, '0')}` });
const setRates = async (rates: Record<string, string>, fetchedAt = new Date()) => {
	for (const [code, rate] of Object.entries(rates))
		await t.handle.db
			.insert(fxRate)
			.values({ code, rate, fetchedAt, source: 'test' })
			.onConflictDoUpdate({ target: fxRate.code, set: { rate, fetchedAt } });
};

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	configureFx(null);
	await t.handle.db.insert(user).values([
		{ id: 'user_ast_0001', name: 'A', email: 'aa@example.com' },
		{ id: 'user_ast_0002', name: 'B', email: 'ab@example.com' },
		{ id: 'user_ast_0003', name: 'C', email: 'ac@example.com' }
	]);
	await setRates({ PHP: '56', JPY: '157.2', EUR: '0.92' });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('total assets', () => {
	const id = 'user_ast_0001';

	it('converts every wallet to the main currency and adds them up exactly', async () => {
		const wise = await createAccount(as(person(id)), { name: 'Wise', kind: 'ewallet' });
		const cash = await createAccount(as(person(id)), { name: 'Cash', kind: 'cash' });
		await recordIncome(as(person(id)), { accountId: wise.id, amount: 100_000 });
		await recordIncome(as(person(id)), { accountId: wise.id, amount: 5_000, currency: 'USD' });
		await recordIncome(as(person(id)), { accountId: wise.id, amount: 20_000, currency: 'JPY' });
		await recordIncome(as(person(id)), { accountId: cash.id, amount: 30_000 });
		const view = await assetsSummary(person(id));
		expect(view.currency).toBe('PHP');
		const byCurrency = Object.fromEntries(
			view.wallets.filter((w) => w.accountId === wise.id).map((w) => [w.currency, w])
		);
		// 100.00 pesos as they are; 50.00 dollars at 56; 20,000 yen at 157.2 to the dollar, then 56 pesos to the dollar
		expect(byCurrency.PHP).toMatchObject({ value: 100_000, rate: null, missingRate: false });
		expect(byCurrency.USD).toMatchObject({ value: 280_000, rate: '56', missingRate: false });
		expect(byCurrency.JPY).toMatchObject({ value: 712_468, rate: '0.356234' });
		expect(view.total).toBe(100_000 + 280_000 + 712_468 + 30_000);
		expect(view.accounts.find((a) => a.accountId === wise.id)).toMatchObject({
			subtotal: 1_092_468,
			wallets: 3,
			hasMissing: false
		});
		expect(view.missing).toEqual([]);
		expect(view.rates.stale).toBe(false);
		expect(view.rates.source).toBe('test');
	});

	it('leaves a wallet without a rate out of the total and names it, never counting it as zero', async () => {
		const acc = await createAccount(as(person(id)), { name: 'Cape', kind: 'bank' });
		await recordIncome(as(person(id)), { accountId: acc.id, amount: 77_700, currency: 'ZAR' });
		const view = await assetsSummary(person(id));
		expect(view.missing).toEqual(['ZAR']);
		const wallet = view.wallets.find((w) => w.accountId === acc.id && w.currency === 'ZAR');
		expect(wallet).toMatchObject({ balance: 77_700, value: null, missingRate: true });
		expect(view.accounts.find((a) => a.accountId === acc.id)).toMatchObject({
			subtotal: 0,
			hasMissing: true
		});
		// The total is the same as before the wallet existed
		expect(view.total).toBe(100_000 + 280_000 + 712_468 + 30_000);
	});

	it('counts an overdraft as negative, and leaves out an archived account', async () => {
		const card = await createAccount(as(person(id)), { name: 'Card', kind: 'other' });
		await logExpense(as(person(id)), { accountId: card.id, amount: 40_000 });
		const before = await assetsSummary(person(id));
		expect(before.wallets.find((w) => w.accountId === card.id)).toMatchObject({
			balance: -40_000,
			value: -40_000
		});
		expect(before.total).toBe(100_000 + 280_000 + 712_468 + 30_000 - 40_000);
		await archiveAccount(as(person(id)), { accountId: card.id });
		const after = await assetsSummary(person(id));
		expect(after.wallets.some((w) => w.accountId === card.id)).toBe(false);
		expect(after.total).toBe(100_000 + 280_000 + 712_468 + 30_000);
	});

	it('follows the main currency: the same wallets read in dollars, with no conversion of a wallet already in it', async () => {
		await setSettings(as(person(id)), { currency: 'USD' });
		try {
			await readInDollars();
		} finally {
			await setSettings(as(person(id)), { currency: 'PHP' });
		}
	});

	const readInDollars = async () => {
		const view = await assetsSummary(person(id));
		expect(view.currency).toBe('USD');
		const wise = (await listAccounts(person(id))).find((a) => a.name === 'Wise');
		const usd = view.wallets.find((w) => w.accountId === wise?.id && w.currency === 'USD');
		expect(usd).toMatchObject({ value: 5_000, rate: null });
		// 1,000.00 pesos is 17.857 dollars: 1,786 cents (rounded to the nearest)
		const php = view.wallets.find((w) => w.accountId === wise?.id && w.currency === 'PHP');
		expect(php?.value).toBe(1_786);
		expect(php?.rate).toBe('0.0178571');
	};

	it('is the total on the home summary too', async () => {
		const sync = await syncGet(person(id), {});
		expect(sync.summary).toMatchObject({
			total: 100_000 + 280_000 + 712_468 + 30_000,
			currency: 'PHP',
			totalMissing: 1
		});
	});

	it('does not wait for rates and says when there are none', async () => {
		const empty = 'user_ast_0003';
		await createAccount(as(person(empty)), { name: 'Jar', kind: 'cash' });
		await t.handle.owner.exec('delete from fx_rate');
		try {
			const view = await assetsSummary(person(empty));
			expect(view.total).toBe(0);
			expect(view.rates).toMatchObject({ asOf: null, stale: true });
			await recordIncome(as(person(empty)), {
				accountId: (await listAccounts(person(empty)))[0]?.id ?? '',
				amount: 100,
				currency: 'EUR'
			});
			const noRate = await assetsSummary(person(empty));
			expect(noRate.missing).toEqual(['EUR']);
			expect(noRate.total).toBe(0);
		} finally {
			await setRates({ PHP: '56', JPY: '157.2', EUR: '0.92' });
		}
	});
});

describe('converting for an answer', () => {
	const id = 'user_ast_0001';

	it('gives the converted amount in the smallest unit with the rate and its date', async () => {
		const out = await fxConvert(person(id), { amount: 5_000, from: 'USD', to: 'PHP' });
		expect(out).toMatchObject({ status: 'ok', converted: 280_000, rate: '56', stale: false });
		const yen = await fxConvert(person(id), { amount: 15_720, from: 'JPY', to: 'USD' });
		expect(yen).toMatchObject({ status: 'ok', converted: 10_000 });
		expect(await fxConvert(person(id), { amount: 7, from: 'PHP', to: 'PHP' })).toMatchObject({
			converted: 7,
			rate: '1'
		});
	});

	it('answers a missing rate as missing and refuses a code that is not one', async () => {
		expect(await fxConvert(person(id), { amount: 100, from: 'ZAR', to: 'PHP' })).toEqual({
			status: 'missing_rate',
			amount: 100,
			from: 'ZAR',
			to: 'PHP',
			missing: ['ZAR']
		});
		await expect(
			fxConvert(person(id), { amount: 100, from: 'XXX', to: 'PHP' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('is offered to the assistant, as are the assets', async () => {
		const out = (await invokeVerb(agent(id), 'fx_convert', {
			amount: 100,
			from: 'USD',
			to: 'PHP'
		})) as { converted: number };
		expect(out.converted).toBe(5_600);
		const assets = (await invokeVerb(agent(id), 'assets_summary', {})) as { currency: string };
		expect(assets.currency).toBe('PHP');
	});
});

describe('the assistant and a new currency', () => {
	const id = 'user_ast_0002';

	it('records in any currency without asking, opening the wallet itself', async () => {
		const acc = await createAccount(as(person(id)), { name: 'PayPal', kind: 'ewallet' });
		await expect(
			invokeVerb(as(agent(id)), 'expense_log', { accountId: acc.id, amount: 500 })
		).resolves.toBeTruthy();
		// A currency the account has not used opens its wallet at once (owner decision 2026-10-28)
		await expect(
			invokeVerb(as(agent(id)), 'expense_log', { accountId: acc.id, amount: 500, currency: 'USD' })
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'income_record', {
				accountId: acc.id,
				amount: 100,
				currency: 'EUR'
			})
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'expense_from_text', { text: 'coffee usd 5 paypal' })
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'expense_from_text', { text: 'lunch 180 paypal' })
		).resolves.toBeTruthy();
	});

	it('moves money into a new wallet, changes a currency and adds a wallet freely, and still asks before a count', async () => {
		const acc = (await listAccounts(person(id))).find((a) => a.name === 'PayPal');
		const other = await createAccount(as(person(id)), { name: 'Maya', kind: 'ewallet' });
		const fresh = await createAccount(as(person(id)), { name: 'Fresh', kind: 'ewallet' });
		if (!acc) throw new Error('no account');
		await expect(
			invokeVerb(as(agent(id)), 'transfer_record', {
				fromAccountId: acc.id,
				toAccountId: other.id,
				amount: 100,
				toCurrency: 'SGD',
				toAmount: 3
			})
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'account_update', { accountId: fresh.id, currency: 'SGD' })
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'account_update', { accountId: other.id, name: 'Maya wallet' })
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'account_wallet_add', { accountId: fresh.id, currency: 'JPY' })
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'snapshot_record', {
				accountId: acc.id,
				amount: 1,
				currency: 'USD'
			})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});

	it('writes cards in the currency they are for', async () => {
		const acc = (await listAccounts(person(id))).find((a) => a.name === 'PayPal');
		const other = (await listAccounts(person(id))).find((a) => a.name === 'Maya wallet');
		if (!acc || !other) throw new Error('missing');
		const count = await createAction(as(agent(id)), {
			verb: 'snapshot_record',
			args: { accountId: acc.id, amount: 12_345, currency: 'USD' }
		});
		expect(count.summary).toContain('$123.45');
		expect(count.summary).toContain('PayPal');
		const move = await createAction(as(agent(id)), {
			verb: 'transfer_record',
			args: {
				fromAccountId: acc.id,
				toAccountId: other.id,
				amount: 10_000,
				currency: 'USD',
				toCurrency: 'PHP',
				toAmount: 560_000
			}
		});
		expect(move.summary).toContain('$100.00');
		expect(move.summary).toContain('₱5,600.00 arrives');
		const wallet = await createAction(as(agent(id)), {
			verb: 'account_wallet_add',
			args: { accountId: other.id, currency: 'SGD' }
		});
		expect(wallet.summary).toContain('SGD wallet');
		const gone = await createAction(as(agent(id)), {
			verb: 'account_wallet_remove',
			args: { accountId: other.id, currency: 'SGD' }
		});
		expect(gone.summary).toContain('Remove the SGD wallet');
	});

	it('refuses paying a bill from a wallet that does not exist, and pays an ordinary payment', async () => {
		const gcash = await createAccount(as(person(id)), { name: 'GCash', kind: 'ewallet' });
		const usdBill = await createBill(as(person(id)), {
			name: 'Cloud',
			category: 'subscription',
			accountId: gcash.id,
			kind: 'fixed',
			amount: 999,
			currency: 'USD',
			schedule: { kind: 'monthly', day: 12 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		const phpBill = await createBill(as(person(id)), {
			name: 'Water',
			category: 'bills',
			accountId: gcash.id,
			kind: 'fixed',
			amount: 50_000,
			schedule: { kind: 'monthly', day: 13 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		await expect(
			invokeVerb(as(agent(id)), 'bill_mark_paid', { billId: usdBill.id, dueDate: '2026-08-12' })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(as(agent(id)), 'bill_mark_paid', {
				billId: usdBill.id,
				dueDate: '2026-08-12',
				paidCurrency: 'PHP',
				paidAmount: 56_000
			})
		).resolves.toBeTruthy();
		await expect(
			invokeVerb(as(agent(id)), 'bill_mark_paid', { billId: phpBill.id, dueDate: '2026-08-13' })
		).resolves.toBeTruthy();
		// The currency of a bill with payments cannot change under them, and that is a plain refusal now, not a card
		await expect(
			invokeVerb(as(agent(id)), 'bill_update', { billId: phpBill.id, currency: 'USD' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('bills in another currency in the plan', () => {
	const id = 'user_ast_0003';

	it('lists a bill with its value in the main currency, and says when the rate is missing', async () => {
		const acc = await createAccount(as(person(id)), { name: 'Bank', kind: 'bank' });
		await createBill(as(person(id)), {
			name: 'Netflix',
			category: 'subscription',
			accountId: acc.id,
			kind: 'fixed',
			amount: 1_599,
			currency: 'USD',
			schedule: { kind: 'weekly', days: [3] },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		await createBill(as(person(id)), {
			name: 'Zar thing',
			category: 'other',
			accountId: acc.id,
			kind: 'fixed',
			amount: 1_000,
			currency: 'ZAR',
			schedule: { kind: 'weekly', days: [4] },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		});
		const list = await listBills(person(id));
		expect(list.find((b) => b.name === 'Netflix')).toMatchObject({
			currency: 'USD',
			mainCurrency: 'PHP',
			estimateMain: 89_544
		});
		expect(list.find((b) => b.name === 'Zar thing')?.estimateMain).toBeNull();
		const due = await listDueBills(person(id), '2026-11-01', '2026-11-30');
		const nf = due.filter((b) => b.name === 'Netflix');
		expect(nf.length).toBeGreaterThan(0);
		expect(nf.every((b) => b.amountMain === 89_544 && !b.missingRate)).toBe(true);
		const zar = due.filter((b) => b.name === 'Zar thing');
		expect(zar.every((b) => b.amountMain === null && b.missingRate)).toBe(true);
	});

	it('counts the dollar bill in the split at its rate rounded up, keeps the rate, and stops for a bill without a rate', async () => {
		const bank = (await listAccounts(person(id)))[0]?.id ?? '';
		const income = await createIncome(as(person(id)), {
			label: 'Pay',
			accountId: bank,
			expectedAmount: 5_000_000,
			schedule: { kind: 'semi_monthly', days: [15, 30] },
			weekendRule: 'before'
		});
		// The bill without a rate stops the split with a plain message
		await expect(
			proposeSplitPlan(as(person(id)), { incomeScheduleId: income.id })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('ZAR') });
		await setRates({ ZAR: '18' });
		const plan = await proposeSplitPlan(as(person(id)), { incomeScheduleId: income.id });
		if (plan.status === 'needs_amounts') throw new Error('needs amounts');
		const foreign = plan.result.foreignBills ?? [];
		expect(foreign.length).toBeGreaterThan(1);
		const nf = foreign.filter((f) => f.currency === 'USD');
		expect(nf.length).toBeGreaterThan(0);
		for (const f of nf) {
			expect(f.amount).toBe(1_599);
			expect(f.converted).toBe(convertUp(1_599, 'USD', 'PHP', { PHP: '56' }));
			expect(f.rate).toBe('56');
			expect(f.ratesAsOf).not.toBeNull();
		}
		// The lines of the split add up exactly to the pay, whatever the rounding
		expect(plan.result.lines.reduce((s, l) => s + l.amount, 0)).toBe(plan.pay);
		const total = plan.result.lines
			.filter((l) => l.kind === 'bill')
			.reduce((s, l) => s + l.amount, 0);
		expect(total).toBe(foreign.reduce((s, f) => s + f.converted, 0));
	});

	it('takes a dollar bill off the forecast at its rate, and counts one it cannot convert', async () => {
		// From today for 40 days, so the window always holds the bills' next date (a fixed week went stale once the clock passed it)
		const from = new Date().toISOString().slice(0, 10);
		const to = new Date(Date.now() + 40 * 86_400_000).toISOString().slice(0, 10);
		const range = await calendarRange(person(id), { from, to });
		expect(range.forecast.unconvertedBills).toBe(0);
		await t.handle.owner.exec("delete from fx_rate where code = 'ZAR'");
		const missing = await calendarRange(person(id), { from, to });
		expect(missing.forecast.unconvertedBills).toBeGreaterThan(0);
		await setRates({ ZAR: '18' });
	});
});
