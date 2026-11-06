// DEVICE VERBS: A PHONE REGISTERS ITS PUSH TOKEN WHEN IT SIGNS IN, ROTATES IT WHEN FCM CHANGES IT, AND REMOVES IT ON SIGN OUT

// -- TYPES -- //
import type { Ctx } from './context';
import type { DeviceRegisterInput, DeviceUnregisterInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { device, pushTokenOwner } from '../db/schema';
import { deviceRegisterInput, deviceUnregisterInput } from '../db/zod';
import { hashToken } from '../push/send';
import { reconcileReminders } from '../schedule/reminders';
import { OpsError, run, runWrite } from './context';
import { inPersonZone, reportedClock } from './zone';

// -- TYPES -- //

/** A phone as the app sees it: never the push token. Dates are ISO strings so a replayed answer equals the first one. */
export type DeviceRow = {
	id: string;
	platform: string;
	label: string;
	lastSeenAt: string;
};

// -- FUNCTIONS -- //

const toRow = (r: {
	id: string;
	platform: string;
	label: string;
	lastSeenAt: Date;
}): DeviceRow => ({ ...r, lastSeenAt: r.lastSeenAt.toISOString() });

/** Registers a phone, or refreshes it when the same push token is already known for this person. Never returns the token. */
export async function registerDevice(ctx: Ctx, input: DeviceRegisterInput): Promise<DeviceRow> {
	const parsed = deviceRegisterInput.safeParse(input);
	if (!parsed.success)
		throw new OpsError('INVALID', parsed.error.issues[0]?.message ?? 'Invalid device');
	const { platform, pushToken, label, clock } = parsed.data;
	return runWrite(ctx, 'device.register', parsed.data, async (tx, userId) => {
		// The clock the phones reported until now, to tell below whether this registration changes it
		const clockBefore = clock ? await reportedClock(tx, userId) : null;
		const [row] = await tx
			.insert(device)
			.values({ userId, platform, pushToken, label, clock })
			.onConflictDoUpdate({
				target: [device.userId, device.pushToken],
				// A registration with no clock (an older app) keeps the clock this phone reported before
				set: {
					label,
					platform,
					...(clock ? { clock } : {}),
					lastSeenAt: sql`now()`,
					updatedAt: sql`now()`
				}
			})
			.returning({
				id: device.id,
				platform: device.platform,
				label: device.label,
				lastSeenAt: device.lastSeenAt
			});
		if (!row) throw new OpsError('CONFLICT', 'The device could not be saved');
		// A new clock moves how the reminders already planned read ("at 3:30 PM" or "at 15:30"): rebuilt now, not at some later rebuild
		if (clock && clock !== clockBefore)
			await inPersonZone(tx, userId, () => reconcileReminders(tx, userId));
		// The newest registration owns the token. A phone shared with someone who registered it earlier now belongs to this
		// person, and a push for the earlier one is dropped (see push/send.ts)
		await tx
			.insert(pushTokenOwner)
			.values({ tokenHash: hashToken(pushToken), userId, lastSeenAt: new Date() })
			.onConflictDoUpdate({
				target: pushTokenOwner.tokenHash,
				set: { userId, lastSeenAt: sql`now()` }
			});
		return toRow(row);
	});
}

/** Removes a phone of the caller: on sign out, or when push answers that the token is no longer registered. */
export async function unregisterDevice(ctx: Ctx, input: DeviceUnregisterInput): Promise<void> {
	const parsed = deviceUnregisterInput.safeParse(input);
	if (!parsed.success) throw new OpsError('INVALID', 'deviceId must be an id');
	await runWrite(ctx, 'device.unregister', parsed.data, async (tx, userId) => {
		// The user filter is a second wall behind row level security, so the intent reads clearly
		const gone = await tx
			.delete(device)
			.where(and(eq(device.id, parsed.data.deviceId), eq(device.userId, userId)))
			.returning({ id: device.id, pushToken: device.pushToken });
		const removed = gone[0];
		if (!removed) throw new OpsError('NOT_FOUND', 'That device is not registered');
		// Signing out gives the token up, but only if it is still this person's
		if (removed.pushToken)
			await tx
				.delete(pushTokenOwner)
				.where(
					and(
						eq(pushTokenOwner.tokenHash, hashToken(removed.pushToken)),
						eq(pushTokenOwner.userId, userId)
					)
				);
		return null;
	});
}

/**
 * Removes the person's phone that holds this push token. Used when the push service answers Unregistered or NotRegistered:
 * a dead token is dropped at once so nothing is sent to it again. Quietly does nothing when the token is already gone.
 */
export async function unregisterDeviceByToken(ctx: Ctx, pushToken: string): Promise<void> {
	if (!pushToken || pushToken.length > 4096)
		throw new OpsError('INVALID', 'pushToken is not valid');
	// Deleting is naturally repeatable, and the push sender that calls this has no client request id, so it is not a runWrite
	await run(ctx, async (tx, userId) => {
		await tx.delete(device).where(and(eq(device.userId, userId), eq(device.pushToken, pushToken)));
	});
}

/** The caller's phones, without push tokens. */
export async function listDevices(ctx: Ctx): Promise<DeviceRow[]> {
	const rows = await run(ctx, (tx) =>
		tx
			.select({
				id: device.id,
				platform: device.platform,
				label: device.label,
				lastSeenAt: device.lastSeenAt
			})
			.from(device)
			.orderBy(device.lastSeenAt)
	);
	return rows.map(toRow);
}
