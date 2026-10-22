// RESETTING A BALANCE (BTL-20261022-0218, L.1 AND L.7): THE ASSISTANT'S CARD, THE PERSON'S APPROVAL AND WHAT THE BALANCE IS AFTERWARDS

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { createAction, decideAction } from '../../src/lib/server/ops/actions';
import {
	accountBalances,
	listTransactions,
	recordSnapshot,
	spendingSummary
} from '../../src/lib/server/ops/ledger';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const as = (c: Ctx): Ctx => ({
	...c,
	requestId: `req-reset-${String(++counter).padStart(6, '0')}`
});
const agent = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test' }
});
const balanceOf = async (c: Ctx, accountId: string) =>
	(await accountBalances(c)).find((b) => b.id === accountId)?.balance;

/** An account that holds `amount` after a first count. */
async function accountWith(userId: string, name: string, amount: number) {
	const c = person(userId);
	const acc = await createAccount(as(c), { name, kind: 'ewallet', minBalance: 0 });
	await recordSnapshot(as(c), { accountId: acc.id, amount, confirmed: true });
	return acc.id;
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_reset_001', name: 'R', email: 'r@example.com' },
		{ id: 'user_reset_002', name: 'S', email: 's@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the assistant resets an account to zero', () => {
	it('is one approval of one card, whatever the old balance was', async () => {
		const id = 'user_reset_001';
		const gcash = await accountWith(id, 'GCash', 500_000);
		expect(await balanceOf(person(id), gcash)).toBe(500_000);
		// The assistant can only ask: it makes a card
		const card = await createAction(agent(id), {
			verb: 'snapshot_record',
			args: { accountId: gcash, amount: 0 }
		});
		// The person taps approve once
		const done = await decideAction(as(person(id)), {
			actionId: card.actionId,
			decision: 'approve'
		});
		expect(done.status).toBe('applied');
		expect(await balanceOf(person(id), gcash)).toBe(0);
	});
});

describe('a reset keeps the history and is not spending', () => {
	const id = 'user_reset_002';

	it('says the old balance, the new one, the difference and the reason on the card', async () => {
		const acc = await accountWith(id, 'Maya', 250_000);
		const card = await createAction(agent(id), {
			verb: 'snapshot_record',
			args: { accountId: acc, amount: 0, mode: 'reset', reason: 'Starting over' }
		});
		expect(card.summary).toBe(
			'Reset Maya to ₱0.00. It shows ₱2,500.00 now, a difference of -₱2,500.00. Reason given by Botler: "Starting over". Your history is kept.'
		);
		const done = await decideAction(as(person(id)), {
			actionId: card.actionId,
			decision: 'approve'
		});
		expect(done.status).toBe('applied');
		expect(done.result).toMatchObject({
			status: 'saved',
			counted: 0,
			drift: -250_000,
			mode: 'reset'
		});
		expect(await balanceOf(person(id), acc)).toBe(0);
	});

	it('leaves every earlier record, and the reset is not untracked spending', async () => {
		const c = person(id);
		const rows = await listTransactions(c);
		expect(rows.map((r) => [r.type, r.category, r.note])).toContainEqual([
			'adjustment',
			'reset',
			'Balance reset: Starting over'
		]);
		const week = await spendingSummary(c, { from: '2026-01-01', to: '2099-12-31' });
		expect(week.untracked).toBe(0);
	});

	it('needs a reason, and is confirmed even when a person asks for it directly', async () => {
		const c = person(id);
		const acc = (await accountBalances(c))[0]?.id ?? '';
		await expect(
			recordSnapshot(as(c), { accountId: acc, amount: 0, mode: 'reset' })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringMatching(/why/) });
		expect(
			await recordSnapshot(as(c), { accountId: acc, amount: 0, mode: 'reset', reason: 'Test' })
		).toMatchObject({ status: 'needs_confirmation' });
	});

	it('refuses a reset made by the assistant itself, and an ordinary count that is not a reset still counts as untracked', async () => {
		const c = person(id);
		const acc = await accountWith(id, 'Cash2', 100_000);
		await expect(
			recordSnapshot(as(agent(id)), {
				accountId: acc,
				amount: 0,
				mode: 'reset',
				reason: 'x',
				confirmed: true
			})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		const r = await recordSnapshot(as(c), { accountId: acc, amount: 90_000, confirmed: true });
		expect(r).toMatchObject({ status: 'saved', untracked: 10_000, mode: 'count' });
	});
});
