// ISOLATION BETWEEN TWO PEOPLE ON EVERY USER TABLE, RUN AS THE app_runtime ROLE.
// Each user table needs a case below that writes a row for Anna. The last test fails when a registered table has no case,
// so a new table cannot ship without an isolation check.

// -- TYPES -- //
import type { Tx } from '../../src/lib/server/db/client';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	USER_TABLES,
	account,
	accountWallet,
	agentAction,
	allocationRule,
	balanceSnapshot,
	bill,
	billOverride,
	billPayment,
	calendarEvent,
	chat,
	chatTurn,
	device,
	goal,
	incomeSchedule,
	ledgerTxn,
	memoryFact,
	memoryProfile,
	userSetting,
	auditEvent,
	memorySummary,
	notebook,
	notebookRevision,
	modelUsage,
	reminder,
	requestLog,
	routine,
	splitPlan,
	task,
	undoJournal,
	user
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { chatOf } from '../support/chats';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const ANNA = 'user_anna_0001';
const BEN = 'user_ben_00001';

/** One writer per user table: it creates a row owned by the person in context. */
// Fixed ids let the finance rows point at each other. The cases run in this order, parents first.
const ACCOUNT_ID = '00000000-0000-4000-8000-000000000001';
const BILL_ID = '00000000-0000-4000-8000-000000000002';
const TXN_ID = '00000000-0000-4000-8000-000000000003';

const CASES: Record<string, (tx: Tx, userId: string) => Promise<unknown>> = {
	device: (tx, userId) =>
		tx.insert(device).values({ userId, label: 'phone', pushToken: 'token-isolation-0001' }),
	model_usage: (tx, userId) =>
		tx.insert(modelUsage).values({ userId, bucket: 'chat', month: '2026-10', calls: 1 }),
	request_log: (tx, userId) =>
		tx
			.insert(requestLog)
			.values({ userId, requestId: 'req-isolation-1', verb: 'v', fingerprint: 'f' }),
	undo_journal: (tx, userId) =>
		tx.insert(undoJournal).values({ userId, verb: 'v', entity: 'device', entityId: '1' }),
	account: (tx, userId) =>
		tx.insert(account).values({ id: ACCOUNT_ID, userId, name: 'RCBC', kind: 'bank' }),
	account_wallet: (tx, userId) =>
		tx.insert(accountWallet).values({ userId, accountId: ACCOUNT_ID, currency: 'PHP' }),
	income_schedule: (tx, userId) =>
		tx.insert(incomeSchedule).values({
			userId,
			label: 'Pay',
			accountId: ACCOUNT_ID,
			schedule: { kind: 'monthly', day: 15 }
		}),
	bill: (tx, userId) =>
		tx.insert(bill).values({
			id: BILL_ID,
			userId,
			name: 'Rent',
			accountId: ACCOUNT_ID,
			kind: 'fixed',
			amount: 100,
			schedule: { kind: 'monthly', day: 1 }
		}),
	goal: (tx, userId) =>
		tx.insert(goal).values({ userId, name: 'Fund', accountId: ACCOUNT_ID, perPayday: 0 }),
	allocation_rule: (tx, userId) =>
		tx.insert(allocationRule).values({
			userId,
			position: 1,
			mode: 'rest',
			targetAccountId: ACCOUNT_ID,
			effectiveFrom: '2026-10-21'
		}),
	ledger_txn: (tx, userId) =>
		tx
			.insert(ledgerTxn)
			.values({ id: TXN_ID, userId, type: 'expense', accountId: ACCOUNT_ID, amount: 100 }),
	bill_payment: (tx, userId) =>
		tx
			.insert(billPayment)
			.values({ userId, billId: BILL_ID, dueDate: '2026-10-01', amount: 100, txnId: TXN_ID }),
	bill_override: (tx, userId) =>
		tx.insert(billOverride).values({
			userId,
			billId: BILL_ID,
			originalDueDate: '2026-10-01',
			newDueDate: '2026-10-03'
		}),
	balance_snapshot: (tx, userId) =>
		tx.insert(balanceSnapshot).values({ userId, accountId: ACCOUNT_ID, amount: 100 }),
	split_plan: (tx, userId) =>
		tx.insert(splitPlan).values({ userId, payday: '2026-10-30', pay: 100, result: {} }),
	agent_action: (tx, userId) =>
		tx.insert(agentAction).values({
			userId,
			verb: 'bill_create',
			args: {},
			summary: 'Add a bill.',
			expiresAt: new Date('2099-01-01')
		}),
	task: (tx, userId) => tx.insert(task).values({ userId, title: 'Call mama' }),
	calendar_event: (tx, userId) =>
		tx.insert(calendarEvent).values({
			userId,
			title: 'Lunch',
			startsAt: new Date('2026-10-22T04:00:00Z'),
			endsAt: new Date('2026-10-22T05:00:00Z')
		}),
	routine: (tx, userId) =>
		tx
			.insert(routine)
			.values({ userId, title: 'Gym', recurrence: { freq: 'daily', time: '06:00' } }),
	reminder: (tx, userId) =>
		tx.insert(reminder).values({
			userId,
			kind: 'custom',
			refKey: 'custom:isolation',
			title: 'Hello',
			remindAt: new Date('2026-10-22T04:00:00Z')
		}),
	memory_profile: (tx, userId) => tx.insert(memoryProfile).values({ userId, persona: 'Be brief.' }),
	user_setting: (tx, userId) => tx.insert(userSetting).values({ userId, currency: 'USD' }),
	audit_event: (tx, userId) =>
		tx.insert(auditEvent).values({
			userId,
			seq: 1_000_000,
			actorKind: 'person',
			channel: 'app',
			entity: 'account',
			entityId: 'x',
			action: 'create',
			hash: 'h'
		}),
	memory_fact: (tx, userId) =>
		tx.insert(memoryFact).values({ userId, text: 'I like tea.', textHash: 'h-isolation' }),
	memory_summary: (tx, userId) =>
		tx
			.insert(memorySummary)
			.values({ userId, period: 'day', periodStart: '2026-10-20', text: 'A day.' }),
	notebook: (tx, userId) =>
		tx.insert(notebook).values({ userId, text: '# About you\n- Likes tea\n' }),
	notebook_revision: async (tx, userId) => {
		const [book] = await tx
			.insert(notebook)
			.values({ userId, text: 'current' })
			.onConflictDoUpdate({ target: notebook.userId, set: { updatedAt: new Date() } })
			.returning({ id: notebook.id });
		await tx
			.insert(notebookRevision)
			.values({ userId, notebookId: book!.id, version: 1, text: 'before', actor: 'user' });
	},
	chat: (tx, userId) => tx.insert(chat).values({ userId, title: 'A chat' }),
	chat_turn: async (tx, userId) =>
		tx.insert(chatTurn).values({
			userId,
			chatId: await chatOf(tx, userId),
			clientMessageId: 'msg-isolation-1',
			userText: 'hi'
		})
};

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: ANNA, name: 'Anna', email: 'anna@example.com' },
		{ id: BEN, name: 'Ben', email: 'ben@example.com' }
	]);
	for (const write of Object.values(CASES)) await withUser(t.handle, ANNA, (tx) => write(tx, ANNA));
});

afterAll(async () => {
	await t.close();
});

/** Tables whose rows can be added and read but never changed or removed. */
const APPEND_ONLY = new Set(USER_TABLES.filter((u) => u.appendOnly).map((u) => u.name));

const count = (tx: Tx, table: string) =>
	tx.execute(sql.raw(`select count(*)::int as n from "${table}"`)).then((r) => {
		const rows = (r as unknown as { rows: { n: number }[] }).rows;
		return rows[0]?.n ?? -1;
	});

// -- TESTS -- //

describe('user table isolation', () => {
	for (const name of Object.keys(CASES)) {
		it(`${name}: the owner sees the row, another person and no context see nothing`, async () => {
			const mine = await withUser(t.handle, ANNA, (tx) => count(tx, name));
			// The trail has a row for every change the other cases made, the rest have the one row made here
			if (APPEND_ONLY.has(name)) expect(mine).toBeGreaterThanOrEqual(1);
			else expect(mine).toBe(1);
			expect(await withUser(t.handle, BEN, (tx) => count(tx, name))).toBe(0);
			// No user set at all: the same connection role, but no context
			const bare = await t.handle.db.transaction((tx) => count(tx, name));
			expect(bare).toBe(0);
		});

		it(`${name}: another person cannot write a row for someone else`, async () => {
			const write = CASES[name]!;
			// Ben's context, Anna's id: the policy's WITH CHECK refuses it
			// Drizzle wraps the Postgres error, so the policy message is on the cause: it must be the row level security refusal and not,
			// say, a unique key clash that would pass for the wrong reason
			const error = await withUser(t.handle, BEN, (tx) => write(tx, ANNA)).then(
				() => null,
				(e: unknown) => e as Error & { cause?: Error }
			);
			expect(error, 'the write should have been refused').not.toBeNull();
			expect(String(error?.cause?.message ?? error?.message)).toMatch(/row-level security/i);
		});

		it(`${name}: another person cannot delete the row`, async () => {
			const before = await withUser(t.handle, ANNA, (tx) => count(tx, name));
			const attempt = withUser(t.handle, BEN, (tx) =>
				tx.execute(sql.raw(`delete from "${name}" returning 1`))
			);
			if (APPEND_ONLY.has(name)) {
				// An append-only table refuses a delete to everyone: the role has no right to it
				const error = await attempt.then(
					() => null,
					(e: unknown) => e as Error & { cause?: Error }
				);
				expect(String(error?.cause?.message ?? error?.message)).toMatch(/permission denied/i);
			} else {
				expect(((await attempt) as unknown as { rows: unknown[] }).rows).toHaveLength(0);
			}
			expect(await withUser(t.handle, ANNA, (tx) => count(tx, name))).toBe(before);
		});
	}

	it('has an isolation case for every registered user table', () => {
		const missing = USER_TABLES.map((u) => u.name).filter((n) => !(n in CASES));
		expect(missing, `Add an isolation case for: ${missing.join(', ')}`).toEqual([]);
	});
});
