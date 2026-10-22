// THE REMINDER ENGINE: WORKS OUT WHAT THE PERSON SHOULD BE REMINDED OF, AND KEEPS THE reminder TABLE TRUE.
// A reminder exists only while something needs action: a bill is reminded until it is paid, a payday until its split is approved, a task
// until it is done, an event until it starts. When the thing is dealt with, its reminder is cancelled by the next reconcile, so the phone
// never rings for a paid bill. The phone reads the whole list and replaces its alarms (see ops/sync.ts).
// Reminders never carry amounts: a lock screen is not the place for them.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Recurrence } from '../../schedule/recurrence';
import type { Schedule } from '../../finance/schedule';
// -- DEP-MODULES -- //
import { and, eq, inArray, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, toManilaDate } from '../../finance/dates';
import { occurrencesBetween } from '../../finance/schedule';
import { atManilaTime, recurrenceOccurrences } from '../../schedule/recurrence';
import { calendarEvent, incomeSchedule, reminder, routine, splitPlan, task } from '../db/schema';
import { dueBills } from '../ops/bills';

// -- TYPES -- //

export type Desired = {
	kind: (typeof reminder.$inferSelect)['kind'];
	refKey: string;
	title: string;
	remindAt: Date;
};

export type Reconciled = { created: number; moved: number; cancelled: number };

// -- CONSTANTS -- //

export const HORIZON_DAYS = 14;
const MINUTE = 60_000;
const HOUR = 3_600_000;
/** An overdue nudge comes at this hour. */
const NUDGE_TIME = '09:00';
/** How long after being sent an overdue reminder may come again. */
const RESEND_AFTER_MS = 12 * HOUR;
/** A dismissed reminder stays dismissed unless the thing it is about moved by more than this. */
const DISMISS_STICKS_MS = 3 * 24 * HOUR;
const OVERDUE_BILL_DAYS = 7;
const OVERDUE_TASK_DAYS = 30;

// -- FUNCTIONS -- //

/** The next 09:00 in Manila after `now`. */
function nextNudge(now: Date): Date {
	const today = toManilaDate(now);
	const t = atManilaTime(today, NUDGE_TIME);
	return t.getTime() > now.getTime() ? t : atManilaTime(addDays(today, 1), NUDGE_TIME);
}

const clock = (d: Date) =>
	new Intl.DateTimeFormat('en-PH', {
		hour: 'numeric',
		minute: '2-digit',
		hour12: true,
		timeZone: 'Asia/Manila'
	}).format(d);

/** Everything that should be on the phone now, from the rest of the data. Reads only. */
export async function desiredReminders(tx: Tx, userId: string, now: Date): Promise<Desired[]> {
	const out: Desired[] = [];
	const today = toManilaDate(now);
	const end = addDays(today, HORIZON_DAYS);
	const endInstant = new Date(now.getTime() + HORIZON_DAYS * 24 * HOUR);

	// -- BILLS -- //
	for (const b of (await dueBills(tx, userId, addDays(today, -OVERDUE_BILL_DAYS), end)).filter(
		(x) => !x.paid
	)) {
		const refKey = `bill:${b.billId}:${b.dueDate}`;
		if (b.dueDate < today) {
			out.push({ kind: 'bill', refKey, title: `${b.name} is overdue`, remindAt: nextNudge(now) });
			continue;
		}
		const eve = atManilaTime(addDays(b.dueDate, -1), '18:00');
		const morning = atManilaTime(b.dueDate, '08:00');
		if (eve.getTime() > now.getTime())
			out.push({ kind: 'bill', refKey, title: `${b.name} is due tomorrow`, remindAt: eve });
		else if (morning.getTime() > now.getTime())
			out.push({ kind: 'bill', refKey, title: `${b.name} is due today`, remindAt: morning });
	}

	// -- PAYDAYS: UNTIL THE SPLIT IS APPROVED -- //
	const incomes = await tx
		.select()
		.from(incomeSchedule)
		.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.active, true)));
	const approved = await tx
		.select({ payday: splitPlan.payday, incomeId: splitPlan.incomeScheduleId })
		.from(splitPlan)
		.where(and(eq(splitPlan.userId, userId), eq(splitPlan.status, 'approved')));
	const done = new Set(approved.map((a) => `${a.incomeId}|${a.payday}`));
	for (const inc of incomes)
		for (const d of occurrencesBetween(inc.schedule as Schedule, today, end, {
			weekend: inc.weekendRule
		})) {
			if (done.has(`${inc.id}|${d}`)) continue;
			const at = atManilaTime(d, '08:00');
			if (at.getTime() > now.getTime())
				out.push({
					kind: 'payday',
					refKey: `payday:${inc.id}:${d}`,
					title: `Payday: time to split your pay (${inc.label})`,
					remindAt: at
				});
			else if (d === today)
				out.push({
					kind: 'payday',
					refKey: `payday:${inc.id}:${d}`,
					title: `Payday: time to split your pay (${inc.label})`,
					remindAt: nextNudge(now)
				});
		}

	// -- TASKS: UNTIL DONE -- //
	for (const t of await tx
		.select()
		.from(task)
		.where(and(eq(task.userId, userId), eq(task.status, 'open')))) {
		const base = t.followUpAt ?? (t.dueAt ? new Date(t.dueAt.getTime() - HOUR) : null);
		if (!base) continue;
		if (base.getTime() > endInstant.getTime()) continue;
		if (base.getTime() > now.getTime())
			out.push({ kind: 'task', refKey: `task:${t.id}`, title: t.title, remindAt: base });
		else if (now.getTime() - base.getTime() < OVERDUE_TASK_DAYS * 24 * HOUR)
			out.push({ kind: 'task', refKey: `task:${t.id}`, title: t.title, remindAt: nextNudge(now) });
	}

	// -- EVENTS -- //
	const events = await tx
		.select()
		.from(calendarEvent)
		.where(
			and(
				eq(calendarEvent.userId, userId),
				sql`${calendarEvent.deletedAt} is null`,
				inArray(calendarEvent.source, ['botler', 'google'])
			)
		);
	for (const e of events) {
		const at = e.allDay
			? atManilaTime(toManilaDate(e.startsAt), '08:00')
			: new Date(e.startsAt.getTime() - 30 * MINUTE);
		if (at.getTime() <= now.getTime() || at.getTime() > endInstant.getTime()) continue;
		out.push({
			kind: 'event',
			refKey: `event:${e.id}`,
			title: e.allDay ? `${e.title} today` : `${e.title} at ${clock(e.startsAt)}`,
			remindAt: at
		});
	}

	// -- ROUTINES -- //
	for (const r of await tx
		.select()
		.from(routine)
		.where(and(eq(routine.userId, userId), eq(routine.active, true))))
		for (const occ of recurrenceOccurrences(
			r.recurrence as Recurrence,
			new Date(now.getTime() + r.leadMinutes * MINUTE),
			new Date(endInstant.getTime() + r.leadMinutes * MINUTE)
		)) {
			const at = new Date(occ.getTime() - r.leadMinutes * MINUTE);
			if (at.getTime() > now.getTime())
				out.push({
					kind: 'routine',
					refKey: `routine:${r.id}:${occ.toISOString()}`,
					title: r.title,
					remindAt: at
				});
		}
	return out;
}

/** Brings the system reminders in line with what is needed now. Reminders the person or the assistant made on purpose are left alone. */
export async function reconcileReminders(
	tx: Tx,
	userId: string,
	now: Date = new Date()
): Promise<Reconciled> {
	const wanted = await desiredReminders(tx, userId, now);
	const existing = await tx
		.select()
		.from(reminder)
		.where(and(eq(reminder.userId, userId), eq(reminder.origin, 'system')));
	const have = new Map(existing.map((e) => [e.refKey, e]));
	const result: Reconciled = { created: 0, moved: 0, cancelled: 0 };
	const wantKeys = new Set<string>();
	const bump = { version: sql`${reminder.version} + 1`, updatedAt: sql`now()` };
	const set = (id: string, values: Partial<typeof reminder.$inferInsert>) =>
		tx
			.update(reminder)
			.set({ ...values, ...bump })
			.where(and(eq(reminder.userId, userId), eq(reminder.id, id)));

	for (const d of wanted) {
		wantKeys.add(d.refKey);
		const ex = have.get(d.refKey);
		if (!ex) {
			await tx.insert(reminder).values({
				userId,
				kind: d.kind,
				refKey: d.refKey,
				title: d.title,
				remindAt: d.remindAt,
				origin: 'system'
			});
			result.created++;
			continue;
		}
		const shift = d.remindAt.getTime() - ex.remindAt.getTime();
		const changed = Math.abs(shift) >= MINUTE || ex.title !== d.title;
		if (
			ex.status === 'cancelled' ||
			(ex.status === 'scheduled' && changed) ||
			(ex.status === 'sent' && shift >= RESEND_AFTER_MS) ||
			(ex.status === 'dismissed' && Math.abs(shift) > DISMISS_STICKS_MS)
		) {
			await set(ex.id, { status: 'scheduled', remindAt: d.remindAt, title: d.title });
			result.moved++;
		}
	}
	// Whatever no longer needs action is closed: one whose time has passed counts as sent, the rest are cancelled
	for (const ex of existing)
		if (!wantKeys.has(ex.refKey) && ex.status === 'scheduled') {
			await set(ex.id, { status: ex.remindAt.getTime() <= now.getTime() ? 'sent' : 'cancelled' });
			result.cancelled++;
		}
	return result;
}
