// INCOME AND GOAL VERBS: WHEN THE PAY ARRIVES AND WHAT THE PERSON IS SAVING FOR

// -- TYPES -- //
import type { Ctx } from './context';
import type {
	GoalCreateInput,
	GoalUpdateInput,
	IncomeCreateInput,
	IncomeUpdateInput,
	SchedulePreviewInput
} from '../db/zod';
import type { Plain } from './shared';
import type { Schedule } from '../../finance/schedule';
// -- DEP-MODULES -- //
import { and, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, toManilaDate } from '../../finance/dates';
import { describeSchedule, occurrencesBetween, previewOccurrences } from '../../finance/schedule';
import { allocationRule, goal, incomeSchedule } from '../db/schema';
import {
	goalCreateInput,
	goalDeleteInput,
	goalUpdateInput,
	incomeCreateInput,
	incomeUpdateInput,
	schedulePreviewInput
} from '../db/zod';
import { assertUserId } from '../db/tenant';
import { OpsError, run, runWrite } from './context';
import {
	checkVersion,
	mapped,
	parse,
	plain,
	requireActiveAccount,
	requireGoal,
	requireIncome,
	requirePerson
} from './shared';

// -- TYPES -- //

export type IncomeView = Plain<typeof incomeSchedule.$inferSelect>;
export type GoalView = Plain<typeof goal.$inferSelect>;

// -- INCOME -- //

export async function createIncome(ctx: Ctx, raw: IncomeCreateInput): Promise<IncomeView> {
	requirePerson(ctx.actor.kind, 'set up an income');
	const input = parse(incomeCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'income.create', input, async (tx, userId) => {
			await requireActiveAccount(tx, userId, input.accountId, 'account the pay lands in');
			const [row] = await tx
				.insert(incomeSchedule)
				.values({ ...input, userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The income could not be saved.');
			return plain(row);
		})
	);
}

export async function updateIncome(ctx: Ctx, raw: IncomeUpdateInput): Promise<IncomeView> {
	const { incomeId, expectVersion, ...changes } = parse(incomeUpdateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'income.update', { incomeId, expectVersion, ...changes }, async (tx, userId) => {
			const current = await requireIncome(tx, userId, incomeId);
			checkVersion(current.version, expectVersion, 'income');
			if (changes.accountId) await requireActiveAccount(tx, userId, changes.accountId);
			const [row] = await tx
				.update(incomeSchedule)
				.set({ ...changes, version: sql`${incomeSchedule.version} + 1`, updatedAt: sql`now()` })
				.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, incomeId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That income does not exist.');
			return plain(row);
		})
	);
}

export async function listIncome(ctx: Ctx): Promise<IncomeView[]> {
	return plain(
		await run(ctx, (tx, userId) =>
			tx
				.select()
				.from(incomeSchedule)
				.where(eq(incomeSchedule.userId, userId))
				.orderBy(incomeSchedule.label)
		)
	);
}

/** The next paydays of an income, starting today (Manila). */
export async function nextPaydays(ctx: Ctx, incomeId: string, count = 4): Promise<string[]> {
	const row = await run(ctx, (tx, userId) => requireIncome(tx, userId, incomeId));
	const today = toManilaDate(new Date());
	const found = occurrencesBetween(row.schedule as Schedule, today, addDays(today, 800), {
		weekend: row.weekendRule
	});
	return found.slice(0, Math.min(Math.max(count, 1), 24));
}

/** What a schedule means and when it would next fall, so a person sees a wrong schedule before saving it. Nothing is read or written. */
export async function schedulePreview(ctx: Ctx, raw: SchedulePreviewInput) {
	assertUserId(ctx.actor.userId);
	const input = parse(schedulePreviewInput, raw);
	const schedule = input.schedule as Schedule;
	const from = input.from ?? toManilaDate(new Date());
	const sentence = describeSchedule(schedule);
	return {
		key: sentence.key,
		args: sentence.args,
		text: sentence.text,
		windows: previewOccurrences(schedule, from, input.count ?? 6, {
			weekend: input.weekend ?? 'none'
		})
	};
}

// -- GOALS -- //

export async function createGoal(ctx: Ctx, raw: GoalCreateInput): Promise<GoalView> {
	requirePerson(ctx.actor.kind, 'add a goal');
	const input = parse(goalCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'goal.create', input, async (tx, userId) => {
			await requireActiveAccount(tx, userId, input.accountId, 'account the goal sits in');
			const [row] = await tx
				.insert(goal)
				.values({ ...input, userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The goal could not be saved.');
			return plain(row);
		})
	);
}

export async function updateGoal(ctx: Ctx, raw: GoalUpdateInput): Promise<GoalView> {
	const { goalId, expectVersion, ...changes } = parse(goalUpdateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'goal.update', { goalId, expectVersion, ...changes }, async (tx, userId) => {
			const current = await requireGoal(tx, userId, goalId);
			checkVersion(current.version, expectVersion, 'goal');
			if (changes.accountId) await requireActiveAccount(tx, userId, changes.accountId);
			const [row] = await tx
				.update(goal)
				.set({ ...changes, version: sql`${goal.version} + 1`, updatedAt: sql`now()` })
				.where(and(eq(goal.userId, userId), eq(goal.id, goalId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That goal does not exist.');
			return plain(row);
		})
	);
}

/**
 * Removes a goal for good. Every payday rule that points at it goes first, whatever its status (the reference from a rule to its goal
 * allows no delete), then the goal, in one transaction. No money moves: what was saved stays in its account. The audit trail keeps both
 * deletes, and a stored payday split that names the goal stays readable (it holds only the goal's id and label). Only a person can, or the
 * person's approval of a card the assistant made.
 */
export async function deleteGoal(
	ctx: Ctx,
	raw: unknown
): Promise<{ deleted: true; name: string; rulesRemoved: number }> {
	requirePerson(ctx.actor.kind, 'remove a goal');
	const input = parse(goalDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'goal.delete', input, async (tx, userId) => {
			const current = await requireGoal(tx, userId, input.goalId);
			const removed = await tx
				.delete(allocationRule)
				.where(
					and(eq(allocationRule.userId, userId), eq(allocationRule.targetGoalId, input.goalId))
				)
				.returning({ id: allocationRule.id });
			await tx.delete(goal).where(and(eq(goal.userId, userId), eq(goal.id, input.goalId)));
			return { deleted: true as const, name: current.name, rulesRemoved: removed.length };
		})
	);
}

export async function listGoals(ctx: Ctx): Promise<GoalView[]> {
	return plain(
		await run(ctx, (tx, userId) =>
			tx.select().from(goal).where(eq(goal.userId, userId)).orderBy(goal.name)
		)
	);
}
