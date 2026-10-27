// THE JOB QUEUE: ENQUEUE ONCE PER KEY, CLAIM WITH SKIP LOCKED, ONE RUNNING JOB PER PERSON, RETRY WITH BACKOFF, RECLAIM A CRASHED WORKER'S JOB.
// Handlers run inside the owner's user context (withUser), so every query a job makes is bound to that person by row level security.

// -- TYPES -- //
import type { DbHandle, Tx } from '../db/client';
import type { Ctx } from '../ops/context';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
// -- MODULES -- //
import { job, user } from '../db/schema';
import { lockPerson, setAuditContext, withUser } from '../db/tenant';
import { auditOf } from '../ops/context';

// -- TYPES -- //

export type JobRow = {
	id: string;
	userId: string;
	kind: string;
	key: string;
	payload: Record<string, unknown>;
	attempts: number;
	maxAttempts: number;
};

export type JobHandler = (job: JobRow, tx: Tx, ctx: Ctx) => Promise<void>;

export type EnqueueInput = {
	userId: string;
	kind: string;
	/** Unique per person and kind: the same key twice enqueues once (use the day or the entity id). */
	key: string;
	/** Ids only. A payload with text or amounts does not belong here (the table refuses more than 2 KB). */
	payload?: Record<string, unknown>;
	runAfter?: Date;
	maxAttempts?: number;
};

// -- CONSTANTS -- //

const CLAIM_MS = 5 * 60_000;

/**
 * Jobs that wait on the model for a long time. Every other job holds the person's lock for its whole run, so their own writes line up
 * behind it; these would make the next chat message wait for a summary or a tidy. They read first without the lock, call the model, and take
 * the lock themselves just before they write, checking again that nothing changed.
 */
export const UNLOCKED_JOBS: ReadonlySet<string> = new Set(['chat.compact', 'notebook.seed']);
const BACKOFF_BASE_MS = 30_000;
const BACKOFF_MAX_MS = 60 * 60_000;
/** Finished jobs are kept a week, failed ones a month, then removed. */
const DONE_KEEP_MS = 7 * 24 * 3_600_000;
const FAILED_KEEP_MS = 30 * 24 * 3_600_000;

// -- FUNCTIONS -- //

/** The wait before the next try: 30 s, 60 s, 120 s ... up to an hour. */
export function backoffMs(attempts: number): number {
	return Math.min(BACKOFF_MAX_MS, BACKOFF_BASE_MS * 2 ** Math.max(0, attempts - 1));
}

/** Adds a job unless one with the same person, kind and key exists. Returns whether it was added. Call it inside a verb's transaction to enqueue atomically with the write. */
export async function enqueue(tx: Tx, input: EnqueueInput): Promise<boolean> {
	const rows = await tx
		.insert(job)
		.values({
			userId: input.userId,
			kind: input.kind,
			key: input.key,
			payload: input.payload ?? {},
			runAfter: input.runAfter ?? new Date(),
			maxAttempts: input.maxAttempts ?? 5
		})
		.onConflictDoNothing()
		.returning({ id: job.id });
	return rows.length > 0;
}

/**
 * Claims up to `limit` runnable jobs: queued and due, or running with an expired claim. At most one job per person is claimed,
 * and none for a person who already has a running job with a live claim, so one person's jobs never overlap.
 * Safe with several workers: a per-person advisory lock keeps two claimers from taking two jobs of one person, and the final
 * update repeats the runnable test, so a job another worker just took is never taken again.
 * A running job whose claim expired after its last allowed try is marked failed first: a job that crashes the process cannot loop.
 */
export async function claim(handle: DbHandle, now: Date, limit: number): Promise<JobRow[]> {
	await handle.db.execute(sql`
		update job set status = 'failed', locked_until = null, last_error = 'Abandoned', updated_at = now()
		where status = 'running' and locked_until < ${now} and attempts >= max_attempts`);
	const result = await handle.db.execute(sql`
		with candidates as (
			select distinct on (j.user_id) j.id
			from job j
			where ((j.status = 'queued' and j.run_after <= ${now}) or (j.status = 'running' and j.locked_until < ${now}))
			  and not exists (
				select 1 from job r
				where r.user_id = j.user_id and r.status = 'running' and r.locked_until >= ${now} and r.id <> j.id
			  )
			order by j.user_id, j.run_after, j.created_at
		), picked as (
			select j.id from job j
			where j.id in (select id from candidates) and pg_try_advisory_xact_lock(hashtext(j.user_id))
			for update of j skip locked limit ${limit}
		)
		update job set status = 'running', attempts = attempts + 1,
			locked_until = ${new Date(now.getTime() + CLAIM_MS)}, updated_at = now()
		where id in (select id from picked)
		  and ((status = 'queued' and run_after <= ${now}) or (status = 'running' and locked_until < ${now}))
		returning id, user_id as "userId", kind, key, payload, attempts, max_attempts as "maxAttempts"`);
	return (result as unknown as { rows: JobRow[] }).rows;
}

/** Marks a job done. */
export async function complete(handle: DbHandle, id: string): Promise<void> {
	await handle.db.execute(
		sql`update job set status = 'done', locked_until = null, last_error = null, updated_at = now() where id = ${id}`
	);
}

/** Queues the job again after a backoff, or marks it failed when it used all its tries. Stores the error class only. */
export async function fail(
	handle: DbHandle,
	row: JobRow,
	error: unknown,
	now: Date
): Promise<void> {
	const name = error instanceof Error ? error.name : 'Error';
	if (row.attempts >= row.maxAttempts) {
		await handle.db.execute(
			sql`update job set status = 'failed', locked_until = null, last_error = ${name}, updated_at = now() where id = ${row.id}`
		);
		return;
	}
	const next = new Date(now.getTime() + backoffMs(row.attempts));
	await handle.db.execute(
		sql`update job set status = 'queued', run_after = ${next}, locked_until = null, last_error = ${name}, updated_at = now() where id = ${row.id}`
	);
}

const logError = (event: string, e: unknown, extra: Record<string, string> = {}) =>
	console.error(JSON.stringify({ event, error: e instanceof Error ? e.name : 'Error', ...extra }));

/**
 * Claims and runs one batch. Returns how many jobs ran. A handler that throws is retried later. A failure while recording
 * the outcome is logged and leaves the job to be reclaimed after its claim expires; it never aborts the other jobs of the batch.
 */
export async function runBatch(
	handle: DbHandle,
	handlers: Record<string, JobHandler>,
	options: { now?: Date; limit?: number } = {}
): Promise<number> {
	const now = options.now ?? new Date();
	const rows = await claim(handle, now, options.limit ?? 5);
	await Promise.allSettled(
		rows.map(async (row) => {
			const handler = handlers[row.kind];
			let outcome: 'done' | { error: unknown };
			try {
				if (!handler) throw new Error('NoHandler');
				const ctx: Ctx = {
					handle,
					actor: { userId: row.userId, kind: 'agent', tool: `job:${row.kind}` },
					via: 'job',
					channel: 'job'
				};
				// The handler's transaction sets the owner's user id before its first query, then who is acting for the audit trail
				await withUser(handle, row.userId, async (tx) => {
					if (!UNLOCKED_JOBS.has(row.kind)) await lockPerson(tx, row.userId);
					await setAuditContext(tx, { ...auditOf(ctx) });
					return handler(row, tx, ctx);
				});
				outcome = 'done';
			} catch (e) {
				logError('job_failed', e, { kind: row.kind });
				outcome = { error: e };
			}
			try {
				if (outcome === 'done') await complete(handle, row.id);
				else await fail(handle, row, outcome.error, now);
			} catch (e) {
				logError('job_outcome_not_recorded', e, { kind: row.kind });
			}
		})
	);
	return rows.length;
}

/** Removes finished jobs after a week and failed ones after a month, so the table does not grow for ever. */
export async function purgeFinished(handle: DbHandle, now: Date = new Date()): Promise<void> {
	await handle.db.execute(sql`
		delete from job
		where (status = 'done' and updated_at < ${new Date(now.getTime() - DONE_KEEP_MS)})
		   or (status = 'failed' and updated_at < ${new Date(now.getTime() - FAILED_KEEP_MS)})`);
}

/** Queues the daily maintenance job (purge old request ids and undo entries) for every person, once per day. */
export async function scheduleMaintenance(handle: DbHandle, now: Date = new Date()): Promise<void> {
	const people = await handle.db.select({ id: user.id }).from(user);
	const day = now.toISOString().slice(0, 10);
	for (const p of people) {
		await handle.db
			.insert(job)
			.values({ userId: p.id, kind: 'maintenance.purge', key: day })
			.onConflictDoNothing();
		// The exchange rates are refreshed once a day (the first job to run fetches, the rest find them fresh)
		await handle.db
			.insert(job)
			.values({ userId: p.id, kind: 'fx.refresh', key: day })
			.onConflictDoNothing();
	}
}

/** Runs batches on a timer until stopped, and the housekeeping about once an hour. A failure is logged, never silent. */
export function startWorker(
	handle: DbHandle,
	handlers: Record<string, JobHandler>,
	intervalMs = 5000
): () => void {
	let busy = false;
	let ticks = 0;
	const timer = setInterval(() => {
		if (busy) return;
		busy = true;
		ticks += 1;
		// Hourly: purge old jobs and queue the daily work
		const hourly = ticks % Math.round(3_600_000 / intervalMs) === 1;
		const housekeeping = hourly
			? purgeFinished(handle).then(() => scheduleMaintenance(handle))
			: Promise.resolve();
		housekeeping
			.then(() => runBatch(handle, handlers))
			.catch((e: unknown) => logError('job_worker_error', e))
			.finally(() => {
				busy = false;
			});
	}, intervalMs);
	timer.unref?.();
	return () => clearInterval(timer);
}
