// THE WEEK PLANNER (BTL-20261105-0015, P6.4). PURE: FREE TIME AND THE WORKOUTS WANTED GO IN, A WEEK COMES OUT, AND WHAT DID NOT FIT IS NAMED.
// Sessions are shorter on work days and longer on free days, strength days are never next to each other, and at least one day stays empty. Nothing here writes anything:
// a week becomes real only when the person accepts it.

// -- TYPES -- //
import type { ManilaDate } from '../finance/dates';
import type { FreeSlot } from '../schedule/availability';
// -- MODULES -- //
import { addDays, manilaStart } from '../finance/dates';
import { timeOf } from '../schedule/availability';

// -- TYPES -- //

export type WantedSession = {
	kind: 'strength' | 'walk' | 'run';
	sessionKey: string;
	programId: string | null;
	/** The length on a work day. */
	shortMinutes: number;
	/** The length on a free day. A program session that cannot be shorter has both the same. */
	longMinutes: number;
};

export type PlacedSession = {
	day: ManilaDate;
	startsAt: string;
	time: string;
	minutes: number;
	kind: WantedSession['kind'];
	sessionKey: string;
	programId: string | null;
};

export type WeekPlan = {
	placed: PlacedSession[];
	/** The sessions no free time could hold. */
	unplaced: WantedSession[];
	movingMinutes: number;
	strengthDays: number;
};

export type PlannerInput = {
	monday: ManilaDate;
	slots: readonly FreeSlot[];
	/** The days of this week with a work block. */
	workDays: ReadonlySet<ManilaDate>;
	wanted: readonly WantedSession[];
	/** Days to leave out, because something is already on them. */
	taken?: ReadonlySet<ManilaDate>;
	/** A free day's first session starts no earlier than this. */
	freeDayStartMinute?: number;
};

// -- CONSTANTS -- //

const ROUND_MINUTES = 15;
const EVENING_GAP_MINUTES = 15;
const DEFAULT_FREE_DAY_START = 480;
const MINUTE_MS = 60_000;
/** One day of a week stays empty, whatever is asked. */
const MAX_SESSION_DAYS = 6;

// -- FUNCTIONS -- //

const roundUp = (minute: number) => Math.ceil(minute / ROUND_MINUTES) * ROUND_MINUTES;

/** Where a session of this length goes on a day: the longest free stretch, a little after it opens, or at the morning start on a free day. Null when it does not fit. */
export function placeOn(
	slots: readonly FreeSlot[],
	day: ManilaDate,
	minutes: number,
	isWorkDay: boolean,
	freeDayStart: number
): number | null {
	const mine = slots.filter((s) => s.day === day && s.minutes >= minutes);
	const best = [...mine].sort((a, b) => b.minutes - a.minutes || a.startMinute - b.startMinute)[0];
	if (!best) return null;
	const wanted = isWorkDay
		? roundUp(best.startMinute + EVENING_GAP_MINUTES)
		: roundUp(Math.max(best.startMinute, freeDayStart));
	if (wanted + minutes <= best.endMinute) return wanted;
	// The rounded time does not leave room, so it starts as the stretch opens
	return best.startMinute;
}

function placed(day: ManilaDate, minute: number, minutes: number, w: WantedSession): PlacedSession {
	return {
		day,
		startsAt: new Date(manilaStart(day).getTime() + minute * MINUTE_MS).toISOString(),
		time: timeOf(minute),
		minutes,
		kind: w.kind,
		sessionKey: w.sessionKey,
		programId: w.programId
	};
}

/** Lays out a week. Strength goes first because it has the harder rule; free days are tried first for it, because they hold the longer session. */
export function planWeek(input: PlannerInput): WeekPlan {
	const days = [0, 1, 2, 3, 4, 5, 6].map((i) => addDays(input.monday, i));
	const freeDayStart = input.freeDayStartMinute ?? DEFAULT_FREE_DAY_START;
	const used = new Set<ManilaDate>(input.taken ?? []);
	const strengthDays = new Set<ManilaDate>();
	const out: PlacedSession[] = [];
	const unplaced: WantedSession[] = [];
	const nextToStrength = (d: ManilaDate) =>
		strengthDays.has(addDays(d, -1)) || strengthDays.has(addDays(d, 1));
	const lengthFor = (w: WantedSession, d: ManilaDate) =>
		input.workDays.has(d) ? w.shortMinutes : w.longMinutes;
	const tryPlace = (w: WantedSession, d: ManilaDate): boolean => {
		if (used.has(d)) return false;
		if (w.kind === 'strength' && nextToStrength(d)) return false;
		const isWork = input.workDays.has(d);
		// A free day with little time still takes the shorter session
		for (const minutes of [lengthFor(w, d), w.shortMinutes]) {
			const at = placeOn(input.slots, d, minutes, isWork, freeDayStart);
			if (at !== null) {
				out.push(placed(d, at, minutes, w));
				used.add(d);
				if (w.kind === 'strength') strengthDays.add(d);
				return true;
			}
		}
		return false;
	};
	const order = (first: 'free' | 'spread') =>
		first === 'free'
			? [
					...days.filter((d) => !input.workDays.has(d)),
					...days.filter((d) => input.workDays.has(d))
				]
			: days;
	const strength = input.wanted.filter((w) => w.kind === 'strength');
	const others = input.wanted.filter((w) => w.kind !== 'strength');
	for (const w of strength) {
		const fits = used.size < MAX_SESSION_DAYS && order('free').some((d) => tryPlace(w, d));
		if (!fits) unplaced.push(w);
	}
	for (const w of others) {
		const fits = used.size < MAX_SESSION_DAYS && order('spread').some((d) => tryPlace(w, d));
		if (!fits) unplaced.push(w);
	}
	out.sort((a, b) => (a.startsAt < b.startsAt ? -1 : 1));
	return {
		placed: out,
		unplaced,
		movingMinutes: out.reduce((a, p) => a + p.minutes, 0),
		strengthDays: strengthDays.size
	};
}

/** Whether a session still has room in the free time it was placed in. */
export function stillFits(
	slots: readonly FreeSlot[],
	day: ManilaDate,
	startsAt: Date,
	minutes: number
): boolean {
	const from = startsAt.getTime();
	const to = from + minutes * MINUTE_MS;
	return slots.some(
		(s) => s.day === day && Date.parse(s.startsAt) <= from && Date.parse(s.endsAt) >= to
	);
}

/** The next place on the same day a session would fit, for the "needs a move" card. */
export function moveSuggestion(
	slots: readonly FreeSlot[],
	day: ManilaDate,
	minutes: number,
	isWorkDay: boolean,
	freeDayStart = DEFAULT_FREE_DAY_START
): string | null {
	const at = placeOn(slots, day, minutes, isWorkDay, freeDayStart);
	return at === null ? null : timeOf(at);
}
