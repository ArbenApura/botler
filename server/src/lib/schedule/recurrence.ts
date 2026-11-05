// REPEATING THINGS OF EVERY DAY LIFE (A GYM DAY, A MEDICINE, A WEEKLY CALL): A RULE PLUS A CLOCK TIME IN ASIA/MANILA.
// Dates are chosen the way src/lib/finance/schedule.ts chooses them (so a day-31 rule clamps to the last day and a 14 day cycle never drifts);
// weekly and daily rules are added here. The result is instants, because a reminder fires at a moment, not on a day.
// freq 'schedule' takes any schedule of the finance engine (1st Wednesday, week of the month, a day range, every k months ...) plus a time;
// a window fires on its first day.

// -- TYPES -- //
import type { ManilaDate } from '../finance/dates';
import type { Schedule } from '../finance/schedule';
// -- MODULES -- //
import { addDays, atLocalTime, toLocalDate, weekday } from '../finance/dates';
// The clock-time helper lives with the zone maths; callers of the recurrence module keep importing it from here
export { atLocalTime };
import { occurrencesBetween, validateSchedule, windowsBetween } from '../finance/schedule';

// -- TYPES -- //

export type Recurrence =
	| { freq: 'daily'; time: string }
	/** days: 0 is Sunday, 6 is Saturday. */
	| { freq: 'weekly'; days: readonly number[]; time: string }
	| { freq: 'monthly'; day: number; time: string }
	| { freq: 'every_n_days'; anchor: ManilaDate; n: number; time: string }
	| { freq: 'schedule'; schedule: Schedule; time: string };

// -- CONSTANTS -- //

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

// -- FUNCTIONS -- //

export const isTime = (t: string): boolean => TIME_RE.test(t);

/** The first problem with a recurrence in plain words, or null. */
export function validateRecurrence(r: Recurrence): string | null {
	if (!isTime(r.time)) return 'Use a time like 06:30.';
	switch (r.freq) {
		case 'daily':
			return null;
		case 'weekly':
			if (r.days.length === 0 || r.days.some((d) => !Number.isInteger(d) || d < 0 || d > 6))
				return 'Pick the days of the week (0 Sunday to 6 Saturday).';
			return null;
		case 'monthly':
			return Number.isInteger(r.day) && r.day >= 1 && r.day <= 31
				? null
				: 'Pick a day of the month, 1 to 31.';
		case 'every_n_days':
			return Number.isInteger(r.n) && r.n >= 1 && r.n <= 366 ? null : 'Repeat every 1 to 366 days.';
		case 'schedule':
			return validateSchedule(r.schedule);
	}
}

/** Every moment the rule fires between two instants, inclusive, earliest first. */
export function recurrenceOccurrences(r: Recurrence, from: Date, to: Date): Date[] {
	const problem = validateRecurrence(r);
	if (problem) throw new RangeError(problem);
	// A day either side, so an instant near midnight is not lost to the day it falls in
	const first = addDays(toLocalDate(from), -1);
	const last = addDays(toLocalDate(to), 1);
	let dates: ManilaDate[] = [];
	switch (r.freq) {
		case 'daily':
			for (let d = first; d <= last; d = addDays(d, 1)) dates.push(d);
			break;
		case 'weekly':
			for (let d = first; d <= last; d = addDays(d, 1))
				if (r.days.includes(weekday(d))) dates.push(d);
			break;
		case 'monthly':
			dates = occurrencesBetween({ kind: 'monthly', day: r.day }, first, last);
			break;
		case 'every_n_days':
			dates = occurrencesBetween({ kind: 'every_n_days', anchor: r.anchor, n: r.n }, first, last);
			break;
		case 'schedule':
			// A window is found by its end, so look a month past the range and keep the windows that START inside it
			dates = windowsBetween(r.schedule, first, addDays(last, 31))
				.map((w) => w.start)
				.filter((d) => d >= first && d <= last);
			break;
	}
	return dates
		.map((d) => atLocalTime(d, r.time))
		.filter((t) => t.getTime() >= from.getTime() && t.getTime() <= to.getTime());
}

/** The next moment strictly after `after`, or null when there is none within two years. */
export function nextOccurrence(r: Recurrence, after: Date): Date | null {
	const horizon = new Date(after.getTime() + 2 * 366 * 86_400_000);
	return recurrenceOccurrences(r, new Date(after.getTime() + 1), horizon)[0] ?? null;
}
