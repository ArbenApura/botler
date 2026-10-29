// ALLOCATION RULE VERBS: A RULE IS PROPOSED (BY FORM OR IN PLAIN WORDS), SHOWN TO THE PERSON, AND APPLIES ONLY AFTER THEY APPROVE IT
// Approving and retiring change the money plan, so only a person can do them, never the agent. The text a person approves is built here
// from the saved fields, never from free text a model wrote.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { Rule } from '../../finance/rules';
import type { RuleFromTextInput, RuleProposeInput } from '../db/zod';
import type { Plain } from './shared';
// -- DEP-MODULES -- //
import { and, desc, eq, inArray, sql } from 'drizzle-orm';
// -- MODULES -- //
import { toManilaDate } from '../../finance/dates';
import { DEFAULT_CURRENCY, formatMoney } from '../../finance/currency';
import { validateRules } from '../../finance/rules';
import { parseRuleText } from '../../finance/text';
import { account, allocationRule, bill, goal } from '../db/schema';
import {
	ruleDeleteInput,
	ruleFromTextInput,
	ruleIdInput,
	ruleProposeInput,
	ruleUpdateInput
} from '../db/zod';
import { readSettings } from './settings';
import { OpsError, run, runWrite } from './context';
import { mapped, parse, plain, requireAccount, requireGoal, requirePerson } from './shared';

// -- TYPES -- //

export type RuleRow = typeof allocationRule.$inferSelect;
export type RuleView = Plain<RuleRow> & {
	/** The sentence the person approves, built from the fields. */
	summary: string;
	targetName: string;
	/** The name of the bill the rule saves for, or null. */
	fundsBillName: string | null;
};

// -- FUNCTIONS -- //

/** The sentence shown on an approval card, from the saved fields only. */
export function describeRule(
	r: Pick<RuleRow, 'mode' | 'amount' | 'basisPoints' | 'base' | 'effectiveFrom'>,
	targetName: string,
	currency: string = DEFAULT_CURRENCY
): string {
	const from = `from ${r.effectiveFrom}`;
	if (r.mode === 'fixed')
		return `Put ${formatMoney(r.amount ?? 0, currency)} into ${targetName}, ${from}.`;
	if (r.mode === 'rest') return `Put whatever is left into ${targetName}, ${from}.`;
	const pct = `${(r.basisPoints ?? 0) / 100}%`;
	return r.base === 'pay'
		? `Put ${pct} of your pay into ${targetName}, ${from}.`
		: `Put ${pct} of what is left after bills into ${targetName}, ${from}.`;
}

/** A saved row as the engine's Rule. */
export const toRule = (r: RuleRow, label?: string): Rule => ({
	id: r.id,
	label: label ?? r.label ?? undefined,
	position: r.position,
	target: r.targetAccountId
		? { kind: 'account', id: r.targetAccountId }
		: { kind: 'goal', id: r.targetGoalId ?? '' },
	mode: r.mode,
	amount: r.amount,
	basisPoints: r.basisPoints,
	base: r.base,
	effectiveFrom: r.effectiveFrom,
	version: r.version
});

/** The names a rule's sentence uses (accounts, goals and bills), and the currency its amounts read in. */
type Targets = { names: Map<string, string>; bills: Map<string, string>; currency: string };

async function targetNames(tx: Tx, userId: string): Promise<Targets> {
	const accounts = await tx
		.select({ id: account.id, name: account.name })
		.from(account)
		.where(eq(account.userId, userId));
	const goals = await tx
		.select({ id: goal.id, name: goal.name })
		.from(goal)
		.where(eq(goal.userId, userId));
	const bills = await tx
		.select({ id: bill.id, name: bill.name })
		.from(bill)
		.where(eq(bill.userId, userId));
	const names = new Map<string, string>();
	for (const a of accounts) names.set(a.id, a.name);
	for (const g of goals) names.set(g.id, g.name);
	return {
		names,
		bills: new Map(bills.map((b) => [b.id, b.name])),
		currency: (await readSettings(tx, userId)).currency
	};
}

const view = (r: RuleRow, t: Targets): RuleView => {
	const targetName = t.names.get(r.targetAccountId ?? r.targetGoalId ?? '') ?? 'an account';
	const fundsBillName = r.fundsBillId ? (t.bills.get(r.fundsBillId) ?? 'a bill') : null;
	const said = describeRule(r, targetName, t.currency);
	const sentence = fundsBillName ? `${said} It saves for ${fundsBillName}.` : said;
	return {
		...plain(r),
		summary: r.label ? `${r.label}: ${sentence}` : sentence,
		targetName,
		fundsBillName
	};
};

async function activeRules(tx: Tx, userId: string) {
	return tx
		.select()
		.from(allocationRule)
		.where(and(eq(allocationRule.userId, userId), eq(allocationRule.status, 'active')));
}

/**
 * Refuses a link between a rule and a bill that could not count in the split (finance/funding.ts checks it again on every payday, since
 * the bill can change later): only a fixed rule in force or waiting, into the account the bill is paid from, for a bill that is switched
 * on, in the main currency and not already saved for by another rule.
 */
async function requireLinkable(
	tx: Tx,
	userId: string,
	rule: Pick<RuleRow, 'mode' | 'status' | 'targetAccountId'> & { id: string | null },
	billId: string
) {
	if (rule.status === 'retired')
		throw new OpsError('INVALID', 'That rule is retired, so it cannot save for a bill.');
	if (rule.mode !== 'fixed')
		throw new OpsError('INVALID', 'Only a rule with a fixed amount can save for a bill.');
	if (!rule.targetAccountId)
		throw new OpsError(
			'INVALID',
			'That rule puts money into a goal. A rule that saves for a bill puts it into the account the bill is paid from.'
		);
	const [b] = await tx
		.select()
		.from(bill)
		.where(and(eq(bill.userId, userId), eq(bill.id, billId)));
	if (!b) throw new OpsError('NOT_FOUND', 'That bill does not exist.');
	if (!b.active) throw new OpsError('INVALID', `"${b.name}" is switched off.`);
	const main = (await readSettings(tx, userId)).currency;
	if (b.currency !== main)
		throw new OpsError(
			'INVALID',
			`"${b.name}" is in ${b.currency}. A rule saves in ${main}, so it can only save for a bill in ${main}.`
		);
	if (b.accountId !== rule.targetAccountId)
		throw new OpsError(
			'INVALID',
			`"${b.name}" is paid from another account. The rule must put its money into the account the bill is paid from.`
		);
	const [other] = await tx
		.select()
		.from(allocationRule)
		.where(
			and(
				eq(allocationRule.userId, userId),
				eq(allocationRule.fundsBillId, billId),
				inArray(allocationRule.status, ['proposed', 'active'])
			)
		);
	if (other && other.id !== rule.id)
		throw new OpsError(
			'CONFLICT',
			`"${b.name}" already has a rule saving for it${other.label ? ` (${other.label})` : ''}. Unlink that one first.`
		);
}

/** A rule whose link to a bill was cleared because the bill changed, and why. */
export type UnlinkedRule = { ruleId: string; label: string | null; reason: string };

/**
 * Clears the links of the rules that save for a bill the person is deleting (bill null) or that no longer fits after an edit: switched
 * off, moved to another account, or in another currency than the main one. Done in the same write, so the audit trail shows it and the
 * split never trusts a stale link. Returns what was cleared, so the answer can say so.
 */
export async function unlinkRulesOf(
	tx: Tx,
	userId: string,
	billId: string,
	b: Pick<typeof bill.$inferSelect, 'active' | 'accountId' | 'currency'> | null
): Promise<UnlinkedRule[]> {
	const linked = await tx
		.select()
		.from(allocationRule)
		.where(and(eq(allocationRule.userId, userId), eq(allocationRule.fundsBillId, billId)));
	if (linked.length === 0) return [];
	const main = (await readSettings(tx, userId)).currency;
	const out: UnlinkedRule[] = [];
	for (const r of linked) {
		const reason = !b
			? 'the bill was removed'
			: !b.active
				? 'the bill is switched off'
				: b.currency !== main
					? `the bill is now in ${b.currency}`
					: b.accountId !== r.targetAccountId
						? 'the bill is now paid from another account'
						: null;
		if (!reason) continue;
		await tx
			.update(allocationRule)
			.set({
				fundsBillId: null,
				version: sql`${allocationRule.version} + 1`,
				updatedAt: sql`now()`
			})
			.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, r.id)));
		out.push({ ruleId: r.id, label: r.label, reason });
	}
	return out;
}

/** Saves a rule as proposed. It does nothing until a person approves it. The set (active rules plus this one) must stay valid. */
export async function proposeRule(
	ctx: Ctx,
	raw: RuleProposeInput,
	sourceText?: string
): Promise<RuleView> {
	const input = parse(ruleProposeInput, raw);
	const hasAccount = Boolean(input.targetAccountId);
	const hasGoal = Boolean(input.targetGoalId);
	if (hasAccount === hasGoal)
		throw new OpsError('INVALID', 'Pick an account or a goal, not both and not neither.');
	return mapped(() =>
		runWrite(ctx, 'rule.propose', { ...input, sourceText }, async (tx, userId) => {
			if (input.targetAccountId) await requireAccount(tx, userId, input.targetAccountId);
			if (input.targetGoalId) await requireGoal(tx, userId, input.targetGoalId);
			if (input.fundsBillId)
				await requireLinkable(
					tx,
					userId,
					{
						id: null,
						mode: input.mode,
						status: 'proposed',
						targetAccountId: input.targetAccountId ?? null
					},
					input.fundsBillId
				);
			const active = await activeRules(tx, userId);
			// Numbered after every rule in force or waiting, so two rules never share a place (0033 renumbered the old ones)
			const waiting = await tx
				.select({ position: allocationRule.position })
				.from(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.status, 'proposed')));
			const position =
				input.position ?? Math.max(0, ...[...active, ...waiting].map((r) => r.position)) + 1;
			const [row] = await tx
				.insert(allocationRule)
				.values({
					userId,
					label: input.label ?? null,
					mode: input.mode,
					amount: input.amount ?? null,
					basisPoints: input.basisPoints ?? null,
					base: input.base ?? (input.mode === 'rest' ? 'remaining' : 'pay'),
					targetAccountId: input.targetAccountId ?? null,
					targetGoalId: input.targetGoalId ?? null,
					fundsBillId: input.fundsBillId ?? null,
					effectiveFrom: input.effectiveFrom ?? toManilaDate(new Date()),
					position,
					status: 'proposed',
					sourceText: sourceText ?? null
				})
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The rule could not be saved.');
			// Tell the person now if the rule cannot fit with the ones already in force
			const problems = validateRules([...active, row].map((r) => toRule(r)));
			if (problems[0]) throw new OpsError('INVALID', problems[0]);
			return view(row, await targetNames(tx, userId));
		})
	);
}

/** Reads a rule said in plain words ("20% to emergency fund") and proposes it. What cannot be read is refused with the reason. */
export async function proposeRuleFromText(ctx: Ctx, raw: RuleFromTextInput): Promise<RuleView> {
	const input = parse(ruleFromTextInput, raw);
	const { targets, currency } = await run(ctx, async (tx, userId) => {
		const accounts = await tx
			.select({ id: account.id, name: account.name })
			.from(account)
			.where(eq(account.userId, userId));
		const goals = await tx
			.select({ id: goal.id, name: goal.name })
			.from(goal)
			.where(eq(goal.userId, userId));
		return {
			targets: [
				...accounts.map((a) => ({ kind: 'account' as const, id: a.id, name: a.name })),
				...goals.map((g) => ({ kind: 'goal' as const, id: g.id, name: g.name }))
			],
			// "500 to cash" is 500 of the person's own currency
			currency: (await readSettings(tx, userId)).currency
		};
	});
	const parsed = parseRuleText(input.text, targets, currency);
	if (!parsed.ok) throw new OpsError('INVALID', parsed.reason);
	return proposeRule(
		ctx,
		{
			label: input.label,
			mode: parsed.mode,
			amount: parsed.amount,
			basisPoints: parsed.basisPoints,
			base: parsed.base,
			targetAccountId: parsed.target.kind === 'account' ? parsed.target.id : null,
			targetGoalId: parsed.target.kind === 'goal' ? parsed.target.id : null,
			effectiveFrom: input.effectiveFrom,
			position: input.position
		},
		input.text
	);
}

/** Puts a proposed rule in force. Only a person can. */
export async function approveRule(ctx: Ctx, raw: { ruleId: string }): Promise<RuleView> {
	requirePerson(ctx.actor.kind, 'approve a rule');
	const { ruleId } = parse(ruleIdInput, raw);
	return mapped(() =>
		runWrite(ctx, 'rule.approve', { ruleId }, async (tx, userId) => {
			const [row] = await tx
				.select()
				.from(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, ruleId)));
			if (!row) throw new OpsError('NOT_FOUND', 'That rule does not exist.');
			if (row.status !== 'proposed')
				throw new OpsError('CONFLICT', 'That rule is not waiting for approval.');
			const active = await activeRules(tx, userId);
			const problems = validateRules([...active, row].map((r) => toRule(r)));
			if (problems[0]) throw new OpsError('INVALID', problems[0]);
			const [done] = await tx
				.update(allocationRule)
				.set({
					status: 'active',
					approvedAt: sql`now()`,
					version: sql`${allocationRule.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, ruleId)))
				.returning();
			if (!done) throw new OpsError('NOT_FOUND', 'That rule does not exist.');
			return view(done, await targetNames(tx, userId));
		})
	);
}

/** Takes a rule out of force, or drops a proposal. Only a person can. */
export async function retireRule(ctx: Ctx, raw: { ruleId: string }): Promise<RuleView> {
	requirePerson(ctx.actor.kind, 'retire a rule');
	const { ruleId } = parse(ruleIdInput, raw);
	return mapped(() =>
		runWrite(ctx, 'rule.retire', { ruleId }, async (tx, userId) => {
			const [done] = await tx
				.update(allocationRule)
				.set({
					status: 'retired',
					// A retired rule saves for nothing, so its link to a bill goes with it
					fundsBillId: null,
					version: sql`${allocationRule.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(
					and(
						eq(allocationRule.userId, userId),
						eq(allocationRule.id, ruleId),
						inArray(allocationRule.status, ['proposed', 'active'])
					)
				)
				.returning();
			if (!done) throw new OpsError('NOT_FOUND', 'There is no such rule to retire.');
			return view(done, await targetNames(tx, userId));
		})
	);
}

/**
 * Gives a rule a name, or links it to the bill it saves for (BTL-20261029-0119). A field left out stays as it is and null clears it. The
 * money and the target stay as approved, so the assistant may do it without a card (owner decision 2026-10-28); the audit trail keeps both.
 */
export async function updateRule(ctx: Ctx, raw: unknown): Promise<RuleView> {
	const input = parse(ruleUpdateInput, raw);
	const { ruleId } = input;
	if (input.label === undefined && input.fundsBillId === undefined)
		throw new OpsError('INVALID', 'Say the new label or the bill the rule saves for.');
	return mapped(() =>
		runWrite(ctx, 'rule.update', input, async (tx, userId) => {
			const [row] = await tx
				.select()
				.from(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, ruleId)));
			if (!row) throw new OpsError('NOT_FOUND', 'That rule does not exist.');
			if (input.fundsBillId) await requireLinkable(tx, userId, row, input.fundsBillId);
			// Only the fields that were given are written
			const changes: Partial<Pick<RuleRow, 'label' | 'fundsBillId'>> = {};
			if (input.label !== undefined) changes.label = input.label;
			if (input.fundsBillId !== undefined) changes.fundsBillId = input.fundsBillId;
			const [done] = await tx
				.update(allocationRule)
				.set({ ...changes, version: sql`${allocationRule.version} + 1`, updatedAt: sql`now()` })
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, ruleId)))
				.returning();
			if (!done) throw new OpsError('NOT_FOUND', 'That rule does not exist.');
			return view(done, await targetNames(tx, userId));
		})
	);
}

/**
 * Removes a payday rule for good, whatever its status. Nothing points at a rule (a stored split holds only its own copy of the numbers), so
 * the delete is clean. The assistant may call it (owner decision 2026-10-28); the audit trail keeps the removed row.
 */
export async function deleteRule(ctx: Ctx, raw: unknown) {
	const { ruleId } = parse(ruleDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'rule.delete', { ruleId }, async (tx, userId) => {
			const [row] = await tx
				.select()
				.from(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, ruleId)));
			if (!row) throw new OpsError('NOT_FOUND', 'That rule does not exist.');
			const names = await targetNames(tx, userId);
			await tx
				.delete(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, ruleId)));
			// The removed rule is returned whole, so it can be made again if it was a mistake
			return { deleted: true as const, rule: view(row, names) };
		})
	);
}

export async function listRules(ctx: Ctx, status?: RuleRow['status']): Promise<RuleView[]> {
	return run(ctx, async (tx, userId) => {
		const rows = await tx
			.select()
			.from(allocationRule)
			.where(
				and(
					eq(allocationRule.userId, userId),
					status ? eq(allocationRule.status, status) : undefined
				)
			)
			.orderBy(allocationRule.position, desc(allocationRule.createdAt));
		const names = await targetNames(tx, userId);
		return rows.map((r) => view(r, names));
	});
}
