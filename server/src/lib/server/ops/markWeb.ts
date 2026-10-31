// MARK FROM THE WEB (BTL-20261031-1334): THE ASSISTANT NAMES AN ACCOUNT OR BILL AND WHERE ITS LOGO LIVES; THE PHONE FINDS, CUTS AND SHOWS THE CANDIDATES; THE PERSON APPROVES
// The server never fetches a picture. The card carries a domain (the bank's site) and up to four https picture addresses; the phone downloads
// them behind its own address guard, trims and fits them, and sends the one the person picked with the approval (imageData).

// -- TYPES -- //
import type { Ctx } from './context';
import type { MarkFromWebInput } from '../db/zod';
// -- DEP-MODULES -- //
import net from 'node:net';
// -- MODULES -- //
import { markFromWebInput } from '../db/zod';
import { checkPublicUrl, FetchRefused } from '../agent/fetchGuard';
import { OpsError } from './context';
import { updateAccount } from './accounts';
import { updateBill } from './bills';
import { findTarget } from './markPhoto';
import { mapped, parse } from './shared';

// -- CONSTANTS -- //

/** A plain host name with a dot: letters, digits and hyphens in labels, no port, no path, no login. */
const DOMAIN = /^(?=.{3,100}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/;

/** After untrusted text: a short domain, labels of at most 30 characters, no run of four digits, at most three hyphens. */
const PLAIN_DOMAIN = /^(?!.*\d{4})(?!(?:[^-]*-){4})(?=.{3,45}$)([a-z0-9][a-z0-9-]{0,29}\.)+[a-z]{2,24}$/;

// -- FUNCTIONS -- //

/**
 * Checks a request before it becomes a card. A picture address must be https, public, without a query string or fragment (an address is
 * the one place text from this chat could be carried out by the phone's own download), and short. The assistant is told what to fix, so a
 * bad request never reaches the person as a card.
 */
export async function checkMarkFromWeb(
	ctx: Ctx,
	raw: unknown,
	opts: { tainted?: boolean } = {}
): Promise<void> {
	const input = parse(markFromWebInput, raw);
	if (!input.domain && !(input.urls && input.urls.length > 0))
		throw new OpsError(
			'INVALID',
			'Give the domain of the organisation (for example rcbc.com) or at least one https picture address.'
		);
	if (opts.tainted) {
		// Untrusted text (a page, a photo, a calendar) was read in this message. The phone downloads whatever the card names before the person
		// approves anything, so an address must not be a way to carry text out: only a short plain domain is allowed, like a short plain search
		if (input.urls && input.urls.length > 0)
			throw new OpsError(
				'INVALID',
				'Untrusted text was already read in this message, so give only the domain of the organisation (such as rcbc.com), no picture addresses.'
			);
		if (input.domain && !PLAIN_DOMAIN.test(input.domain))
			throw new OpsError(
				'INVALID',
				'Untrusted text was already read in this message, so the domain must be a short plain host name with no long digit runs.'
			);
	}
	if (input.domain) {
		if (net.isIP(input.domain) || !DOMAIN.test(input.domain))
			throw new OpsError(
				'INVALID',
				'The domain must be a plain host name such as rcbc.com, without https://, a path or a port.'
			);
		try {
			checkPublicUrl(`https://${input.domain}/`);
		} catch (e) {
			if (e instanceof FetchRefused) throw new OpsError('INVALID', e.message);
			throw e;
		}
	}
	for (const u of input.urls ?? []) {
		let url: URL;
		try {
			url = new URL(checkPublicUrl(u));
		} catch (e) {
			if (e instanceof FetchRefused) throw new OpsError('INVALID', e.message);
			throw e;
		}
		if (url.protocol !== 'https:')
			throw new OpsError('INVALID', 'Picture addresses must start with https://.');
		if (url.search || url.hash)
			throw new OpsError(
				'INVALID',
				'A picture address must not have a query string (?...) or a fragment (#...). Use the plain address of the picture.'
			);
	}
	await findTarget(ctx, input.target, input.name);
}

/**
 * Sets the picture of the named account or bill from the picture the phone picked and cut. Needs the picture itself (imageData), which only
 * the person's phone sends with the approval; without it nothing is written and the card can be approved again.
 */
export async function markFromWeb(ctx: Ctx, raw: MarkFromWebInput) {
	const input = parse(markFromWebInput, raw);
	return mapped(async () => {
		if (!input.imageData)
			throw new OpsError(
				'INVALID',
				'The picture is chosen and cut on your phone. Approve this card in the Botler app to apply it.'
			);
		const found = await findTarget(ctx, input.target, input.name);
		return input.target === 'account'
			? updateAccount(ctx, { accountId: found.id, imageData: input.imageData })
			: updateBill(ctx, { billId: found.id, imageData: input.imageData });
	});
}
