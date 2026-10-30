// SPLIT_DELETE (BTL-20261030-0911): THE PERSON AND THE ASSISTANT CAN REMOVE RECORDED PAYDAY SPLITS FOR GOOD, ONE OR ALL, WITH OR WITHOUT THE
// LEDGER ENTRIES THE SPLITS WROTE. EVERYTHING ELSE (BILLS, RULES, PAYDAYS, OTHER PEOPLE) IS LEFT ALONE.

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { DELETE_VERBS } from '../../src/lib/server/agent/turn';
import { auditEvent, ledgerTxn, splitPlan } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { archiveAccount } from '../../src/lib/server/ops/accounts';
import { accountBalances } from '../../src/lib/server/ops/ledger';
import { listIncome } from '../../src/lib/server/ops/planning';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { approveRule, proposeRule } from '../../src/lib/server/ops/rules';
import {
	approveSplit,
	listSplits,
	markTransferSent,
	proposeSplitPlan,
	type SplitPlanView,
	type StoredSplit
} from '../../src/lib/server/ops/split';
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
	requestId: `sd-req-${String(++rids).padStart(8, '0')}`
});
const agentOf = (who: Fixture) => ({
	...w(who),
	actor: { userId: who.userId, kind: 'agent' as const }
});
const plan = async (who: Fixture) =>
	(await proposeSplitPlan(w(who), { incomeScheduleId: who.incomeId })) as SplitPlanView;
const balanceOf = async (who: Fixture, accountId: string) => {
	const rows = (await accountBalances(who.ctx)) as { id: string; balance: number }[];
	return rows.find((r) => r.id === accountId)?.balance ?? 0;
};
const rowsOf = (who: Fixture) =>
	withUser(t.handle, who.userId, (tx) =>
		tx.select().from(splitPlan).where(eq(splitPlan.userId, who.userId))
	);

// -- TESTS -- //

describe('split_delete', () => {
	it('is a free verb the assistant may call, and counts as a delete', () => {
		const v = verbByName('split_delete');
		expect(v).toMatchObject({ kind: 'free', agent: true });
		expect(DELETE_VERBS.has('split_delete')).toBe(true);
	});

	it('removes one split of any status and says what went', async () => {
		const f = await seedPerson(t);
		const first = await plan(f);
		const second = await plan(f);
		// The first is replaced by the second: both are rows, and both can go
		expect(await rowsOf(f)).toHaveLength(2);
		const done = (await invokeVerb(agentOf(f), 'split_delete', { splitId: first.id })) as {
			deleted: number;
			splits: { id: string }[];
		};
		expect(done).toMatchObject({ deleted: 1, entriesVoided: 0 });
		expect(done.splits[0]?.id).toBe(first.id);
		expect((await rowsOf(f)).map((r) => r.id)).toEqual([second.id]);
		await expect(
			invokeVerb(agentOf(f), 'split_delete', { splitId: first.id })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
	});

	it('removes every split with all true, replaced ones too, and leaves paydays alone', async () => {
		const f = await seedPerson(t);
		await plan(f);
		await plan(f);
		const done = (await invokeVerb(w(f), 'split_delete', { all: true })) as { deleted: number };
		expect(done.deleted).toBe(2);
		expect(await listSplits(f.ctx)).toEqual([]);
		expect(await listIncome(f.ctx)).toHaveLength(1);
		// Nothing left is a plain answer, not an error
		expect(await invokeVerb(w(f), 'split_delete', { all: true })).toMatchObject({ deleted: 0 });
	});

	it('needs exactly one of splitId and all', async () => {
		const f = await seedPerson(t);
		const p = await plan(f);
		await expect(invokeVerb(w(f), 'split_delete', {})).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(w(f), 'split_delete', { splitId: p.id, all: true })
		).rejects.toMatchObject({ code: 'INVALID' });
		expect(await rowsOf(f)).toHaveLength(1);
	});

	it('keeps the pay in the ledger by default and takes it out with removeEntries', async () => {
		const f = await seedPerson(t);
		const before = await balanceOf(f, f.rcbc);
		const p = await plan(f);
		await approveSplit(w(f), { splitId: p.id, recordIncome: true });
		const after = await balanceOf(f, f.rcbc);
		expect(after).toBe(before + p.pay);
		// Deleting the split alone: the money did arrive, so the balance stays
		await invokeVerb(w(f), 'split_delete', { splitId: p.id });
		expect(await balanceOf(f, f.rcbc)).toBe(after);

		const q = await plan(f);
		await approveSplit(w(f), { splitId: q.id, recordIncome: true });
		const again = await balanceOf(f, f.rcbc);
		expect(again).toBe(after + q.pay);
		const done = (await invokeVerb(w(f), 'split_delete', {
			splitId: q.id,
			removeEntries: true
		})) as { entriesVoided: number };
		expect(done.entriesVoided).toBe(1);
		expect(await balanceOf(f, f.rcbc)).toBe(after);
		// The voided entry is kept for the record
		const txns = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(ledgerTxn).where(eq(ledgerTxn.splitId, q.id))
		);
		expect(txns).toHaveLength(1);
		expect(txns[0]?.voidedAt).not.toBeNull();
	});

	it('never touches another person, and names the actor in the audit trail', async () => {
		const mine = await seedPerson(t);
		const theirs = await seedPerson(t);
		const mineSplit = await plan(mine);
		const theirSplit = await plan(theirs);
		await expect(
			invokeVerb(w(mine), 'split_delete', { splitId: theirSplit.id })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await invokeVerb(agentOf(mine), 'split_delete', { all: true });
		expect(await rowsOf(theirs)).toHaveLength(1);
		expect(await rowsOf(mine)).toHaveLength(0);
		const trail = await withUser(t.handle, mine.userId, (tx) =>
			tx.select().from(auditEvent).where(eq(auditEvent.userId, mine.userId))
		);
		const deleted = trail.filter((r) => r.entity === 'split_plan' && r.entityId === mineSplit.id);
		expect(deleted.length).toBeGreaterThanOrEqual(2);
		expect(JSON.stringify(deleted.at(-1))).toContain('agent');
	});
});

describe('removing the entries a split wrote', () => {
	it('is for the person: the assistant gets a refusal that the turn turns into a card', async () => {
		const f = await seedPerson(t);
		const p = await plan(f);
		await approveSplit(w(f), { splitId: p.id, recordIncome: true });
		const before = await balanceOf(f, f.rcbc);
		await expect(
			invokeVerb(agentOf(f), 'split_delete', { splitId: p.id, removeEntries: true })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		expect(await rowsOf(f)).toHaveLength(1);
		expect(await balanceOf(f, f.rcbc)).toBe(before);
		// Without it the assistant may delete the split itself
		await invokeVerb(agentOf(f), 'split_delete', { splitId: p.id });
		expect(await rowsOf(f)).toHaveLength(0);
	});
});

describe('one approved split per payday', () => {
	it('refuses a new plan for an approved payday until that split is deleted', async () => {
		const f = await seedPerson(t);
		const p = await plan(f);
		await approveSplit(w(f), { splitId: p.id });
		await expect(
			proposeSplitPlan(w(f), { incomeScheduleId: f.incomeId, payday: p.payday })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await invokeVerb(w(f), 'split_delete', { splitId: p.id });
		const again = (await proposeSplitPlan(w(f), {
			incomeScheduleId: f.incomeId,
			payday: p.payday
		})) as SplitPlanView;
		expect(again.status).not.toBe('approved');
	});

	it('hides replaced plans from the list unless asked', async () => {
		const f = await seedPerson(t);
		await plan(f);
		const second = await plan(f);
		expect((await listSplits(f.ctx)).map((p) => p.id)).toEqual([second.id]);
		expect(await listSplits(f.ctx, 10, true)).toHaveLength(2);
	});
});

describe('marking a transfer sent', () => {
	it('sends once, returns the plan, and a second tap is refused', async () => {
		const f = await seedPerson(t);
		const p = (await proposeSplitPlan(w(f), {
			incomeScheduleId: f.incomeId,
			payday: '2030-04-15'
		})) as SplitPlanView;
		await approveSplit(w(f), { splitId: p.id });
		const sent = await markTransferSent(w(f), { splitId: p.id, index: 0 });
		expect(sent.plan.id).toBe(p.id);
		expect(sent.plan.sentTransfers).toHaveLength(1);
		await expect(markTransferSent(w(f), { splitId: p.id, index: 0 })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
	});
});

describe('a rule into a hidden account', () => {
	it('is skipped and said so on the plan', async () => {
		const f = await seedPerson(t);
		const rule = await proposeRule(w(f), {
			mode: 'fixed',
			amount: 100_000,
			targetAccountId: f.gcash
		});
		await approveRule(w(f), { ruleId: rule.id });
		await archiveAccount(w(f), { accountId: f.gcash });
		const p = await plan(f);
		const stored = p.result as StoredSplit;
		expect(stored.skippedRules?.[0]?.note).toContain('hidden');
		expect(JSON.stringify(stored.lines)).not.toContain(f.gcash);
	});
});
