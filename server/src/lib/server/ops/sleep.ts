// SLEEP VERBS (BTL-20261105-0015, P7). WHEN A PERSON SLEPT AND FOR HOW LONG, WITH NO SCORES AND NO STAGES. A SLEEP IS DATED BY THE DAY THEY WOKE, SO A NIGHT SHIFT AND A NAP
// BOTH LAND ON THE RIGHT DAY. A PATTERN IS SHOWN ONLY AFTER 14 NIGHTS, AND IT IS WORDED AS SOMETHING TO NOTICE, NEVER AS A CAUSE.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { SleepDeleteInput, SleepEditInput, SleepLogInput, SleepSummaryInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, asc, desc, eq, gte, lte, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, toLocalDate, localHm } from '../../finance/dates';
import { minuteOf, windDownFor } from '../../schedule/availability';
import { atLocalTime } from '../../schedule/recurrence';
import { availabilitySetting, foodEntry, sleepEntry } from '../db/schema';
import { sleepDeleteInput, sleepEditInput, sleepLogInput, sleepSummaryInput } from '../db/zod';
import { readAvailability } from './availability';
import { OpsError, run, runWrite } from './context';
import { mapped, parse, plain } from './shared';

// -- CONSTANTS -- //

const NAP_UNDER_MINUTES = 180;
const LONGEST_SLEEP_MINUTES = 20 * 60;
/** Nights needed before any pattern is shown. */
export const PATTERN_NIGHTS = 14;
const SHORT_NIGHT_MINUTES = 360;
const PATTERN_MIN_SIDE = 3;
const PATTERN_MIN_KCAL = 150;
const MINUTE_MS = 60_000;

// -- FUNCTIONS -- //

const isAgent = (ctx: Ctx) => ctx.actor.kind === 'agent' || ctx.onBehalfOf === 'agent';

const minutesOf = (s: { startsAt: Date; endsAt: Date }) =>
	Math.round((s.endsAt.getTime() - s.startsAt.getTime()) / MINUTE_MS);

/** The instants of "slept 11 to 6, waking on this day". A start later than the end was the evening before. */
export function sleepTimes(day: string, from: string, to: string) {
	const endsAt = atLocalTime(day, to);
	const startDay = minuteOf(from) >= minuteOf(to) ? addDays(day, -1) : day;
	return { startsAt: atLocalTime(startDay, from), endsAt };
}

function checkLength(minutes: number) {
	if (minutes < 1 || minutes > LONGEST_SLEEP_MINUTES)
		throw new OpsError('INVALID', 'That sleep is longer than 20 hours. Check the times.');
}

const view = (s: typeof sleepEntry.$inferSelect) => ({
	id: s.id,
	day: s.day,
	startsAt: s.startsAt.toISOString(),
	endsAt: s.endsAt.toISOString(),
	minutes: minutesOf(s),
	nap: s.nap,
	byAgent: s.byAgent
});

/** Logs a sleep. The day is the day they woke, today unless given. Under 3 hours counts as a nap unless they say otherwise. */
export async function logSleep(ctx: Ctx, raw: SleepLogInput) {
	const input = parse(sleepLogInput, raw);
	return mapped(() =>
		runWrite(ctx, 'sleep.log', input, async (tx, userId) => {
			const day = input.day ?? toLocalDate(new Date());
			const { startsAt, endsAt } = sleepTimes(day, input.from, input.to);
			const minutes = minutesOf({ startsAt, endsAt });
			checkLength(minutes);
			const [row] = await tx
				.insert(sleepEntry)
				.values({
					userId,
					day,
					startsAt,
					endsAt,
					nap: input.nap ?? minutes < NAP_UNDER_MINUTES,
					byAgent: isAgent(ctx)
				})
				.returning();
			if (!row) throw new OpsError('INVALID', 'The sleep could not be saved.');
			return view(row);
		})
	);
}

/** Changes a sleep. A time left out stays as it was. */
export async function editSleep(ctx: Ctx, raw: SleepEditInput) {
	const input = parse(sleepEditInput, raw);
	return mapped(() =>
		runWrite(ctx, 'sleep.edit', input, async (tx, userId) => {
			const [s] = await tx
				.select()
				.from(sleepEntry)
				.where(and(eq(sleepEntry.userId, userId), eq(sleepEntry.id, input.id)));
			if (!s) throw new OpsError('NOT_FOUND', 'That sleep is not there.');
			const clock = (d: Date) => localHm(d);
			const day = input.day ?? s.day;
			const { startsAt, endsAt } = sleepTimes(
				day,
				input.from ?? clock(s.startsAt),
				input.to ?? clock(s.endsAt)
			);
			checkLength(minutesOf({ startsAt, endsAt }));
			const [row] = await tx
				.update(sleepEntry)
				.set({
					day,
					startsAt,
					endsAt,
					nap: input.nap ?? s.nap,
					version: sql`${sleepEntry.version} + 1`,
					updatedAt: new Date()
				})
				.where(and(eq(sleepEntry.userId, userId), eq(sleepEntry.id, s.id)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That sleep is not there.');
			return view(row);
		})
	);
}

/** Removes a sleep and answers what was removed. */
export async function deleteSleep(ctx: Ctx, raw: SleepDeleteInput) {
	const input = parse(sleepDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'sleep.delete', input, async (tx, userId) => {
			const [row] = await tx
				.delete(sleepEntry)
				.where(and(eq(sleepEntry.userId, userId), eq(sleepEntry.id, input.id)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That sleep is not there.');
			return { removed: plain(view(row)) };
		})
	);
}

/** The pattern to notice, or null. Only after 14 nights, and only when both sides have enough nights and the gap is big enough to mention. */
async function readPattern(
	tx: Tx,
	userId: string,
	nights: readonly { day: string; minutes: number }[]
) {
	if (nights.length < PATTERN_NIGHTS) return null;
	const days = nights.map((n) => n.day).sort();
	const first = days[0];
	const last = days.at(-1);
	if (!first || !last) return null;
	const food = await tx
		.select({ day: foodEntry.day, kcal: sql<string>`sum(${foodEntry.kcal})` })
		.from(foodEntry)
		.where(and(eq(foodEntry.userId, userId), gte(foodEntry.day, first), lte(foodEntry.day, last)))
		.groupBy(foodEntry.day);
	const byDay = new Map(food.map((f) => [f.day, Number(f.kcal)]));
	const average = (v: number[]) => v.reduce((a, b) => a + b, 0) / v.length;
	const kcalOn = (n: readonly { day: string }[]) =>
		n.flatMap((x) => {
			const k = byDay.get(x.day);
			return k === undefined ? [] : [k];
		});
	const short = kcalOn(nights.filter((n) => n.minutes < SHORT_NIGHT_MINUTES));
	const rest = kcalOn(nights.filter((n) => n.minutes >= SHORT_NIGHT_MINUTES));
	if (short.length < PATTERN_MIN_SIDE || rest.length < PATTERN_MIN_SIDE) return null;
	const gap = Math.round((average(short) - average(rest)) / 10) * 10;
	return gap >= PATTERN_MIN_KCAL ? { shortNightExtraKcal: gap } : null;
}

/** How long and how regularly a person slept. The spread is the gap between their earliest and latest bedtime in the last week. */
export async function readSleep(tx: Tx, userId: string, today: string, days: number) {
	const rows = await tx
		.select()
		.from(sleepEntry)
		.where(
			and(
				eq(sleepEntry.userId, userId),
				gte(sleepEntry.day, addDays(today, -(Math.max(days, 30) - 1))),
				lte(sleepEntry.day, today)
			)
		)
		.orderBy(asc(sleepEntry.day), asc(sleepEntry.startsAt));
	const nightsAll = rows.filter((r) => !r.nap).map(view);
	const week = nightsAll.filter((n) => n.day >= addDays(today, -6));
	const shown = nightsAll.filter((n) => n.day >= addDays(today, -(days - 1)));
	const last = nightsAll.at(-1) ?? null;
	const bedtimes = week.map((n) => {
		// Read from the instant in the person's zone now, so nights logged before a zone change line up with the rest
		const [h, mi] = localHm(new Date(n.startsAt)).split(':').map(Number);
		const minute = (h ?? 0) * 60 + (mi ?? 0);
		// An evening bedtime counts as minutes before midnight, so 23:00 and 01:00 are two hours apart
		return minute >= 12 * 60 ? minute - 24 * 60 : minute;
	});
	const [setting] = await tx
		.select({ windDown: availabilitySetting.windDown })
		.from(availabilitySetting)
		.where(eq(availabilitySetting.userId, userId));
	const availability = await readAvailability(tx, userId, today, addDays(today, 1));
	return {
		last,
		nights: shown,
		naps: rows.filter((r) => r.nap && r.day >= addDays(today, -6)).map(view),
		averageMinutes: week.length
			? Math.round(week.reduce((a, n) => a + n.minutes, 0) / week.length)
			: null,
		bedtimeSpreadMinutes:
			bedtimes.length > 1 ? Math.max(...bedtimes) - Math.min(...bedtimes) : null,
		nightCount: nightsAll.length,
		pattern: await readPattern(tx, userId, nightsAll),
		windDownOn: setting?.windDown ?? false,
		windDownTonight: windDownFor(addDays(today, 1), availability)
	};
}

export async function getSleepSummary(ctx: Ctx, raw: SleepSummaryInput) {
	const { days } = parse(sleepSummaryInput, raw);
	return run(ctx, (tx, userId) => readSleep(tx, userId, toLocalDate(new Date()), days ?? 7));
}

/** The latest sleep rows, for the home tile's small bars. */
export async function lastNights(tx: Tx, userId: string, limit: number) {
	const rows = await tx
		.select()
		.from(sleepEntry)
		.where(and(eq(sleepEntry.userId, userId), eq(sleepEntry.nap, false)))
		.orderBy(desc(sleepEntry.day))
		.limit(limit);
	return rows.reverse().map(view);
}
