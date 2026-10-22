// THE JOB HANDLERS BY KIND. LATER PHASES ADD THEIR OWN: memory.extract, memory.summary, memory.night (P4), reminder.push (P5).
// A handler runs inside the owner's user context and receives ids only; it loads what it needs through that context.

// -- TYPES -- //
import type { JobHandler } from './queue';
// -- DEP-MODULES -- //
import { lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { requestLog, undoJournal } from '../db/schema';

// -- CONSTANTS -- //

/** How long a request id is remembered for replays, and how long an undo entry is kept. */
const REQUEST_LOG_DAYS = 30;
const UNDO_DAYS = 90;

/** Removes the person's old request ids and old undo entries. Safe to run any time: row level security limits it to their own rows. */
export const purgeOld: JobHandler = async (_job, tx) => {
	await tx
		.delete(requestLog)
		.where(lt(requestLog.createdAt, sql`now() - ${REQUEST_LOG_DAYS} * interval '1 day'`));
	await tx
		.delete(undoJournal)
		.where(lt(undoJournal.createdAt, sql`now() - ${UNDO_DAYS} * interval '1 day'`));
};

export const jobHandlers: Record<string, JobHandler> = {
	'maintenance.purge': purgeOld
};
