// PICTURES THAT MARK ACCOUNTS AND BILLS (BTL-20261031-0917): STORING, REPLACING AND DROPPING THE PICTURE A ROW OWNS, AND THE READ VERB THE APP FETCHES IT WITH
// A picture is owned by exactly one account or bill (image_id is unique), so there is no upload verb on its own and nothing is left behind:
// it is made from imageData in the same request that sets it, and dropped in the same transaction when it is replaced, cleared or its row goes.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { IconKey } from '../../finance/visual';
// -- DEP-MODULES -- //
import { and, eq, or, isNotNull } from 'drizzle-orm';
// -- MODULES -- //
import { checkPicture } from '../../finance/visual';
import { account, bill, picture } from '../db/schema';
import { pictureGetInput } from '../db/zod';
import { OpsError, run } from './context';
import { mapped, parse } from './shared';

// -- TYPES -- //

/** The mark fields an account or bill verb takes. */
export type MarkInput = { icon?: IconKey | null; imageData?: string; clearImage?: boolean };

/** The mark of an account or a bill as a view carries it: an icon key or a picture id, never the bytes. */
export type Mark = { icon: string | null; imageId: string | null };

/** What to write on the row, and the picture that stops being used once the row is written. */
export type MarkPlan = {
	set: { icon?: string | null; imageId?: string | null };
	dropId: string | null;
};

// -- FUNCTIONS -- //

/** Takes the mark fields out of an input, so the rest can be written to the row as it is. */
export function splitMark<T extends MarkInput>(
	input: T
): { rest: Omit<T, keyof MarkInput>; mark: MarkInput } {
	const { icon, imageData, clearImage, ...rest } = input;
	return { rest, mark: { icon, imageData, clearImage } };
}

/**
 * Works out how a row's mark changes. A new picture is stored here (it must exist before the row points at it); the old one is returned
 * to be dropped after the row is written. An icon and a picture never sit on one row: setting one clears the other. The assistant can
 * set an icon and clear a picture, never send one.
 */
export async function planMark(
	ctx: Ctx,
	tx: Tx,
	userId: string,
	currentImageId: string | null,
	mark: MarkInput
): Promise<MarkPlan> {
	const { icon, imageData, clearImage } = mark;
	if (imageData !== undefined && ctx.actor.kind !== 'person')
		throw new OpsError('FORBIDDEN', 'Only you can add a picture, not the assistant.');
	if (imageData !== undefined && clearImage)
		throw new OpsError('INVALID', 'Send a picture or clear it, not both.');
	if (imageData !== undefined && typeof icon === 'string')
		throw new OpsError('INVALID', 'A mark is an icon or a picture, not both.');
	if (imageData !== undefined) {
		const checked = checkPicture(imageData);
		if (!checked.ok) throw new OpsError('INVALID', checked.reason);
		const [row] = await tx
			.insert(picture)
			.values({ userId, mime: checked.mime, data: checked.data, bytes: checked.bytes })
			.returning({ id: picture.id });
		if (!row) throw new OpsError('CONFLICT', 'The picture could not be saved.');
		return { set: { imageId: row.id, icon: null }, dropId: currentImageId };
	}
	if (typeof icon === 'string') return { set: { icon, imageId: null }, dropId: currentImageId };
	if (clearImage)
		return {
			set: { imageId: null, ...(icon === null ? { icon: null } : {}) },
			dropId: currentImageId
		};
	if (icon === null) return { set: { icon: null }, dropId: null };
	return { set: {}, dropId: null };
}

/** The marks of every account and bill that has one, by id. A view that lists items by account or bill id joins them from here. */
export async function marksOf(
	tx: Tx,
	userId: string
): Promise<{ accounts: Map<string, Mark>; bills: Map<string, Mark> }> {
	const has = (t: typeof account | typeof bill) => or(isNotNull(t.icon), isNotNull(t.imageId));
	const accounts = await tx
		.select({ id: account.id, icon: account.icon, imageId: account.imageId })
		.from(account)
		.where(and(eq(account.userId, userId), has(account)));
	const bills = await tx
		.select({ id: bill.id, icon: bill.icon, imageId: bill.imageId })
		.from(bill)
		.where(and(eq(bill.userId, userId), has(bill)));
	const toMap = (rows: { id: string; icon: string | null; imageId: string | null }[]) =>
		new Map(rows.map((r) => [r.id, { icon: r.icon, imageId: r.imageId }] as const));
	return { accounts: toMap(accounts), bills: toMap(bills) };
}

/** Drops a picture no row points at any more. Call it after the row is written. */
export async function dropPicture(tx: Tx, userId: string, imageId: string | null): Promise<void> {
	if (!imageId) return;
	await tx.delete(picture).where(and(eq(picture.userId, userId), eq(picture.id, imageId)));
}

/**
 * One picture, by id: its kind and the image as base64 text. A read verb for the app only (it is not offered to the assistant, so the
 * bytes never reach the model). Pictures never change under an id, so the app keeps what it fetched.
 */
export async function getPicture(ctx: Ctx, raw: unknown) {
	const { imageId } = parse(pictureGetInput, raw);
	return mapped(() =>
		run(ctx, async (tx, userId) => {
			const [row] = await tx
				.select({ id: picture.id, mime: picture.mime, data: picture.data })
				.from(picture)
				.where(and(eq(picture.userId, userId), eq(picture.id, imageId)));
			if (!row) throw new OpsError('NOT_FOUND', 'That picture does not exist.');
			return row;
		})
	);
}
