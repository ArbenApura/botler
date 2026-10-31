// PUSHING TO A PERSON'S PHONES, AND THE RULE THAT A PUSH NEVER GOES TO A PHONE THAT NOW BELONGS TO SOMEONE ELSE.
// One phone can be registered under two people (they share it, or the first never signed out). The newest registration owns the token.
// Before every send the owner is checked: if it is another person, this person's row is a stale leftover and is deleted, not sent to.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Push, Pusher } from './fcm';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { device, pushTokenOwner } from '../db/schema';
import { run } from '../ops/context';

// -- TYPES -- //

export type PushSummary = { sent: number; removed: number; failed: number };

// -- FUNCTIONS -- //

export const hashToken = (token: string): string =>
	createHash('sha256').update(token).digest('hex');

/** Sends to every phone the caller owns the token of. Dead and stale tokens are forgotten. */
export async function pushToUser(
	ctx: Ctx,
	pusher: Pusher,
	message: { kind: 'sync' } | { kind: 'notice'; title: string; body?: string; key?: string }
): Promise<PushSummary> {
	const summary: PushSummary = { sent: 0, removed: 0, failed: 0 };
	const devices = await run(ctx, (tx, userId) =>
		tx
			.select({ id: device.id, pushToken: device.pushToken })
			.from(device)
			.where(eq(device.userId, userId))
	);
	for (const d of devices) {
		// A phone that has not given a push token yet cannot be pushed to
		if (!d.pushToken) continue;
		const hash = hashToken(d.pushToken);
		const owner = await run(
			ctx,
			async (tx) =>
				(await tx.select().from(pushTokenOwner).where(eq(pushTokenOwner.tokenHash, hash)))[0]
		);
		if (owner && owner.userId !== ctx.actor.userId) {
			// The phone was registered by someone else after this person did. This row is stale: drop it, send nothing
			await run(ctx, (tx, userId) =>
				tx.delete(device).where(and(eq(device.userId, userId), eq(device.id, d.id)))
			);
			summary.removed++;
			continue;
		}
		const result = await pusher.send({ ...message, token: d.pushToken } as Push);
		if (result === 'sent') summary.sent++;
		else if (result !== 'unregistered') summary.failed++;
		// Only a token Firebase called dead (UNREGISTERED or NOT_FOUND) is deleted; any other answer keeps the phone
		else {
			await run(ctx, async (tx, userId) => {
				await tx.delete(device).where(and(eq(device.userId, userId), eq(device.id, d.id)));
				await tx
					.delete(pushTokenOwner)
					.where(and(eq(pushTokenOwner.tokenHash, hash), eq(pushTokenOwner.userId, userId)));
			});
			summary.removed++;
		}
	}
	return summary;
}
