// HEALTH RULES: THE FIRST CALORIE ESTIMATE AND THE SAFETY LIMITS (BTL-20261105-0015, ADR 5). PURE: NO DATABASE, NO CLOCK. WHOLE NUMBERS ONLY.
// Weight is in grams, height in millimetres, energy in whole kcal. The limits apply to every actor: the verbs refuse anything outside them.

// -- TYPES -- //

export type Sex = 'female' | 'male' | 'skip';
export type Activity = 'sitting' | 'some_walking' | 'on_feet' | 'very_active';
export type GoalKind = 'lose' | 'maintain' | 'gain' | 'track';

export type BodyFacts = {
	weightG: number;
	heightMm: number;
	birthYear: number;
	sex: Sex;
};

export type GoalChoice = {
	kind: GoalKind;
	/** Null for maintain and track. */
	goalWeightG: number | null;
	/** Basis points of body weight a week: 50 is 0.5%. */
	paceBp: number;
};

// -- CONSTANTS -- //

export const SEXES = ['female', 'male', 'skip'] as const;
export const ACTIVITIES = ['sitting', 'some_walking', 'on_feet', 'very_active'] as const;
export const GOAL_KINDS = ['lose', 'maintain', 'gain', 'track'] as const;

/** The usual multipliers of resting burn, in hundredths. A first estimate only: the weight trend replaces it. */
export const ACTIVITY_FACTOR: Record<Activity, number> = {
	sitting: 120,
	some_walking: 137,
	on_feet: 155,
	very_active: 172
};

/** Never a target under this, whatever the sums say. */
export const MIN_TARGET_KCAL = 1310;
/** Never further than this below the estimated burn. */
export const MAX_DEFICIT_KCAL = 1000;
/** Never further than this above the estimated burn. */
export const MAX_SURPLUS_KCAL = 500;
export const DEFAULT_PACE_BP = 50;
export const MIN_PACE_BP = 25;
/** Losing faster than 1% of body weight a week is refused. */
export const MAX_LOSS_PACE_BP = 100;
/** Gaining faster than 0.5% of body weight a week is refused. */
export const MAX_GAIN_PACE_BP = 50;
/** Tenths of a kilocalorie per gram of body weight change: 7,700 kcal per kg. */
const KCAL_PER_KG = 7700;
/** A goal under this body mass index is refused. In tenths: 185 is 18.5. */
export const MIN_BMI_TENTHS = 185;
/** Protein per kg of body weight, in tenths of a gram. */
export const DEFAULT_PROTEIN_TENTHS = 16;
export const MIN_PROTEIN_TENTHS = 14;
export const MAX_PROTEIN_TENTHS = 20;
/** A 7-day average under this brings the gentle message. */
export const LOW_INTAKE_KCAL = 800;

// -- FUNCTIONS -- //

const div = (a: number, b: number) => Math.round(a / b);

/** The Mifflin-St Jeor estimate of resting burn, in whole kcal. Skipping sex uses the midpoint of its two constants. */
export function restingBurn(f: BodyFacts, year: number): number {
	const age = year - f.birthYear;
	const constant = f.sex === 'male' ? 5 : f.sex === 'female' ? -161 : -78;
	// In hundredths so the whole sum stays in integers: 10 kcal per kg, 6.25 per cm, 5 per year
	const hundredths = (f.weightG / 100) * 100 + (f.heightMm * 625) / 10 - 500 * age + constant * 100;
	return div(hundredths, 100);
}

/** The first estimate of a day's burn. */
export function dailyBurn(f: BodyFacts, activity: Activity, year: number): number {
	return div(restingBurn(f, year) * ACTIVITY_FACTOR[activity], 100);
}

/** Body mass index in tenths: 74 kg at 170 cm is 256. */
export function bmiTenths(weightG: number, heightMm: number): number {
	return div((weightG * 10_000) / heightMm / heightMm, 1) / 1;
}

/** The lowest goal weight allowed for a height, in grams, rounded up to a whole 100 g. */
export function minGoalWeightG(heightMm: number): number {
	const grams = (MIN_BMI_TENTHS * heightMm * heightMm) / 10_000;
	return Math.ceil(grams / 100) * 100;
}

/** The energy gap a weekly pace needs, in kcal a day. */
export function paceKcalPerDay(weightG: number, paceBp: number): number {
	return div((((weightG * paceBp) / 10_000) * KCAL_PER_KG) / 1000, 7);
}

/** The lowest calorie target this person may have: their resting burn, and never under the hard floor. */
export function minTargetKcal(resting: number): number {
	return Math.max(resting, MIN_TARGET_KCAL);
}

/** The first problem with a goal in plain words, or null. Height is needed to check a goal weight. */
export function goalProblem(g: GoalChoice, weightG: number, heightMm: number): string | null {
	if (g.kind === 'maintain' || g.kind === 'track') return null;
	const floor = minGoalWeightG(heightMm);
	if (g.kind === 'lose') {
		if (weightG <= floor)
			return 'A weight loss goal is not available: you are already at the lower end of a healthy weight for your height.';
		if (g.goalWeightG === null) return 'Give a goal weight.';
		if (g.goalWeightG < floor)
			return `That goal is under a healthy weight for your height. The lowest goal here is ${(floor / 1000).toFixed(1)} kg.`;
		if (g.goalWeightG >= weightG) return 'A weight loss goal must be under your current weight.';
		if (g.paceBp < MIN_PACE_BP || g.paceBp > MAX_LOSS_PACE_BP)
			return 'Losing more than 1% of your body weight a week is not allowed here. Choose a slower pace.';
		return null;
	}
	if (g.goalWeightG === null) return 'Give a goal weight.';
	if (g.goalWeightG <= weightG) return 'A weight gain goal must be over your current weight.';
	if (g.paceBp < MIN_PACE_BP || g.paceBp > MAX_GAIN_PACE_BP)
		return 'Gaining more than 0.5% of your body weight a week is not allowed here. Choose a slower pace.';
	return null;
}

/**
 * The calorie target for a goal given a day's burn. Null for track. The gap never passes its limit, and the result never falls under the
 * floor, so a small body or a low burn gets a smaller gap rather than a target that is too low.
 */
export function targetFor(
	g: GoalChoice,
	weightG: number,
	burn: number,
	resting: number
): number | null {
	if (g.kind === 'track') return null;
	if (g.kind === 'maintain') return Math.max(burn, minTargetKcal(resting));
	const gap = paceKcalPerDay(weightG, g.paceBp);
	if (g.kind === 'gain') return burn + Math.min(gap, MAX_SURPLUS_KCAL);
	return Math.max(burn - Math.min(gap, MAX_DEFICIT_KCAL), minTargetKcal(resting));
}

/** A target from any source, held inside the limits. The verbs use this before anything is saved. */
export function targetProblem(kcal: number, resting: number, burn: number): string | null {
	const floor = minTargetKcal(resting);
	if (kcal < floor)
		return `That target is too low. The lowest target for you is ${floor.toLocaleString('en-US')} kcal a day.`;
	if (burn - kcal > MAX_DEFICIT_KCAL)
		return `That target is too far under what you burn. The lowest target for you now is ${(burn - MAX_DEFICIT_KCAL).toLocaleString('en-US')} kcal a day.`;
	return null;
}

/** The protein target in milligrams a day. */
export function proteinTargetMg(weightG: number, tenthsPerKg: number): number {
	return div(weightG * tenthsPerKg * 100, 1000);
}
