// OPERATIONS BOOKKEEPING: THE REQUEST LOG (A WRITE WITH THE SAME ID IS ANSWERED, NOT APPLIED TWICE) AND THE UNDO JOURNAL

// -- DEP-MODULES -- //
import { index, jsonb, text, timestamp, unique } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, stamps, userTable } from './helpers';

// -- REQUEST LOG -- //

/**
 * One row per write that carried a client request id. The row is claimed in the same transaction as the write, so a write that
 * fails leaves no row and can be retried, and a replay of a finished write returns the stored result.
 */
export const requestLog = userTable(
	'request_log',
	() => user.id,
	{
		id: id(),
		requestId: text('request_id').notNull(),
		verb: text('verb').notNull(),
		/** A hash of the verb and its input. The same id with other input is refused, not answered with the first result. */
		fingerprint: text('fingerprint').notNull(),
		/** The JSON the verb returned, replayed as is. */
		result: jsonb('result'),
		createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow()
	},
	(t) => [
		unique('request_log_user_request_uq').on(t.userId, t.requestId),
		index('request_log_created_idx').on(t.createdAt)
	]
);

// -- UNDO JOURNAL -- //

/**
 * What a write changed, so it can be undone: the row before and after. The undo verbs that apply `before` back and mark the entry undone are written with the verbs of each feature (P2 onwards); only the journal and recordUndo exist so far.
 * Verbs that change data write an entry in their own transaction (see recordUndo).
 */
export const undoJournal = userTable(
	'undo_journal',
	() => user.id,
	{
		id: id(),
		verb: text('verb').notNull(),
		requestId: text('request_id'),
		/** The table the change was made in and the row id, as text. */
		entity: text('entity').notNull(),
		entityId: text('entity_id').notNull(),
		/** The row as it was (null for a create) and as it became (null for a delete). */
		before: jsonb('before'),
		after: jsonb('after'),
		undoneAt: timestamp('undone_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [index('undo_journal_user_created_idx').on(t.userId, t.createdAt)]
);
