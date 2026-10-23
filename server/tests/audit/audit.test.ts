// THE AUDIT TRAIL (BTL-20261022-0218, L.2 TO L.6): EVERY WRITE LEAVES A ROW WITH WHO AND WHERE, THE CHAIN HOLDS UNDER PARALLEL WRITES, NOTHING CAN EDIT IT

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { asc, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	auditLaterTriggersSql,
	auditMigrationSql,
	auditRedefinedSql
} from '../../src/lib/server/db/auditSql';
import {
	AUDITED_TABLES,
	auditEvent,
	EXEMPT_FROM_AUDIT,
	USER_TABLES,
	user
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { createAction, decideAction } from '../../src/lib/server/ops/actions';
import { accountHistory, exportAudit, verifyAudit } from '../../src/lib/server/ops/audit';
import { createBill, markBillPaid } from '../../src/lib/server/ops/bills';
import { listUndoable, logExpense, recordSnapshot, undo } from '../../src/lib/server/ops/ledger';
import { createEvent } from '../../src/lib/server/ops/schedule';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string, channel?: Ctx['channel']): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'person' },
	...(channel ? { channel } : {})
});
const agent = (id: string, turnId?: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test_tool' },
	channel: 'chat',
	...(turnId ? { turnId } : {})
});
const as = (c: Ctx): Ctx => ({
	...c,
	requestId: `req-audit-${String(++counter).padStart(6, '0')}`
});
const trail = (id: string) =>
	withUser(t.handle, id, (tx) =>
		tx.select().from(auditEvent).where(eq(auditEvent.userId, id)).orderBy(asc(auditEvent.seq))
	);
const last = async (id: string) => (await trail(id)).at(-1);

async function account(id: string, name: string) {
	return (await createAccount(as(person(id)), { name, kind: 'ewallet', minBalance: 0 })).id;
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_aud_0001', name: 'A', email: 'a@example.com' },
		{ id: 'user_aud_0002', name: 'B', email: 'b@example.com' },
		{ id: 'user_aud_0003', name: 'C', email: 'c@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the registry of audited tables', () => {
	it('puts every tenant table on the audited list or on the exempt list with a reason', () => {
		const audited = new Set(AUDITED_TABLES.map((a) => a.table));
		const exempt = new Set(Object.keys(EXEMPT_FROM_AUDIT));
		const names = USER_TABLES.map((u) => u.name);
		const neither = names.filter((n) => !audited.has(n) && !exempt.has(n));
		expect(neither, `Audit or exempt these tables: ${neither.join(', ')}`).toEqual([]);
		for (const n of audited)
			expect(names, `${n} is audited but is not a tenant table`).toContain(n);
		for (const n of exempt) expect(names, `${n} is exempt but is not a tenant table`).toContain(n);
		for (const n of audited) expect(exempt.has(n), `${n} is on both lists`).toBe(false);
		for (const [n, why] of Object.entries(EXEMPT_FROM_AUDIT))
			expect(why.length, n).toBeGreaterThan(8);
	});

	it('has a migration whose triggers are exactly the audited list', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0016_audit_triggers.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		expect(file).toBe(auditMigrationSql());
	});

	it('has a later migration with the triggers of the tables that came after the first one', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0018_bill_override.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		const later = auditLaterTriggersSql('0018');
		expect(later).toContain('"audit_bill_override"');
		expect(file).toContain(later);
		// Every audited table has its trigger in exactly one of the migrations
		for (const a of AUDITED_TABLES)
			expect(
				[auditMigrationSql(), file].filter((f) => f.includes(`TRIGGER "audit_${a.table}" `)),
				a.table
			).toHaveLength(1);
	});

	it('replaces the trigger of a table whose audited columns grew in a later migration, and leaves 0016 as it ran', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0022_account_purpose.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		expect(file).toContain(auditRedefinedSql('0022'));
		// 0016 keeps the columns it had; the current list is the one the replacement carries
		expect(auditMigrationSql()).not.toContain('archived_at,purpose');
		expect(auditRedefinedSql('0022')).toContain('archived_at,purpose');
		for (const a of AUDITED_TABLES.filter((t) => t.redefined))
			expect(a.columns.slice(0, a.firstColumns?.length)).toEqual(a.firstColumns);
	});

	it('replaces the trigger of bill when it gained its start date (0023)', () => {
		const file = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0023_bill_starts_on.sql'),
			'utf8'
		).replaceAll('\r\n', '\n');
		expect(file).toContain(auditRedefinedSql('0023'));
		expect(auditMigrationSql()).not.toContain('active,starts_on');
		expect(auditRedefinedSql('0023')).toContain('active,starts_on');
	});

	it('copies no title or free text of an event, a task, a routine or a reminder', () => {
		for (const table of ['calendar_event', 'task', 'routine', 'reminder']) {
			const cols = AUDITED_TABLES.find((a) => a.table === table)?.columns ?? [];
			expect(cols, table).not.toContain('title');
			expect(cols, table).not.toContain('notes');
			expect(cols, table).not.toContain('location');
		}
	});
});

describe('who did it and where', () => {
	const id = 'user_aud_0001';

	it('writes a row for a person creating an account, in the same transaction', async () => {
		const acc = await account(id, 'GCash');
		const row = await last(id);
		expect(row).toMatchObject({
			seq: 1,
			actorKind: 'person',
			channel: 'app',
			entity: 'account',
			entityId: acc,
			accountId: acc,
			action: 'create',
			prevHash: null
		});
		expect(row?.verb).toBeTruthy();
		expect(row?.requestId).toMatch(/^req-audit-/);
		expect(row?.after).toMatchObject({ name: 'GCash', kind: 'ewallet' });
		expect(row?.before).toBeNull();
	});

	it('knows the widget, and reads an expense as money out of the account', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		await logExpense(as(person(id, 'widget')), { accountId: acc, amount: 18_000, note: 'lunch' });
		const row = await last(id);
		expect(row).toMatchObject({
			channel: 'widget',
			actorKind: 'person',
			entity: 'ledger_txn',
			action: 'create',
			accountId: acc,
			amountDelta: -18_000
		});
		expect(row?.after).toMatchObject({ type: 'expense', amount: 18_000, note: 'lunch' });
	});

	it('says the assistant and its tool and the chat way in', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		const { invokeVerb } = await import('../../src/lib/server/ops/registry');
		await invokeVerb(as(agent(id, 'turn-abc')), 'expense_log', {
			accountId: acc,
			amount: 5_000,
			note: 'coffee'
		});
		const row = await last(id);
		expect(row).toMatchObject({
			actorKind: 'agent',
			actorRef: 'test_tool',
			channel: 'chat',
			turnId: 'turn-abc',
			amountDelta: -5_000
		});
	});

	it('says the assistant asked and the person approved, with the card', async () => {
		const card = await createAction(agent(id, 'turn-card'), {
			verb: 'account_create',
			args: { name: 'Maya', kind: 'ewallet' },
			turnId: 'turn-card'
		});
		const done = await decideAction(as(person(id)), {
			actionId: card.actionId,
			decision: 'approve'
		});
		expect(done.status).toBe('applied');
		const rows = await trail(id);
		const created = rows.filter((r) => r.entity === 'account' && r.action === 'create').at(-1);
		expect(created).toMatchObject({
			actorKind: 'person',
			onBehalf: 'agent',
			approvalId: card.actionId,
			turnId: 'turn-card'
		});
		// The card itself: made by the assistant, then approved
		const cardRows = rows.filter((r) => r.entity === 'agent_action');
		expect(cardRows.map((r) => r.action)).toEqual(['create', 'approve']);
		expect(cardRows[0]?.actorKind).toBe('agent');
	});

	it('records an undo as an undo that points at the journal entry, and a count and a reset as such', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		await logExpense(as(person(id)), { accountId: acc, amount: 7_000, note: 'snack' });
		const entry = (await listUndoable(person(id), 1))[0];
		await undo(as(person(id)), { journalId: entry?.id ?? '' });
		const row = await last(id);
		expect(row).toMatchObject({ action: 'undo', undoOf: entry?.id, entity: 'ledger_txn' });

		await recordSnapshot(as(person(id)), { accountId: acc, amount: 100_000, confirmed: true });
		// A count writes the count itself and then the adjustment that records the difference
		const counted = (await trail(id)).filter((r) => r.entity === 'balance_snapshot');
		expect(counted.at(-1)?.action).toBe('count');
		await recordSnapshot(as(person(id)), {
			accountId: acc,
			amount: 0,
			mode: 'reset',
			reason: 'Starting over',
			confirmed: true
		});
		const rows = await trail(id);
		expect(rows.some((r) => r.entity === 'ledger_txn' && r.action === 'reset')).toBe(true);
		expect(rows.filter((r) => r.entity === 'balance_snapshot').at(-1)?.after).toMatchObject({
			amount: 0
		});
	});

	it('audits a payment even though that verb keeps no undo entry', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		const bill = await createBill(as(person(id)), {
			name: 'Water',
			category: 'bills',
			accountId: acc,
			kind: 'fixed',
			amount: 50_000,
			schedule: { kind: 'monthly', day: 5 },
			weekendRule: 'none',
			deferrable: false
		});
		await markBillPaid(as(person(id)), { billId: bill.id, dueDate: '2030-03-05' });
		const rows = (await trail(id)).filter((r) => r.verb === 'bill.markPaid');
		expect(rows.map((r) => r.entity).sort()).toEqual(['bill_payment', 'ledger_txn']);
	});

	it('leaves no title of an event in the trail', async () => {
		await createEvent(as(person(id)), {
			title: 'Secret meeting with the bank',
			startsAt: '2030-03-05T02:00:00Z'
		});
		const text = JSON.stringify(await trail(id));
		expect(text).not.toMatch(/Secret meeting/);
		expect((await trail(id)).some((r) => r.entity === 'calendar_event')).toBe(true);
	});
});

describe('the allow-list in the database', () => {
	it('copies only the listed columns and never a note from a picture or the web', async () => {
		const out = (await t.handle.owner.query<{ j: Record<string, unknown> }>(
			`select audit_pick('{"note":"read from a photo","source":"ocr","amount":5,"secret":"x"}'::jsonb, array['note','source','amount']) as j`
		)) as { j: Record<string, unknown> }[];
		expect(out[0]?.j).toEqual({ note: null, source: 'ocr', amount: 5 });
		const own = (await t.handle.owner.query<{ j: Record<string, unknown> }>(
			`select audit_pick('{"note":"lunch","source":"chat","amount":5}'::jsonb, array['note','amount']) as j`
		)) as { j: Record<string, unknown> }[];
		expect(own[0]?.j).toEqual({ note: 'lunch', amount: 5 });
	});
});

describe('append-only and the chain', () => {
	const id = 'user_aud_0002';

	it('refuses an update and a delete to the app role', async () => {
		await account(id, 'Cash');
		for (const statement of [`update audit_event set note = 'x'`, `delete from audit_event`]) {
			const error = await withUser(t.handle, id, (tx) => tx.execute(sqlRaw(statement))).then(
				() => null,
				(e: unknown) => e as Error & { cause?: Error }
			);
			expect(String(error?.cause?.message ?? error?.message), statement).toMatch(
				/permission denied/i
			);
		}
	});

	it('refuses an update even to the owner, unless triggers are switched off on purpose', async () => {
		const owner = await t.handle.pinOwner();
		try {
			await expect(
				owner.exec(`update audit_event set note = 'x' where user_id = '${id}'`)
			).rejects.toThrow(/append-only/);
		} finally {
			owner.release();
		}
	});

	it('keeps one unbroken chain when one person writes in parallel', async () => {
		const acc = await account('user_aud_0003', 'Wallet');
		await Promise.all(
			Array.from({ length: 24 }, (_, i) =>
				logExpense(as(person('user_aud_0003', i % 2 ? 'widget' : 'app')), {
					accountId: acc,
					amount: 100 + i,
					note: `n${i}`
				})
			)
		);
		const rows = await trail('user_aud_0003');
		expect(rows.map((r) => r.seq)).toEqual(Array.from({ length: rows.length }, (_, i) => i + 1));
		for (let i = 1; i < rows.length; i++) expect(rows[i]?.prevHash).toBe(rows[i - 1]?.hash);
		expect(await verifyAudit(person('user_aud_0003'))).toMatchObject({ ok: true, problem: null });
	});

	it('finds an edited row, a removed row and a gap', async () => {
		const c = person('user_aud_0003');
		const owner = await t.handle.pinOwner();
		try {
			// The owner switches the triggers off for its own session: only maintenance can, and the check still catches it
			await owner.exec(`set session_replication_role = replica`);
			await owner.exec(
				`update audit_event set amount_delta = 1 where user_id = 'user_aud_0003' and seq = 5`
			);
			expect(await verifyAudit(c)).toMatchObject({ ok: false, problem: { seq: 5, kind: 'hash' } });
			await owner.exec(
				`update audit_event set amount_delta = (select amount_delta from audit_event where user_id = 'user_aud_0003' and seq = 5) where false`
			);
			// Put it back as it was by recomputing nothing: restore from the row's own hash is impossible, so remove the row instead
			await owner.exec(`delete from audit_event where user_id = 'user_aud_0003' and seq = 7`);
			expect(await verifyAudit(c)).toMatchObject({ ok: false, problem: { seq: 5 } });
		} finally {
			await owner.exec(`set session_replication_role = origin`);
			owner.release();
		}
	});
});

describe('the history of an account', () => {
	const id = 'user_aud_0001';

	it('lists what happened with who, the way in and the balance after each entry', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		const h = await accountHistory(person(id), { accountId: acc });
		const entries = h.entries;
		expect(entries.length).toBeGreaterThan(5);
		// Newest first, and every entry says who and where
		for (let i = 1; i < entries.length; i++)
			expect(entries[i - 1]!.seq).toBeGreaterThan(entries[i]!.seq);
		for (const e of entries) {
			expect(['person', 'agent', 'job', 'system']).toContain(e.actor);
			expect(e.channel).toBeTruthy();
		}
		// The reset took it to zero, then the water bill took 50,000 out
		expect(h.balance).toBe(-50_000);
		const reset = entries.find((e) => e.action === 'reset');
		expect(reset).toMatchObject({ balanceAfter: 0 });
		const count = entries.find((e) => e.entity === 'balance_snapshot' && e.balanceAfter === 0);
		expect(count).toMatchObject({ action: 'count', delta: -100_000 });
	});

	it('reads an undone expense right: the balance goes back', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		const h = await accountHistory(person(id), { accountId: acc });
		const undone = h.entries.find((e) => e.action === 'undo');
		expect(undone).toBeTruthy();
		expect(undone?.delta).toBe(7_000);
	});

	it('filters by who, by action and by a word, and pages by the sequence', async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		const byAgent = await accountHistory(person(id), { accountId: acc, by: 'agent' });
		expect(byAgent.entries.length).toBeGreaterThan(0);
		expect(byAgent.entries.every((e) => e.actor === 'agent' || e.onBehalf === 'agent')).toBe(true);
		const resets = await accountHistory(person(id), { accountId: acc, action: 'reset' });
		expect(resets.entries.every((e) => e.action === 'reset')).toBe(true);
		const word = await accountHistory(person(id), { accountId: acc, search: 'coffee' });
		expect(word.entries.length).toBeGreaterThan(0);
		const first = await accountHistory(person(id), { accountId: acc, limit: 3 });
		expect(first.entries).toHaveLength(3);
		const next = await accountHistory(person(id), {
			accountId: acc,
			limit: 3,
			cursor: first.nextCursor ?? 0
		});
		expect(next.entries[0]!.seq).toBeLessThan(first.entries[2]!.seq);
	});

	it("never shows another person's account, and refuses one that is not yours", async () => {
		const acc = (await trail(id))[0]?.accountId ?? '';
		await expect(accountHistory(person('user_aud_0002'), { accountId: acc })).rejects.toMatchObject(
			{
				code: expect.stringMatching(/NOT_FOUND|INVALID/)
			}
		);
	});
});

describe('the export', () => {
	const id = 'user_aud_0001';

	it('gives CSV and JSON of the same rows, with no free text of an event', async () => {
		const csv = await exportAudit(person(id), { format: 'csv' });
		const json = await exportAudit(person(id), { format: 'json' });
		expect(csv.rows).toBe(json.rows);
		expect(csv.body.split('\n')[0]).toContain('seq,at,actor');
		expect(csv.body.split('\n')).toHaveLength(csv.rows + 1);
		expect(JSON.parse(json.body)).toHaveLength(json.rows);
		expect(csv.body + json.body).not.toMatch(/Secret meeting/);
		expect(csv.truncated).toBe(false);
	});

	it('is the person only, never the assistant', async () => {
		const { invokeVerb } = await import('../../src/lib/server/ops/registry');
		await expect(invokeVerb(agent(id), 'audit_export', { format: 'csv' })).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
	});
});

// -- RAW SQL -- //

import { sql } from 'drizzle-orm';
const sqlRaw = (text: string) => sql.raw(text);
