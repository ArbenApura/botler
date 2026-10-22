// THE SCHEDULING TABLES: TASKS, EVENTS (WITH THEIR GOOGLE CALENDAR TWIN), ROUTINES, THE REMINDERS THE PHONE SCHEDULES, AND THE CALENDAR SYNC STATE.
// Reminders are rows the server computes from everything else (bills, paydays, tasks, events, routines) and keeps true: when the thing
// no longer needs action (a bill is paid) its reminder is cancelled. The phone replaces its whole set of alarms from this list.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import {
	boolean,
	check,
	index,
	integer,
	jsonb,
	text,
	timestamp,
	unique
} from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, plainTable, stamps, userTable, version } from './helpers';

// -- CONSTANTS -- //

export const TASK_STATUSES = ['open', 'done', 'dropped'] as const;
export const TASK_SOURCES = ['user', 'chat', 'calendar'] as const;
export const EVENT_SOURCES = ['botler', 'google', 'bill', 'payday'] as const;
export const REMINDER_KINDS = [
	'task',
	'event',
	'bill',
	'payday',
	'routine',
	'custom',
	'alarm',
	'timer'
] as const;
export const REMINDER_STATUSES = ['scheduled', 'sent', 'dismissed', 'cancelled'] as const;
export const REMINDER_ORIGINS = ['user', 'agent', 'system'] as const;
export const CALENDAR_STATUSES = ['off', 'ok', 'error'] as const;

// -- TASKS -- //

export const task = userTable(
	'task',
	() => user.id,
	{
		id: id(),
		title: text('title').notNull(),
		notes: text('notes').notNull().default(''),
		/** When it is due, as an instant. Null for a task with no deadline. */
		dueAt: timestamp('due_at', { withTimezone: true }),
		/** When to bring it up again, if the person did not finish it. */
		followUpAt: timestamp('follow_up_at', { withTimezone: true }),
		status: text('status', { enum: TASK_STATUSES }).notNull().default('open'),
		priority: integer('priority').notNull().default(2),
		source: text('source', { enum: TASK_SOURCES }).notNull().default('user'),
		doneAt: timestamp('done_at', { withTimezone: true }),
		version: version(),
		...stamps()
	},
	(t) => [
		index('task_user_status_idx').on(t.userId, t.status, t.dueAt),
		oneOf('task_status_chk', t.status, TASK_STATUSES),
		oneOf('task_source_chk', t.source, TASK_SOURCES),
		check(
			'task_title_chk',
			sql`length(${t.title}) between 1 and 200 and length(${t.notes}) <= 2000`
		),
		check('task_priority_chk', sql`${t.priority} between 1 and 3`)
	]
);

// -- EVENTS -- //

export const calendarEvent = userTable(
	'calendar_event',
	() => user.id,
	{
		id: id(),
		title: text('title').notNull(),
		startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
		endsAt: timestamp('ends_at', { withTimezone: true }).notNull(),
		allDay: boolean('all_day').notNull().default(false),
		location: text('location').notNull().default(''),
		notes: text('notes').notNull().default(''),
		/** Made in Botler, read from Google, or made by Botler for a bill or a payday. Text from Google is untrusted. */
		source: text('source', { enum: EVENT_SOURCES }).notNull().default('botler'),
		/** What a bill or payday event stands for, so it is kept in step with it ("bill:<id>:<due date>"). */
		refKey: text('ref_key'),
		googleEventId: text('google_event_id'),
		/** Google's version of the event as we last saw it, to tell our own writes from a change someone made. */
		googleEtag: text('google_etag'),
		googleUpdatedAt: timestamp('google_updated_at', { withTimezone: true }),
		/** The local version that Google has. A local version above this means there is something to send. */
		syncedVersion: integer('synced_version').notNull().default(0),
		/** A repeat instance carries the id of the series it belongs to. */
		recurringEventId: text('recurring_event_id'),
		/** Removed locally or in Google; kept until the removal has reached the other side. */
		deletedAt: timestamp('deleted_at', { withTimezone: true }),
		version: version(),
		...stamps()
	},
	(t) => [
		index('calendar_event_user_time_idx').on(t.userId, t.startsAt),
		unique('calendar_event_google_uq').on(t.userId, t.googleEventId),
		unique('calendar_event_ref_uq').on(t.userId, t.refKey),
		oneOf('calendar_event_source_chk', t.source, EVENT_SOURCES),
		check('calendar_event_time_chk', sql`${t.endsAt} >= ${t.startsAt}`),
		check(
			'calendar_event_text_chk',
			sql`length(${t.title}) between 1 and 300 and length(${t.notes}) <= 4000 and length(${t.location}) <= 300`
		)
	]
);

// -- ROUTINES -- //

export const routine = userTable(
	'routine',
	() => user.id,
	{
		id: id(),
		title: text('title').notNull(),
		/** A Recurrence (see src/lib/schedule/recurrence.ts), checked by Zod. */
		recurrence: jsonb('recurrence').notNull(),
		/** Remind this long before the time. */
		leadMinutes: integer('lead_minutes').notNull().default(0),
		active: boolean('active').notNull().default(true),
		version: version(),
		...stamps()
	},
	(t) => [
		check('routine_title_chk', sql`length(${t.title}) between 1 and 200`),
		check('routine_lead_chk', sql`${t.leadMinutes} between 0 and 1440`)
	]
);

// -- REMINDERS -- //

export const reminder = userTable(
	'reminder',
	() => user.id,
	{
		id: id(),
		kind: text('kind', { enum: REMINDER_KINDS }).notNull(),
		/** What it is for, stable across recomputing ("bill:<id>:2026-11-01"). One reminder per key. */
		refKey: text('ref_key').notNull(),
		title: text('title').notNull(),
		remindAt: timestamp('remind_at', { withTimezone: true }).notNull(),
		status: text('status', { enum: REMINDER_STATUSES }).notNull().default('scheduled'),
		origin: text('origin', { enum: REMINDER_ORIGINS }).notNull().default('system'),
		/** Bumped on every change the phone should hear about. */
		version: version(),
		...stamps()
	},
	(t) => [
		unique('reminder_user_ref_uq').on(t.userId, t.refKey),
		index('reminder_user_status_time_idx').on(t.userId, t.status, t.remindAt),
		oneOf('reminder_kind_chk', t.kind, REMINDER_KINDS),
		oneOf('reminder_status_chk', t.status, REMINDER_STATUSES),
		oneOf('reminder_origin_chk', t.origin, REMINDER_ORIGINS),
		check('reminder_title_chk', sql`length(${t.title}) between 1 and 200`)
	]
);

// -- CALENDAR SYNC STATE -- //

export const calendarSync = userTable(
	'calendar_sync',
	() => user.id,
	{
		id: id(),
		status: text('status', { enum: CALENDAR_STATUSES }).notNull().default('off'),
		calendarId: text('calendar_id').notNull().default('primary'),
		/** Google's cursor for "what changed since". Never shown. */
		syncToken: text('sync_token'),
		/** Why it stopped, when it did: invalid_grant means Google no longer lets us in and the person must reconnect. */
		errorCode: text('error_code'),
		lastSyncAt: timestamp('last_sync_at', { withTimezone: true }),
		lastFullSyncAt: timestamp('last_full_sync_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [
		unique('calendar_sync_user_uq').on(t.userId),
		oneOf('calendar_sync_status_chk', t.status, CALENDAR_STATUSES)
	]
);

// -- PUSH TOKEN OWNERSHIP -- //

/**
 * Who holds each push token right now. A phone shared by two people registers the same token under both, and a notification for the
 * first must never reach the second. This table is plain (not per person) so the check can see across people, and it holds only a hash of
 * the token. The person who registered last, by last_seen_at, is the only one a push goes to.
 */
export const pushTokenOwner = plainTable(
	'push_token_owner',
	{
		tokenHash: text('token_hash').primaryKey(),
		userId: text('user_id')
			.notNull()
			.references(() => user.id, { onDelete: 'cascade' }),
		lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow()
	},
	(t) => [index('push_token_owner_user_idx').on(t.userId)]
);
