// THE JOB QUEUE: BACKGROUND WORK (MEMORY EXTRACTION, SUMMARIES, THE NIGHT JOB, REMINDER PUSHES) AS ROWS.
// The table is plain, not user scoped, because the worker claims jobs of every person. It therefore holds only ids, kinds and
// schedules, never personal text. A handler always runs inside withUser(job.userId), so it can only touch that person's rows.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { check, index, integer, jsonb, text, timestamp, unique } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, plainTable, stamps } from './helpers';

// -- CONSTANTS -- //

export const JOB_STATUSES = ['queued', 'running', 'done', 'failed'] as const;

// -- TABLES -- //

export const job = plainTable(
	'job',
	{
		id: id(),
		userId: text('user_id')
			.notNull()
			.references(() => user.id, { onDelete: 'cascade' }),
		/** What to do, for example memory.extract or memory.night. */
		kind: text('kind').notNull(),
		/** Makes the job unique per person and kind, for example the day it is for. Enqueueing the same key twice adds nothing. */
		key: text('key').notNull(),
		/** Ids only. Never message text, names or amounts. */
		payload: jsonb('payload').notNull().default({}),
		status: text('status', { enum: JOB_STATUSES }).notNull().default('queued'),
		runAfter: timestamp('run_after', { withTimezone: true }).notNull().defaultNow(),
		attempts: integer('attempts').notNull().default(0),
		maxAttempts: integer('max_attempts').notNull().default(5),
		/** While running: until when the claim holds. A crashed worker's job is picked up again after this. */
		lockedUntil: timestamp('locked_until', { withTimezone: true }),
		/** The error class of the last failure, never its message. */
		lastError: text('last_error'),
		...stamps()
	},
	(t) => [
		unique('job_user_kind_key_uq').on(t.userId, t.kind, t.key),
		index('job_runnable_idx').on(t.status, t.runAfter),
		// The claim query asks, for each person, whether another job of theirs is running
		index('job_user_status_idx').on(t.userId, t.status),
		oneOf('job_status_chk', t.status, JOB_STATUSES),
		// The table is readable across people, so a payload is ids only: the database refuses a big one
		check('job_payload_size_chk', sql`pg_column_size(${t.payload}) <= 2048`)
	]
);
