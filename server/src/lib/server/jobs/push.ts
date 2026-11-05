// THE PUSH JOBS. push.sync: tell the phone to look at the server again (silent). push.nudge: a visible notice for a reminder the assistant made.
// A missing push setup is not an error for push.sync (the phone also syncs when opened and on a timer). For push.nudge it fails loudly, so a
// reminder that was meant to reach the person never silently does not.
// Both are NO_TX jobs: no transaction, connection or person lock is held while Firebase answers, and a call that never answers is cut off.

// -- TYPES -- //
import type { Push, Pusher } from '../push/fcm';
import type { JobHandler } from './queue';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { reminder } from '../db/schema';
import { run } from '../ops/context';
import { createMasker } from '../proxy/mask';
import { pushToUser } from '../push/send';
import { noTx } from './queue';

// -- CONSTANTS -- //

/** One Firebase call may take this long; after it the job fails and is retried later. */
export const PUSH_TIMEOUT_MS = 15_000;

// -- FUNCTIONS -- //

/** The pusher with a time limit on each send. fcm.ts takes no abort signal, so a send that hangs is abandoned (its result is ignored). */
export function withTimeout(pusher: Pusher, ms: number = PUSH_TIMEOUT_MS): Pusher {
	return {
		send: (p: Push) => {
			let timer: ReturnType<typeof setTimeout> | undefined;
			const limit = new Promise<never>((_, reject) => {
				timer = setTimeout(() => {
					const e = new Error('Push timed out');
					e.name = 'PushTimeout';
					reject(e);
				}, ms);
			});
			return Promise.race([pusher.send(p), limit]).finally(() => clearTimeout(timer));
		}
	};
}

export function createPushHandlers(deps: {
	pusher: () => Pusher | null;
	/** Test hook: the time limit of one send. */
	timeoutMs?: number;
}): Record<string, JobHandler> {
	const limited = (): Pusher | null => {
		const p = deps.pusher();
		return p ? withTimeout(p, deps.timeoutMs) : null;
	};
	const sync: JobHandler = noTx(async (_job, ctx) => {
		const pusher = limited();
		if (!pusher) return;
		await pushToUser(ctx, pusher, { kind: 'sync' });
	});
	const nudge: JobHandler = noTx(async (job, ctx) => {
		const pusher = limited();
		if (!pusher) throw new Error('PushNotConfigured');
		const id = typeof job.payload.reminderId === 'string' ? job.payload.reminderId : '';
		// Checked again in a short transaction right before sending: closed, cancelled, moved on or not yet due since it was queued, so nothing to say
		const [r] = await run(ctx, (tx) =>
			tx
				.select()
				.from(reminder)
				.where(and(eq(reminder.userId, job.userId), eq(reminder.id, id)))
		);
		if (!r || r.status !== 'scheduled' || r.remindAt.getTime() > Date.now() + 60_000) return;
		// The title leaves for Firebase, so numbers that look like accounts, phones and emails are masked first
		await pushToUser(ctx, pusher, {
			kind: 'notice',
			title: createMasker().mask(r.title),
			key: r.refKey
		});
	});
	// The weekly check-in. No numbers in it: a lock screen is not the place for a weight or a calorie target. No push set up means the Health screen still shows it
	const health: JobHandler = noTx(async (_job, ctx) => {
		const pusher = limited();
		if (!pusher) return;
		await pushToUser(ctx, pusher, {
			kind: 'notice',
			title: 'Your weekly Health check-in is ready',
			key: 'health-weekly'
		});
	});
	return { 'push.sync': sync, 'push.nudge': nudge, 'push.health': health };
}
