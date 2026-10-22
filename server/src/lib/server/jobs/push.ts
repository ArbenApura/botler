// THE PUSH JOBS. push.sync: tell the phone to look at the server again (silent). push.nudge: a visible notice for a reminder the assistant made.
// A missing push setup is not an error for push.sync (the phone also syncs when opened and on a timer). For push.nudge it fails loudly, so a
// reminder that was meant to reach the person never silently does not.

// -- TYPES -- //
import type { Pusher } from '../push/fcm';
import type { JobHandler } from './queue';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { reminder } from '../db/schema';
import { pushToUser } from '../push/send';

// -- FUNCTIONS -- //

export function createPushHandlers(deps: {
	pusher: () => Pusher | null;
}): Record<string, JobHandler> {
	const sync: JobHandler = async (_job, _tx, ctx) => {
		const pusher = deps.pusher();
		if (!pusher) return;
		await pushToUser(ctx, pusher, { kind: 'sync' });
	};
	const nudge: JobHandler = async (job, tx, ctx) => {
		const pusher = deps.pusher();
		if (!pusher) throw new Error('PushNotConfigured');
		const id = typeof job.payload.reminderId === 'string' ? job.payload.reminderId : '';
		const [r] = await tx
			.select()
			.from(reminder)
			.where(and(eq(reminder.userId, job.userId), eq(reminder.id, id)));
		// Closed, cancelled or moved on since it was queued: nothing to say
		if (!r || r.status !== 'scheduled') return;
		await pushToUser(ctx, pusher, { kind: 'notice', title: r.title, key: r.refKey });
	};
	return { 'push.sync': sync, 'push.nudge': nudge };
}
