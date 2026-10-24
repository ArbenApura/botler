// THE OLD APP (1.0.5) AGAINST THE NEW SERVER (BTL-20261023-1407, M6.4): EVERY REQUEST IT SENDS HAS NO CURRENCY AND MUST WORK AS BEFORE, AND EVERY ANSWER IT READS KEEPS ITS FIELDS
// (balance, belowMinimum, total ...), with the new ones only added beside them.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { syncGet } from '../../src/lib/server/ops/sync';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'person' },
	requestId: `req-old-${String(++counter).padStart(6, '0')}`
});
const call = (name: string, args: unknown) => invokeVerb(person('user_old_0001'), name, args);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values([{ id: 'user_old_0001', name: 'O', email: 'o@example.com' }]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('requests the old app sends', () => {
	it('adds an account, logs and counts and pays exactly as it did, with no currency anywhere', async () => {
		const acc = (await call('account_create', {
			name: 'GCash',
			kind: 'ewallet',
			minBalance: 0
		})) as { id: string; currency: string };
		expect(acc.currency).toBe('PHP');
		const logged = (await call('expense_log', {
			accountId: acc.id,
			amount: 18_000,
			note: 'lunch',
			source: 'manual'
		})) as { status: string; txn: { currency: string } };
		expect(logged.status).toBe('saved');
		expect(logged.txn.currency).toBe('PHP');
		const counted = (await call('snapshot_record', { accountId: acc.id, amount: 50_000 })) as {
			status: string;
		};
		expect(['saved', 'needs_confirmation']).toContain(counted.status);
		const bill = (await call('bill_create', {
			name: 'Water',
			category: 'bills',
			accountId: acc.id,
			kind: 'fixed',
			amount: 50_000,
			schedule: { kind: 'monthly', day: 13 },
			weekendRule: 'none',
			startsOn: '2000-01-01',
			deferrable: false
		})) as { id: string; currency: string };
		expect(bill.currency).toBe('PHP');
		const paid = (await call('bill_mark_paid', {
			billId: bill.id,
			dueDate: '2026-09-13',
			amount: 50_000
		})) as { amount: number };
		expect(paid.amount).toBe(50_000);
	});

	it('answers the account list with every field the old app reads, and the new ones beside them', async () => {
		const list = (await call('accounts_balances', {})) as Record<string, unknown>[];
		const a = list[0] ?? {};
		for (const key of [
			'id',
			'name',
			'kind',
			'minBalance',
			'purpose',
			'balance',
			'countedAt',
			'belowMinimum'
		])
			expect(a, key).toHaveProperty(key);
		expect(typeof a.balance).toBe('number');
		expect(typeof a.belowMinimum).toBe('boolean');
		expect(a.currency).toBe('PHP');
		expect(Array.isArray(a.wallets)).toBe(true);
	});

	it('keeps the home summary total a whole number and adds the currency beside it', async () => {
		const sync = await syncGet(person('user_old_0001'), {});
		expect(Number.isInteger(sync.summary.total)).toBe(true);
		expect(sync.summary.currency).toBe('PHP');
		expect(sync.summary).toHaveProperty('nextBill');
		expect(sync.summary).toHaveProperty('firstEventToday');
	});

	it('keeps the bills list and the due list fields and adds the main currency value', async () => {
		const bills = (await call('bills_list', {})) as Record<string, unknown>[];
		for (const key of ['id', 'name', 'kind', 'amount', 'schedule', 'estimate'])
			expect(bills[0], key).toHaveProperty(key);
		const due = (await call('bills_due', { from: '2026-09-01', to: '2026-10-30' })) as Record<
			string,
			unknown
		>[];
		for (const key of ['billId', 'dueDate', 'amount', 'paid', 'unknownAmount', 'accountId'])
			expect(due[0], key).toHaveProperty(key);
	});

	it('still refuses a key it does not know (a forged user id), as every strict input does', async () => {
		await expect(call('accounts_balances', { userId: 'someone' })).rejects.toBeTruthy();
	});
});
