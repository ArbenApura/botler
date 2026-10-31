// THE NIGHTLY RATE REFRESH JOB: ONE PER PERSON PER DAY, BUT ONLY THE FIRST ONE THAT RUNS REALLY FETCHES (THE REFRESH CLAIM IS GLOBAL)
// It makes no call to the model, so the monthly model cap does not count it. It is a NO_TX job: no transaction, connection or person lock is
// held while it waits on the feed, so a slow feed never stops the person from writing; the stored rates are written in one short transaction.

// -- TYPES -- //
import type { JobHandler } from './queue';
// -- MODULES -- //
import { refreshRates } from '../fx/store';
import { noTx } from './queue';

// -- FUNCTIONS -- //

export const fxRefreshJob: JobHandler = noTx(async (_job, ctx) => {
	const outcome = await refreshRates(ctx.handle);
	// A failed refresh is recorded in the rates table and shown as "rates as of"; it is not a failed job to be retried every minute
	if (outcome.status === 'failed')
		console.warn(JSON.stringify({ event: 'fx_job_failed', reason: outcome.reason }));
});

export const fxHandlers: Record<string, JobHandler> = { 'fx.refresh': fxRefreshJob };
