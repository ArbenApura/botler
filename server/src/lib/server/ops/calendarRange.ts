// THE CALENDAR READ MODEL (BTL-20261022-0218, ADR 4): EVERYTHING DATED IN A RANGE OF DAYS, AND AN ESTIMATE OF WHAT EACH ACCOUNT WILL HOLD
// One verb for the app's month, week and agenda views and for the assistant. It reads and changes nothing. Bills come as payment windows, paydays
// as single days, routines as their next moments, events as they are.
// The forecast starts from today's real balances, takes off the unpaid bills on the last day of their window and adds the expected pay on
// payday. It is an estimate and says so: a variable bill with no estimate yet counts as zero and is reported.

// -- TYPES -- //
import type { Ctx } from './context';
import type { CalendarRangeInput } from '../db/zod';
import type { Schedule } from '../../finance/schedule';
import type { Recurrence } from '../../schedule/recurrence';
import type { ManilaDate } from '../../finance/dates';
// -- DEP-MODULES -- //
import { and, eq, gte, isNull, lte, ne } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, diffDays, manilaStart, toManilaDate } from '../../finance/dates';
import { occurrencesBetween } from '../../finance/schedule';
import { recurrenceOccurrences } from '../../schedule/recurrence';
import {
	account,
	calendarEvent,
	incomeSchedule,
	reminder,
	routine,
	splitPlan,
	task
} from '../db/schema';
import { calendarRangeInput } from '../db/zod';
import { OpsError, run } from './context';
import { dueBills } from './bills';
import { balanceFor } from './ledger';
import { parse } from './shared';

// -- TYPES -- //

type Base = {
	id: string;
	title: string;
	/** The first day, a Manila date. */
	date: ManilaDate;
	/** The last day, the same as date for a single day. */
	endDate: ManilaDate;
};

export type CalendarItem =
	| (Base & {
			type: 'bill';
			amount: number | null;
			unknownAmount: boolean;
			paid: boolean;
			overdue: boolean;
			accountId: string;
	  })
	| (Base & { type: 'payday'; amount: number | null; done: boolean })
	| (Base & {
			type: 'event';
			startsAt: string;
			endsAt: string;
			allDay: boolean;
			source: string;
	  })
	| (Base & { type: 'routine'; at: string })
	| (Base & { type: 'task'; dueAt: string; priority: number })
	| (Base & { type: 'reminder'; at: string });

export type ForecastDay = {
	date: ManilaDate;
	/** The estimated total over all accounts at the end of the day. */
	total: number;
	/** Accounts that would be under their minimum at the end of the day. */
	lowAccountIds: string[];
};

export type CalendarRange = {
	from: ManilaDate;
	to: ManilaDate;
	items: CalendarItem[];
	forecast: {
		/** Always true: this is an estimate, not a promise. */
		estimate: true;
		days: ForecastDay[];
		accounts: { id: string; name: string; minBalance: number }[];
		/** Bills in the range with no amount to take off yet. */
		unknownBills: number;
	};
};

// -- CONSTANTS -- //

export const LAYERS = ['bills', 'paydays', 'events', 'routines', 'tasks', 'reminders'] as const;
/** The same lookback the reminders use, so a bill is overdue in the forecast exactly when it is overdue in a reminder. */
const OVERDUE_LOOKBACK_DAYS = 7;
export const MAX_RANGE_DAYS = 92;

// -- FUNCTIONS -- //

const day = (instant: Date) => toManilaDate(instant);

/** Everything dated between two Manila days, with the forecast of the balances over the days from today on. */
export async function calendarRange(ctx: Ctx, raw: CalendarRangeInput): Promise<CalendarRange> {
	const input = parse(calendarRangeInput, raw);
	const layers = new Set(input.layers ?? LAYERS);
	const { from, to } = input;
	if (to < from) throw new OpsError('INVALID', 'The end of the range is before its start.');
	if (diffDays(to, from) > MAX_RANGE_DAYS - 1)
		throw new OpsError('INVALID', `Ask for at most ${MAX_RANGE_DAYS} days at a time.`);
	return run(ctx, async (tx, userId) => {
		const now = new Date();
		const today = toManilaDate(now);
		const items: CalendarItem[] = [];
		const startInstant = manilaStart(from);
		const endInstant = manilaStart(addDays(to, 1));

		// -- BILLS: PAYMENT WINDOWS -- //
		const bills = await dueBills(tx, userId, from, to);
		if (layers.has('bills'))
			for (const b of bills)
				items.push({
					type: 'bill',
					id: b.billId,
					title: b.name,
					date: b.windowStart,
					endDate: b.windowEnd,
					amount: b.amount,
					unknownAmount: b.unknownAmount,
					paid: b.paid,
					overdue: !b.paid && b.windowEnd < today,
					accountId: b.accountId
				});

		// -- PAYDAYS -- //
		const incomes = await tx
			.select()
			.from(incomeSchedule)
			.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.active, true)));
		const approved = new Set(
			(
				await tx
					.select({ p: splitPlan.payday, i: splitPlan.incomeScheduleId })
					.from(splitPlan)
					.where(and(eq(splitPlan.userId, userId), eq(splitPlan.status, 'approved')))
			).map((a) => `${a.i}|${a.p}`)
		);
		const paydays: {
			id: string;
			label: string;
			date: ManilaDate;
			amount: number | null;
			accountId: string;
		}[] = [];
		for (const inc of incomes)
			for (const d of occurrencesBetween(inc.schedule as Schedule, from, to, {
				weekend: inc.weekendRule
			}))
				paydays.push({
					id: inc.id,
					label: inc.label,
					date: d,
					amount: inc.expectedAmount,
					accountId: inc.accountId
				});
		if (layers.has('paydays'))
			for (const p of paydays)
				items.push({
					type: 'payday',
					id: p.id,
					title: p.label,
					date: p.date,
					endDate: p.date,
					amount: p.amount,
					done: approved.has(`${p.id}|${p.date}`)
				});

		// -- EVENTS -- //
		if (layers.has('events')) {
			const events = await tx
				.select()
				.from(calendarEvent)
				.where(
					and(
						eq(calendarEvent.userId, userId),
						isNull(calendarEvent.deletedAt),
						// Overlapping the range: starts before it ends and ends after it starts
						lte(calendarEvent.startsAt, endInstant),
						gte(calendarEvent.endsAt, startInstant),
						// Bills and paydays Botler put on the calendar are shown by their own layers
						ne(calendarEvent.source, 'bill'),
						ne(calendarEvent.source, 'payday')
					)
				);
			for (const e of events) {
				// An all-day event ends the day after its last day
				const lastDay = e.allDay ? day(new Date(e.endsAt.getTime() - 1)) : day(e.endsAt);
				items.push({
					type: 'event',
					id: e.id,
					title: e.title,
					date: day(e.startsAt),
					endDate: lastDay < day(e.startsAt) ? day(e.startsAt) : lastDay,
					startsAt: e.startsAt.toISOString(),
					endsAt: e.endsAt.toISOString(),
					allDay: e.allDay,
					source: e.source
				});
			}
		}

		// -- ROUTINES -- //
		if (layers.has('routines')) {
			const routines = await tx
				.select()
				.from(routine)
				.where(and(eq(routine.userId, userId), eq(routine.active, true)));
			for (const r of routines)
				for (const at of recurrenceOccurrences(
					r.recurrence as Recurrence,
					startInstant,
					endInstant
				))
					items.push({
						type: 'routine',
						id: r.id,
						title: r.title,
						date: day(at),
						endDate: day(at),
						at: at.toISOString()
					});
		}

		// -- TASKS -- //
		if (layers.has('tasks')) {
			const tasks = await tx
				.select()
				.from(task)
				.where(
					and(
						eq(task.userId, userId),
						eq(task.status, 'open'),
						gte(task.dueAt, startInstant),
						lte(task.dueAt, endInstant)
					)
				);
			for (const t of tasks)
				if (t.dueAt)
					items.push({
						type: 'task',
						id: t.id,
						title: t.title,
						date: day(t.dueAt),
						endDate: day(t.dueAt),
						dueAt: t.dueAt.toISOString(),
						priority: t.priority
					});
		}

		// -- REMINDERS THE PERSON MADE -- //
		if (layers.has('reminders')) {
			const reminders = await tx
				.select()
				.from(reminder)
				.where(
					and(
						eq(reminder.userId, userId),
						eq(reminder.status, 'scheduled'),
						ne(reminder.origin, 'system'),
						gte(reminder.remindAt, startInstant),
						lte(reminder.remindAt, endInstant)
					)
				);
			for (const r of reminders)
				items.push({
					type: 'reminder',
					id: r.id,
					title: r.title,
					date: day(r.remindAt),
					endDate: day(r.remindAt),
					at: r.remindAt.toISOString()
				});
		}

		items.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.title < b.title ? -1 : 1));

		// -- THE FORECAST -- //
		const accounts = await tx
			.select({ id: account.id, name: account.name, minBalance: account.minBalance })
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)));
		const days: ForecastDay[] = [];
		let unknownBills = 0;
		const first = from > today ? from : today;
		if (first <= to && accounts.length > 0) {
			const balances = new Map<string, number>();
			for (const a of accounts)
				balances.set(a.id, (await balanceFor(tx, userId, a.id, now)).balance);
			// Bills the range does not show, still unpaid and past due, come off today
			const overdue = (
				await dueBills(tx, userId, addDays(today, -OVERDUE_LOOKBACK_DAYS), addDays(today, -1))
			).filter((b) => !b.paid);
			const ahead = await dueBills(tx, userId, first, to);
			const unpaid = [
				...overdue.map((b) => ({ ...b, dueDate: today })),
				...ahead.filter((b) => !b.paid)
			];
			const unknown = new Set<string>();
			const delta = new Map<ManilaDate, Map<string, number>>();
			const add = (date: ManilaDate, accountId: string, amount: number) => {
				const m = delta.get(date) ?? new Map<string, number>();
				m.set(accountId, (m.get(accountId) ?? 0) + amount);
				delta.set(date, m);
			};
			for (const b of unpaid) {
				if (b.amount === null) unknown.add(`${b.billId}|${b.dueDate}`);
				else add(b.dueDate, b.accountId, -b.amount);
			}
			// Expected pay arrives on payday, after today (today's is assumed recorded already)
			const futurePaydays = await Promise.all(
				incomes.map(async (inc) => ({
					inc,
					dates: occurrencesBetween(inc.schedule as Schedule, addDays(today, 1), to, {
						weekend: inc.weekendRule
					})
				}))
			);
			for (const { inc, dates } of futurePaydays)
				for (const d of dates) if (inc.expectedAmount) add(d, inc.accountId, inc.expectedAmount);
			unknownBills = unknown.size;
			const span = diffDays(to, first);
			for (let i = 0; i <= span; i++) {
				const d = addDays(first, i);
				for (const [accountId, amount] of delta.get(d) ?? [])
					balances.set(accountId, (balances.get(accountId) ?? 0) + amount);
				if (d < from) continue;
				let total = 0;
				const low: string[] = [];
				for (const a of accounts) {
					const b = balances.get(a.id) ?? 0;
					total += b;
					if (b < a.minBalance) low.push(a.id);
				}
				days.push({ date: d, total, lowAccountIds: low });
			}
		}
		return {
			from,
			to,
			items,
			forecast: { estimate: true as const, days, accounts, unknownBills }
		};
	});
}

/** The layers a person can switch, for the app's toggles. */
export const CALENDAR_LAYERS = LAYERS;
