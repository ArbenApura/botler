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
import { formatPhp } from '../../finance/money';
import { validateRules } from '../../finance/rules';
import { parseRuleText } from '../../finance/text';
import { account, allocationRule, goal } from '../db/schema';
import { ruleFromTextInput, ruleIdInput, ruleProposeInput } from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { mapped, parse, plain, requireAccount, requireGoal, requirePerson } from './shared';

// -- TYPES -- //

export type RuleRow = typeof allocationRule.$inferSelect;
export type RuleView = Plain<RuleRow> & {
	/** The sentence the person approves, built from the fields. */
	summary: string;
	targetName: string;
};

// -- FUNCTIONS -- //

/** The sentence shown on an approval card, from the saved fields only. */
export function describeRule(
	r: Pick<RuleRow, 'mode' | 'amount' | 'basisPoints' | 'base' | 'effectiveFrom'>,
	targetName: string
): string {
	const from = `from ${r.effectiveFrom}`;
	if (r.mode === 'fixed') return `Put ${formatPhp(r.amount ?? 0)} into ${targetName}, ${from}.`;
	if (r.mode === 'rest') return `Put whatever is left into ${targetName}, ${from}.`;
	const pct = `${(r.basisPoints ?? 0) / 100}%`;
	return r.base === 'pay'
		? `Put ${pct} of your pay into ${targetName}, ${from}.`
		: `Put ${pct} of what is left after bills into ${targetName}, ${from}.`;
}

/** A saved row as the engine's Rule. */
export const toRule = (r: RuleRow, label?: string): Rule => ({
	id: r.id,
	label,
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

async function targetNames(tx: Tx, userId: string) {
	const accounts = await tx
		.select({ id: account.id, name: account.name })
		.from(account)
		.where(eq(account.userId, userId));
	const goals = await tx
		.select({ id: goal.id, name: goal.name })
		.from(goal)
		.where(eq(goal.userId, userId));
	const names = new Map<string, string>();
	for (const a of accounts) names.set(a.id, a.name);
	for (const g of goals) names.set(g.id, g.name);
	return names;
}

const view = (r: RuleRow, names: Map<string, string>): RuleView => {
	const targetName = names.get(r.targetAccountId ?? r.targetGoalId ?? '') ?? 'an account';
	return { ...plain(r), summary: describeRule(r, targetName), targetName };
};

async function activeRules(tx: Tx, userId: string) {
	return tx
		.select()
		.from(allocationRule)
		.where(and(eq(allocationRule.userId, userId), eq(allocationRule.status, 'active')));
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
			const active = await activeRules(tx, userId);
			const position = input.position ?? Math.max(0, ...active.map((r) => r.position)) + 1;
			const [row] = await tx
				.insert(allocationRule)
				.values({
					userId,
					mode: input.mode,
					amount: input.amount ?? null,
					basisPoints: input.basisPoints ?? null,
					base: input.base ?? (input.mode === 'rest' ? 'remaining' : 'pay'),
					targetAccountId: input.targetAccountId ?? null,
					targetGoalId: input.targetGoalId ?? null,
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
	const targets = await run(ctx, async (tx, userId) => {
		const accounts = await tx
			.select({ id: account.id, name: account.name })
			.from(account)
			.where(eq(account.userId, userId));
		const goals = await tx
			.select({ id: goal.id, name: goal.name })
			.from(goal)
			.where(eq(goal.userId, userId));
		return [
			...accounts.map((a) => ({ kind: 'account' as const, id: a.id, name: a.name })),
			...goals.map((g) => ({ kind: 'goal' as const, id: g.id, name: g.name }))
		];
	});
	const parsed = parseRuleText(input.text, targets);
	if (!parsed.ok) throw new OpsError('INVALID', parsed.reason);
	return proposeRule(
		ctx,
		{
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
