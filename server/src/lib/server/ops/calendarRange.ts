// THE CALENDAR READ MODEL (BTL-20261022-0218, ADR 4): EVERYTHING DATED IN A RANGE OF DAYS, AND AN ESTIMATE OF WHAT EACH ACCOUNT WILL HOLD
// One verb for the app's month, week and agenda views and for the assistant. It reads and changes nothing. Bills come as payment windows, paydays
// as single days, routines as their next moments, events as they are.
// The forecast is the one of cashflow_forecast (finance/planFlows.ts over today's wallets): it takes off the unpaid bills (late ones up to 31
// days, today) on the last day of their window and adds the expected pay on payday, today's included unless it is recorded. It is an estimate
// and says so: a variable bill with no estimate yet counts as zero and is reported.

// -- TYPES -- //
import type { Ctx } from './context';
import type { CalendarRangeInput } from '../db/zod';
import type { Schedule } from '../../finance/schedule';
import type { Recurrence } from '../../schedule/recurrence';
import type { ManilaDate } from '../../finance/dates';
import type { ForecastFlow, ForecastWallet } from '../../finance/forecast';
// -- DEP-MODULES -- //
import { and, eq, gt, gte, isNull, lt, ne, or } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, diffDays, dayStart, toLocalDate } from '../../finance/dates';
import { forecast } from '../../finance/forecast';
import { placeBills, planFlows } from '../../finance/planFlows';
import { occurrencesBetween } from '../../finance/schedule';
import { recurrenceOccurrences } from '../../schedule/recurrence';
import { workoutTitle } from '../../health/programs';
import {
	calendarEvent,
	incomeSchedule,
	plannedWorkout,
	reminder,
	routine,
	splitPlan,
	task
} from '../db/schema';
import { calendarRangeInput } from '../db/zod';
import { OpsError, run } from './context';
import { dueBills } from './bills';
import { walletBalances } from './ledger';
import { loadPlan } from './planData';
import { marksOf } from './picture';
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
			/** The currency of amount: the bill's own, which is the main currency unless it says another. */
			currency: string;
			unknownAmount: boolean;
			paid: boolean;
			overdue: boolean;
			accountId: string;
			/** The mark of the bill, else the one of the account it is paid from; null when neither has one. */
			icon: string | null;
			imageId: string | null;
	  })
	| (Base & {
			type: 'payday';
			amount: number | null;
			done: boolean;
			/** The mark of the account the pay lands in. */
			icon: string | null;
			imageId: string | null;
	  })
	| (Base & {
			type: 'event';
			startsAt: string;
			endsAt: string;
			allDay: boolean;
			source: string;
	  })
	| (Base & { type: 'routine'; at: string })
	| (Base & { type: 'task'; dueAt: string; priority: number })
	| (Base & { type: 'reminder'; at: string })
	| (Base & { type: 'workout'; at: string; minutes: number; kind: string; status: string });

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
		/** Bills that could not be taken off: in a currency with no known rate, or on an account with no wallet in the bill's currency. */
		unconvertedBills: number;
		/** Currencies held or owed with no exchange rate: left out of every total. */
		missingRates: string[];
	};
};

// -- CONSTANTS -- //

export const LAYERS = [
	'bills',
	'paydays',
	'events',
	'routines',
	'tasks',
	'reminders',
	'workouts'
] as const;
/** How far past today the forecast is worked out (the simulation's reach: 5 years). */
const FORECAST_REACH_DAYS = 1827;
export const MAX_RANGE_DAYS = 92;

// -- FUNCTIONS -- //

const day = (instant: Date) => toLocalDate(instant);

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
		const today = toLocalDate(now);
		const items: CalendarItem[] = [];
		const startInstant = dayStart(from);
		const endInstant = dayStart(addDays(to, 1));
		const marks = await marksOf(tx, userId);
		const none = { icon: null, imageId: null };

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
					currency: b.currency,
					unknownAmount: b.unknownAmount,
					paid: b.paid,
					overdue: !b.paid && b.windowEnd < today,
					accountId: b.accountId,
					...(marks.bills.get(b.billId) ?? marks.accounts.get(b.accountId) ?? none)
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
					done: approved.has(`${p.id}|${p.date}`),
					...(marks.accounts.get(p.accountId) ?? none)
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
						// Overlapping the range: starts before the next day's first instant, and ends after the range starts (or starts in it)
						lt(calendarEvent.startsAt, endInstant),
						or(gt(calendarEvent.endsAt, startInstant), gte(calendarEvent.startsAt, startInstant)),
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
						lt(task.dueAt, endInstant)
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
						lt(reminder.remindAt, endInstant)
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

		// -- PLANNED WORKOUTS -- //
		if (layers.has('workouts')) {
			const workouts = await tx
				.select()
				.from(plannedWorkout)
				.where(
					and(
						eq(plannedWorkout.userId, userId),
						gte(plannedWorkout.startsAt, startInstant),
						lt(plannedWorkout.startsAt, endInstant),
						ne(plannedWorkout.status, 'skipped')
					)
				);
			for (const w of workouts)
				items.push({
					type: 'workout',
					id: w.id,
					title: workoutTitle(w.sessionKey, w.kind),
					date: w.day,
					endDate: w.day,
					at: w.startsAt.toISOString(),
					minutes: w.minutes,
					kind: w.kind,
					status: w.status
				});
		}

		items.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.title < b.title ? -1 : 1));

		// -- THE FORECAST -- //
		// The same engine as cashflow_forecast and the simulation: the plan's flows (finance/planFlows.ts, future mode) over today's wallets, with
		// every rule that rests on a hidden account or a switched-off goal already left out (ops/planData.ts). Wallets of other currencies are
		// forecast in their own currency and converted at the stored rates for the total; a currency with no rate is named, never counted as zero.
		const loaded = await loadPlan(tx, userId, { now, incomeSince: dayStart(today) });
		const main = loaded.settings.currency;
		const activeAccounts = loaded.accounts.filter((a) => a.archivedAt === null);
		const { order, balances: walletNow } = await walletBalances(tx, userId, activeAccounts, now);
		// The minimum balance is judged in the main currency: an account with no wallet in it has nothing to judge or forecast
		const accounts = activeAccounts
			.filter((a) => (order.get(a.id) ?? []).includes(main))
			.map((a) => ({ id: a.id, name: a.name, minBalance: a.minBalance }));
		const days: ForecastDay[] = [];
		let unknownBills = 0;
		let unconvertedBills = 0;
		const missing = new Set<string>();
		const first = from > today ? from : today;
		if (first <= to && diffDays(to, today) < FORECAST_REACH_DAYS && activeAccounts.length > 0) {
			const wallets: ForecastWallet[] = [];
			for (const a of activeAccounts)
				for (const currency of order.get(a.id) ?? [])
					wallets.push({
						accountId: a.id,
						accountName: a.name,
						currency,
						balance: walletNow.get(`${a.id}|${currency}`)?.balance ?? 0
					});
			const mainNow = new Map(
				wallets.filter((w) => w.currency === main).map((w) => [w.accountId, w.balance])
			);
			const made = planFlows(
				{
					...loaded.plan,
					accounts: loaded.plan.accounts.filter((x) => !x.archived),
					balances: mainNow
				},
				{ mode: 'future', from: today, to, today }
			);
			// Bills go on the wallets that exist (finance/planFlows.ts placeBills); one that has none to be paid from is counted, not dropped
			const placed = placeBills(made.flows, wallets, main, loaded.status.rates);
			const flows: ForecastFlow[] = placed.flows.map(
				({ origin: _origin, refId: _refId, ...flow }) => flow
			);
			unconvertedBills = placed.unplaced.filter((x) => x.date >= first).length;
			for (const c of placed.unrated) missing.add(c);
			unknownBills = made.unknown.filter((u) => u.kind === 'bill' && u.date >= first).length;
			const result = forecast({
				from: today,
				to,
				group: 'day',
				weekStart: loaded.settings.weekStartsOn,
				main,
				rates: loaded.status.rates,
				wallets,
				flows,
				limits: {
					maxDays: FORECAST_REACH_DAYS,
					maxDailyDays: FORECAST_REACH_DAYS,
					maxWeeklyDays: FORECAST_REACH_DAYS
				}
			});
			// The main currency balance of each listed account, moved day by day by the wallets that changed
			const running = new Map(
				wallets.filter((w) => w.currency === main).map((w) => [w.accountId, w.balance])
			);
			for (const p of result.periods) {
				for (const w of p.wallets) if (w.currency === main) running.set(w.accountId, w.end);
				if (p.from < from) continue;
				days.push({
					date: p.from,
					total: p.endTotal,
					lowAccountIds: accounts
						.filter((a) => (running.get(a.id) ?? 0) < a.minBalance)
						.map((a) => a.id)
				});
			}
			for (const c of result.missing) missing.add(c);
		}
		return {
			from,
			to,
			items,
			forecast: {
				estimate: true as const,
				days,
				accounts,
				unknownBills,
				unconvertedBills,
				missingRates: [...missing].sort()
			}
		};
	});
}

/** The layers a person can switch, for the app's toggles. */
export const CALENDAR_LAYERS = LAYERS;
