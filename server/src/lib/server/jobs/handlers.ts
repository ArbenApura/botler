// THE JOB HANDLERS BY KIND. LATER PHASES ADD THEIR OWN: memory.extract, memory.summary, memory.night (P4), reminder.push (P5).
// A handler runs inside the owner's user context and receives ids only; it loads what it needs through that context.

// -- TYPES -- //
import type { JobHandler } from './queue';
// -- DEP-MODULES -- //
import { lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { toManilaDate } from '../../finance/dates';
import { notebook, notebookPage, NOTEBOOK_TRASH_DAYS, requestLog, undoJournal } from '../db/schema';
import { runWeekly, runWeeklyReview } from '../ops/weight';
import { enqueue } from './queue';
import { advancePrograms } from '../ops/workouts';

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
	// A deleted page can be restored for a while; after that it goes, with its changes (they follow it by the composite key). A parent is
	// kept while any sub-page stays (a live one, or a hidden one that is not old enough yet), so a page never goes from under a live sub-page.
	await tx.delete(notebookPage).where(
		sql`${notebookPage.deletedAt} < now() - ${NOTEBOOK_TRASH_DAYS} * interval '1 day'
			and not exists (
				select 1 from notebook_page c
				where c.user_id = ${notebookPage.userId} and c.parent_page_id = ${notebookPage.id}
				  and (c.deleted_at is null or c.deleted_at >= now() - ${NOTEBOOK_TRASH_DAYS} * interval '1 day'))`
	);
	// A deleted notebook can be restored for a while; after that it goes, with its pages and changes (they follow it by the composite key)
	await tx
		.delete(notebook)
		.where(lt(notebook.deletedAt, sql`now() - ${NOTEBOOK_TRASH_DAYS} * interval '1 day'`));
};

/**
 * The jobs of the fact memory that the notebook replaced. Nothing schedules them any more; one that was queued before is closed here
 * without running, instead of failing as a job nobody can handle. The old facts and digests stay in the database, unused.
 */
const retired: JobHandler = async () => undefined;

export const RETIRED_JOB_KINDS = [
	'memory.embed',
	'memory.extract',
	'memory.digest',
	'memory.night'
];

export const jobHandlers: Record<string, JobHandler> = {
	'maintenance.purge': purgeOld,
	// The weekly Health sums make no model call, and only ever propose
	'health.weekly': async (job, tx) => {
		const today = toManilaDate(new Date());
		await advancePrograms(tx, job.userId, today);
		const target = await runWeekly(tx, job.userId, today);
		const review = await runWeeklyReview(tx, job.userId, today);
		if (target.proposed || review.proposed)
			await enqueue(tx, { userId: job.userId, kind: 'push.health', key: job.key });
	},
	...Object.fromEntries(RETIRED_JOB_KINDS.map((kind) => [kind, retired]))
};
