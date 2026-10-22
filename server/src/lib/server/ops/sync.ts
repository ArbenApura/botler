// THE SYNC CONTRACT FOR THE PHONE (P5.6). The phone asks "what should I have?" on app open, when a silent push arrives, and on a timer, and
// REPLACES its whole set of scheduled alarms with the answer. It never patches: a server that cancels a reminder simply stops listing it, and the
// phone drops it. Writes the phone made while offline wait in its own outbox and are sent to /api/v1/do/<verb> with their request ids.
// `cursor` is a cheap fingerprint of the reminder set; when it matches, the reminder list is left out and the phone keeps what it has.
// The summary card is always fresh. If calendar sync broke (Google refused us), the answer says so, so the app can show a banner.

// -- TYPES -- //
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, asc, eq, gte, isNull, lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, manilaStart, toManilaDate } from '../../finance/dates';
import { account, calendarEvent, calendarSync, reminder } from '../db/schema';
import { syncInput } from '../db/zod';
import { reconcileReminders } from '../schedule/reminders';
import { dueBills } from './bills';
import { run } from './context';
import { balanceFor } from './ledger';
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
	/** Centavos, across the accounts. */
	total: number;
	nextBill: { name: string; dueDate: string; windowStart: string; windowEnd: string } | null;
	firstEventToday: { title: string; startsAt: string; untrusted: boolean } | null;
};

export type SyncAnswer = {
	cursor: string;
	changed: boolean;
	/** Left out when the cursor matched. */
	reminders?: SyncReminder[];
	summary: SummaryCard;
	calendar: { status: string; errorCode: string | null; lastSyncAt: string | null };
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
		const accounts = await tx
			.select({ id: account.id })
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)));
		let total = 0;
		for (const a of accounts) total += (await balanceFor(tx, userId, a.id, now)).balance;
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
		const [cal] = await tx.select().from(calendarSync).where(eq(calendarSync.userId, userId));
		return {
			cursor,
			changed,
			...(reminders ? { reminders } : {}),
			summary: {
				total,
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
							startsAt: first.startsAt.toISOString(),
							untrusted: first.source === 'google'
						}
					: null
			},
			calendar: {
				status: cal?.status ?? 'off',
				errorCode: cal?.errorCode ?? null,
				lastSyncAt: cal?.lastSyncAt?.toISOString() ?? null
			},
			serverTime: now.toISOString()
		};
	});
}
