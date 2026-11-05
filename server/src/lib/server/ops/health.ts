// HEALTH PROFILE AND GOAL VERBS (BTL-20261105-0015): SETUP, THE GOAL AND THE CALORIE TARGET IN FORCE
// The assistant may do all of this for the person (ADR 10). The safety limits are checked here for every actor, so no caller can get past them.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { HealthGoalSetInput, HealthProfileSaveInput } from '../db/zod';
import type { Activity, BodyFacts, GoalChoice, GoalKind, Sex } from '../../health/rules';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, desc, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, parseDate, toLocalDate } from '../../finance/dates';
import {
	dailyBurn,
	DEFAULT_PACE_BP,
	DEFAULT_PROTEIN_TENTHS,
	goalProblem,
	minGoalWeightG,
	minTargetKcal,
	paceKcalPerDay,
	proteinTargetMg,
	restingBurn,
	targetFor,
	targetProblem
} from '../../health/rules';
import { energyEstimate, healthGoal, healthProfile, weightEntry } from '../db/schema';
import { healthGoalSetInput, healthProfileSaveInput } from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { mapped, parse } from './shared';

// -- TYPES -- //

export type HealthView = {
	profile: {
		heightMm: number | null;
		birthYear: number | null;
		sex: Sex;
		activity: Activity;
		setupDone: boolean;
	};
	/** What setup still needs before a calorie target can be worked out. */
	missing: ('height' | 'birth_year' | 'weight')[];
	latestWeightG: number | null;
	latestWeightDay: string | null;
	goal: {
		kind: GoalKind;
		goalWeightG: number | null;
		paceBp: number;
		targetKcal: number | null;
		proteinTenths: number;
		proteinTargetMg: number | null;
	};
	/** All of these are estimates, and null until setup has the facts. */
	estimate: {
		restingKcal: number;
		burnKcal: number;
		/** Worked out from the formula, or from the weight trend once the weekly job has enough days. */
		burnSource: 'formula' | 'trend';
		minTargetKcal: number;
		lowestGoalWeightG: number;
		paceKcalPerDay: number;
	} | null;
};

// -- FUNCTIONS -- //

/** Everything the limits and screens need, read in the caller's transaction. */
export async function readHealth(tx: Tx, userId: string, today: string): Promise<HealthView> {
	const [p] = await tx.select().from(healthProfile).where(eq(healthProfile.userId, userId));
	const [g] = await tx.select().from(healthGoal).where(eq(healthGoal.userId, userId));
	const [w] = await tx
		.select({ grams: weightEntry.grams, day: weightEntry.day })
		.from(weightEntry)
		.where(eq(weightEntry.userId, userId))
		.orderBy(desc(weightEntry.day))
		.limit(1);
	const [e] = await tx
		.select({ burnKcal: energyEstimate.burnKcal, trendG: energyEstimate.trendG })
		.from(energyEstimate)
		.where(eq(energyEstimate.userId, userId))
		.orderBy(desc(energyEstimate.weekKey))
		.limit(1);
	const profile = {
		heightMm: p?.heightMm ?? null,
		birthYear: p?.birthYear ?? null,
		sex: p?.sex ?? 'skip',
		activity: p?.activity ?? 'sitting',
		setupDone: p?.setupDoneAt != null
	};
	const missing: HealthView['missing'] = [];
	if (profile.heightMm === null) missing.push('height');
	if (profile.birthYear === null) missing.push('birth_year');
	// The trend is the better figure for current weight once there is one
	const currentG = e?.trendG ?? w?.grams ?? null;
	if (currentG === null) missing.push('weight');
	const paceBp = g?.paceBp ?? DEFAULT_PACE_BP;
	const proteinTenths = g?.proteinTenths ?? DEFAULT_PROTEIN_TENTHS;
	let estimate: HealthView['estimate'] = null;
	if (missing.length === 0) {
		// The checks above make these present
		const facts = factsOf(profile.heightMm, profile.birthYear, profile.sex, currentG);
		const year = parseDate(today)?.year ?? new Date().getUTCFullYear();
		const resting = restingBurn(facts, year);
		estimate = {
			restingKcal: resting,
			burnKcal: e?.burnKcal ?? dailyBurn(facts, profile.activity, year),
			burnSource: e ? 'trend' : 'formula',
			minTargetKcal: minTargetKcal(resting),
			lowestGoalWeightG: minGoalWeightG(facts.heightMm),
			paceKcalPerDay: paceKcalPerDay(facts.weightG, paceBp)
		};
	}
	return {
		profile,
		missing,
		latestWeightG: w?.grams ?? null,
		latestWeightDay: w?.day ?? null,
		goal: {
			kind: g?.kind ?? 'track',
			goalWeightG: g?.goalWeightG ?? null,
			paceBp,
			targetKcal: g?.targetKcal ?? null,
			proteinTenths,
			proteinTargetMg: currentG === null ? null : proteinTargetMg(currentG, proteinTenths)
		},
		estimate
	};
}

function factsOf(
	heightMm: number | null,
	birthYear: number | null,
	sex: Sex,
	weightG: number | null
): BodyFacts {
	if (heightMm === null || birthYear === null || weightG === null)
		throw new OpsError('INVALID', 'Your height, birth year and weight are needed first.');
	return { heightMm, birthYear, sex, weightG };
}

/**
 * What a goal would mean, before it is saved: the target, the weekly change and about when the goal weight is reached. Writes nothing. A goal
 * outside the limits answers its problem in plain words, so a screen can show it under the field.
 */
export async function previewHealthGoal(ctx: Ctx, raw: HealthGoalSetInput) {
	const input = parse(healthGoalSetInput, raw);
	return run(ctx, async (tx, userId) => {
		const today = toLocalDate(new Date());
		const now = await readHealth(tx, userId, today);
		const choice: GoalChoice = {
			kind: input.kind ?? now.goal.kind,
			goalWeightG: input.goalWeightG !== undefined ? input.goalWeightG : now.goal.goalWeightG,
			paceBp: input.paceBp ?? now.goal.paceBp
		};
		const weightG = now.latestWeightG;
		const heightMm = now.profile.heightMm;
		if (!now.estimate || weightG === null || heightMm === null)
			return {
				problem: null,
				missing: now.missing,
				targetKcal: null,
				gramsPerWeek: null,
				reachOn: null
			};
		const problem = goalProblem(choice, weightG, heightMm);
		const targetKcal = problem
			? null
			: targetFor(choice, weightG, now.estimate.burnKcal, now.estimate.restingKcal);
		const gramsPerWeek = Math.round((weightG * choice.paceBp) / 10_000);
		const gap = choice.goalWeightG === null ? null : Math.abs(weightG - choice.goalWeightG);
		const reachOn =
			problem || gap === null || gramsPerWeek <= 0
				? null
				: addDays(today, Math.ceil((gap / gramsPerWeek) * 7));
		return { problem, missing: now.missing, targetKcal, gramsPerWeek, reachOn };
	});
}

export async function getHealth(ctx: Ctx): Promise<HealthView> {
	return run(ctx, (tx, userId) => readHealth(tx, userId, toLocalDate(new Date())));
}

/** Saves the facts given and keeps the rest. A weight is today's weigh-in. Setup can stop halfway and carry on later. */
export async function saveHealthProfile(ctx: Ctx, raw: HealthProfileSaveInput) {
	const input = parse(healthProfileSaveInput, raw);
	return mapped(() =>
		runWrite(ctx, 'health.profile_save', input, async (tx, userId) => {
			const today = toLocalDate(new Date());
			const { weightG, setupDone, ...facts } = input;
			const setupDoneAt =
				setupDone === undefined ? {} : { setupDoneAt: setupDone ? new Date() : null };
			await tx
				.insert(healthProfile)
				.values({ userId, ...facts, ...setupDoneAt })
				.onConflictDoUpdate({
					target: healthProfile.userId,
					set: {
						...facts,
						...setupDoneAt,
						version: sql`${healthProfile.version} + 1`,
						updatedAt: new Date()
					}
				});
			if (weightG !== undefined)
				await tx
					.insert(weightEntry)
					.values({ userId, day: today, grams: weightG, byAgent: ctx.actor.kind === 'agent' })
					.onConflictDoUpdate({
						target: [weightEntry.userId, weightEntry.day],
						set: { grams: weightG, updatedAt: new Date() }
					});
			return readHealth(tx, userId, today);
		})
	);
}

/**
 * Sets the goal and the target from it. A target given by the caller is used when it is inside the limits; otherwise the target follows the
 * burn and the pace. Track needs no facts; the others are refused until setup has them, because the limits depend on them.
 */
export async function setHealthGoal(ctx: Ctx, raw: HealthGoalSetInput) {
	const input = parse(healthGoalSetInput, raw);
	return mapped(() =>
		runWrite(ctx, 'health.goal_set', input, async (tx, userId) => {
			const today = toLocalDate(new Date());
			const now = await readHealth(tx, userId, today);
			const choice: GoalChoice = {
				kind: input.kind ?? now.goal.kind,
				goalWeightG: input.goalWeightG !== undefined ? input.goalWeightG : now.goal.goalWeightG,
				paceBp: input.paceBp ?? now.goal.paceBp
			};
			if (choice.kind === 'maintain' || choice.kind === 'track') choice.goalWeightG = null;
			const proteinTenths = input.proteinTenths ?? now.goal.proteinTenths;
			let target: number | null = null;
			if (choice.kind !== 'track') {
				const est = now.estimate;
				const [p] = await tx
					.select({ heightMm: healthProfile.heightMm })
					.from(healthProfile)
					.where(and(eq(healthProfile.userId, userId)));
				const weightG = now.latestWeightG;
				if (!est || !p?.heightMm || weightG === null)
					throw new OpsError(
						'INVALID',
						`Set up Health first: ${now.missing.join(', ').replaceAll('_', ' ')} still missing.`
					);
				const problem = goalProblem(choice, weightG, p.heightMm);
				if (problem) throw new OpsError('INVALID', problem);
				target = input.targetKcal ?? targetFor(choice, weightG, est.burnKcal, est.restingKcal);
				if (target !== null) {
					const refused = targetProblem(target, est.restingKcal, est.burnKcal);
					if (refused) throw new OpsError('INVALID', refused);
				}
			}
			const values = {
				kind: choice.kind,
				goalWeightG: choice.goalWeightG,
				paceBp: choice.paceBp,
				proteinTenths,
				targetKcal: target
			};
			await tx
				.insert(healthGoal)
				.values({ userId, ...values })
				.onConflictDoUpdate({
					target: healthGoal.userId,
					set: { ...values, version: sql`${healthGoal.version} + 1`, updatedAt: new Date() }
				});
			return readHealth(tx, userId, today);
		})
	);
}
