// WEIGHT, THE WEEKLY CHECK-IN AND THE PROPOSALS (BTL-20261105-0015, P5). THE JOB ONLY PROPOSES: A TARGET CHANGES WHEN THE PERSON SAYS YES, IN THE APP OR IN CHAT.
// A proposal is worked out by the server and fingerprints the data it came from, so accepting one after that data changed is refused. The window ends on the proposal's
// own date, so a new weigh-in does not invalidate it; correcting a past day inside the window does.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { GoalChoice } from '../../health/rules';
import type { IntakeDay, WeighIn } from '../../health/energy';
import type {
	ProposalAnswerInput,
	WeightDeleteInput,
	WeightLogInput,
	WeightTrendInput
} from '../db/zod';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
import { and, desc, eq, gte, lte, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, toLocalDate } from '../../finance/dates';
import {
	estimateBurn,
	forecastGoal,
	MIN_CHANGE_KCAL,
	MIN_WEIGH_INS,
	nextTarget,
	slopeOf,
	trendOf,
	weekKeyOf,
	WINDOW_DAYS
} from '../../health/energy';
import { LOW_INTAKE_KCAL, targetProblem } from '../../health/rules';
import {
	dayStatus,
	energyEstimate,
	foodEntry,
	healthGoal,
	healthProposal,
	weightEntry
} from '../db/schema';
import {
	proposalAnswerInput,
	weightDeleteInput,
	weightLogInput,
	weightTrendInput
} from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { readHealth } from './health';
import { mapped, parse, plain } from './shared';
import { supersedeAndPropose } from './proposals';
import { acceptWeekProposal, mondayOf, readTrain } from './workouts';
import { readSleep } from './sleep';

// -- CONSTANTS -- //

const RECENT_WEIGH_INS = 7;
const SHORT_SLEEP_MINUTES = 360;
const ENOUGH_FOOD_DAYS = 4;
const ENOUGH_WEIGH_INS = 3;

// -- FUNCTIONS -- //

async function weightsBetween(
	tx: Tx,
	userId: string,
	from: string,
	to: string
): Promise<WeighIn[]> {
	return tx
		.select({ day: weightEntry.day, grams: weightEntry.grams })
		.from(weightEntry)
		.where(
			and(eq(weightEntry.userId, userId), gte(weightEntry.day, from), lte(weightEntry.day, to))
		)
		.orderBy(weightEntry.day);
}

/** The logged calories of each complete day in a range. A day not marked complete is left out. */
async function intakeBetween(
	tx: Tx,
	userId: string,
	from: string,
	to: string
): Promise<IntakeDay[]> {
	const rows = await tx
		.select({
			day: dayStatus.day,
			kcal: sql<string>`coalesce(sum(${foodEntry.kcal}), 0)`
		})
		.from(dayStatus)
		.leftJoin(
			foodEntry,
			and(eq(foodEntry.userId, dayStatus.userId), eq(foodEntry.day, dayStatus.day))
		)
		.where(
			and(
				eq(dayStatus.userId, userId),
				eq(dayStatus.complete, true),
				gte(dayStatus.day, from),
				lte(dayStatus.day, to)
			)
		)
		.groupBy(dayStatus.day);
	return rows.map((r) => ({ day: r.day, kcal: Number(r.kcal) }));
}

const fingerprint = (weights: readonly WeighIn[], intake: readonly IntakeDay[]): string =>
	createHash('sha256')
		.update(
			JSON.stringify({
				w: weights.map((x) => [x.day, x.grams]),
				i: [...intake].sort((a, b) => (a.day < b.day ? -1 : 1)).map((x) => [x.day, x.kcal])
			})
		)
		.digest('hex');

/** Logs a weigh-in. A second one the same day replaces the first. */
export async function logWeight(ctx: Ctx, raw: WeightLogInput) {
	const input = parse(weightLogInput, raw);
	return mapped(() =>
		runWrite(ctx, 'weight.log', input, async (tx, userId) => {
			const day = input.day ?? toLocalDate(new Date());
			await tx
				.insert(weightEntry)
				.values({
					userId,
					day,
					grams: input.grams,
					byAgent: ctx.actor.kind === 'agent' || ctx.onBehalfOf === 'agent'
				})
				.onConflictDoUpdate({
					target: [weightEntry.userId, weightEntry.day],
					set: {
						grams: input.grams,
						byAgent: ctx.actor.kind === 'agent' || ctx.onBehalfOf === 'agent',
						updatedAt: new Date()
					}
				});
			return readTrend(tx, userId, toLocalDate(new Date()), 28);
		})
	);
}

/** Removes a weigh-in and answers what was removed. */
export async function deleteWeight(ctx: Ctx, raw: WeightDeleteInput) {
	const input = parse(weightDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'weight.delete', input, async (tx, userId) => {
			const [row] = await tx
				.delete(weightEntry)
				.where(and(eq(weightEntry.userId, userId), eq(weightEntry.day, input.day)))
				.returning({ day: weightEntry.day, grams: weightEntry.grams });
			if (!row) throw new OpsError('NOT_FOUND', 'There is no weigh-in on that day.');
			return { removed: plain(row) };
		})
	);
}

/** The line, the change, the forecast and the gentle low-intake flag. */
export async function readTrend(tx: Tx, userId: string, today: string, days: number) {
	// A longer run in, so the smoothed line has settled by the first day shown
	const shownFrom = addDays(today, -(days - 1));
	const all = await weightsBetween(tx, userId, addDays(today, -(days + 60)), today);
	const points = trendOf(all).filter((p) => p.day >= shownFrom);
	const latest = points.at(-1);
	const first = points[0];
	const recent = all.filter((w) => w.day >= addDays(today, -(WINDOW_DAYS - 1)));
	// A couple of weigh-ins are too few for a date
	const gramsPerDay = recent.length >= MIN_WEIGH_INS ? slopeOf(recent) : null;
	const entries = await tx
		.select({ day: weightEntry.day, grams: weightEntry.grams, byAgent: weightEntry.byAgent })
		.from(weightEntry)
		.where(eq(weightEntry.userId, userId))
		.orderBy(desc(weightEntry.day))
		.limit(RECENT_WEIGH_INS);
	const [goal] = await tx
		.select({ goalWeightG: healthGoal.goalWeightG })
		.from(healthGoal)
		.where(eq(healthGoal.userId, userId));
	// Seven days of food that were logged as complete, to notice very low eating without a judgement
	const week = await intakeBetween(tx, userId, addDays(today, -6), today);
	const average = week.length ? week.reduce((a, d) => a + d.kcal, 0) / week.length : null;
	return {
		points,
		entries,
		trendG: latest?.trendG ?? null,
		scaleG: latest?.grams ?? null,
		goalWeightG: goal?.goalWeightG ?? null,
		changeG: latest && first ? latest.trendG - first.trendG : null,
		sinceDay: first?.day ?? null,
		forecast: latest
			? forecastGoal(today, latest.trendG, gramsPerDay, goal?.goalWeightG ?? null)
			: null,
		lowIntake: average !== null && week.length >= 3 && average < LOW_INTAKE_KCAL
	};
}

export async function getWeightTrend(ctx: Ctx, raw: WeightTrendInput) {
	const { days } = parse(weightTrendInput, raw);
	return run(ctx, (tx, userId) => readTrend(tx, userId, toLocalDate(new Date()), days ?? 28));
}

/** About when the goal is reached at the pace of the last weeks. The model quotes this and never works it out. */
export async function getForecast(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const trend = await readTrend(tx, userId, toLocalDate(new Date()), WINDOW_DAYS);
		return { trendG: trend.trendG, forecast: trend.forecast };
	});
}

/** Marks open proposals past their date, and answers the ones still open. */
export async function listProposals(ctx: Ctx) {
	return mapped(() =>
		run(ctx, async (tx, userId) => {
			const rows = await tx
				.select()
				.from(healthProposal)
				.where(and(eq(healthProposal.userId, userId), eq(healthProposal.status, 'open')))
				.orderBy(desc(healthProposal.createdAt));
			const now = Date.now();
			return plain(rows.filter((r) => r.expiresAt.getTime() > now));
		})
	);
}

/**
 * The weekly work for one person: the burn from the last four weeks, then a proposal when the target should move. It makes no model call, and it never changes a target
 * itself. Safe to repeat within a week: the estimate is replaced and a new proposal takes the place of the open one.
 */
export async function runWeekly(tx: Tx, userId: string, today: string) {
	const health = await readHealth(tx, userId, today);
	const from = addDays(today, -(WINDOW_DAYS - 1));
	const weights = await weightsBetween(tx, userId, from, today);
	const intake = await intakeBetween(tx, userId, from, today);
	const estimate = estimateBurn(today, weights, intake);
	if (!estimate) return { proposed: false as const, reason: 'not_enough_data' };
	const trend = trendOf(await weightsBetween(tx, userId, addDays(today, -90), today)).at(-1);
	const trendG = trend?.trendG ?? health.latestWeightG;
	if (trendG === null) return { proposed: false as const, reason: 'no_weight' };
	const weekKey = weekKeyOf(today);
	await tx
		.insert(energyEstimate)
		.values({
			userId,
			weekKey,
			trendG,
			burnKcal: estimate.burnKcal,
			intakeKcal: estimate.intakeKcal,
			completeDays: estimate.completeDays,
			weighIns: estimate.weighIns
		})
		.onConflictDoUpdate({
			target: [energyEstimate.userId, energyEstimate.weekKey],
			set: {
				trendG,
				burnKcal: estimate.burnKcal,
				intakeKcal: estimate.intakeKcal,
				completeDays: estimate.completeDays,
				weighIns: estimate.weighIns,
				updatedAt: new Date()
			}
		});
	const goal = health.goal;
	const heightMm = health.profile.heightMm;
	const resting = health.estimate?.restingKcal;
	if (goal.kind === 'track' || goal.targetKcal === null || !heightMm || !resting)
		return { proposed: false as const, reason: 'no_target' };
	const choice: GoalChoice = {
		kind: goal.kind,
		goalWeightG: goal.goalWeightG,
		paceBp: goal.paceBp
	};
	const next = nextTarget(goal.targetKcal, estimate.burnKcal, resting, trendG, heightMm, choice);
	if (next === null || Math.abs(next - goal.targetKcal) < MIN_CHANGE_KCAL)
		return { proposed: false as const, reason: 'no_change' };
	const row = await supersedeAndPropose(tx, userId, {
		kind: 'target',
		weekKey,
		basisHash: fingerprint(weights, intake),
		payload: {
			asOf: today,
			fromKcal: goal.targetKcal,
			toKcal: next,
			burnKcal: estimate.burnKcal,
			gramsPerWeek: Math.round((trendG * goal.paceBp) / 10_000),
			trendG
		}
	});
	return { proposed: true as const, proposalId: row?.id };
}

/**
 * The week in one card: food, weight, workouts and sleep for the week that just ended, with one thing to try. It is worked out here with no model call. The person may open it
 * and ask, and only then does the model see it. Nothing logged means no card.
 */
export async function runWeeklyReview(tx: Tx, userId: string, today: string) {
	const lastDay = addDays(mondayOf(today), -1);
	const firstDay = addDays(lastDay, -6);
	const intake = await intakeBetween(tx, userId, firstDay, lastDay);
	const weights = await weightsBetween(tx, userId, firstDay, lastDay);
	const train = await readTrain(tx, userId, lastDay);
	const sleep = await readSleep(tx, userId, lastDay, 7);
	const nothing =
		!intake.length && !weights.length && train.minutes === 0 && sleep.nights.length === 0;
	if (nothing) return { proposed: false as const };
	const first = weights[0];
	const last = weights.at(-1);
	const payload = {
		from: firstDay,
		to: lastDay,
		completeDays: intake.length,
		averageKcal: intake.length
			? Math.round(intake.reduce((a, d) => a + d.kcal, 0) / intake.length)
			: null,
		weighIns: weights.length,
		changeG: first && last && first !== last ? last.grams - first.grams : null,
		minutes: train.minutes,
		strengthDays: train.strengthDays,
		averageSleepMinutes: sleep.averageMinutes,
		suggestion: reviewSuggestion({
			completeDays: intake.length,
			weighIns: weights.length,
			minutes: train.minutes,
			minutesGoal: train.minutesGoal,
			averageSleepMinutes: sleep.averageMinutes
		})
	};
	const row = await supersedeAndPropose(tx, userId, {
		kind: 'review',
		weekKey: weekKeyOf(today),
		payload,
		basisHash: ''
	});
	return { proposed: true as const, proposalId: row?.id };
}

/** One thing to try next week, and only one: the first of these that applies. Sleep comes first because it makes the others easier. */
export function reviewSuggestion(w: {
	completeDays: number;
	weighIns: number;
	minutes: number;
	minutesGoal: number;
	averageSleepMinutes: number | null;
}): 'sleep_earlier' | 'log_food' | 'weigh_more' | 'move_more' | 'keep_going' {
	if (w.averageSleepMinutes !== null && w.averageSleepMinutes < SHORT_SLEEP_MINUTES)
		return 'sleep_earlier';
	if (w.completeDays < ENOUGH_FOOD_DAYS) return 'log_food';
	if (w.weighIns < ENOUGH_WEIGH_INS) return 'weigh_more';
	if (w.minutes < w.minutesGoal) return 'move_more';
	return 'keep_going';
}

/**
 * Answers a proposal. accept takes the value the person was shown, so they can never accept a different number from the one on the screen. A proposal that was replaced
 * or whose data changed is refused, and the limits are checked again. The assistant may send the answer only when the person gave it in that message.
 */
export async function answerProposal(ctx: Ctx, raw: ProposalAnswerInput) {
	const input = parse(proposalAnswerInput, raw);
	return mapped(() =>
		runWrite(ctx, 'health.proposal_answer', input, async (tx, userId) => {
			const [p] = await tx
				.select()
				.from(healthProposal)
				.where(and(eq(healthProposal.userId, userId), eq(healthProposal.id, input.proposalId)));
			if (!p) throw new OpsError('NOT_FOUND', 'That check-in is not there any more.');
			if (p.status === 'superseded')
				throw new OpsError('CONFLICT', 'A newer check-in replaced this one. Look at the new one.');
			if (p.status !== 'open' || p.expiresAt.getTime() < Date.now())
				throw new OpsError('CONFLICT', 'This check-in has already closed.');
			const payload = p.payload as {
				asOf?: string;
				toKcal?: number;
				fromKcal?: number;
				weekKey?: string;
			};
			let applied: unknown = null;
			if (input.accept && p.kind === 'target') {
				if (input.value !== payload.toKcal)
					throw new OpsError(
						'CONFLICT',
						`This check-in proposes ${payload.toKcal} kcal, not ${input.value ?? 'that'}. Look at it again.`
					);
				const asOf = payload.asOf ?? toLocalDate(new Date());
				const from = addDays(asOf, -(WINDOW_DAYS - 1));
				const basis = fingerprint(
					await weightsBetween(tx, userId, from, asOf),
					await intakeBetween(tx, userId, from, asOf)
				);
				if (basis !== p.basisHash)
					throw new OpsError(
						'CONFLICT',
						'Your food or weight changed after this was worked out. The next check-in will use the new numbers.'
					);
				const health = await readHealth(tx, userId, toLocalDate(new Date()));
				if (health.goal.kind === 'track' || health.goal.targetKcal !== payload.fromKcal)
					throw new OpsError(
						'CONFLICT',
						'Your goal changed after this was worked out. The next check-in will use the new goal.'
					);
				const toKcal = payload.toKcal ?? 0;
				if (health.estimate) {
					const refused = targetProblem(
						toKcal,
						health.estimate.restingKcal,
						health.estimate.burnKcal
					);
					if (refused) throw new OpsError('INVALID', refused);
				}
				await tx
					.update(healthGoal)
					.set({
						targetKcal: toKcal,
						version: sql`${healthGoal.version} + 1`,
						updatedAt: new Date()
					})
					.where(eq(healthGoal.userId, userId));
				applied = { targetKcal: toKcal };
			}
			if (input.accept && p.kind === 'week')
				applied = await acceptWeekProposal(tx, userId, p.payload, p.weekKey);
			await tx
				.update(healthProposal)
				.set({
					status: input.accept ? 'accepted' : 'kept',
					answeredAt: new Date(),
					updatedAt: new Date()
				})
				.where(and(eq(healthProposal.userId, userId), eq(healthProposal.id, input.proposalId)));
			return { proposalId: input.proposalId, accepted: input.accept, applied };
		})
	);
}
