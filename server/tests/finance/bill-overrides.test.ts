// CHANGES TO ONE DUE DATE OF A BILL AGAINST A REAL (THROWAWAY) DATABASE (BTL-20261022-0650): MOVE, SKIP, ANOTHER AMOUNT OR ACCOUNT, PAYING, THE AGENT, UNDO AND RESET
// Each group uses its own person, so the groups do not depend on each other.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { asc, eq, sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { auditEvent, billOverride, ledgerTxn, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { calendarRange } from '../../src/lib/server/ops/calendarRange';
import {
	createBill,
	listDueBills,
	markBillPaid,
	resetBillOccurrence,
	updateBill,
	updateBillOccurrence
} from '../../src/lib/server/ops/bills';
import { listUndoable, undo } from '../../src/lib/server/ops/ledger';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const PEOPLE = [
	'move',
	'pay',
	'skip',
	'agent',
	'series',
	'undo',
	'wall',
	'reset',
	'calendar',
	'edge',
	'paidmove'
].map((k, i) => ({
	key: k,
	id: `user_ovr_${String(i + 1).padStart(4, '0')}`
}));

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const rid = () => `req-ovr-${String(++counter).padStart(6, '0')}`;
const person = (userId: string): Ctx => ({ handle: t.handle, actor: { userId, kind: 'person' } });
const agent = (userId: string): Ctx => ({
	handle: t.handle,
	actor: { userId, kind: 'agent', tool: 'test_tool' },
	channel: 'chat'
});
const as = (base: Ctx): Ctx => ({ ...base, requestId: rid() });
const idOf = (key: string) => PEOPLE.find((p) => p.key === key)?.id ?? '';

const overridesOf = (id: string) =>
	withUser(t.handle, id, (tx) => tx.select().from(billOverride).where(eq(billOverride.userId, id)));
const trail = (id: string) =>
	withUser(t.handle, id, (tx) =>
		tx.select().from(auditEvent).where(eq(auditEvent.userId, id)).orderBy(asc(auditEvent.seq))
	);

/** A person with two accounts and a way to add a bill due on the 10th of every month. */
async function household(id: string) {
	const a = (await createAccount(as(person(id)), { name: 'RCBC', kind: 'bank', minBalance: 0 })).id;
	const b = (await createAccount(as(person(id)), { name: 'GCash', kind: 'ewallet', minBalance: 0 }))
		.id;
	const monthly = (name: string, extra: Record<string, unknown> = {}) =>
		createBill(as(person(id)), {
			name,
			category: 'bills',
			accountId: a,
			kind: 'fixed',
			amount: 10_000,
			schedule: { kind: 'monthly', day: 10 },
			weekendRule: 'none',
			deferrable: false,
			...extra
		} as Parameters<typeof createBill>[1]);
	const due = (from: string, to: string) => listDueBills(person(id), from, to);
	return { a, b, monthly, due };
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values(PEOPLE.map((p) => ({ id: p.id, name: p.key, email: `${p.key}-ovr@example.com` })));
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('moving one date', () => {
	const id = idOf('move');
	let h: Awaited<ReturnType<typeof household>>;
	let billId = '';

	beforeAll(async () => {
		h = await household(id);
		billId = (await h.monthly('Meralco')).id;
	});

	it('moves one date and leaves the series alone', async () => {
		const r = await updateBillOccurrence(as(person(id)), {
			billId,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-14'
		});
		expect(r.override).toMatchObject({ originalDueDate: '2026-11-10', newDueDate: '2026-11-14' });
		const list = await h.due('2026-11-01', '2026-12-31');
		expect(list.map((d) => [d.dueDate, d.originalDueDate, d.overridden])).toEqual([
			['2026-11-14', '2026-11-10', true],
			['2026-12-10', '2026-12-10', false]
		]);
	});

	it('shows a moved date in a range its old day is outside of, and not in one it left', async () => {
		expect((await h.due('2026-11-12', '2026-11-30')).map((d) => d.dueDate)).toEqual(['2026-11-14']);
		expect(await h.due('2026-11-01', '2026-11-12')).toEqual([]);
	});

	it('merges a later change into the same date and removes the override when nothing is left', async () => {
		const r = await updateBillOccurrence(as(person(id)), {
			billId,
			dueDate: '2026-11-14',
			amount: 7_500
		});
		expect(r.override).toMatchObject({ newDueDate: '2026-11-14', amount: 7_500, version: 2 });
		const cleared = await updateBillOccurrence(as(person(id)), {
			billId,
			dueDate: '2026-11-14',
			newDueDate: null,
			amount: null
		});
		expect(cleared.override).toBeNull();
		expect(await overridesOf(id)).toHaveLength(0);
	});

	it('refuses a move of more than a month, onto another date of the bill, or a stale version', async () => {
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId,
				dueDate: '2026-11-10',
				newDueDate: '2026-12-20'
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId,
				dueDate: '2026-11-10',
				newDueDate: '2026-12-10'
			})
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await updateBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-10', amount: 5_000 });
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId,
				dueDate: '2026-11-10',
				amount: 6_000,
				expectVersion: 9
			})
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await expect(
			updateBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-11', amount: 6_000 })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('moving a date onto its own schedule day is the same as not moving it', async () => {
		const r = await updateBillOccurrence(as(person(id)), {
			billId,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-10'
		});
		expect(r.override).toMatchObject({ newDueDate: null, amount: 5_000 });
	});

	it('answers a replay with the first result, and refuses the same id for another request', async () => {
		const ctx = as(person(id));
		const first = await updateBillOccurrence(ctx, { billId, dueDate: '2026-12-10', amount: 4_000 });
		const again = await updateBillOccurrence(ctx, { billId, dueDate: '2026-12-10', amount: 4_000 });
		expect(again).toEqual(first);
		await expect(
			updateBillOccurrence(ctx, { billId, dueDate: '2026-12-10', amount: 4_100 })
		).rejects.toMatchObject({ code: 'CONFLICT' });
	});
});

describe('paying a changed date', () => {
	const id = idOf('pay');
	let h: Awaited<ReturnType<typeof household>>;

	beforeAll(async () => {
		h = await household(id);
	});

	it('pays a moved date by the day it has now or the day the schedule gave, with its own amount and account', async () => {
		const a = await h.monthly('Water');
		await updateBillOccurrence(as(person(id)), {
			billId: a.id,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-14',
			amount: 6_000,
			accountId: h.b
		});
		const paid = await markBillPaid(as(person(id)), { billId: a.id, dueDate: '2026-11-14' });
		expect(paid.amount).toBe(6_000);
		const [txn] = await withUser(t.handle, id, (tx) =>
			tx.select().from(ledgerTxn).where(eq(ledgerTxn.id, paid.txnId))
		);
		expect(txn).toMatchObject({ accountId: h.b, amount: 6_000 });
		const nov = (await h.due('2026-11-01', '2026-11-30')).find((d) => d.billId === a.id);
		expect(nov).toMatchObject({ dueDate: '2026-11-14', paid: true });

		const b = await h.monthly('Internet');
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-13'
		});
		// The schedule's own day finds the moved date too
		expect(
			await markBillPaid(as(person(id)), { billId: b.id, dueDate: '2026-11-10' })
		).toMatchObject({ amount: 10_000 });
	});

	it('refuses to change or reset a date that is paid, and a move onto a paid stretch', async () => {
		const [water] = (await h.due('2026-11-01', '2026-11-30')).filter((d) => d.name === 'Water');
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId: water?.billId ?? '',
				dueDate: '2026-11-14',
				newDueDate: '2026-11-20'
			})
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await expect(
			resetBillOccurrence(as(person(id)), { billId: water?.billId ?? '', dueDate: '2026-11-14' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		const c = await h.monthly('Phone');
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId: c.id,
				dueDate: '2026-12-10',
				newDueDate: '2026-11-14'
			})
		).resolves.toBeTruthy();
	});

	it('falls back to the bill account when the account of a date was archived since', async () => {
		const d = await h.monthly('Cable');
		await updateBillOccurrence(as(person(id)), {
			billId: d.id,
			dueDate: '2026-12-10',
			accountId: h.b
		});
		await t.handle.owner.exec(`update account set archived_at = now() where id = '${h.b}'`);
		const paid = await markBillPaid(as(person(id)), { billId: d.id, dueDate: '2026-12-10' });
		const [txn] = await withUser(t.handle, id, (tx) =>
			tx.select().from(ledgerTxn).where(eq(ledgerTxn.id, paid.txnId))
		);
		expect(txn?.accountId).toBe(h.a);
	});
});

describe('skipping a date', () => {
	const id = idOf('skip');
	let h: Awaited<ReturnType<typeof household>>;
	let billId = '';

	beforeAll(async () => {
		h = await household(id);
		billId = (await h.monthly('Gym')).id;
	});

	it('hides a skipped date, brings it back on reset, and refuses a skip that also changes it', async () => {
		await updateBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-10', skipped: true });
		expect((await h.due('2026-11-01', '2026-12-31')).map((d) => d.dueDate)).toEqual(['2026-12-10']);
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId,
				dueDate: '2026-12-10',
				skipped: true,
				amount: 1_000
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		// A skipped date can still be found to un-skip it
		await updateBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-10', skipped: false });
		expect((await h.due('2026-11-01', '2026-11-30')).map((d) => d.dueDate)).toEqual(['2026-11-10']);
		await updateBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-10', skipped: true });
		const r = await resetBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-10' });
		expect(r).toMatchObject({ reset: true, originalDueDate: '2026-11-10' });
		expect((await h.due('2026-11-01', '2026-11-30')).map((d) => d.dueDate)).toEqual(['2026-11-10']);
		// Nothing left to reset is not an error
		expect(
			await resetBillOccurrence(as(person(id)), { billId, dueDate: '2026-11-10' })
		).toMatchObject({
			reset: false
		});
	});
});

describe('the other readers of a date', () => {
	const id = idOf('calendar');

	it('puts a moved bill on its new day in the calendar, and a skipped one nowhere', async () => {
		const h = await household(id);
		const moved = await h.monthly('Moved');
		const gone = await h.monthly('Gone');
		await updateBillOccurrence(as(person(id)), {
			billId: moved.id,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-14'
		});
		await updateBillOccurrence(as(person(id)), {
			billId: gone.id,
			dueDate: '2026-11-10',
			skipped: true
		});
		const r = await calendarRange(person(id), {
			from: '2026-11-01',
			to: '2026-11-30',
			layers: ['bills']
		});
		const bills = r.items.filter((x) => x.type === 'bill');
		expect(bills.map((x) => [x.title, x.date])).toEqual([['Moved', '2026-11-14']]);
	});
});

describe('the assistant', () => {
	const id = idOf('agent');
	let h: Awaited<ReturnType<typeof household>>;
	let fixed = '';
	let varying = '';

	beforeAll(async () => {
		h = await household(id);
		fixed = (await h.monthly('Rent')).id;
		varying = (await h.monthly('Electric', { kind: 'variable', amount: 9_000 })).id;
	});

	it('moves, re-accounts and skips a date at once, and the trail names it', async () => {
		await invokeVerb(as(agent(id)), 'bill_occurrence_update', {
			billId: fixed,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-12',
			accountId: h.b
		});
		const last = (await trail(id)).filter((e) => e.entity === 'bill_override').at(-1);
		expect(last).toMatchObject({ actorKind: 'agent', actorRef: 'test_tool', action: 'create' });
		expect(last?.verb).toBe('bill.occurrenceUpdate');
		expect(last?.after).toMatchObject({ new_due_date: '2026-11-12', account_id: h.b });
		await invokeVerb(as(agent(id)), 'bill_occurrence_reset', {
			billId: fixed,
			dueDate: '2026-11-12'
		});
		expect(await overridesOf(id)).toHaveLength(0);
	});

	it('cannot set an amount on a bill whose amount varies, through the verb or the registry', async () => {
		await expect(
			updateBillOccurrence(as(agent(id)), { billId: varying, dueDate: '2026-11-10', amount: 1_000 })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await expect(
			invokeVerb(as(agent(id)), 'bill_occurrence_update', {
				billId: varying,
				dueDate: '2026-11-10',
				amount: 1_000
			})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		// The person can, and the agent can still move that bill's date
		await updateBillOccurrence(as(person(id)), {
			billId: varying,
			dueDate: '2026-11-10',
			amount: 1_000
		});
		await invokeVerb(as(agent(id)), 'bill_occurrence_update', {
			billId: varying,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-11'
		});
		expect(
			(await h.due('2026-11-01', '2026-11-30')).find((d) => d.billId === varying)
		).toMatchObject({ dueDate: '2026-11-11', amount: 1_000 });
	});

	it('takes only a bill, a date and what changes: a person or tenant field is refused', async () => {
		await expect(
			invokeVerb(as(agent(id)), 'bill_occurrence_update', {
				billId: fixed,
				dueDate: '2026-11-10',
				userId: 'someone-else',
				amount: 1_000
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		expect((await overridesOf(id)).every((o) => o.userId === id)).toBe(true);
	});
});

describe('changing the whole series', () => {
	const id = idOf('series');
	let h: Awaited<ReturnType<typeof household>>;
	let billId = '';

	beforeAll(async () => {
		h = await household(id);
		billId = (await h.monthly('Insurance')).id;
		// Far in the future, so the dates are always "from today on"
		await updateBillOccurrence(as(person(id)), {
			billId,
			dueDate: '2099-11-10',
			newDueDate: '2099-11-14'
		});
		await updateBillOccurrence(as(person(id)), { billId, dueDate: '2099-12-10', amount: 5_000 });
		await updateBillOccurrence(as(person(id)), { billId, dueDate: '2100-01-10', skipped: true });
	});

	it('a new amount drops the per-date amounts and keeps moves and skips', async () => {
		const r = await updateBill(as(person(id)), { billId, amount: 12_000 });
		expect(r.clearedOverrides).toBe(1);
		const left = await overridesOf(id);
		expect(left.map((o) => o.originalDueDate).sort()).toEqual(['2099-11-10', '2100-01-10']);
	});

	it('a new schedule or weekend rule drops every override from today on, and a plain edit drops none', async () => {
		expect(
			(await updateBill(as(person(id)), { billId, name: 'Insurance plan' })).clearedOverrides
		).toBe(0);
		const r = await updateBill(as(person(id)), {
			billId,
			schedule: { kind: 'monthly', day: 12 }
		});
		expect(r.clearedOverrides).toBe(2);
		expect(await overridesOf(id)).toHaveLength(0);
	});
});

describe('two dates that could claim one day', () => {
	const id = idOf('edge');

	it('refuses a move onto a skipped date, and answers a day with the date due on it now', async () => {
		const h = await household(id);
		const b = await h.monthly('Loan');
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-12-10',
			skipped: true
		});
		// The skipped date still holds its own day
		await expect(
			updateBillOccurrence(as(person(id)), {
				billId: b.id,
				dueDate: '2026-11-10',
				newDueDate: '2026-12-10'
			})
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-12-10',
			skipped: false
		});
		// November moves away, December moves onto November's old day
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-11-10',
			newDueDate: '2026-11-20'
		});
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-12-10',
			newDueDate: '2026-11-10'
		});
		// "The 10th of November" now means the one due on it: December's
		const r = await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-11-10',
			amount: 2_000
		});
		expect(r.override).toMatchObject({ originalDueDate: '2026-12-10', amount: 2_000 });
		// Putting November back on its own day would double up with December, so it is refused until December moves
		await expect(
			resetBillOccurrence(as(person(id)), { billId: b.id, dueDate: '2026-11-20' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
	});
});

describe('a moved date that was paid', () => {
	const id = idOf('paidmove');

	it('keeps its change when the series is edited or the change is undone', async () => {
		const h = await household(id);
		const b = await h.monthly('Tax');
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2099-11-10',
			newDueDate: '2099-11-14'
		});
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2099-12-10',
			newDueDate: '2099-12-14'
		});
		await markBillPaid(as(person(id)), { billId: b.id, dueDate: '2099-11-14' });
		// A new rule drops the December change but not the paid one
		const r = await updateBill(as(person(id)), {
			billId: b.id,
			schedule: { kind: 'monthly', day: 12 }
		});
		expect(r.clearedOverrides).toBe(1);
		expect((await overridesOf(id)).map((o) => o.originalDueDate)).toEqual(['2099-11-10']);
		// Undoing the move of a paid date is refused
		const entry = (await listUndoable(person(id))).find(
			(u) =>
				u.entity === 'bill_override' &&
				(u.after as { originalDueDate?: string } | null)?.originalDueDate === '2099-11-10'
		);
		expect(entry).toBeTruthy();
		await expect(undo(as(person(id)), { journalId: entry?.id ?? '' })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		expect(await overridesOf(id)).toHaveLength(1);
	});
});

describe('undo', () => {
	const id = idOf('undo');

	it('removes the override a change created, and refuses to undo an edit of an existing one', async () => {
		const h = await household(id);
		const b = await h.monthly('Tuition');
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-11-10',
			amount: 3_000
		});
		const entries = await listUndoable(person(id));
		const entry = entries.find((u) => u.entity === 'bill_override');
		expect(entry).toBeTruthy();
		await undo(as(person(id)), { journalId: entry?.id ?? '' });
		expect(await overridesOf(id)).toHaveLength(0);
	});
});

describe('one person cannot reach another', () => {
	const mine = idOf('wall');
	const other = idOf('reset');

	it('hides and refuses a bill that belongs to someone else', async () => {
		const h = await household(mine);
		const b = await h.monthly('Mine');
		await updateBillOccurrence(as(person(mine)), {
			billId: b.id,
			dueDate: '2026-11-10',
			amount: 1_000
		});
		await expect(
			updateBillOccurrence(as(person(other)), { billId: b.id, dueDate: '2026-11-10', amount: 1 })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await expect(
			resetBillOccurrence(as(person(other)), { billId: b.id, dueDate: '2026-11-10' })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		expect(await overridesOf(other)).toHaveLength(0);
		// The database itself hides the row, whatever the query says
		const seen = await withUser(t.handle, other, (tx) =>
			tx.select().from(billOverride).where(eq(billOverride.billId, b.id))
		);
		expect(seen).toHaveLength(0);
	});
});

describe('erasing the money data', () => {
	const id = idOf('reset');

	it('removes the overrides with the bills and counts them', async () => {
		const h = await household(id);
		const b = await h.monthly('Loan');
		await updateBillOccurrence(as(person(id)), {
			billId: b.id,
			dueDate: '2026-11-10',
			amount: 1_000
		});
		const counts = await withUser(t.handle, id, async (tx) => {
			const r = (await tx.execute(sql`select data_reset(${id}, 'money') as counts`)) as unknown as {
				rows: { counts: Record<string, number> }[];
			};
			return r.rows[0]?.counts ?? {};
		});
		expect(counts.bill_override).toBe(1);
		expect(counts.bill).toBe(1);
		expect(await overridesOf(id)).toHaveLength(0);
	});
});
