// SCHEDULING VERBS: TASKS, EVENTS, ROUTINES, REMINDERS, ALARMS AND TIMERS.
// Every write ends by bringing the reminders in line (src/lib/server/schedule/reminders.ts) and asking the phone to look again, so what
// the person sees on the phone is what the server believes.

// -- TYPES -- //
import type { Ctx } from './context';
import type { Plain } from './shared';
import type { Recurrence } from '../../schedule/recurrence';
// -- DEP-MODULES -- //
import { and, asc, desc, eq, gte, inArray, isNull, lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, manilaStart } from '../../finance/dates';
import { calendarEvent, reminder, routine, task } from '../db/schema';
import {
	eventCreateInput,
	eventIdInput,
	eventListInput,
	eventUpdateInput,
	reminderCreateInput,
	reminderIdInput,
	routineCreateInput,
	routineUpdateInput,
	taskCreateInput,
	taskIdInput,
	taskListInput,
	taskUpdateInput,
	timerCreateInput
} from '../db/zod';
import { enqueue } from '../jobs/queue';
import { reconcileReminders } from '../schedule/reminders';
import { OpsError, run, runWrite } from './context';
import { checkVersion, mapped, parse, plain } from './shared';

// -- TYPES -- //

export type TaskView = Plain<typeof task.$inferSelect>;
export type EventView = Plain<typeof calendarEvent.$inferSelect>;
export type RoutineView = Plain<typeof routine.$inferSelect>;
export type ReminderView = Plain<typeof reminder.$inferSelect>;

// -- CONSTANTS -- //

const HOUR = 3_600_000;

// -- FUNCTIONS -- //

const eventView = (e: typeof calendarEvent.$inferSelect): EventView => plain(e);

/** After a change: reminders in line, and the phone asked to look again (at most once a minute). */
export async function afterScheduleChange(
	tx: Parameters<typeof reconcileReminders>[0],
	userId: string
) {
	await reconcileReminders(tx, userId);
	await enqueue(tx, { userId, kind: 'push.sync', key: new Date().toISOString().slice(0, 16) });
}

// -- TASKS -- //

export async function createTask(ctx: Ctx, raw: unknown): Promise<TaskView> {
	const input = parse(taskCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'task.create', input, async (tx, userId) => {
			const [row] = await tx
				.insert(task)
				.values({
					userId,
					title: input.title,
					notes: input.notes ?? '',
					dueAt: input.dueAt ? new Date(input.dueAt) : null,
					followUpAt: input.followUpAt ? new Date(input.followUpAt) : null,
					priority: input.priority ?? 2,
					source: ctx.actor.kind === 'agent' ? 'chat' : 'user'
				})
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The task could not be saved.');
			await afterScheduleChange(tx, userId);
			return plain(row);
		})
	);
}

export async function updateTask(ctx: Ctx, raw: unknown): Promise<TaskView> {
	const { taskId, expectVersion, ...changes } = parse(taskUpdateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'task.update', { taskId, expectVersion, ...changes }, async (tx, userId) => {
			const [cur] = await tx
				.select()
				.from(task)
				.where(and(eq(task.userId, userId), eq(task.id, taskId)));
			if (!cur) throw new OpsError('NOT_FOUND', 'That task does not exist.');
			checkVersion(cur.version, expectVersion, 'task');
			const set: Partial<typeof task.$inferInsert> = {};
			if (changes.title !== undefined) set.title = changes.title;
			if (changes.notes !== undefined) set.notes = changes.notes;
			if (changes.priority !== undefined) set.priority = changes.priority;
			if (changes.dueAt !== undefined) set.dueAt = changes.dueAt ? new Date(changes.dueAt) : null;
			if (changes.followUpAt !== undefined)
				set.followUpAt = changes.followUpAt ? new Date(changes.followUpAt) : null;
			if (changes.status !== undefined) {
				set.status = changes.status;
				set.doneAt = changes.status === 'done' ? new Date() : null;
			}
			const [row] = await tx
				.update(task)
				.set({ ...set, version: sql`${task.version} + 1`, updatedAt: sql`now()` })
				.where(and(eq(task.userId, userId), eq(task.id, taskId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That task does not exist.');
			await afterScheduleChange(tx, userId);
			return plain(row);
		})
	);
}

/** Marks a task done. */
export const completeTask = (ctx: Ctx, raw: unknown) => {
	const { taskId } = parse(taskIdInput, raw);
	return updateTask(ctx, { taskId, status: 'done' });
};

export async function listTasks(ctx: Ctx, raw: unknown = {}): Promise<TaskView[]> {
	const input = parse(taskListInput, raw);
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(task)
			.where(and(eq(task.userId, userId), eq(task.status, input.status ?? 'open')))
			.orderBy(sql`${task.dueAt} asc nulls last`, desc(task.priority), asc(task.createdAt))
			.limit(input.limit ?? 100)
	);
	return plain(rows);
}

// -- EVENTS -- //

export async function createEvent(ctx: Ctx, raw: unknown): Promise<EventView> {
	const input = parse(eventCreateInput, raw);
	const start = new Date(input.startsAt);
	const end = input.endsAt
		? new Date(input.endsAt)
		: new Date(start.getTime() + (input.allDay ? 24 : 1) * HOUR);
	if (end.getTime() < start.getTime())
		throw new OpsError('INVALID', 'The event ends before it starts.');
	return mapped(() =>
		runWrite(ctx, 'event.create', input, async (tx, userId) => {
			const [row] = await tx
				.insert(calendarEvent)
				.values({
					userId,
					title: input.title,
					startsAt: start,
					endsAt: end,
					allDay: input.allDay ?? false,
					location: input.location ?? '',
					notes: input.notes ?? '',
					source: 'botler'
				})
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The event could not be saved.');
			await afterScheduleChange(tx, userId);
			return eventView(row);
		})
	);
}

export async function updateEvent(ctx: Ctx, raw: unknown): Promise<EventView> {
	const { eventId, expectVersion, ...changes } = parse(eventUpdateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'event.update', { eventId, expectVersion, ...changes }, async (tx, userId) => {
			const [cur] = await tx
				.select()
				.from(calendarEvent)
				.where(
					and(
						eq(calendarEvent.userId, userId),
						eq(calendarEvent.id, eventId),
						isNull(calendarEvent.deletedAt)
					)
				);
			if (!cur) throw new OpsError('NOT_FOUND', 'That event does not exist.');
			if (cur.source === 'bill' || cur.source === 'payday')
				throw new OpsError('INVALID', 'That event is made from a bill or payday and follows it.');
			checkVersion(cur.version, expectVersion, 'event');
			const startsAt = changes.startsAt ? new Date(changes.startsAt) : cur.startsAt;
			const endsAt = changes.endsAt
				? new Date(changes.endsAt)
				: changes.startsAt
					? new Date(startsAt.getTime() + (cur.endsAt.getTime() - cur.startsAt.getTime()))
					: cur.endsAt;
			if (endsAt.getTime() < startsAt.getTime())
				throw new OpsError('INVALID', 'The event ends before it starts.');
			const [row] = await tx
				.update(calendarEvent)
				.set({
					startsAt,
					endsAt,
					...(changes.title !== undefined ? { title: changes.title } : {}),
					...(changes.allDay !== undefined ? { allDay: changes.allDay } : {}),
					...(changes.location !== undefined ? { location: changes.location } : {}),
					...(changes.notes !== undefined ? { notes: changes.notes } : {}),
					version: sql`${calendarEvent.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(and(eq(calendarEvent.userId, userId), eq(calendarEvent.id, eventId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That event does not exist.');
			await afterScheduleChange(tx, userId);
			return eventView(row);
		})
	);
}

/** Removes an event. */
export async function deleteEvent(ctx: Ctx, raw: unknown) {
	const { eventId } = parse(eventIdInput, raw);
	return mapped(() =>
		runWrite(ctx, 'event.delete', { eventId }, async (tx, userId) => {
			const [cur] = await tx
				.select()
				.from(calendarEvent)
				.where(
					and(
						eq(calendarEvent.userId, userId),
						eq(calendarEvent.id, eventId),
						isNull(calendarEvent.deletedAt)
					)
				);
			if (!cur) throw new OpsError('NOT_FOUND', 'That event does not exist.');
			await tx
				.delete(calendarEvent)
				.where(and(eq(calendarEvent.userId, userId), eq(calendarEvent.id, eventId)));
			await afterScheduleChange(tx, userId);
			return { deleted: true };
		})
	);
}

/** Events between two Manila dates, inclusive. */
export async function listEvents(ctx: Ctx, raw: unknown): Promise<EventView[]> {
	const { from, to } = parse(eventListInput, raw);
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(calendarEvent)
			.where(
				and(
					eq(calendarEvent.userId, userId),
					isNull(calendarEvent.deletedAt),
					gte(calendarEvent.startsAt, manilaStart(from)),
					lt(calendarEvent.startsAt, manilaStart(addDays(to, 1)))
				)
			)
			.orderBy(asc(calendarEvent.startsAt))
			.limit(300)
	);
	return rows.map(eventView);
}

// -- ROUTINES -- //

export async function createRoutine(ctx: Ctx, raw: unknown): Promise<RoutineView> {
	const input = parse(routineCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'routine.create', input, async (tx, userId) => {
			const [row] = await tx
				.insert(routine)
				.values({
					userId,
					title: input.title,
					recurrence: input.recurrence as Recurrence,
					leadMinutes: input.leadMinutes ?? 0
				})
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The routine could not be saved.');
			await afterScheduleChange(tx, userId);
			return plain(row);
		})
	);
}

export async function updateRoutine(ctx: Ctx, raw: unknown): Promise<RoutineView> {
	const { routineId, expectVersion, ...changes } = parse(routineUpdateInput, raw);
	return mapped(() =>
		runWrite(
			ctx,
			'routine.update',
			{ routineId, expectVersion, ...changes },
			async (tx, userId) => {
				const [cur] = await tx
					.select()
					.from(routine)
					.where(and(eq(routine.userId, userId), eq(routine.id, routineId)));
				if (!cur) throw new OpsError('NOT_FOUND', 'That routine does not exist.');
				checkVersion(cur.version, expectVersion, 'routine');
				const [row] = await tx
					.update(routine)
					.set({
						...(changes.title !== undefined ? { title: changes.title } : {}),
						...(changes.recurrence !== undefined ? { recurrence: changes.recurrence } : {}),
						...(changes.leadMinutes !== undefined ? { leadMinutes: changes.leadMinutes } : {}),
						...(changes.active !== undefined ? { active: changes.active } : {}),
						version: sql`${routine.version} + 1`,
						updatedAt: sql`now()`
					})
					.where(and(eq(routine.userId, userId), eq(routine.id, routineId)))
					.returning();
				if (!row) throw new OpsError('NOT_FOUND', 'That routine does not exist.');
				await afterScheduleChange(tx, userId);
				return plain(row);
			}
		)
	);
}

export async function listRoutines(ctx: Ctx): Promise<RoutineView[]> {
	return plain(
		await run(ctx, (tx, userId) =>
			tx.select().from(routine).where(eq(routine.userId, userId)).orderBy(routine.title)
		)
	);
}

// -- REMINDERS, ALARMS, TIMERS -- //

async function addReminder(
	ctx: Ctx,
	verb: string,
	kind: 'custom' | 'alarm' | 'timer',
	title: string,
	at: Date,
	input: unknown
): Promise<ReminderView> {
	if (at.getTime() < Date.now() - 60_000)
		throw new OpsError(
			'INVALID',
			`That time has already passed. It is now ${new Date(Date.now() + 8 * 3_600_000).toISOString().slice(0, 19)}+08:00; give a later instant.`
		);
	return mapped(() =>
		runWrite(ctx, verb, input, async (tx, userId) => {
			const [row] = await tx
				.insert(reminder)
				.values({
					userId,
					kind,
					refKey: `${kind}:${crypto.randomUUID()}`,
					title,
					remindAt: at,
					origin: ctx.actor.kind === 'agent' ? 'agent' : 'user'
				})
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The reminder could not be saved.');
			await enqueue(tx, { userId, kind: 'push.sync', key: new Date().toISOString().slice(0, 16) });
			// A reminder the assistant made also gets a visible push at its time, in case the phone has not heard of it yet
			if (row.origin === 'agent')
				await enqueue(tx, {
					userId,
					kind: 'push.nudge',
					key: row.id,
					payload: { reminderId: row.id },
					runAfter: at
				});
			return plain(row);
		})
	);
}

export async function createReminder(ctx: Ctx, raw: unknown) {
	const input = parse(reminderCreateInput, raw);
	return addReminder(ctx, 'reminder.create', 'custom', input.title, new Date(input.at), input);
}

/** An alarm: the phone sets it on its own clock app. */
export async function createAlarm(ctx: Ctx, raw: unknown) {
	const input = parse(reminderCreateInput, raw);
	return addReminder(ctx, 'alarm.create', 'alarm', input.title, new Date(input.at), input);
}

/** A timer for some minutes from now. */
export async function createTimer(ctx: Ctx, raw: unknown) {
	const input = parse(timerCreateInput, raw);
	return addReminder(
		ctx,
		'timer.create',
		'timer',
		input.title ?? `${input.minutes} minute timer`,
		new Date(Date.now() + input.minutes * 60_000),
		input
	);
}

/** The person (or the phone, after showing it) closes a reminder. */
export async function closeReminder(
	ctx: Ctx,
	raw: unknown,
	status: 'cancelled' | 'dismissed' = 'cancelled'
) {
	const { reminderId } = parse(reminderIdInput, raw);
	return mapped(() =>
		runWrite(ctx, `reminder.${status}`, { reminderId }, async (tx, userId) => {
			const [row] = await tx
				.update(reminder)
				.set({
					// A reminder the engine makes would come back at the next sync if it were only cancelled: closing it is a dismissal
					status:
						status === 'cancelled'
							? sql`case when ${reminder.origin} = 'system' then 'dismissed' else 'cancelled' end`
							: status,
					version: sql`${reminder.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(
					and(
						eq(reminder.userId, userId),
						eq(reminder.id, reminderId),
						inArray(reminder.status, ['scheduled', 'sent'])
					)
				)
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'There is no such open reminder.');
			await enqueue(tx, { userId, kind: 'push.sync', key: new Date().toISOString().slice(0, 16) });
			return plain(row);
		})
	);
}

export async function listReminders(ctx: Ctx): Promise<ReminderView[]> {
	return plain(
		await run(ctx, (tx, userId) =>
			tx
				.select()
				.from(reminder)
				.where(and(eq(reminder.userId, userId), eq(reminder.status, 'scheduled')))
				.orderBy(asc(reminder.remindAt))
				.limit(200)
		)
	);
}
