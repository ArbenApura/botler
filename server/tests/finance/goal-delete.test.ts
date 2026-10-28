// goal_delete: A GOAL REMOVED FOR GOOD WITH THE RULES THAT POINT AT IT, FREE FOR THE ASSISTANT (A CARD AFTER UNTRUSTED TEXT), THE TRAIL KEPT, OLD SPLITS STILL READABLE; AND A
// PAYDAY SPLIT THAT NO LONGER FAILS ON A RULE THAT POINTS AT A SWITCHED-OFF GOAL

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { decideAction, listActions } from '../../src/lib/server/ops/actions';
import { allocationRule, auditEvent, goal } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { accountBalances, recordSnapshot } from '../../src/lib/server/ops/ledger';
import { createGoal, deleteGoal, listGoals, updateGoal } from '../../src/lib/server/ops/planning';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { approveRule, proposeRule } from '../../src/lib/server/ops/rules';
import { listSplits, proposeSplitPlan } from '../../src/lib/server/ops/split';
import { cardEvents, doneEvent, play, seedPerson, stubModel, toolEvents } from '../agent/support';
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
	requestId: `gd-req-${String(++rids).padStart(8, '0')}`
});
const agentOf = (who: Fixture) => ({
	...w(who),
	actor: { userId: who.userId, kind: 'agent' as const }
});

const rulesOf = (who: Fixture) =>
	withUser(t.handle, who.userId, (tx) =>
		tx.select().from(allocationRule).where(eq(allocationRule.userId, who.userId))
	);

const trail = (who: Fixture) =>
	withUser(t.handle, who.userId, (tx) =>
		tx.select().from(auditEvent).where(eq(auditEvent.userId, who.userId)).orderBy(auditEvent.seq)
	);

/** A rule pointing at a goal, proposed and approved. */
async function ruleFor(who: Fixture, goalId: string, over: Record<string, unknown> = {}) {
	const proposed = await proposeRule(w(who), {
		mode: 'fixed',
		amount: 300_000,
		targetGoalId: goalId,
		...over
	});
	return approveRule(w(who), { ruleId: proposed.id });
}

// -- TESTS -- //

describe('goal_delete', () => {
	it('is a free verb the assistant runs on its own, and the answer holds the removed goal', async () => {
		expect(verbByName('goal_delete')).toMatchObject({ kind: 'free', agent: true });
		const f = await seedPerson(t);
		const done = (await invokeVerb(agentOf(f), 'goal_delete', { goalId: f.goalId })) as {
			deleted: boolean;
			goal: { id: string };
		};
		expect(done).toMatchObject({ deleted: true, goal: { id: f.goalId } });
		expect(await listGoals(f.ctx)).toHaveLength(0);
	});

	it('removes the goal and every rule that points at it, whatever its status, and nothing else', async () => {
		const f = await seedPerson(t);
		const other = await createGoal(w(f), {
			name: 'Holiday',
			accountId: f.maya,
			targetAmount: null,
			perPayday: 0
		});
		await ruleFor(f, f.goalId); // active
		await proposeRule(w(f), { mode: 'fixed', amount: 100_000, targetGoalId: f.goalId }); // proposed
		const keep = await ruleFor(f, other.id, { amount: 50_000 });
		const toAccount = await ruleFor(f, '', {
			targetGoalId: null,
			targetAccountId: f.gcash,
			amount: 20_000
		});
		expect((await rulesOf(f)).length).toBe(4);
		const done = await deleteGoal(w(f), { goalId: f.goalId });
		expect(done).toMatchObject({ deleted: true, name: 'Emergency fund', rulesRemoved: 2 });
		expect((await listGoals(f.ctx)).map((g) => g.name)).toEqual(['Holiday']);
		expect((await rulesOf(f)).map((r) => r.id).sort()).toEqual([keep.id, toAccount.id].sort());
	});

	it('moves no money: the account that held the savings keeps its balance', async () => {
		const f = await seedPerson(t);
		await recordSnapshot(w(f), { accountId: f.maya, amount: 777_700 });
		const before = (await accountBalances(f.ctx)).find((a) => a.id === f.maya);
		await deleteGoal(w(f), { goalId: f.goalId });
		const after = (await accountBalances(f.ctx)).find((a) => a.id === f.maya);
		expect(after?.balance).toBe(777_700);
		expect(after?.balance).toBe(before?.balance);
	});

	it('leaves both deletes in the audit trail, and the trail still checks out', async () => {
		const f = await seedPerson(t);
		const rule = await ruleFor(f, f.goalId);
		await deleteGoal(w(f), { goalId: f.goalId });
		const rows = (await trail(f)).filter((r) => r.verb === 'goal.delete');
		expect(rows.map((r) => [r.entity, r.action]).sort()).toEqual([
			['allocation_rule', 'delete'],
			['goal', 'delete']
		]);
		expect(rows.find((r) => r.entity === 'allocation_rule')?.entityId).toBe(rule.id);
		expect(rows.find((r) => r.entity === 'goal')?.entityId).toBe(f.goalId);
	});

	it('keeps an old payday split readable after its goal is gone', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId);
		const plan = await proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId });
		expect('result' in plan && JSON.stringify(plan.result)).toContain(f.goalId);
		await deleteGoal(w(f), { goalId: f.goalId });
		const [old] = await listSplits(f.ctx, 5);
		expect(old?.id).toBe('id' in plan ? plan.id : '');
		expect(JSON.stringify(old?.result)).toContain('Emergency fund');
		// A new split no longer has the goal or its rule, and still adds up to the pay
		const next = await proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId });
		expect('result' in next && next.result.status).toBe('ok');
		if ('result' in next && next.result.status === 'ok') {
			expect(next.result.lines.reduce((s, l) => s + l.amount, 0)).toBe(next.result.pay);
			expect(next.result.lines.some((l) => l.goalId === f.goalId)).toBe(false);
		}
	});

	it('replays a repeated request, refuses an unknown goal, and never touches another person’s', async () => {
		const f = await seedPerson(t);
		const g = await seedPerson(t);
		const ctx = w(f);
		const first = await deleteGoal(ctx, { goalId: f.goalId });
		expect(await deleteGoal(ctx, { goalId: f.goalId })).toEqual(first);
		await expect(deleteGoal(w(f), { goalId: f.goalId })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await expect(deleteGoal(w(f), { goalId: g.goalId })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect(await listGoals(g.ctx)).toHaveLength(1);
		await expect(invokeVerb(w(f), 'goal_delete', { goalId: 'nope' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(
			invokeVerb(w(f), 'goal_delete', { goalId: g.goalId, userId: 'x' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('asking Botler to delete a goal', () => {
	it('deletes at once when the message is the person’s own words', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId);
		const model = stubModel([
			{ calls: [['goal_delete', { goalId: f.goalId }]] },
			{ say: 'Removed Emergency fund.' }
		]);
		const events = await play({ f, model, text: 'delete my Emergency fund goal' });
		expect(toolEvents(events)[0]).toMatchObject({ name: 'goal_delete', status: 'ok' });
		expect(cardEvents(events)).toHaveLength(0);
		expect(await listGoals(f.ctx)).toHaveLength(0);
		expect(await rulesOf(f)).toHaveLength(0);
	});

	it('makes a card that says what goes and what stays after untrusted text, and deletes only when the person approves it', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId);
		const model = stubModel([
			{ calls: [['goal_delete', { goalId: f.goalId }]] },
			{ say: 'I made a card for you to approve.' }
		]);
		const events = await play({
			f,
			model,
			text: 'delete my Emergency fund goal',
			ocrText: 'receipt text'
		});
		expect(toolEvents(events)[0]).toMatchObject({ name: 'goal_delete', status: 'needs_approval' });
		const [card] = cardEvents(events);
		expect(card?.summary).toContain('Emergency fund');
		expect(card?.summary).toMatch(/for good/);
		expect(card?.summary).toMatch(/money saved for it stays/);
		expect(card?.summary).toMatch(/payday rules/);
		expect(doneEvent(events)?.reply).toMatch(/card/);
		// Nothing is deleted yet
		expect(await listGoals(f.ctx)).toHaveLength(1);
		expect((await listActions(f.ctx, 'pending')).map((a) => a.verb)).toContain('goal_delete');
		await decideAction(f.ctx, { actionId: card?.actionId ?? '', decision: 'approve' });
		expect(await listGoals(f.ctx)).toHaveLength(0);
		expect(await rulesOf(f)).toHaveLength(0);
	});

	it('tells the model it may delete things at once and says what was removed, and never to forget a memory instead', async () => {
		const { SYSTEM_PREFIX } = await import('../../src/lib/server/agent/prompt');
		expect(SYSTEM_PREFIX).toMatch(/goal_delete/);
		expect(SYSTEM_PREFIX).toMatch(/never say these cannot be deleted/i);
		expect(SYSTEM_PREFIX).toMatch(/Always say exactly what you removed/);
		expect(SYSTEM_PREFIX).toMatch(/Never use memory or the notebook to "delete" anything/);
		expect(verbByName('goal_delete')?.description).toMatch(/Never forget a memory/);
	});
});

describe('a payday split with a rule that points at a switched-off goal', () => {
	it('skips the rule instead of failing, names it, and still adds up to the pay (a percent rule)', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId, { mode: 'percent', amount: null, basisPoints: 2000 });
		await updateGoal(w(f), { goalId: f.goalId, active: false });
		const plan = await proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId });
		if (!('result' in plan)) throw new Error('expected a plan');
		expect(plan.result.status).toBe('ok');
		if (plan.result.status !== 'ok') return;
		expect(plan.result.lines.reduce((s, l) => s + l.amount, 0)).toBe(plan.result.pay);
		expect(plan.result.skippedRules).toEqual([
			{
				ruleId: expect.any(String),
				goal: 'Emergency fund',
				note: expect.stringContaining('Emergency fund')
			}
		]);
		expect(plan.result.lines.some((l) => l.goalId === f.goalId)).toBe(false);
	});

	it('skips a fixed rule the same way, and the pay it would have taken goes where unclaimed pay goes', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId, { amount: 400_000 });
		const toGcash = await ruleFor(f, '', {
			targetGoalId: null,
			targetAccountId: f.gcash,
			amount: 100_000
		});
		await updateGoal(w(f), { goalId: f.goalId, active: false });
		const plan = await proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId });
		if (!('result' in plan) || plan.result.status !== 'ok') throw new Error('expected an ok plan');
		expect(plan.result.lines.reduce((s, l) => s + l.amount, 0)).toBe(plan.result.pay);
		expect(plan.result.skippedRules).toHaveLength(1);
		// What no rule claims goes to the first rule in force: the one to GCash
		const toGcashLine = plan.result.lines.filter(
			(l) => l.accountId === f.gcash && l.refId === toGcash.id
		);
		expect(toGcashLine.length).toBeGreaterThan(0);
		const total = toGcashLine.reduce((s, l) => s + l.amount, 0);
		expect(total).toBeGreaterThan(100_000);
	});

	it('adds nothing to the plan when no rule is skipped', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId);
		const plan = await proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId });
		if (!('result' in plan)) throw new Error('expected a plan');
		expect(plan.result).not.toHaveProperty('skippedRules');
	});

	it('works when the only rule is skipped, and the pay stays where it landed', async () => {
		const f = await seedPerson(t);
		await ruleFor(f, f.goalId);
		await updateGoal(w(f), { goalId: f.goalId, active: false });
		const plan = await proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId });
		if (!('result' in plan) || plan.result.status !== 'ok') throw new Error('expected an ok plan');
		expect(plan.result.lines.reduce((s, l) => s + l.amount, 0)).toBe(plan.result.pay);
		const rows = await withUser(t.handle, f.userId, (tx) =>
			tx
				.select()
				.from(goal)
				.where(and(eq(goal.userId, f.userId), eq(goal.id, f.goalId)))
		);
		expect(rows[0]?.active).toBe(false);
	});
});
