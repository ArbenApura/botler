// WORK HOURS AND FREE TIME VERBS (BTL-20261105-0015, P2). THE PERSON OR THE ASSISTANT CAN SET THEM, AND EVERYTHING THAT PLANS TIME READS free_slots.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type {
	AvailabilityInput,
	Block,
	DayOverride,
	WeeklyBlock
} from '../../schedule/availability';
import type {
	AvailabilityOverrideSetInput,
	AvailabilitySetInput,
	AvailabilitySettingSetInput,
	FreeSlotsInput
} from '../db/zod';
// -- DEP-MODULES -- //
import { and, eq, gte, gt, inArray, isNull, lt } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, manilaStart, toManilaDate } from '../../finance/dates';
import {
	blocksProblem,
	DEFAULT_AVAILABILITY,
	freeSlots,
	minuteOf,
	timeOf
} from '../../schedule/availability';
import {
	availabilityOverride,
	availabilitySetting,
	calendarEvent,
	weeklyBlock
} from '../db/schema';
import {
	availabilityOverrideSetInput,
	availabilitySetInput,
	availabilitySettingSetInput,
	freeSlotsInput
} from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { mapped, parse } from './shared';

// -- TYPES -- //

type TimeBlock = {
	start: string;
	end: string;
	kind: Block['kind'];
	label?: string | null | undefined;
};

// -- CONSTANTS -- //

const MAX_RANGE_DAYS = 31;

// -- FUNCTIONS -- //

const toBlock = (b: TimeBlock): Block => ({
	startMinute: minuteOf(b.start),
	endMinute: minuteOf(b.end),
	kind: b.kind,
	...(b.label ? { label: b.label } : {})
});

const toTimes = (b: Block) => ({
	start: timeOf(b.startMinute),
	end: timeOf(b.endMinute),
	kind: b.kind,
	label: b.label ?? null
});

function checkBlocks(blocks: readonly Block[]) {
	for (const b of blocks)
		if (b.startMinute === b.endMinute)
			throw new OpsError(
				'INVALID',
				`A time from ${timeOf(b.startMinute)} to the same time is empty.`
			);
	const problem = blocksProblem(blocks);
	if (problem) throw new OpsError('INVALID', problem);
}

/** Everything the planner needs for a range of days, read in the caller's transaction. */
export async function readAvailability(
	tx: Tx,
	userId: string,
	from: string,
	to: string
): Promise<AvailabilityInput> {
	const blocks = await tx.select().from(weeklyBlock).where(eq(weeklyBlock.userId, userId));
	const overrides = await tx
		.select()
		.from(availabilityOverride)
		.where(
			and(
				eq(availabilityOverride.userId, userId),
				// The day before the range, for a block that runs past midnight into it
				gte(availabilityOverride.day, addDays(from, -1))
			)
		);
	const [s] = await tx
		.select()
		.from(availabilitySetting)
		.where(eq(availabilitySetting.userId, userId));
	const events = await tx
		.select({ startsAt: calendarEvent.startsAt, endsAt: calendarEvent.endsAt })
		.from(calendarEvent)
		.where(
			and(
				eq(calendarEvent.userId, userId),
				isNull(calendarEvent.deletedAt),
				eq(calendarEvent.allDay, false),
				lt(calendarEvent.startsAt, manilaStart(addDays(to, 1))),
				gt(calendarEvent.endsAt, manilaStart(from))
			)
		);
	return {
		weekly: blocks.map((b): WeeklyBlock => ({
			weekday: b.weekday,
			startMinute: b.startMinute,
			endMinute: b.endMinute,
			kind: b.kind,
			...(b.label ? { label: b.label } : {})
		})),
		overrides: overrides.map((o): DayOverride => ({ day: o.day, off: o.off, blocks: o.blocks })),
		settings: s
			? {
					wakeStartMinute: s.wakeStartMinute,
					wakeEndMinute: s.wakeEndMinute,
					travelMinutes: s.travelMinutes
				}
			: DEFAULT_AVAILABILITY,
		events
	};
}

/** The week as a person reads it: clock times per weekday, the changes still to come, and the settings. */
export async function getAvailability(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const today = toManilaDate(new Date());
		const blocks = await tx.select().from(weeklyBlock).where(eq(weeklyBlock.userId, userId));
		const overrides = await tx
			.select()
			.from(availabilityOverride)
			.where(and(eq(availabilityOverride.userId, userId), gte(availabilityOverride.day, today)))
			.orderBy(availabilityOverride.day);
		const [s] = await tx
			.select()
			.from(availabilitySetting)
			.where(eq(availabilitySetting.userId, userId));
		return {
			days: [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({
				weekday,
				blocks: blocks
					.filter((b) => b.weekday === weekday)
					.sort((a, b) => a.startMinute - b.startMinute)
					.map((b) =>
						toTimes({
							startMinute: b.startMinute,
							endMinute: b.endMinute,
							kind: b.kind,
							...(b.label ? { label: b.label } : {})
						})
					)
			})),
			changes: overrides.map((o) => ({
				day: o.day,
				off: o.off,
				blocks: o.blocks.map(toTimes)
			})),
			awakeFrom: timeOf(s?.wakeStartMinute ?? DEFAULT_AVAILABILITY.wakeStartMinute),
			awakeTo: timeOf(s?.wakeEndMinute ?? DEFAULT_AVAILABILITY.wakeEndMinute),
			travelMinutes: s?.travelMinutes ?? DEFAULT_AVAILABILITY.travelMinutes,
			windDown: s?.windDown ?? false
		};
	});
}

/** Replaces the blocks of the weekdays named and leaves the others. An empty list clears those days. */
export async function setAvailability(ctx: Ctx, raw: AvailabilitySetInput) {
	const input = parse(availabilitySetInput, raw);
	const days = new Map<number, Block[]>();
	for (const d of input.days)
		for (const w of d.weekdays) days.set(w, [...(days.get(w) ?? []), ...d.blocks.map(toBlock)]);
	for (const blocks of days.values()) checkBlocks(blocks);
	return mapped(async () => {
		await runWrite(ctx, 'availability.set', input, async (tx, userId) => {
			await tx
				.delete(weeklyBlock)
				.where(and(eq(weeklyBlock.userId, userId), inArray(weeklyBlock.weekday, [...days.keys()])));
			const rows = [...days.entries()].flatMap(([weekday, blocks]) =>
				blocks.map((b) => ({ userId, weekday, ...b }))
			);
			if (rows.length) await tx.insert(weeklyBlock).values(rows);
			return { saved: rows.length };
		});
		return getAvailability(ctx);
	});
}

/** One date that differs from its week: its own blocks, or off. clear puts the date back to its week. */
export async function setAvailabilityOverride(ctx: Ctx, raw: AvailabilityOverrideSetInput) {
	const input = parse(availabilityOverrideSetInput, raw);
	const blocks = (input.blocks ?? []).map(toBlock);
	checkBlocks(blocks);
	if (!input.clear && !input.off && blocks.length === 0)
		throw new OpsError('INVALID', 'Give the times for that day, or say it is off.');
	return mapped(async () => {
		await runWrite(ctx, 'availability.override_set', input, async (tx, userId) => {
			await tx
				.delete(availabilityOverride)
				.where(
					and(eq(availabilityOverride.userId, userId), eq(availabilityOverride.day, input.day))
				);
			if (!input.clear)
				await tx
					.insert(availabilityOverride)
					.values({ userId, day: input.day, off: input.off ?? false, blocks });
			return { day: input.day };
		});
		return getAvailability(ctx);
	});
}

/** Awake hours, the trip to and from work, and the wind-down reminder. */
export async function setAvailabilitySetting(ctx: Ctx, raw: AvailabilitySettingSetInput) {
	const input = parse(availabilitySettingSetInput, raw);
	const changes = {
		...(input.awakeFrom !== undefined ? { wakeStartMinute: minuteOf(input.awakeFrom) } : {}),
		...(input.awakeTo !== undefined ? { wakeEndMinute: minuteOf(input.awakeTo) } : {}),
		...(input.travelMinutes !== undefined ? { travelMinutes: input.travelMinutes } : {}),
		...(input.windDown !== undefined ? { windDown: input.windDown } : {})
	};
	return mapped(async () => {
		await runWrite(ctx, 'availability.setting_set', input, async (tx, userId) => {
			await tx
				.insert(availabilitySetting)
				.values({ userId, ...changes })
				.onConflictDoUpdate({
					target: availabilitySetting.userId,
					set: { ...changes, updatedAt: new Date() }
				});
			return { saved: true };
		});
		return getAvailability(ctx);
	});
}

/** When the person is free between two dates, at most a month at a time. */
export async function listFreeSlots(ctx: Ctx, raw: FreeSlotsInput) {
	const { from, to, minMinutes } = parse(freeSlotsInput, raw);
	if (to < from) throw new OpsError('INVALID', 'The end date is before the start date.');
	if (to > addDays(from, MAX_RANGE_DAYS))
		throw new OpsError('INVALID', 'Ask for at most a month of free time at once.');
	return run(ctx, async (tx, userId) => {
		const input = await readAvailability(tx, userId, from, to);
		return freeSlots(from, to, input, minMinutes ?? 1).map((s) => ({
			day: s.day,
			from: timeOf(s.startMinute),
			to: timeOf(s.endMinute),
			minutes: s.minutes,
			startsAt: s.startsAt,
			endsAt: s.endsAt
		}));
	});
}
