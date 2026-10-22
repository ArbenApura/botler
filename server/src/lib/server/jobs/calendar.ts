// THE CALENDAR JOB: ONE SYNC PASS FOR ONE PERSON (src/lib/server/calendar/sync.ts). IT RUNS EVERY TEN MINUTES FOR EVERYONE AND DOES NOTHING FOR
// A PERSON WHO HAS NOT TURNED CALENDAR SYNC ON. After a pass that changed something, the phone is asked to look again.

// -- TYPES -- //
import type { GoogleCalendarApi } from '../calendar/google';
import type { JobHandler } from './queue';
// -- MODULES -- //
import { syncCalendar } from '../calendar/sync';
import { enqueue } from './queue';

// -- FUNCTIONS -- //

export function createCalendarHandlers(deps: {
	api: (userId: string) => GoogleCalendarApi;
	now?: () => Date;
}): Record<string, JobHandler> {
	const sync: JobHandler = async (job, tx) => {
		const report = await syncCalendar(
			tx,
			job.userId,
			deps.api(job.userId),
			deps.now?.() ?? new Date()
		);
		if (report.pulled + report.pushed + report.deleted > 0)
			await enqueue(tx, {
				userId: job.userId,
				kind: 'push.sync',
				key: new Date().toISOString().slice(0, 16)
			});
	};
	return { 'calendar.sync': sync };
}
