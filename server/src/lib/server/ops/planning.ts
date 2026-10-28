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
import { allocationRule, goal, incomeSchedule, splitPlan } from '../db/schema';
import {
	goalCreateInput,
	goalDeleteInput,
	goalUpdateInput,
	incomeCreateInput,
	incomeDeleteInput,
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
	requireIncome
} from './shared';

// -- TYPES -- //

export type IncomeView = Plain<typeof incomeSchedule.$inferSelect>;
export type GoalView = Plain<typeof goal.$inferSelect>;

// -- INCOME -- //

export async function createIncome(ctx: Ctx, raw: IncomeCreateInput): Promise<IncomeView> {
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

/**
 * Removes a payday schedule. One that a payday split was made for keeps that history: it is switched off instead (active false) and the
 * answer says so. The assistant may call it (owner decision 2026-10-28); the removed schedule is returned whole.
 */
export async function deleteIncome(ctx: Ctx, raw: unknown) {
	const { incomeId } = parse(incomeDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'income.delete', { incomeId }, async (tx, userId) => {
			const current = await requireIncome(tx, userId, incomeId);
			const [plans] = await tx
				.select({ n: sql<number>`count(*)::int` })
				.from(splitPlan)
				.where(and(eq(splitPlan.userId, userId), eq(splitPlan.incomeScheduleId, incomeId)));
			if ((plans?.n ?? 0) > 0) {
				const [row] = await tx
					.update(incomeSchedule)
					.set({
						active: false,
						version: sql`${incomeSchedule.version} + 1`,
						updatedAt: sql`now()`
					})
					.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, incomeId)))
					.returning();
				if (!row) throw new OpsError('NOT_FOUND', 'That income does not exist.');
				return {
					deleted: false as const,
					switchedOff: true as const,
					reason:
						'A payday split was made for it, so its history is kept and it is switched off instead.',
					income: plain(row)
				};
			}
			await tx
				.delete(incomeSchedule)
				.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, incomeId)));
			return { deleted: true as const, switchedOff: false as const, income: plain(current) };
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
 * deletes, and a stored payday split that names the goal stays readable (it holds only the goal's id and label). The assistant may call
 * it (owner decision 2026-10-28); the removed goal is returned whole, so it can be added again.
 */
export async function deleteGoal(
	ctx: Ctx,
	raw: unknown
): Promise<{ deleted: true; name: string; rulesRemoved: number; goal: GoalView }> {
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
			return {
				deleted: true as const,
				name: current.name,
				rulesRemoved: removed.length,
				goal: plain(current)
			};
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
