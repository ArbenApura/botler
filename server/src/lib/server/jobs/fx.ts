// THE NIGHTLY RATE REFRESH JOB: ONE PER PERSON PER DAY, BUT ONLY THE FIRST ONE THAT RUNS REALLY FETCHES (THE REFRESH CLAIM IS GLOBAL)
// It makes no call to the model, so the monthly model cap does not count it. It runs inside the person's job transaction like every job,
// so the first fetch holds that one person's turn for up to the request time limit; the others find the rates fresh and return at once.

// -- TYPES -- //
import type { JobHandler } from './queue';
// -- MODULES -- //
import { refreshRates } from '../fx/store';

// -- FUNCTIONS -- //

export const fxRefreshJob: JobHandler = async (_job, _tx, ctx) => {
	const outcome = await refreshRates(ctx.handle);
	// A failed refresh is recorded in the rates table and shown as "rates as of"; it is not a failed job to be retried every minute
	if (outcome.status === 'failed')
		console.warn(JSON.stringify({ event: 'fx_job_failed', reason: outcome.reason }));
};

export const fxHandlers: Record<string, JobHandler> = { 'fx.refresh': fxRefreshJob };
