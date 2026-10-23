// ONE DUE DATE OF A BILL AFTER ITS OVERRIDES: THE SCHEDULE GIVES THE DATES, AN OVERRIDE MOVES OR SKIPS ONE OF THEM (BTL-20261022-0650)
// Pure rules, no database. Every reader of a bill's dates (the screen, the split, reminders, the calendar, marking paid) goes through
// effectiveOccurrences so a moved or skipped date is the same everywhere. An override is keyed by the date the schedule gives (the end
// of its window); one that matches no window any more is ignored, never an error.

// -- TYPES -- //
import type { ManilaDate } from './dates';
import type { Schedule, ScheduleOptions } from './schedule';
// -- MODULES -- //
import { addDays } from './dates';
import { windowsBetween } from './schedule';

// -- TYPES -- //

/** What an override changes on one due date. A null field keeps the bill's own value. */
export type OverrideLike = {
	originalDueDate: ManilaDate;
	newDueDate: ManilaDate | null;
	amount: number | null;
	accountId: string | null;
	skipped: boolean;
};

/** One due date of a bill as it stands: the window it is paid in, the date the schedule gave it, and the override on it if any. */
export type Occurrence<O extends OverrideLike> = {
	/** The date the schedule gives (the end of the window before any move). The key of the override. */
	original: ManilaDate;
	start: ManilaDate;
	/** The due date. Equal to `start` after a move. */
	end: ManilaDate;
	override: O | null;
};

// -- CONSTANTS -- //

/** How far a date may be moved from the one the schedule gives, in days either way. */
export const MOVE_LIMIT_DAYS = 31;

/** How far outside a range an override can sit and still belong in it: the longest move plus the longest weekend shift. */
export const OVERRIDE_REACH_DAYS = MOVE_LIMIT_DAYS + 3;

// -- FUNCTIONS -- //

/**
 * The due dates of a bill whose effective date falls between `from` and `to` inclusive, in date order. The schedule is read over a range
 * widened by the longest move, so a date moved into the range from outside it is found, and a date moved out of it is left out.
 * `startsOn` is the first day the bill counts: schedule dates before it are left out (never for a one-time bill).
 */
export function effectiveOccurrences<O extends OverrideLike>(
	schedule: Schedule,
	from: ManilaDate,
	to: ManilaDate,
	opts: ScheduleOptions,
	overrides: readonly O[],
	startsOn: ManilaDate | null = null
): Occurrence<O>[] {
	const byOriginal = new Map<ManilaDate, O>();
	for (const o of overrides) byOriginal.set(o.originalDueDate, o);
	const out: Occurrence<O>[] = [];
	for (const w of windowsBetween(
		schedule,
		addDays(from, -MOVE_LIMIT_DAYS),
		addDays(to, MOVE_LIMIT_DAYS),
		opts
	)) {
		// Dates the schedule gives before the bill began do not exist; a one-time bill keeps its date even when it is already past
		if (startsOn !== null && schedule.kind !== 'once' && w.end < startsOn) continue;
		const override = byOriginal.get(w.end) ?? null;
		if (override?.skipped) continue;
		const moved = override?.newDueDate ?? null;
		const start = moved ?? w.start;
		const end = moved ?? w.end;
		if (end < from || end > to) continue;
		out.push({ original: w.end, start, end, override });
	}
	return out.sort((a, b) =>
		a.end < b.end ? -1 : a.end > b.end ? 1 : a.original < b.original ? -1 : 1
	);
}

/** The occurrence a date points at: the one due on it now, else the one whose schedule date it is, else the one whose window holds it. Null when none. */
export function occurrenceOn<O extends OverrideLike>(
	list: readonly Occurrence<O>[],
	date: ManilaDate
): Occurrence<O> | null {
	return (
		list.find((o) => o.end === date) ??
		list.find((o) => o.original === date) ??
		list.find((o) => o.start <= date && date <= o.end) ??
		null
	);
}
