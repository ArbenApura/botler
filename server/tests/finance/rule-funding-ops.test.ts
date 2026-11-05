// A RULE THAT SAVES FOR A BILL (BTL-20261029-0119): LINKING AND UNLINKING WITH rule_propose AND rule_update, EVERY REFUSAL, A PARTIAL UPDATE THAT
// NEVER CLEARS THE OTHER FIELD, THE AUDIT TRAIL, AND A BILL EDIT OR DELETE THAT CLEARS A LINK AND SAYS SO. RUN AS app_runtime IN THE TENANT CONTEXT.

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, asc, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { toLocalDate } from '../../src/lib/finance/dates';
import { allocationRule, auditEvent } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createBill, deleteBill, markBillPaid, updateBill } from '../../src/lib/server/ops/bills';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { approveRule, proposeRule, retireRule } from '../../src/lib/server/ops/rules';
import { seedPerson } from '../agent/support';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let rids = 0;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

const w = (who: Fixture) => ({
	...who.ctx,
	requestId: `rf-req-${String(++rids).padStart(8, '0')}`
});
const agentOf = (who: Fixture) => ({
	...w(who),
	actor: { userId: who.userId, kind: 'agent' as const }
});

/** A weekly bill paid from GCash, and an approved fixed rule into GCash. */
async function setup(f: Fixture) {
	const b = await createBill(w(f), {
		name: 'WiFi',
		category: 'bills',
		accountId: f.gcash,
		kind: 'fixed',
		amount: 150_000,
		schedule: { kind: 'monthly', day: 4 },
		weekendRule: 'none',
		deferrable: false
	});
	const r = await proposeRule(w(f), {
		label: 'Internet',
		mode: 'fixed',
		amount: 40_000,
		targetAccountId: f.gcash
	});
	await approveRule(w(f), { ruleId: r.id });
	return { billId: b.id, ruleId: r.id };
}

const ruleOf = async (f: Fixture, ruleId: string) =>
	(
		await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(allocationRule).where(eq(allocationRule.id, ruleId))
		)
	)[0];

// -- TESTS -- //

describe('linking a rule to a bill', () => {
	it('links with rule_update, keeps the label, unlinks with null, and names the bill in the summary', async () => {
		const f = await seedPerson(t);
		const { billId, ruleId } = await setup(f);
		const linked = (await invokeVerb(agentOf(f), 'rule_update', {
			ruleId,
			fundsBillId: billId
		})) as { fundsBillId: string; label: string; summary: string; fundsBillName: string };
		expect(linked).toMatchObject({ fundsBillId: billId, label: 'Internet', fundsBillName: 'WiFi' });
		expect(linked.summary).toMatch(/It saves for WiFi\.$/);
		// A label change leaves the link, a link change leaves the label
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, label: 'Net' });
		expect(await ruleOf(f, ruleId)).toMatchObject({ label: 'Net', fundsBillId: billId });
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, fundsBillId: null });
		expect(await ruleOf(f, ruleId)).toMatchObject({ label: 'Net', fundsBillId: null });
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, label: null });
		expect(await ruleOf(f, ruleId)).toMatchObject({ label: null, fundsBillId: null });
		await expect(invokeVerb(agentOf(f), 'rule_update', { ruleId })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('records the link in the audit trail with the agent as actor', async () => {
		const f = await seedPerson(t);
		const { billId, ruleId } = await setup(f);
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, fundsBillId: billId });
		const events = await withUser(t.handle, f.userId, (tx) =>
			tx
				.select()
				.from(auditEvent)
				.where(and(eq(auditEvent.userId, f.userId), eq(auditEvent.entity, 'allocation_rule')))
				.orderBy(asc(auditEvent.seq))
		);
		const last = events.at(-1);
		expect(last?.actorKind).toBe('agent');
		expect((last?.before as Record<string, unknown>).funds_bill_id).toBeNull();
		expect((last?.after as Record<string, unknown>).funds_bill_id).toBe(billId);
	});

	it('links when proposing, and numbers a new rule after the ones waiting for approval', async () => {
		const f = await seedPerson(t);
		const { billId } = await setup(f);
		const a = await proposeRule(w(f), {
			mode: 'fixed',
			amount: 10_000,
			targetAccountId: f.gcash,
			fundsBillId: billId
		});
		const b = await proposeRule(w(f), { mode: 'fixed', amount: 10_000, targetAccountId: f.rcbc });
		expect(a.fundsBillId).toBe(billId);
		expect(b.position).toBe(a.position + 1);
	});

	it('refuses every link that could not count, with the reason', async () => {
		const f = await seedPerson(t);
		const { billId, ruleId } = await setup(f);
		const refuse = (args: Record<string, unknown>, words: RegExp, code = 'INVALID') =>
			expect(invokeVerb(agentOf(f), 'rule_update', args)).rejects.toMatchObject({
				code,
				message: expect.stringMatching(words)
			});
		// A percentage, a goal target, the wrong account
		const pct = await proposeRule(w(f), {
			mode: 'percent',
			basisPoints: 1000,
			targetAccountId: f.gcash
		});
		await refuse({ ruleId: pct.id, fundsBillId: billId }, /fixed amount/);
		const toGoal = await proposeRule(w(f), {
			mode: 'fixed',
			amount: 5_000,
			targetGoalId: f.goalId
		});
		await refuse({ ruleId: toGoal.id, fundsBillId: billId }, /goal/);
		const wrong = await proposeRule(w(f), {
			mode: 'fixed',
			amount: 5_000,
			targetAccountId: f.rcbc
		});
		await refuse({ ruleId: wrong.id, fundsBillId: billId }, /another account/);
		// A bill in another currency, a switched-off bill
		const usd = await createBill(w(f), {
			name: 'VPS',
			category: 'bills',
			accountId: f.gcash,
			kind: 'fixed',
			amount: 535,
			schedule: { kind: 'monthly', day: 19 },
			weekendRule: 'none',
			deferrable: false,
			currency: 'USD'
		});
		await refuse({ ruleId, fundsBillId: usd.id }, /USD/);
		// A second rule for the same bill, then a retired rule
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, fundsBillId: billId });
		const other = await proposeRule(w(f), {
			mode: 'fixed',
			amount: 5_000,
			targetAccountId: f.gcash
		});
		await refuse({ ruleId: other.id, fundsBillId: billId }, /already has a rule/, 'CONFLICT');
		await retireRule(w(f), { ruleId: other.id });
		await refuse({ ruleId: other.id, fundsBillId: billId }, /retired/);
		await updateBill(w(f), { billId: usd.id, active: false });
		const third = await proposeRule(w(f), {
			mode: 'fixed',
			amount: 5_000,
			targetAccountId: f.gcash
		});
		await refuse({ ruleId: third.id, fundsBillId: usd.id }, /switched off/);
	});
});

describe('a bill edit or delete clears a link that no longer fits', () => {
	it('clears it when the bill moves to another account, and says so', async () => {
		const f = await seedPerson(t);
		const { billId, ruleId } = await setup(f);
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, fundsBillId: billId });
		const kept = await updateBill(w(f), { billId, amount: 160_000 });
		expect(kept.unlinkedRules).toEqual([]);
		const moved = await updateBill(w(f), { billId, accountId: f.rcbc });
		expect(moved.unlinkedRules).toEqual([
			{ ruleId, label: 'Internet', reason: 'the bill is now paid from another account' }
		]);
		expect((await ruleOf(f, ruleId))?.fundsBillId).toBeNull();
	});

	it('clears it when a bill with no history is deleted, and when one with payments is switched off', async () => {
		const f = await seedPerson(t);
		const { billId, ruleId } = await setup(f);
		await invokeVerb(agentOf(f), 'rule_update', { ruleId, fundsBillId: billId });
		const gone = await deleteBill(w(f), { billId });
		expect(gone).toMatchObject({
			deleted: true,
			unlinkedRules: [{ ruleId, reason: 'the bill was removed' }]
		});
		expect(await ruleOf(f, ruleId)).toMatchObject({ fundsBillId: null, userId: f.userId });

		const again = await setup(f);
		await invokeVerb(agentOf(f), 'rule_update', {
			ruleId: again.ruleId,
			fundsBillId: again.billId
		});
		// The next 4th of a month, the day the bill is due, whatever day the test runs
		const today = toLocalDate(new Date());
		const [y, m, d] = today.split('-').map(Number) as [number, number, number];
		const next = new Date(Date.UTC(y, d > 4 ? m : m - 1, 4)).toISOString().slice(0, 10);
		await markBillPaid(w(f), { billId: again.billId, dueDate: next, amount: 150_000 });
		const off = await deleteBill(w(f), { billId: again.billId });
		expect(off).toMatchObject({ switchedOff: true, unlinkedRules: [{ ruleId: again.ruleId }] });
		expect((await ruleOf(f, again.ruleId))?.fundsBillId).toBeNull();
	});
});
