// SCHEDULE SEMANTICS (decision, P2.8): HOW PAYDAYS AND BILL DUE DATES REPEAT
// - semi_monthly(days): two days of the month, for example [15, 30]. A day past the end of a short month is clamped to the last day.
// - every_n_days(anchor, n): the anchor date and every n days after (and before) it. A 14 day pay cycle never drifts with the month.
// - monthly(day): one day of the month, clamped to the last day (the 31st in February is the 28th or 29th).
// - weekend rule: 'none' keeps the date, 'before' moves a Saturday, Sunday or holiday to the previous working day, 'after' to the next.
// All dates are Asia/Manila calendar dates (YYYY-MM-DD), so the Manila midnight boundary is the only day boundary there is.

// -- TYPES -- //
import type { ManilaDate } from './dates';
// -- MODULES -- //
import { addDays, daysInMonth, diffDays, formatDate, isDate, isWeekend, parseDate } from './dates';

// -- TYPES -- //

export type Schedule =
	| { kind: 'semi_monthly'; days: readonly [number, number] }
	| { kind: 'every_n_days'; anchor: ManilaDate; n: number }
	| { kind: 'monthly'; day: number };

export type WeekendRule = 'none' | 'before' | 'after';

export type ScheduleOptions = {
	weekend?: WeekendRule;
	/** Non-working days besides weekends, as Manila dates. */
	holidays?: readonly string[];
};

// -- CONSTANTS -- //

export const WEEKEND_RULES = ['none', 'before', 'after'] as const;

const MAX_SHIFT = 10;

// -- FUNCTIONS -- //

const isDay = (n: number) => Number.isInteger(n) && n >= 1 && n <= 31;

/** The first problem with a schedule, in plain words, or null when it is valid. */
export function validateSchedule(s: Schedule): string | null {
	switch (s.kind) {
		case 'semi_monthly': {
			const [a, b] = s.days;
			if (!isDay(a) || !isDay(b)) return 'Pick two days of the month, from 1 to 31.';
			if (a === b) return 'The two paydays must be different days.';
			return null;
		}
		case 'every_n_days':
			if (!isDate(s.anchor)) return 'The start date is not a real date.';
			if (!Number.isInteger(s.n) || s.n < 1 || s.n > 366) return 'Repeat every 1 to 366 days.';
			return null;
		case 'monthly':
			return isDay(s.day) ? null : 'Pick a day of the month, from 1 to 31.';
	}
}

function isOff(d: ManilaDate, holidays: ReadonlySet<string>): boolean {
	return isWeekend(d) || holidays.has(d);
}

/** Moves a date off a weekend or holiday as the rule says. */
export function adjustForWeekend(
	d: ManilaDate,
	rule: WeekendRule,
	holidays: readonly string[] = []
): ManilaDate {
	if (rule === 'none') return d;
	const off = new Set(holidays);
	const step = rule === 'before' ? -1 : 1;
	let out = d;
	for (let i = 0; i < MAX_SHIFT && isOff(out, off); i++) out = addDays(out, step);
	return out;
}

/** The dates of a schedule before any weekend rule, from `from` to `to` inclusive. */
function nominal(s: Schedule, from: ManilaDate, to: ManilaDate): ManilaDate[] {
	const out: ManilaDate[] = [];
	if (s.kind === 'every_n_days') {
		// The first multiple of n at or after `from`. Math.ceil also works when the anchor is after the window
		const k = Math.ceil(diffDays(from, s.anchor) / s.n);
		for (let d = addDays(s.anchor, k * s.n); d <= to; d = addDays(d, s.n)) out.push(d);
		return out;
	}
	const start = parseDate(from);
	const end = parseDate(to);
	if (!start || !end) return out;
	const days = s.kind === 'monthly' ? [s.day] : s.days;
	for (let y = start.year, m = start.month; y < end.year || (y === end.year && m <= end.month);) {
		for (const day of days) {
			const d = formatDate(y, m, Math.min(day, daysInMonth(y, m)));
			if (d >= from && d <= to) out.push(d);
		}
		if (++m > 12) {
			m = 1;
			y++;
		}
	}
	return out;
}

/**
 * Every date the schedule falls on between `from` and `to` inclusive, after the weekend rule, sorted, without repeats.
 * A date moved by the rule counts in the window it lands in, so a payday that moves from Saturday the 31st to Friday the 30th
 * belongs to a window ending on the 30th.
 */
export function occurrencesBetween(
	s: Schedule,
	from: ManilaDate,
	to: ManilaDate,
	opts: ScheduleOptions = {}
): ManilaDate[] {
	const problem = validateSchedule(s);
	if (problem) throw new RangeError(problem);
	const rule = opts.weekend ?? 'none';
	// A date just outside the window can move into it, so look a little wider and filter after the move
	const pad = rule === 'none' ? 0 : MAX_SHIFT;
	const wide = nominal(s, addDays(from, -pad), addDays(to, pad));
	const moved = wide.map((d) => adjustForWeekend(d, rule, opts.holidays));
	return [...new Set(moved)].filter((d) => d >= from && d <= to).sort();
}

/** The first date strictly after `after`, or null when there is none within a few years. */
export function nextOccurrence(
	s: Schedule,
	after: ManilaDate,
	opts: ScheduleOptions = {}
): ManilaDate | null {
	const from = addDays(after, 1);
	return occurrencesBetween(s, from, addDays(from, 800), opts)[0] ?? null;
}
