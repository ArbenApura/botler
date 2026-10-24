// THE SYNC CONTRACT FOR THE PHONE (P5.6). The phone asks "what should I have?" on app open, when a silent push arrives, and on a timer, and
// REPLACES its whole set of scheduled alarms with the answer. It never patches: a server that cancels a reminder simply stops listing it, and the
// phone drops it. Writes the phone made while offline wait in its own outbox and are sent to /api/v1/do/<verb> with their request ids.
// `cursor` is a cheap fingerprint of the reminder set; when it matches, the reminder list is left out and the phone keeps what it has.
// The summary card is always fresh.

// -- TYPES -- //
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, asc, eq, gte, isNull, lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, manilaStart, toManilaDate } from '../../finance/dates';
import { calendarEvent, reminder } from '../db/schema';
import { syncInput } from '../db/zod';
import { reconcileReminders } from '../schedule/reminders';
import { dueBills } from './bills';
import { run } from './context';
import { computeAssets } from './assets';
import { parse } from './shared';

// -- TYPES -- //

export type SyncReminder = {
	key: string;
	id: string;
	kind: string;
	title: string;
	at: string;
	version: number;
};

export type SummaryCard = {
	/** Minor units of the main currency: every wallet of every account converted with the stored rates. */
	total: number;
	/** The main currency the total is in. */
	currency: string;
	/** How many currencies are held but left out of the total because their exchange rate is missing. */
	totalMissing: number;
	/** When the rates used were fetched, or null when there are none. */
	ratesAsOf: string | null;
	nextBill: { name: string; dueDate: string; windowStart: string; windowEnd: string } | null;
	firstEventToday: { title: string; startsAt: string } | null;
};

export type SyncAnswer = {
	cursor: string;
	changed: boolean;
	/** Left out when the cursor matched. */
	reminders?: SyncReminder[];
	summary: SummaryCard;
	serverTime: string;
};

// -- CONSTANTS -- //

/** A reminder this far in the past is still handed over, so a phone that was asleep at the time can show it. */
const LATE_GRACE_MS = 10 * 60_000;
const HORIZON_MS = 14 * 24 * 3_600_000;

// -- FUNCTIONS -- //

export async function syncGet(ctx: Ctx, raw: unknown = {}): Promise<SyncAnswer> {
	const input = parse(syncInput, raw);
	return run(ctx, async (tx, userId) => {
		const now = new Date();
		// What is needed is worked out when asked, so a bill paid a minute ago no longer rings
		await reconcileReminders(tx, userId, now);
		const [stamp] = await tx
			.select({ n: sql<number>`count(*)::int`, m: sql<Date | null>`max(${reminder.updatedAt})` })
			.from(reminder)
			.where(eq(reminder.userId, userId));
		const cursor = `${stamp?.n ?? 0}:${stamp?.m ? new Date(stamp.m).getTime() : 0}`;
		const changed = cursor !== input.cursor;

		const reminders = changed
			? (
					await tx
						.select()
						.from(reminder)
						.where(
							and(
								eq(reminder.userId, userId),
								eq(reminder.status, 'scheduled'),
								gte(reminder.remindAt, new Date(now.getTime() - LATE_GRACE_MS)),
								lt(reminder.remindAt, new Date(now.getTime() + HORIZON_MS))
							)
						)
						.orderBy(asc(reminder.remindAt))
				).map((r) => ({
					key: r.refKey,
					id: r.id,
					kind: r.kind,
					title: r.title,
					at: r.remindAt.toISOString(),
					version: r.version
				}))
			: undefined;

		// The summary card: the total, the next bill, the first event today
		// The total is every wallet converted to the main currency (a wallet with no known rate is left out and counted in totalMissing)
		const { view: assets } = await computeAssets(tx, userId, now);
		const today = toManilaDate(now);
		const next = (await dueBills(tx, userId, today, addDays(today, 60))).find((b) => !b.paid);
		const [first] = await tx
			.select()
			.from(calendarEvent)
			.where(
				and(
					eq(calendarEvent.userId, userId),
					isNull(calendarEvent.deletedAt),
					gte(calendarEvent.startsAt, manilaStart(today)),
					lt(calendarEvent.startsAt, manilaStart(addDays(today, 1)))
				)
			)
			.orderBy(asc(calendarEvent.startsAt))
			.limit(1);
		return {
			cursor,
			changed,
			...(reminders ? { reminders } : {}),
			summary: {
				total: assets.total,
				currency: assets.currency,
				totalMissing: assets.missing.length,
				ratesAsOf: assets.rates.asOf,
				nextBill: next
					? {
							name: next.name,
							dueDate: next.dueDate,
							windowStart: next.windowStart,
							windowEnd: next.windowEnd
						}
					: null,
				firstEventToday: first
					? {
							title: first.title,
							startsAt: first.startsAt.toISOString()
						}
					: null
			},
			serverTime: now.toISOString()
		};
	});
}
