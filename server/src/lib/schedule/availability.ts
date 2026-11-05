// WORK HOURS AND FREE TIME (BTL-20261105-0015, P2). PURE: A WEEK OF BLOCKS, ONE-DATE CHANGES AND THE CALENDAR GO IN, THE FREE SLOTS COME OUT.
// A block belongs to the day it starts on, and an end at or before its start runs past midnight. Work and busy win over free. A date with its own
// blocks replaces that weekday, but the tail of yesterday's overnight block still applies, because the person is still there.
// A day with no free block named has free time inside the waking hours, so a slot can never land at 3 am.

// -- TYPES -- //
import type { ManilaDate } from '../finance/dates';
// -- MODULES -- //
import { addDays, manilaStart, weekday } from '../finance/dates';

// -- TYPES -- //

export type BlockKind = 'work' | 'busy' | 'free';

export type Block = { startMinute: number; endMinute: number; kind: BlockKind; label?: string };

export type WeeklyBlock = Block & { weekday: number };

export type DayOverride = { day: ManilaDate; off: boolean; blocks: readonly Block[] };

export type AvailabilitySettings = {
	wakeStartMinute: number;
	wakeEndMinute: number;
	travelMinutes: number;
};

export type BusyInstant = { startsAt: Date; endsAt: Date };

export type FreeSlot = {
	day: ManilaDate;
	startMinute: number;
	endMinute: number;
	minutes: number;
	startsAt: string;
	endsAt: string;
};

export type AvailabilityInput = {
	weekly: readonly WeeklyBlock[];
	overrides: readonly DayOverride[];
	settings: AvailabilitySettings;
	events: readonly BusyInstant[];
};

type Span = readonly [number, number];

// -- CONSTANTS -- //

const DAY_MINUTES = 1440;
const MINUTE_MS = 60_000;
const WIND_DOWN_LEAD_MINUTES = 540;
/** A first commitment at or after 10 am is not an early start. */
const WIND_DOWN_ONLY_BEFORE = 600;

export const DEFAULT_AVAILABILITY: AvailabilitySettings = {
	wakeStartMinute: 360,
	wakeEndMinute: 1320,
	travelMinutes: 30
};

// -- FUNCTIONS -- //

/** "07:00" as minutes after midnight. */
export const minuteOf = (time: string): number => {
	const [h, m] = time.split(':');
	return Number(h) * 60 + Number(m);
};

/** Minutes after midnight as "07:00". */
export const timeOf = (minute: number): string => {
	const m = minute % DAY_MINUTES;
	return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
};

const overnight = (b: Block) => b.endMinute <= b.startMinute;

/** The part of a block inside its own day. */
const ownSpan = (b: Block): Span => [b.startMinute, overnight(b) ? DAY_MINUTES : b.endMinute];

/** The first overlap in one day's blocks in plain words, or null. Blocks of different kinds cannot overlap either: one thing happens at a time. */
export function blocksProblem(blocks: readonly Block[]): string | null {
	const sorted = [...blocks].sort((a, b) => a.startMinute - b.startMinute);
	for (let i = 1; i < sorted.length; i++) {
		const prev = sorted[i - 1];
		const cur = sorted[i];
		if (prev && cur && ownSpan(prev)[1] > cur.startMinute)
			return `Two times overlap on one day: ${timeOf(prev.startMinute)} to ${timeOf(prev.endMinute)} and ${timeOf(cur.startMinute)} to ${timeOf(cur.endMinute)}.`;
	}
	return null;
}

/** The blocks that apply to a date: its own when it has a change, otherwise its weekday's. */
export function blocksOn(
	day: ManilaDate,
	weekly: readonly WeeklyBlock[],
	overrides: readonly DayOverride[]
): readonly Block[] {
	const o = overrides.find((x) => x.day === day);
	if (o) return o.off ? [] : o.blocks;
	const w = weekday(day);
	return weekly.filter((b) => b.weekday === w);
}

/** Takes spans out of spans. */
function subtract(from: readonly Span[], remove: readonly Span[]): Span[] {
	let out: Span[] = [...from];
	for (const [rs, re] of remove) {
		const next: Span[] = [];
		for (const [s, e] of out) {
			if (re <= s || rs >= e) {
				next.push([s, e]);
				continue;
			}
			if (rs > s) next.push([s, rs]);
			if (re < e) next.push([re, e]);
		}
		out = next;
	}
	return out;
}

/** The work and busy spans of a date, with the travel buffer around work, including the tail of yesterday's overnight block. */
function busyOn(day: ManilaDate, input: AvailabilityInput): Span[] {
	const travel = input.settings.travelMinutes;
	const spans: Span[] = [];
	const wrap = (kind: BlockKind) => (kind === 'work' ? travel : 0);
	for (const b of blocksOn(day, input.weekly, input.overrides)) {
		if (b.kind === 'free') continue;
		const [s, e] = ownSpan(b);
		spans.push([Math.max(0, s - wrap(b.kind)), Math.min(DAY_MINUTES, e + wrap(b.kind))]);
	}
	for (const b of blocksOn(addDays(day, -1), input.weekly, input.overrides)) {
		if (b.kind === 'free' || !overnight(b)) continue;
		spans.push([0, Math.min(DAY_MINUTES, b.endMinute + wrap(b.kind))]);
	}
	// A work block that ended late yesterday can still need the trip home today
	for (const b of blocksOn(addDays(day, -1), input.weekly, input.overrides)) {
		if (b.kind !== 'work' || overnight(b)) continue;
		const spill = b.endMinute + travel - DAY_MINUTES;
		if (spill > 0) spans.push([0, spill]);
	}
	return spans;
}

/** The parts of the calendar's timed events that fall on a date. */
function eventsOn(day: ManilaDate, events: readonly BusyInstant[]): Span[] {
	const start = manilaStart(day).getTime();
	const end = start + DAY_MINUTES * MINUTE_MS;
	const spans: Span[] = [];
	for (const e of events) {
		const s = e.startsAt.getTime();
		const f = e.endsAt.getTime();
		if (f <= start || s >= end) continue;
		spans.push([
			Math.max(0, Math.floor((s - start) / MINUTE_MS)),
			Math.min(DAY_MINUTES, Math.ceil((f - start) / MINUTE_MS))
		]);
	}
	return spans;
}

/**
 * The free slots of a date. The named free blocks when there are any, otherwise the waking hours; then work, busy, travel and the calendar come out.
 * Named free time keeps to the waking hours' spirit by the person's own choice: it is not clipped.
 */
export function freeSlotsOn(day: ManilaDate, input: AvailabilityInput): FreeSlot[] {
	const named = blocksOn(day, input.weekly, input.overrides)
		.filter((b) => b.kind === 'free')
		.map(ownSpan);
	const base: Span[] = named.length
		? named
		: [[input.settings.wakeStartMinute, input.settings.wakeEndMinute]];
	const left = subtract(base, [...busyOn(day, input), ...eventsOn(day, input.events)]);
	const dayStart = manilaStart(day).getTime();
	return left
		.filter(([s, e]) => e > s)
		.sort((a, b) => a[0] - b[0])
		.map(([s, e]) => ({
			day,
			startMinute: s,
			endMinute: e,
			minutes: e - s,
			startsAt: new Date(dayStart + s * MINUTE_MS).toISOString(),
			endsAt: new Date(dayStart + e * MINUTE_MS).toISOString()
		}));
}

/** The first thing a person has to be at on a date: the first work block or timed event, in minutes after midnight, or null. */
export function firstCommitment(day: ManilaDate, input: AvailabilityInput): number | null {
	const work = blocksOn(day, input.weekly, input.overrides)
		.filter((b) => b.kind === 'work')
		.map((b) => b.startMinute);
	// An event that began the day before is not something to get up for
	const dayStart = manilaStart(day).getTime();
	const events = input.events
		.map((e) => (e.startsAt.getTime() - dayStart) / MINUTE_MS)
		.filter((m) => m >= 0 && m < DAY_MINUTES)
		.map((m) => Math.floor(m));
	const all = [...work, ...events];
	return all.length ? Math.min(...all) : null;
}

/**
 * When to start winding down the night before a date: nine hours before the first thing that day, which leaves about eight of sleep and the time to get ready. A late start
 * needs no reminder, so a date with nothing before the cut-off gets null. A time before midnight belongs to the evening before.
 */
export function windDownFor(
	day: ManilaDate,
	input: AvailabilityInput
): { at: string; time: string; firstAt: string } | null {
	const first = firstCommitment(day, input);
	if (first === null || first >= WIND_DOWN_ONLY_BEFORE) return null;
	const at = new Date(manilaStart(day).getTime() + (first - WIND_DOWN_LEAD_MINUTES) * MINUTE_MS);
	return {
		at: at.toISOString(),
		time: timeOf(first - WIND_DOWN_LEAD_MINUTES + DAY_MINUTES),
		firstAt: timeOf(first)
	};
}

/** The free slots of each date from `from` to `to`, at least `minMinutes` long. */
export function freeSlots(
	from: ManilaDate,
	to: ManilaDate,
	input: AvailabilityInput,
	minMinutes = 1
): FreeSlot[] {
	const out: FreeSlot[] = [];
	for (let d = from; d <= to; d = addDays(d, 1))
		out.push(...freeSlotsOn(d, input).filter((s) => s.minutes >= minMinutes));
	return out;
}
