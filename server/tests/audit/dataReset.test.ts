// RESET DATA (BTL-20261022-0218, L.9): A PERSON-ONLY ERASE BY SCOPE, A CONFIRMATION THAT WORKS ONCE, ONE TRANSACTION, A TOMBSTONE IN THE TRAIL

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { asc, eq, sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	dataResetBillOverrideSql,
	dataResetLatestSql,
	dataResetMigrationSql,
	EVERYTHING_TABLES,
	KEPT_ON_RESET,
	SCOPE_TABLES
} from '../../src/lib/server/db/dataResetSql';
import { auditEvent, device, user, USER_TABLES, userSetting } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createAccount, listAccounts } from '../../src/lib/server/ops/accounts';
import { verifyAudit } from '../../src/lib/server/ops/audit';
import { previewDataReset, resetData } from '../../src/lib/server/ops/dataReset';
import { registerDevice } from '../../src/lib/server/ops/devices';
import { listTransactions, logExpense } from '../../src/lib/server/ops/ledger';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createEvent, createTask } from '../../src/lib/server/ops/schedule';
import { setSettings } from '../../src/lib/server/ops/settings';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const agent = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test' }
});
const as = (c: Ctx): Ctx => ({
	...c,
	requestId: `req-reset-${String(++counter).padStart(6, '0')}`
});
const trail = (id: string) =>
	withUser(t.handle, id, (tx) =>
		tx.select().from(auditEvent).where(eq(auditEvent.userId, id)).orderBy(asc(auditEvent.seq))
	);

/** Some money, some schedule, a memory, a setting and a phone for one person. */
async function fill(id: string, name = 'GCash') {
	const c = person(id);
	const acc = (await createAccount(as(c), { name, kind: 'ewallet', minBalance: 0 })).id;
	await logExpense(as(c), { accountId: acc, amount: 18_000, note: 'lunch' });
	await createTask(as(c), { title: 'Call the bank' });
	await createEvent(as(c), { title: 'Dentist', startsAt: '2030-03-05T02:00:00Z' });
	await invokeVerb(as(c), 'memory_remember', { text: 'I get paid on the 15th and the 30th' });
	await setSettings(as(c), { currency: 'USD' });
	await registerDevice(as(c), {
		platform: 'android',
		pushToken: `token-${id}-0123456789`,
		label: 'Phone'
	});
	return acc;
}

const rowCount = (id: string, table: string) =>
	withUser(t.handle, id, async (tx) => {
		const r = (await tx.execute(
			sql.raw(`select count(*)::int as n from "${table}"`)
		)) as unknown as {
			rows: { n: number }[];
		};
		return r.rows[0]?.n ?? -1;
	});

/** Previews and erases in one go, as the app does after the person has typed the word. */
async function erase(id: string, scope: Parameters<typeof previewDataReset>[1]['scope']) {
	const preview = await previewDataReset(as(person(id)), { scope });
	return resetData(as(person(id)), { scope, token: preview.token, typed: 'RESET' });
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_rst_0001', name: 'A', email: 'a@example.com' },
		{ id: 'user_rst_0002', name: 'B', email: 'b@example.com' },
		{ id: 'user_rst_0003', name: 'C', email: 'c@example.com' },
		{ id: 'user_rst_0004', name: 'D', email: 'd@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('what a reset covers', () => {
	it('erases every tenant table or keeps it on purpose, with a reason', () => {
		const erased = new Set(EVERYTHING_TABLES);
		const kept = new Set(Object.keys(KEPT_ON_RESET));
		const names = USER_TABLES.map((u) => u.name);
		const neither = names.filter((n) => !erased.has(n) && !kept.has(n));
		expect(
			neither,
			`Put these in a reset scope or in KEPT_ON_RESET: ${neither.join(', ')}`
		).toEqual([]);
		for (const n of erased) expect(names, `${n} is erased but is not a tenant table`).toContain(n);
		for (const n of kept) expect(names, `${n} is kept but is not a tenant table`).toContain(n);
		for (const n of kept) expect(erased.has(n), `${n} is both erased and kept`).toBe(false);
	});

	it('has a migration that is exactly the function built from the lists', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0017_data_reset.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		expect(file).toBe(dataResetMigrationSql());
	});
});

describe('the conversations copy of the function', () => {
	it('is installed by migration 0021 and erases a chat after its turns', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0021_chats.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		expect(file).toContain(dataResetLatestSql());
		const mem = SCOPE_TABLES.memory_and_chat;
		expect(mem.indexOf('chat')).toBeGreaterThan(mem.indexOf('chat_turn'));
	});
});

describe('the bill override copy of the function', () => {
	it('is installed by a later migration and erases the override of a bill before the bill', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0018_bill_override.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		expect(file).toContain(dataResetBillOverrideSql());
		const money = SCOPE_TABLES.money;
		expect(money.indexOf('bill_override')).toBeGreaterThanOrEqual(0);
		expect(money.indexOf('bill_override')).toBeLessThan(money.indexOf('bill'));
		expect(money.indexOf('bill_override')).toBeLessThan(money.indexOf('account'));
	});
});

describe('the person alone', () => {
	const id = 'user_rst_0001';

	it('is refused to the assistant for both verbs, and a card cannot run it', async () => {
		for (const [verb, args] of [
			['data_reset_preview', { scope: 'money' }],
			['data_reset', { scope: 'money', token: 'a'.repeat(32), typed: 'RESET' }]
		] as const)
			await expect(invokeVerb(as(agent(id)), verb, args)).rejects.toMatchObject({
				code: 'FORBIDDEN'
			});
		const { createAction } = await import('../../src/lib/server/ops/actions');
		await expect(
			createAction(agent(id), { verb: 'data_reset', args: { scope: 'everything' } })
		).rejects.toBeTruthy();
	});

	it('counts without changing anything, and mints a token', async () => {
		await fill(id);
		const before = await rowCount(id, 'account');
		const preview = await previewDataReset(as(person(id)), { scope: 'money' });
		expect(preview.counts).toMatchObject({ account: 1, ledger_txn: 1 });
		expect(preview.total).toBeGreaterThan(2);
		expect(preview.token).toMatch(/^[0-9a-f]{32}$/);
		expect(preview.word).toBe('RESET');
		expect(preview.note).toMatch(/Backups/);
		expect(await rowCount(id, 'account')).toBe(before);
	});
});

describe('the confirmation', () => {
	const id = 'user_rst_0001';

	it('needs the typed word, the right scope and a token that exists', async () => {
		const preview = await previewDataReset(as(person(id)), { scope: 'money' });
		await expect(
			resetData(as(person(id)), { scope: 'money', token: preview.token, typed: 'reset' })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringMatching(/Type RESET/) });
		await expect(
			resetData(as(person(id)), { scope: 'everything', token: preview.token, typed: 'RESET' })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			resetData(as(person(id)), { scope: 'money', token: 'b'.repeat(32), typed: 'RESET' })
		).rejects.toMatchObject({ code: 'INVALID' });
		expect(await rowCount(id, 'account')).toBe(1);
	});

	it("is the person's own: another person cannot use it", async () => {
		const preview = await previewDataReset(as(person(id)), { scope: 'money' });
		await fill('user_rst_0002');
		await expect(
			resetData(as(person('user_rst_0002')), {
				scope: 'money',
				token: preview.token,
				typed: 'RESET'
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		expect(await rowCount('user_rst_0002', 'account')).toBe(1);
	});
});

describe('erasing money', () => {
	const id = 'user_rst_0003';

	it('erases the money, keeps the rest, and leaves one tombstone in a chain that still holds', async () => {
		await fill(id);
		await fill('user_rst_0004');
		const rowsBefore = await trail(id);
		const done = await erase(id, 'money');
		expect(done.deleted).toMatchObject({ account: 1, ledger_txn: 1 });
		expect(await listAccounts(person(id))).toHaveLength(0);
		expect(await listTransactions(person(id))).toHaveLength(0);
		// The schedule, the memory, the settings and the phone are still there
		expect(await rowCount(id, 'task')).toBe(1);
		expect(await rowCount(id, 'calendar_event')).toBe(1);
		expect(await rowCount(id, 'memory_fact')).toBe(1);
		expect(
			await withUser(t.handle, id, (tx) =>
				tx.select().from(userSetting).where(eq(userSetting.userId, id))
			)
		).toHaveLength(1);
		expect(
			await withUser(t.handle, id, (tx) => tx.select().from(device).where(eq(device.userId, id)))
		).toHaveLength(1);
		// The trail kept everything it had and added one tombstone that says what was erased
		const rows = await trail(id);
		expect(rows.length).toBe(rowsBefore.length + 1);
		expect(rows.at(-1)).toMatchObject({
			action: 'data_reset',
			entity: 'data',
			entityId: 'money',
			actorKind: 'person',
			seq: rowsBefore.length + 1
		});
		expect(rows.at(-1)?.after).toMatchObject({ account: 1, ledger_txn: 1 });
		expect(await verifyAudit(person(id))).toMatchObject({ ok: true });
		// Another person is untouched
		expect(await rowCount('user_rst_0004', 'account')).toBe(1);
	});

	it('works once: the same confirmation is refused the second time', async () => {
		const preview = await previewDataReset(as(person(id)), { scope: 'schedule' });
		await resetData(as(person(id)), { scope: 'schedule', token: preview.token, typed: 'RESET' });
		await expect(
			resetData(as(person(id)), { scope: 'schedule', token: preview.token, typed: 'RESET' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		expect(await rowCount(id, 'task')).toBe(0);
		expect(await rowCount(id, 'calendar_event')).toBe(0);
	});
});

describe('erasing the trail and everything', () => {
	it('erasing the trail leaves only the tombstone, a new chain that starts at 1', async () => {
		const id = 'user_rst_0004';
		await erase(id, 'audit');
		const rows = await trail(id);
		expect(rows).toHaveLength(1);
		expect(rows[0]).toMatchObject({
			seq: 1,
			action: 'data_reset',
			entityId: 'audit',
			prevHash: null
		});
		expect(await verifyAudit(person(id))).toMatchObject({ ok: true, checked: 1 });
		// The money is still there, and what happens next continues the new chain
		expect(await rowCount(id, 'account')).toBe(1);
		await logExpense(as(person(id)), {
			accountId: (await listAccounts(person(id)))[0]?.id ?? '',
			amount: 100,
			note: 'after'
		});
		expect((await trail(id)).map((r) => r.seq)).toEqual([1, 2]);
		expect(await verifyAudit(person(id))).toMatchObject({ ok: true, checked: 2 });
	});

	it('everything leaves the sign-in, the settings and the phone, and a clean trail with one row', async () => {
		const id = 'user_rst_0002';
		const done = await erase(id, 'everything');
		expect(done.deleted).toMatchObject({
			account: 1,
			memory_fact: 1,
			audit_event: expect.any(Number)
		});
		for (const table of ['account', 'ledger_txn', 'task', 'calendar_event', 'memory_fact'])
			expect(await rowCount(id, table), table).toBe(0);
		expect(
			await withUser(t.handle, id, (tx) =>
				tx.select().from(userSetting).where(eq(userSetting.userId, id))
			)
		).toHaveLength(1);
		// Pending jobs of this person are gone too (the queue is shared, so counted by person)
		const jobs = await t.handle.owner.query<{ n: number }>(
			`select count(*)::int as n from job where user_id = '${id}'`
		);
		expect(jobs[0]?.n).toBe(0);
		const rows = await trail(id);
		expect(rows).toHaveLength(1);
		expect(rows[0]).toMatchObject({ action: 'data_reset', entityId: 'everything' });
		expect(await verifyAudit(person(id))).toMatchObject({ ok: true });
		// The person can start again at once
		await createAccount(as(person(id)), { name: 'Cash', kind: 'cash', minBalance: 0 });
		expect(await listAccounts(person(id))).toHaveLength(1);
	});
});

describe('one transaction and one person', () => {
	it('puts everything back when anything fails after the erase', async () => {
		const id = 'user_rst_0001';
		const before = await rowCount(id, 'ledger_txn');
		await fill(id, 'Maya');
		const withFill = await rowCount(id, 'ledger_txn');
		expect(withFill).toBeGreaterThan(before);
		await expect(
			withUser(t.handle, id, async (tx) => {
				await tx.execute(sql`select data_reset(${id}, 'money')`);
				expect(await rowCount(id, 'ledger_txn').catch(() => 0)).toBeDefined();
				throw new Error('something failed after the erase');
			})
		).rejects.toThrow(/something failed/);
		expect(await rowCount(id, 'ledger_txn')).toBe(withFill);
	});

	it("cannot erase another person's data from one's own session", async () => {
		await expect(
			withUser(t.handle, 'user_rst_0001', (tx) =>
				tx.execute(sql`select data_reset('user_rst_0004', 'money')`)
			)
		).rejects.toThrow();
		expect(await rowCount('user_rst_0004', 'account')).toBe(1);
	});

	it('cannot be called with an unknown scope or without a session', async () => {
		await expect(
			withUser(t.handle, 'user_rst_0001', (tx) =>
				tx.execute(sql`select data_reset('user_rst_0001', 'nonsense')`)
			)
		).rejects.toThrow();
		await expect(
			t.handle.db.execute(sql`select data_reset('user_rst_0001', 'money')`)
		).rejects.toThrow();
	});
});
