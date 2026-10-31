// THE PERSON'S CURRENCY IN THE SERVER VERBS (BTL-20261022-0218, C.4): EXPENSE TEXT, THE SIZE OF A BALANCE CHANGE THAT NEEDS A YES, RULE AND CARD TEXT

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { parseExpenseText, parseRuleText } from '../../src/lib/finance/text';
import { user } from '../../src/lib/server/db/schema';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { createAction } from '../../src/lib/server/ops/actions';
import { logExpenseFromText, recordSnapshot } from '../../src/lib/server/ops/ledger';
import { proposeRuleFromText } from '../../src/lib/server/ops/rules';
import { setSettings } from '../../src/lib/server/ops/settings';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const as = (c: Ctx): Ctx => ({ ...c, requestId: `req-cur-${String(++counter).padStart(6, '0')}` });

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_cur_php_1', name: 'P', email: 'p@example.com' },
		{ id: 'user_cur_usd_1', name: 'U', email: 'u@example.com' },
		{ id: 'user_cur_jpy_1', name: 'J', email: 'j@example.com' }
	]);
	await setSettings(as(person('user_cur_usd_1')), { currency: 'USD' });
	await setSettings(as(person('user_cur_jpy_1')), { currency: 'JPY' });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('reading amounts from words', () => {
	const accounts = ['Wallet', 'Cash'];

	it('reads pesos as before and dollars, euros and yen in their own units', () => {
		expect(parseExpenseText('lunch 180 wallet', accounts, 'PHP').amount).toBe(18_000);
		// A number written with another separator style is refused, never read as its last piece
		expect(parseExpenseText('lunch 1.234,56 wallet', accounts, 'PHP').amount).toBeNull();
		expect(parseExpenseText('lunch $5.50 wallet', accounts, 'USD').amount).toBe(550);
		expect(parseExpenseText('lunch usd 5 wallet', accounts, 'USD').amount).toBe(500);
		expect(parseExpenseText('coffee €3.20', accounts, 'EUR').amount).toBe(320);
		expect(parseExpenseText('ramen ¥1,200 cash', accounts, 'JPY').amount).toBe(1_200);
		expect(parseExpenseText('rent 1.5k', accounts, 'USD').amount).toBe(150_000);
		expect(parseExpenseText('rent 90k', accounts, 'JPY').amount).toBe(90_000);
	});

	it('reads a currency written before the amount, and never a word that happens to be a code', () => {
		const text = (t: string) => parseExpenseText(t, accounts, 'PHP');
		expect(text('coffee usd 5 wallet')).toMatchObject({ currency: 'USD', amount: 500 });
		expect(text('coffee Eur 3.20 wallet')).toMatchObject({ currency: 'EUR', amount: 320 });
		expect(text('rice $4 wallet')).toMatchObject({ currency: 'USD', amount: 400 });
		expect(text('MOP 150 cash')).toMatchObject({ currency: 'MOP', amount: 15_000 });
		// Ordinary words that are also codes are an expense in the account currency, not a foreign wallet
		for (const word of ['mop', 'pen', 'top', 'cup', 'all', 'try', 'sos']) {
			const r = text(`${word} 150 cash`);
			expect(r.currency, word).toBeNull();
			expect(r.amount, word).toBe(15_000);
			expect(r.note, word).toContain(word);
		}
	});

	it('refuses a decimal part for a currency that has none instead of cutting it, and never mistakes a word for a symbol', () => {
		expect(parseExpenseText('ramen 1200.50', accounts, 'JPY').amount).toBeNull();
		expect(parseExpenseText('ramen 1200', accounts, 'JPY').amount).toBe(1_200);
		// "firm" ends in rm, the symbol of ringgit: it is a word here
		const r = parseExpenseText('firm 500 cash', accounts, 'PHP');
		expect(r.amount).toBe(50_000);
		expect(r.note).toBe('firm');
	});

	it('reads a fixed rule in the person currency', () => {
		const targets = [{ kind: 'account' as const, id: 'a1', name: 'Cash' }];
		expect(parseRuleText('$50 to cash', targets, 'USD')).toMatchObject({ ok: true, amount: 5_000 });
		expect(parseRuleText('500 to cash', targets, 'JPY')).toMatchObject({ ok: true, amount: 500 });
		expect(parseRuleText('500 to cash', targets)).toMatchObject({ ok: true, amount: 50_000 });
	});
});

describe('the verbs follow the currency', () => {
	it('logs "lunch 5" as five of the currency the person chose', async () => {
		for (const [id, text, amount] of [
			['user_cur_php_1', 'lunch 5 cash', 500],
			['user_cur_usd_1', 'lunch $5.25 cash', 525],
			['user_cur_jpy_1', 'lunch 1200 cash', 1_200]
		] as const) {
			const c = person(id);
			await createAccount(as(c), { name: 'Cash', kind: 'cash', minBalance: 0 });
			const r = await logExpenseFromText(as(c), { text });
			expect(r, id).toMatchObject({ status: 'saved', txn: { amount } });
		}
	});

	it('asks for a yes at the same real size in every currency', async () => {
		const snap = async (id: string, amount: number) => {
			const c = person(id);
			const cash = (await (await import('../../src/lib/server/ops/accounts')).listAccounts(c))[0];
			return recordSnapshot(as(c), { accountId: cash?.id ?? '', amount });
		};
		// About 2,000 pesos is about 35 dollars is about 5,500 yen: a change a little over that needs a yes, a little under does not
		await snap('user_cur_php_1', 100_000);
		await snap('user_cur_usd_1', 10_000);
		await snap('user_cur_jpy_1', 100_000);
		expect(await snap('user_cur_php_1', 100_000 + 210_000)).toMatchObject({
			status: 'needs_confirmation'
		});
		expect(await snap('user_cur_usd_1', 10_000 + 3_600)).toMatchObject({
			status: 'needs_confirmation'
		});
		expect(await snap('user_cur_jpy_1', 100_000 + 5_600)).toMatchObject({
			status: 'needs_confirmation'
		});
	});

	it('shows rule and card text in the person currency', async () => {
		const usd = person('user_cur_usd_1');
		const rule = await proposeRuleFromText(as(usd), { text: '$50 to cash' });
		expect(rule.summary).toMatch(/^Put \$50\.00 into Cash/);
		const jpy = person('user_cur_jpy_1');
		const yen = await proposeRuleFromText(as(jpy), { text: '500 to cash' });
		expect(yen.summary).toMatch(/^Put ¥500 into Cash/);
		const cash = (await (await import('../../src/lib/server/ops/accounts')).listAccounts(usd))[0];
		const card = await createAction(
			{ handle: t.handle, actor: { userId: 'user_cur_usd_1', kind: 'agent', tool: 'test' } },
			{
				verb: 'goal_create',
				args: { name: 'Laptop', accountId: cash?.id, targetAmount: 200_000, perPayday: 5_000 }
			}
		);
		expect(card.summary).toContain('$50.00');
		expect(card.summary).not.toContain('₱');
	});
});
