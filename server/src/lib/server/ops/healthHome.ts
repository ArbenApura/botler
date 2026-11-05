// THE HEALTH HOME SCREEN: ONE SHORT LINE FOR EACH PART OF HEALTH. IT READS, IT DOES NOT CALCULATE ANYTHING OF ITS OWN.
// The butler reads (BTL-20261105-0015, P8.2) are here too: what a day looks like across food, money, the calendar and the workout. The numbers come from the verbs that own them.

// -- TYPES -- //
import type { Ctx } from './context';
import type { HealthDayInput, HealthMoneyInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, eq, gte, isNull, lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, diffDays, manilaStart, toManilaDate } from '../../finance/dates';
import { freeSlotsOn, timeOf } from '../../schedule/availability';
import { calendarEvent, foodEntry, healthProposal, ledgerTxn } from '../db/schema';
import { healthDayInput, healthMoneyInput } from '../db/zod';
import { readAvailability } from './availability';
import { OpsError, run } from './context';
import { readDay } from './food';
import { readHealth } from './health';
import { parse, plain } from './shared';
import { readSettings } from './settings';
import { lastNights } from './sleep';
import { readTrend } from './weight';
import { readTrain } from './workouts';

// -- CONSTANTS -- //

const TILE_WEIGHT_DAYS = 21;
const TILE_NIGHTS = 7;
const MONEY_DAYS_MAX = 62;

// -- FUNCTIONS -- //

export async function healthHome(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const today = toManilaDate(new Date());
		const health = await readHealth(tx, userId, today);
		const food = await readDay(tx, userId, today);
		const trend = await readTrend(tx, userId, today, TILE_WEIGHT_DAYS);
		const train = await readTrain(tx, userId, today);
		const nights = await lastNights(tx, userId, TILE_NIGHTS);
		const availability = await readAvailability(tx, userId, today, today);
		const free = freeSlotsOn(today, availability).sort((a, b) => b.minutes - a.minutes)[0];
		const proposals = await tx
			.select()
			.from(healthProposal)
			.where(and(eq(healthProposal.userId, userId), eq(healthProposal.status, 'open')));
		const now = Date.now();
		const open = proposals.filter((p) => p.expiresAt.getTime() > now);
		return {
			today,
			setupDone: health.profile.setupDone,
			missing: health.missing,
			food: {
				eatenKcal: food.totals.kcal,
				targetKcal: food.targetKcal,
				leftKcal: food.leftKcal,
				entries: food.entries.length
			},
			weight: {
				trendG: trend.trendG,
				changeG: trend.changeG,
				sinceDay: trend.sinceDay,
				points: trend.points.map((p) => p.trendG)
			},
			train: {
				days: train.days,
				next: train.next,
				minutes: train.minutes,
				minutesGoal: train.minutesGoal,
				needsMove: train.needsMove.length
			},
			sleep: { last: nights.at(-1) ?? null, nights: nights.map((n) => n.minutes) },
			free: free ? { from: timeOf(free.startMinute), to: timeOf(free.endMinute) } : null,
			proposals: plain(
				open.map((p) => ({ id: p.id, kind: p.kind, weekKey: p.weekKey, payload: p.payload }))
			)
		};
	});
}

/** One day across Health and the calendar, for advice such as a dinner out or a workout that has to move. Nothing here is advice: the assistant reads it and says what fits. */
export async function healthDay(ctx: Ctx, raw: HealthDayInput) {
	const input = parse(healthDayInput, raw);
	return run(ctx, async (tx, userId) => {
		const today = toManilaDate(new Date());
		const day = input.day ?? today;
		const food = await readDay(tx, userId, day);
		const availability = await readAvailability(tx, userId, day, day);
		const events = await tx
			.select({
				title: calendarEvent.title,
				startsAt: calendarEvent.startsAt,
				endsAt: calendarEvent.endsAt,
				allDay: calendarEvent.allDay,
				source: calendarEvent.source
			})
			.from(calendarEvent)
			.where(
				and(
					eq(calendarEvent.userId, userId),
					isNull(calendarEvent.deletedAt),
					lt(calendarEvent.startsAt, manilaStart(addDays(day, 1))),
					gte(calendarEvent.endsAt, manilaStart(day))
				)
			);
		const train = await readTrain(tx, userId, day);
		return {
			day,
			food: {
				eatenKcal: food.totals.kcal,
				targetKcal: food.targetKcal,
				leftKcal: food.leftKcal,
				proteinMg: food.totals.core.proteinMg.mg
			},
			workout: train.todayPlanned,
			needsMove: train.needsMove,
			// Only the events Botler holds itself: no other person's calendar reaches this table
			events: events.map((e) => plain(e)),
			free: freeSlotsOn(day, availability).map((s) => ({
				from: timeOf(s.startMinute),
				to: timeOf(s.endMinute),
				minutes: s.minutes
			}))
		};
	});
}

/** Calories and spending side by side, one line per day. Only the main currency is added up; another is named and left out. Use calc for any sum of these. */
export async function healthMoney(ctx: Ctx, raw: HealthMoneyInput) {
	const { from, to } = parse(healthMoneyInput, raw);
	if (to < from) throw new OpsError('INVALID', 'The end date is before the start date.');
	if (diffDays(to, from) > MONEY_DAYS_MAX - 1)
		throw new OpsError('INVALID', `Ask for at most ${MONEY_DAYS_MAX} days at a time.`);
	return run(ctx, async (tx, userId) => {
		const { currency } = await readSettings(tx, userId);
		const food = await tx
			.select({ day: foodEntry.day, kcal: sql<string>`sum(${foodEntry.kcal})` })
			.from(foodEntry)
			.where(
				and(eq(foodEntry.userId, userId), gte(foodEntry.day, from), sql`${foodEntry.day} <= ${to}`)
			)
			.groupBy(foodEntry.day);
		const txns = await tx
			.select({
				occurredAt: ledgerTxn.occurredAt,
				amount: ledgerTxn.amount,
				type: ledgerTxn.type,
				currency: ledgerTxn.currency,
				category: ledgerTxn.category
			})
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					isNull(ledgerTxn.voidedAt),
					gte(ledgerTxn.occurredAt, manilaStart(from)),
					lt(ledgerTxn.occurredAt, manilaStart(addDays(to, 1))),
					eq(ledgerTxn.type, 'expense')
				)
			);
		const spent = new Map<string, number>();
		const others = new Set<string>();
		for (const t of txns) {
			if (t.currency !== currency) {
				others.add(t.currency);
				continue;
			}
			const d = toManilaDate(t.occurredAt);
			spent.set(d, (spent.get(d) ?? 0) + t.amount);
		}
		const kcal = new Map(food.map((f) => [f.day, Number(f.kcal)]));
		const days = [];
		for (let d = from; d <= to; d = addDays(d, 1))
			days.push({ day: d, kcal: kcal.get(d) ?? null, spent: spent.get(d) ?? 0 });
		return { currency, otherCurrencies: [...others].sort(), days };
	});
}
