// AMOUNT CONFIRMATION (P2.10): AN AMOUNT THE PERSON DID NOT TYPE, OR A BALANCE THAT JUMPS, IS SHOWN AS A CHIP AND SAVED ONLY AFTER A YES.
// - Read from a photo (ocr) or a screenshot: always confirmed.
// - A balance count that changes an account by more than the threshold: confirmed.
// - A balance count more than 10 times larger or smaller than the last one: needs a second, explicit yes (it is most often a typo or a misread).

// -- TYPES -- //

export type AmountSource = 'manual' | 'chat' | 'ocr' | 'screenshot';

export type BalanceCheck = 'ok' | 'confirm' | 'confirm_large';

// -- CONSTANTS -- //

/** A balance count that moves an account by more than this (₱2,000) is confirmed. */
export const BALANCE_CONFIRM_THRESHOLD = 200_000;

// -- FUNCTIONS -- //

/** An amount that came from a picture is never saved unconfirmed. */
export const needsAmountConfirmation = (source: AmountSource): boolean =>
	source === 'ocr' || source === 'screenshot';

/** How careful to be with a new balance count against the last known balance. */
export function checkBalanceChange(
	previous: number | null,
	next: number,
	threshold = BALANCE_CONFIRM_THRESHOLD
): BalanceCheck {
	if (previous === null) return 'ok';
	const before = Math.abs(previous);
	const after = Math.abs(next);
	const tenfold = before > 0 && (after > before * 10 || after * 10 < before);
	if (tenfold && Math.abs(next - previous) > threshold) return 'confirm_large';
	return Math.abs(next - previous) > threshold ? 'confirm' : 'ok';
}
