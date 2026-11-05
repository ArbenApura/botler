// THE WEIGHT TREND, THE REAL BURN AND THE WEEKLY TARGET (BTL-20261105-0015, P5). PURE: NO DATABASE, NO CLOCK. WHOLE NUMBERS AT THE EDGES.
// Food logs and scales are both noisy, so the burn is read from the two together: what was logged on complete days, plus what the weight did. Steady under-logging
// comes out in the burn, so the target still gets the result the person wants. A day that is not marked complete is left out, because a half-logged day says nothing.

// -- TYPES -- //
import type { ManilaDate } from '../finance/dates';
import type { GoalChoice } from './rules';
// -- MODULES -- //
import { addDays, diffDays } from '../finance/dates';
import { minGoalWeightG, targetFor } from './rules';

// -- TYPES -- //

export type WeighIn = { day: ManilaDate; grams: number };
export type IntakeDay = { day: ManilaDate; kcal: number };
export type TrendPoint = { day: ManilaDate; trendG: number; grams: number };

export type BurnEstimate = {
	burnKcal: number;
	intakeKcal: number;
	completeDays: number;
	weighIns: number;
	/** Grams a day, negative when weight is falling. */
	gramsPerDay: number;
};

export type Forecast =
	| { reachOn: ManilaDate; weeks: number; reason: null }
	| {
			reachOn: null;
			weeks: null;
			reason: 'flat' | 'wrong_way' | 'too_far' | 'no_goal' | 'reached';
	  };

// -- CONSTANTS -- //

/** How much of each new day moves the trend. A low number keeps one salty dinner from moving it. */
const TREND_ALPHA = 0.1;
export const WINDOW_DAYS = 28;
export const MIN_COMPLETE_DAYS = 14;
export const MIN_WEIGH_INS = 8;
export const MAX_WEEKLY_CHANGE_KCAL = 150;
/** A proposal this small is not worth a card. */
export const MIN_CHANGE_KCAL = 20;
const KCAL_PER_GRAM = 7.7;
/** Slower than this reads as flat: 70 g a week. */
const FLAT_GRAMS_PER_DAY = 10;
const FORECAST_HORIZON_DAYS = 730;

// -- FUNCTIONS -- //

/** The smoothed line through the weigh-ins, oldest first. A gap counts as that many days of settling. */
export function trendOf(weighIns: readonly WeighIn[]): TrendPoint[] {
	const sorted = [...weighIns].sort((a, b) => (a.day < b.day ? -1 : 1));
	const out: TrendPoint[] = [];
	let trend: number | null = null;
	let prevDay: ManilaDate | null = null;
	for (const w of sorted) {
		if (trend === null || prevDay === null) trend = w.grams;
		else {
			const keep = (1 - TREND_ALPHA) ** Math.max(1, diffDays(w.day, prevDay));
			trend = trend * keep + w.grams * (1 - keep);
		}
		out.push({ day: w.day, trendG: Math.round(trend), grams: w.grams });
		prevDay = w.day;
	}
	return out;
}

/** The straight line through the weigh-ins, in grams a day. Null with fewer than two different days. */
export function slopeOf(points: readonly WeighIn[]): number | null {
	const first = points[0];
	if (!first || points.length < 2) return null;
	const xs = points.map((p) => diffDays(p.day, first.day));
	const meanX = xs.reduce((a, b) => a + b, 0) / xs.length;
	const meanY = points.reduce((a, p) => a + p.grams, 0) / points.length;
	let top = 0;
	let bottom = 0;
	points.forEach((p, i) => {
		const dx = (xs[i] ?? 0) - meanX;
		top += dx * (p.grams - meanY);
		bottom += dx * dx;
	});
	return bottom === 0 ? null : top / bottom;
}

/** The burn over the window that ends on `asOf`, or null while there are too few complete days or weigh-ins. */
export function estimateBurn(
	asOf: ManilaDate,
	weighIns: readonly WeighIn[],
	intake: readonly IntakeDay[]
): BurnEstimate | null {
	const from = addDays(asOf, -(WINDOW_DAYS - 1));
	const inWindow = (d: ManilaDate) => d >= from && d <= asOf;
	const weights = weighIns.filter((w) => inWindow(w.day)).sort((a, b) => (a.day < b.day ? -1 : 1));
	const days = intake.filter((d) => inWindow(d.day));
	if (days.length < MIN_COMPLETE_DAYS || weights.length < MIN_WEIGH_INS) return null;
	const slope = slopeOf(weights);
	if (slope === null) return null;
	const intakeKcal = days.reduce((a, d) => a + d.kcal, 0) / days.length;
	return {
		burnKcal: Math.round(intakeKcal - slope * KCAL_PER_GRAM),
		intakeKcal: Math.round(intakeKcal),
		completeDays: days.length,
		weighIns: weights.length,
		gramsPerDay: slope
	};
}

/**
 * Next week's target. It follows the burn, moves at most 150 kcal from where it is, and never leaves the limits. A person who has reached the lowest healthy weight
 * for their height stops being asked to lose: the goal counts as maintain.
 */
export function nextTarget(
	currentKcal: number,
	burnKcal: number,
	restingKcal: number,
	weightG: number,
	heightMm: number,
	goal: GoalChoice
): number | null {
	const atFloor = goal.kind === 'lose' && weightG <= minGoalWeightG(heightMm);
	const wanted = targetFor(
		atFloor ? { ...goal, kind: 'maintain', goalWeightG: null } : goal,
		weightG,
		burnKcal,
		restingKcal
	);
	if (wanted === null) return null;
	const step = Math.max(
		-MAX_WEEKLY_CHANGE_KCAL,
		Math.min(MAX_WEEKLY_CHANGE_KCAL, wanted - currentKcal)
	);
	// The floor is in targetFor, and a step from a target already at the floor stays there
	return Math.max(currentKcal + step, Math.min(wanted, currentKcal));
}

/** About when the goal is reached at the present pace. Never a date from a flat or wrong-way trend. */
export function forecastGoal(
	today: ManilaDate,
	trendG: number,
	gramsPerDay: number | null,
	goalG: number | null
): Forecast {
	if (goalG === null || gramsPerDay === null)
		return { reachOn: null, weeks: null, reason: 'no_goal' };
	const left = goalG - trendG;
	if (Math.abs(left) < 100) return { reachOn: null, weeks: null, reason: 'reached' };
	if (Math.abs(gramsPerDay) < FLAT_GRAMS_PER_DAY)
		return { reachOn: null, weeks: null, reason: 'flat' };
	if (Math.sign(left) !== Math.sign(gramsPerDay))
		return { reachOn: null, weeks: null, reason: 'wrong_way' };
	const days = Math.ceil(left / gramsPerDay);
	if (days > FORECAST_HORIZON_DAYS) return { reachOn: null, weeks: null, reason: 'too_far' };
	return { reachOn: addDays(today, days), weeks: Math.round(days / 7), reason: null };
}

/** The ISO week of a date: 2026-W48. A week starts on Monday and belongs to the year of its Thursday. */
export function weekKeyOf(day: ManilaDate): string {
	const d = new Date(`${day}T00:00:00Z`);
	const weekdayFromMonday = (d.getUTCDay() + 6) % 7;
	const thursday = new Date(d.getTime() + (3 - weekdayFromMonday) * 86_400_000);
	const year = thursday.getUTCFullYear();
	const firstJan = Date.UTC(year, 0, 1);
	const week = Math.floor((thursday.getTime() - firstJan) / (7 * 86_400_000)) + 1;
	return `${year}-W${String(week).padStart(2, '0')}`;
}
