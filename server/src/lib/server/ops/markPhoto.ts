// MARK FROM A CHAT PHOTO (BTL-20261031-1011): THE ASSISTANT PROPOSES A CROP OF A PHOTO AS THE PICTURE OF AN ACCOUNT OR A BILL; THE PHONE CUTS IT AND THE PERSON APPROVES
// The server never has the chat photo. The assistant only names the item and the part of the photo to keep (fractions); the card carries that
// plan, the phone cuts the photo it still holds and sends the small result with the approval, and the verb below stores it as the person.

// -- TYPES -- //
import type { Ctx } from './context';
import type { MarkFromPhotoInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { account, bill } from '../db/schema';
import { markFromPhotoInput } from '../db/zod';
import { OpsError, run } from './context';
import { updateAccount } from './accounts';
import { updateBill } from './bills';
import { mapped, parse } from './shared';

// -- FUNCTIONS -- //

/**
 * The account or bill the assistant means, by its name. A hidden account or a switched-off bill is passed over when a live one has the name
 * (and used only when nothing live has it); several live ones with one name make the assistant ask the person. The same lookup runs again when
 * the card is approved, so a name that no longer matches exactly one row fails the card instead of marking something else.
 */
export async function findTarget(
	ctx: Ctx,
	target: 'account' | 'bill',
	name: string
): Promise<{ id: string; label: string }> {
	const rows = await run(ctx, async (tx, userId) =>
		target === 'account'
			? tx
					.select({
						id: account.id,
						label: account.name,
						live: sql<boolean>`${account.archivedAt} is null`
					})
					.from(account)
					.where(and(eq(account.userId, userId), sql`lower(${account.name}) = lower(${name})`))
			: tx
					.select({ id: bill.id, label: bill.name, live: sql<boolean>`${bill.active}` })
					.from(bill)
					.where(and(eq(bill.userId, userId), sql`lower(${bill.name}) = lower(${name})`))
	);
	const live = rows.filter((r) => r.live);
	const pool = live.length > 0 ? live : rows;
	if (pool.length === 0)
		throw new OpsError(
			'NOT_FOUND',
			`There is no ${target} called "${name}". Read the list and use its exact name.`
		);
	const first = pool[0];
	if (pool.length > 1 || !first)
		throw new OpsError(
			'INVALID',
			`More than one ${target} is called "${name}". Ask the person which one they mean.`
		);
	return { id: first.id, label: first.label };
}

/** The box has to stay inside the photo. */
function checkBox(input: MarkFromPhotoInput): void {
	if (input.x + input.width > 1.001 || input.y + input.height > 1.001)
		throw new OpsError(
			'INVALID',
			'The box must stay inside the photo: x + width and y + height are at most 1.'
		);
}

/**
 * Checks a request before it becomes a card: the box is inside the photo, the photo number was really attached to this message and the
 * item exists. The assistant is told what to fix, so a bad request never reaches the person as a card.
 */
export async function checkMarkFromPhoto(
	ctx: Ctx,
	raw: unknown,
	photoCount: number
): Promise<void> {
	const input = parse(markFromPhotoInput, raw);
	checkBox(input);
	if (photoCount === 0)
		throw new OpsError(
			'INVALID',
			'There is no photo in this message, so there is nothing to make a picture from.'
		);
	if (input.photo > photoCount)
		throw new OpsError(
			'INVALID',
			`This message has ${photoCount} photo${photoCount === 1 ? '' : 's'}; photo ${input.photo} does not exist.`
		);
	await findTarget(ctx, input.target, input.name);
}

/**
 * Sets the picture of the named account or bill from the cut the phone made. Needs the picture itself (imageData), which only the person's
 * phone sends with the approval; without it nothing is written and the card can be approved again.
 */
export async function markFromPhoto(ctx: Ctx, raw: MarkFromPhotoInput) {
	const input = parse(markFromPhotoInput, raw);
	return mapped(async () => {
		checkBox(input);
		if (!input.imageData)
			throw new OpsError(
				'INVALID',
				'The picture is made on your phone. Approve this card in the Botler app to apply it.'
			);
		const found = await findTarget(ctx, input.target, input.name);
		return input.target === 'account'
			? updateAccount(ctx, { accountId: found.id, imageData: input.imageData })
			: updateBill(ctx, { billId: found.id, imageData: input.imageData });
	});
}
