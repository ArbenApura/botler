// SCHEDULE SEMANTICS (decision, P2.8): HOW PAYDAYS AND BILL DUE DATES REPEAT
// - semi_monthly(days): two days of the month, for example [15, 30]. A day past the end of a short month is clamped to the last day. When both days clamp to the same date (for example [30, 31] in February) that month has one payday on that date, not two; any two days that stay different keep both.
// - every_n_days(anchor, n): the anchor date and every n days after (and before) it. A 14 day pay cycle never drifts with the month.
// - monthly(day): one day of the month, clamped to the last day (the 31st in February is the 28th or 29th). Day -1 is the last day.
// - weekend rule: 'none' keeps the date, 'before' moves a Saturday, Sunday or holiday to the previous working day, 'after' to the next.
// All dates are Asia/Manila calendar dates (YYYY-MM-DD), so the Manila midnight boundary is the only day boundary there is.
//
// FLEXIBLE SCHEDULES (BTL-20261022-0218, ADR 1). Every occurrence is a window {start, end}; a single day has start == end and the end is
// the due date, so a bill that can be paid "any day in the first week" is due on the last day of that week.
// - weekly(days, everyWeeks, anchor): chosen weekdays, every week or every few weeks counted from the week of the anchor (Monday based).
// - nth_weekday(n, weekday, everyMonths): the 1st to 5th or last (-1) weekday of the month, such as every 1st Wednesday. A month without a
//   5th such weekday is skipped.
// - week_of_month(n, basis, pick, ...): the Nth week of the month. basis 'days' means days 1-7, 8-14 and so on (the last week is the last 7
//   days); basis 'calendar' means calendar weeks that start on weekStartsOn, the first one being the week that holds the 1st, clipped to the
//   month. pick 'window' keeps the whole week as a payment window; pick 'weekday' keeps one weekday inside it and skips the month when
//   that weekday is not inside the (clipped) week.
// - day_range(from, to, everyMonths): any day from the 5th to the 10th, clamped to the length of the month; to -1 is the last day.
// - yearly(month, day): once a year, the 29th of February clamped to the 28th in a common year.
// - once(date): a single date that never repeats, for a one-time bill. The weekend rule still applies.
// everyMonths counts months from anchorMonth (YYYY-MM), which is required when it is above 1, so a two month cycle never drifts.
// The weekend rule moves the END of a window only; the start stays unless it would pass the end.

// -- TYPES -- //
import type { ManilaDate } from './dates';
// -- MODULES -- //
import {
	addDays,
	daysInMonth,
	diffDays,
	formatDate,
	isDate,
	isWeekend,
	parseDate,
	weekday
} from './dates';

// -- TYPES -- //

export type ScheduleRule =
	| { kind: 'semi_monthly'; days: readonly [number, number] }
	| { kind: 'every_n_days'; anchor: ManilaDate; n: number }
	| { kind: 'monthly'; day: number; everyMonths?: number; anchorMonth?: string }
	| { kind: 'weekly'; days: readonly number[]; everyWeeks?: number; anchor?: ManilaDate }
	| { kind: 'nth_weekday'; n: number; weekday: number; everyMonths?: number; anchorMonth?: string }
	| {
			kind: 'week_of_month';
			n: number;
			basis: 'days' | 'calendar';
			weekStartsOn?: number;
			pick: 'window' | 'weekday';
			weekday?: number;
			everyMonths?: number;
			anchorMonth?: string;
	  }
	| { kind: 'day_range'; from: number; to: number; everyMonths?: number; anchorMonth?: string }
	| { kind: 'yearly'; month: number; day: number }
	| { kind: 'once'; date: ManilaDate };

/**
 * Limits on any schedule: the first and last due date that count (a one-time schedule ignores both) and single due dates left out, as the
 * person sees them (after the weekend rule). They let a payday skip one date or start later without changing the repeat pattern.
 */
export type ScheduleLimits = {
	startsOn?: ManilaDate;
	endsOn?: ManilaDate;
	skipDates?: readonly ManilaDate[];
};

export type Schedule = ScheduleRule & ScheduleLimits;

export type WeekendRule = 'none' | 'before' | 'after';

export type ScheduleOptions = {
	weekend?: WeekendRule;
	/** Non-working days besides weekends, as Manila dates. */
	holidays?: readonly string[];
};

/** One occurrence: the days it may be paid or done, and the due date (the end). */
export type ScheduleWindow = { start: ManilaDate; end: ManilaDate };

/** A sentence for a schedule, as a key plus arguments (so the app can translate it) and the English text. */
export type ScheduleDescription = {
	key: string;
	args: Record<string, string | number>;
	text: string;
};

// -- CONSTANTS -- //

export const WEEKEND_RULES = ['none', 'before', 'after'] as const;

export const SCHEDULE_KINDS = [
	'semi_monthly',
	'every_n_days',
	'monthly',
	'weekly',
	'nth_weekday',
	'week_of_month',
	'day_range',
	'yearly',
	'once'
] as const;

const MAX_SHIFT = 10;

/** Most single due dates one schedule can leave out. */
export const MAX_SKIP_DATES = 60;

const WEEKDAY_NAMES = [
	'Sunday',
	'Monday',
	'Tuesday',
	'Wednesday',
	'Thursday',
	'Friday',
	'Saturday'
] as const;

const MONTH_NAMES = [
	'January',
	'February',
	'March',
	'April',
	'May',
	'June',
	'July',
	'August',
	'September',
	'October',
	'November',
	'December'
] as const;

const MONTH_RE = /^(\d{4})-(0[1-9]|1[0-2])$/;

// -- FUNCTIONS -- //

const isDay = (n: number) => Number.isInteger(n) && n >= 1 && n <= 31;
const isDayOrLast = (n: number) => n === -1 || isDay(n);
const isWeekdayNumber = (n: number) => Number.isInteger(n) && n >= 0 && n <= 6;
const isNth = (n: number) => n === -1 || (Number.isInteger(n) && n >= 1 && n <= 5);

function ordinal(n: number): string {
	if (n === -1) return 'last';
	const rest = n % 100;
	if (rest >= 11 && rest <= 13) return `${n}th`;
	return `${n}${['th', 'st', 'nd', 'rd'][n % 10 > 3 ? 0 : n % 10] ?? 'th'}`;
}

/** The first problem in an "every k months from a month" pair, or null. */
function monthCycleProblem(everyMonths: number | undefined, anchorMonth: string | undefined) {
	const every = everyMonths ?? 1;
	if (!Number.isInteger(every) || every < 1 || every > 24) return 'Repeat every 1 to 24 months.';
	if (every > 1 && (anchorMonth === undefined || !MONTH_RE.test(anchorMonth)))
		return 'Add "anchorMonth" inside the schedule: the month the cycle starts in, YYYY-MM, for example 2026-10.';
	if (anchorMonth !== undefined && !MONTH_RE.test(anchorMonth))
		return 'The cycle month must look like 2026-10.';
	return null;
}

/** The first problem with the start, end and skipped dates of a schedule, or null. */
function limitsProblem(s: ScheduleLimits): string | null {
	if (s.startsOn !== undefined && !isDate(s.startsOn)) return 'The first date is not a real date.';
	if (s.endsOn !== undefined && !isDate(s.endsOn)) return 'The last date is not a real date.';
	if (s.startsOn !== undefined && s.endsOn !== undefined && s.startsOn > s.endsOn)
		return 'The first date must not be after the last date.';
	if (s.skipDates !== undefined) {
		if (s.skipDates.length > MAX_SKIP_DATES) return `Leave out at most ${MAX_SKIP_DATES} dates.`;
		if (s.skipDates.some((d) => !isDate(d))) return 'A date to leave out is not a real date.';
	}
	return null;
}

/** The first problem with a schedule, in plain words, or null when it is valid. */
export function validateSchedule(s: Schedule): string | null {
	return limitsProblem(s) ?? validateRule(s);
}

function validateRule(s: ScheduleRule): string | null {
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
			if (!isDayOrLast(s.day)) return 'Pick a day of the month, from 1 to 31, or the last day.';
			return monthCycleProblem(s.everyMonths, s.anchorMonth);
		case 'weekly': {
			if (s.days.length === 0 || s.days.some((d) => !isWeekdayNumber(d)))
				return 'Pick the days of the week (0 Sunday to 6 Saturday).';
			if (new Set(s.days).size !== s.days.length) return 'Each weekday can be picked once.';
			const every = s.everyWeeks ?? 1;
			if (!Number.isInteger(every) || every < 1 || every > 52) return 'Repeat every 1 to 52 weeks.';
			if (every > 1 && (s.anchor === undefined || !isDate(s.anchor)))
				return 'Add "anchor" inside the schedule: a YYYY-MM-DD date that falls on one of the chosen weekdays in a week the schedule counts (for example the next one), so every other week is known.';
			return null;
		}
		case 'nth_weekday':
			if (!isNth(s.n)) return 'Pick the 1st to the 5th weekday of the month, or the last.';
			if (!isWeekdayNumber(s.weekday)) return 'Pick a day of the week (0 Sunday to 6 Saturday).';
			return monthCycleProblem(s.everyMonths, s.anchorMonth);
		case 'week_of_month': {
			if (!isNth(s.n)) return 'Pick the 1st to the 5th week of the month, or the last week.';
			if (s.basis !== 'days' && s.basis !== 'calendar')
				return 'Weeks count as days 1 to 7, or as calendar weeks.';
			if (s.weekStartsOn !== undefined && s.weekStartsOn !== 0 && s.weekStartsOn !== 1)
				return 'A week starts on Sunday (0) or Monday (1).';
			if (s.pick !== 'window' && s.pick !== 'weekday')
				return 'Pick any day in the week, or one weekday.';
			if (s.pick === 'weekday' && (s.weekday === undefined || !isWeekdayNumber(s.weekday)))
				return 'Pick a day of the week (0 Sunday to 6 Saturday).';
			return monthCycleProblem(s.everyMonths, s.anchorMonth);
		}
		case 'day_range':
			if (!isDay(s.from) || !isDayOrLast(s.to)) return 'Pick days of the month, from 1 to 31.';
			if (s.to !== -1 && s.from > s.to) return 'The first day must not be after the last day.';
			return monthCycleProblem(s.everyMonths, s.anchorMonth);
		case 'yearly':
			if (!Number.isInteger(s.month) || s.month < 1 || s.month > 12)
				return 'Pick a month, 1 to 12.';
			// 2028 is a leap year, so the 29th of February is allowed
			if (!Number.isInteger(s.day) || s.day < 1 || s.day > daysInMonth(2028, s.month))
				return 'That day is not in that month.';
			return null;
		case 'once':
			return isDate(s.date) ? null : 'The date is not a real date.';
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

const single = (d: ManilaDate): ScheduleWindow => ({ start: d, end: d });

/** A month's index on a line, so "every k months from a month" is plain modular arithmetic. */
const monthIndex = (year: number, month: number) => year * 12 + (month - 1);

function monthIsActive(
	year: number,
	month: number,
	everyMonths: number | undefined,
	anchorMonth: string | undefined
): boolean {
	const every = everyMonths ?? 1;
	if (every === 1 || anchorMonth === undefined) return true;
	const m = MONTH_RE.exec(anchorMonth);
	if (!m) return true;
	const diff = monthIndex(year, month) - monthIndex(Number(m[1]), Number(m[2]));
	return ((diff % every) + every) % every === 0;
}

/** The windows of the month-based kinds inside one month. */
function windowsInMonth(s: Schedule, year: number, month: number): ScheduleWindow[] {
	const dim = daysInMonth(year, month);
	const day = (d: number) => formatDate(year, month, d);
	switch (s.kind) {
		case 'monthly': {
			if (!monthIsActive(year, month, s.everyMonths, s.anchorMonth)) return [];
			return [single(day(s.day === -1 ? dim : Math.min(s.day, dim)))];
		}
		case 'semi_monthly':
			return s.days.map((d) => single(day(Math.min(d, dim))));
		case 'nth_weekday': {
			if (!monthIsActive(year, month, s.everyMonths, s.anchorMonth)) return [];
			const first = formatDate(year, month, 1);
			if (s.n === -1) {
				const last = day(dim);
				const back = (weekday(last) - s.weekday + 7) % 7;
				return [single(addDays(last, -back))];
			}
			const forward = (s.weekday - weekday(first) + 7) % 7;
			const date = 1 + forward + 7 * (s.n - 1);
			return date > dim ? [] : [single(day(date))];
		}
		case 'week_of_month': {
			if (!monthIsActive(year, month, s.everyMonths, s.anchorMonth)) return [];
			const win = weekWindow(s, year, month);
			if (!win) return [];
			if (s.pick === 'window') return [win];
			// One weekday inside the (clipped) week; a month where it falls outside is skipped
			for (let d = win.start; d <= win.end; d = addDays(d, 1))
				if (weekday(d) === s.weekday) return [single(d)];
			return [];
		}
		case 'day_range': {
			if (!monthIsActive(year, month, s.everyMonths, s.anchorMonth)) return [];
			const start = Math.min(s.from, dim);
			const end = s.to === -1 ? dim : Math.min(s.to, dim);
			return [{ start: day(start), end: day(Math.max(start, end)) }];
		}
		default:
			return [];
	}
}

/** The Nth week of a month as a window clipped to the month, or null when the month has no such week. */
function weekWindow(
	s: Extract<Schedule, { kind: 'week_of_month' }>,
	year: number,
	month: number
): ScheduleWindow | null {
	const dim = daysInMonth(year, month);
	const first = formatDate(year, month, 1);
	const last = formatDate(year, month, dim);
	if (s.basis === 'days') {
		if (s.n === -1) return { start: formatDate(year, month, dim - 6), end: last };
		const start = (s.n - 1) * 7 + 1;
		if (start > dim) return null;
		return {
			start: formatDate(year, month, start),
			end: formatDate(year, month, Math.min(s.n * 7, dim))
		};
	}
	// Calendar weeks: the week that holds the 1st is week 1, a week that spills over the month edge is clipped
	const weekStart = s.weekStartsOn ?? 1;
	const firstWeekStart = addDays(first, -((weekday(first) - weekStart + 7) % 7));
	const lastWeekStart = addDays(last, -((weekday(last) - weekStart + 7) % 7));
	const startOfWeek = s.n === -1 ? lastWeekStart : addDays(firstWeekStart, 7 * (s.n - 1));
	if (startOfWeek > last) return null;
	const endOfWeek = addDays(startOfWeek, 6);
	return {
		start: startOfWeek < first ? first : startOfWeek,
		end: endOfWeek > last ? last : endOfWeek
	};
}

/** The windows of a schedule before any weekend rule, whose END falls from `from` to `to` inclusive (a little wider is allowed). */
function nominal(s: Schedule, from: ManilaDate, to: ManilaDate): ScheduleWindow[] {
	const out: ScheduleWindow[] = [];
	if (s.kind === 'every_n_days') {
		// The first multiple of n at or after `from`. Math.ceil also works when the anchor is after the window
		const k = Math.ceil(diffDays(from, s.anchor) / s.n);
		for (let d = addDays(s.anchor, k * s.n); d <= to; d = addDays(d, s.n)) out.push(single(d));
		return out;
	}
	if (s.kind === 'once') {
		// One date that never repeats
		if (s.date >= from && s.date <= to) out.push(single(s.date));
		return out;
	}
	if (s.kind === 'weekly') {
		const every = s.everyWeeks ?? 1;
		const base = s.anchor ?? from;
		// Weeks are counted from the Monday of the anchor's week
		const mondayOfAnchor = addDays(base, -((weekday(base) - 1 + 7) % 7));
		for (let d = from; d <= to; d = addDays(d, 1)) {
			if (!s.days.includes(weekday(d))) continue;
			const weeks = Math.floor(diffDays(d, mondayOfAnchor) / 7);
			if (((weeks % every) + every) % every === 0) out.push(single(d));
		}
		return out;
	}
	const start = parseDate(from);
	const end = parseDate(to);
	if (!start || !end) return out;
	if (s.kind === 'yearly') {
		for (let y = start.year; y <= end.year; y++)
			out.push(single(formatDate(y, s.month, Math.min(s.day, daysInMonth(y, s.month)))));
		return out;
	}
	// A window can end in the month after the one a padded `from` falls in, so every month between is walked
	for (let y = start.year, m = start.month; y < end.year || (y === end.year && m <= end.month);) {
		out.push(...windowsInMonth(s, y, m));
		if (++m > 12) {
			m = 1;
			y++;
		}
	}
	return out;
}

/**
 * Every window of the schedule whose due date (end) falls between `from` and `to` inclusive, after the weekend rule, sorted by end,
 * without repeats. A date moved by the rule counts in the window it lands in, so a payday that moves from Saturday the 31st to Friday
 * the 30th belongs to a window ending on the 30th. The rule moves the end only.
 */
export function windowsBetween(
	s: Schedule,
	from: ManilaDate,
	to: ManilaDate,
	opts: ScheduleOptions = {}
): ScheduleWindow[] {
	const problem = validateSchedule(s);
	if (problem) throw new RangeError(problem);
	const rule = opts.weekend ?? 'none';
	// A date just outside the window can move into it, so look a little wider and filter after the move
	const pad = rule === 'none' ? 0 : MAX_SHIFT;
	const wide = nominal(s, addDays(from, -pad), addDays(to, pad));
	const byEnd = new Map<ManilaDate, ScheduleWindow>();
	for (const w of wide) {
		const end = adjustForWeekend(w.end, rule, opts.holidays);
		if (end < from || end > to) continue;
		// The person's own limits, on the date they see; a one-time schedule is its own date and ignores the range
		if (s.kind !== 'once' && ((s.startsOn && end < s.startsOn) || (s.endsOn && end > s.endsOn)))
			continue;
		// A skip names the date the person sees; the unmoved date also counts, so a changed weekend rule keeps it skipped
		if (s.skipDates?.includes(end) || s.skipDates?.includes(w.end)) continue;
		const start = w.start > end ? end : w.start;
		const seen = byEnd.get(end);
		// Two windows landing on one due date keep the earlier start
		if (!seen || start < seen.start) byEnd.set(end, { start, end });
	}
	return [...byEnd.values()].sort((a, b) => (a.end < b.end ? -1 : a.end > b.end ? 1 : 0));
}

/**
 * Every date the schedule falls on between `from` and `to` inclusive, after the weekend rule, sorted, without repeats (the due date of
 * each window).
 */
export function occurrencesBetween(
	s: Schedule,
	from: ManilaDate,
	to: ManilaDate,
	opts: ScheduleOptions = {}
): ManilaDate[] {
	return windowsBetween(s, from, to, opts).map((w) => w.end);
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

/** The next `count` windows with a due date on or after `from`, for showing a person what a schedule means before it is saved. */
export function previewOccurrences(
	s: Schedule,
	from: ManilaDate,
	count: number,
	opts: ScheduleOptions = {}
): ScheduleWindow[] {
	const wanted = Math.max(1, Math.min(24, Math.floor(count)));
	// Two years is enough for every kind except a cycle of 24 months, which gets a longer look
	const horizon =
		(s.kind === 'monthly' ||
			s.kind === 'nth_weekday' ||
			s.kind === 'week_of_month' ||
			s.kind === 'day_range') &&
		(s.everyMonths ?? 1) > 6
			? 1500
			: 800;
	return windowsBetween(s, from, addDays(from, horizon), opts).slice(0, wanted);
}

function everyMonthsPart(everyMonths: number | undefined): { key: string; text: string } | null {
	return everyMonths && everyMonths > 1
		? { key: '_every_months', text: ` every ${everyMonths} months` }
		: null;
}

/** A plain sentence for a schedule. The key and the arguments let the app translate it; the text is the English one. */
export function describeSchedule(s: Schedule): ScheduleDescription {
	const base = describeRule(s);
	const extra: string[] = [];
	if (s.startsOn) extra.push(`from ${s.startsOn}`);
	if (s.endsOn) extra.push(`until ${s.endsOn}`);
	if (s.skipDates && s.skipDates.length > 0)
		extra.push(`not on ${[...s.skipDates].sort().join(', ')}`);
	return extra.length === 0 ? base : { ...base, text: `${base.text} (${extra.join(', ')})` };
}

function describeRule(s: ScheduleRule): ScheduleDescription {
	const months = everyMonthsPart('everyMonths' in s ? s.everyMonths : undefined);
	const suffix = months?.text ?? '';
	const keySuffix = months?.key ?? '';
	const monthArgs: Record<string, number> =
		months && 'everyMonths' in s ? { everyMonths: s.everyMonths ?? 1 } : {};
	switch (s.kind) {
		case 'semi_monthly':
			return {
				key: 'schedule.semi_monthly',
				args: { first: s.days[0], second: s.days[1] },
				text: `On the ${ordinal(s.days[0])} and the ${ordinal(s.days[1])} of each month`
			};
		case 'every_n_days':
			return {
				key: 'schedule.every_n_days',
				args: { n: s.n, anchor: s.anchor },
				text: s.n === 1 ? `Every day from ${s.anchor}` : `Every ${s.n} days from ${s.anchor}`
			};
		case 'once':
			return { key: 'schedule.once', args: { date: s.date }, text: `Once, on ${s.date}` };
		case 'monthly':
			return s.day === -1
				? {
						key: `schedule.monthly_last${keySuffix}`,
						args: { ...monthArgs },
						text: `On the last day of the month${suffix}`
					}
				: {
						key: `schedule.monthly_day${keySuffix}`,
						args: { day: s.day, ...monthArgs },
						text: `On the ${ordinal(s.day)} of the month${suffix}`
					};
		case 'weekly': {
			const names = s.days.map((d) => WEEKDAY_NAMES[d] ?? '').join(', ');
			const every = s.everyWeeks ?? 1;
			return {
				key: every > 1 ? 'schedule.weekly_every' : 'schedule.weekly',
				args: { days: s.days.join(','), everyWeeks: every },
				text: every > 1 ? `Every ${every} weeks on ${names}` : `Every ${names}`
			};
		}
		case 'nth_weekday':
			return {
				key: `schedule.nth_weekday${keySuffix}`,
				args: { n: s.n, weekday: s.weekday, ...monthArgs },
				text: `Every ${ordinal(s.n)} ${WEEKDAY_NAMES[s.weekday] ?? ''} of the month${suffix}`
			};
		case 'week_of_month': {
			const args = { n: s.n, weekday: s.weekday ?? -1, basis: s.basis, ...monthArgs };
			const span =
				s.basis === 'calendar'
					? ' (calendar week)'
					: s.n === -1
						? ' (the last 7 days)'
						: ` (days ${(s.n - 1) * 7 + 1} to ${s.n * 7})`;
			return s.pick === 'window'
				? {
						key: `schedule.week_window${keySuffix}`,
						args,
						text: `Any day in the ${ordinal(s.n)} week of the month${span}${suffix}`
					}
				: {
						key: `schedule.week_weekday${keySuffix}`,
						args,
						text: `The ${WEEKDAY_NAMES[s.weekday ?? 0] ?? ''} of the ${ordinal(s.n)} week of the month${span}${suffix}`
					};
		}
		case 'day_range':
			return s.to === -1
				? {
						key: `schedule.day_range_to_last${keySuffix}`,
						args: { from: s.from, ...monthArgs },
						text: `Any day from the ${ordinal(s.from)} to the end of the month${suffix}`
					}
				: {
						key: `schedule.day_range${keySuffix}`,
						args: { from: s.from, to: s.to, ...monthArgs },
						text: `Any day between the ${ordinal(s.from)} and the ${ordinal(s.to)}${suffix}`
					};
		case 'yearly':
			return {
				key: 'schedule.yearly',
				args: { month: s.month, day: s.day },
				text: `Once a year on ${MONTH_NAMES[s.month - 1] ?? ''} ${s.day}`
			};
	}
}
