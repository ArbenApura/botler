// THE MARKS OF ACCOUNTS AND BILLS: THE BUILT-IN ICON KEYS AND THE CHECK OF A PICTURE (BTL-20261031-0917). PURE: NO DATABASE, NO CLOCK.
// The app mirrors the keys in app/lib/core/marks.dart; a test on each side pins the list, so a key is never added on one side only.

// -- CONSTANTS -- //

/** The built-in icons, by key. A key is lowercase letters, digits and underscores, at most 24 characters. */
export const ICON_KEYS = [
	'bank',
	'wallet',
	'cash',
	'card',
	'piggy',
	'savings',
	'home',
	'rent',
	'bolt',
	'water',
	'wifi',
	'phone',
	'cart',
	'food',
	'fuel',
	'car',
	'bus',
	'health',
	'school',
	'family',
	'gift',
	'travel',
	'shopping',
	'subscription',
	'tv',
	'game',
	'insurance',
	'tax',
	'loan',
	'invest',
	'crypto',
	'work',
	'pet',
	'baby',
	'tools',
	'gym',
	'coffee',
	'heart',
	'star',
	'flag'
] as const;

export type IconKey = (typeof ICON_KEYS)[number];

/** The most a picture may weigh once decoded, bytes. The phone shrinks it to about 192 px first, so this is generous. */
export const PICTURE_MAX_BYTES = 24 * 1024;

/** The most base64 text that fits that many bytes. */
export const PICTURE_MAX_BASE64 = Math.ceil(PICTURE_MAX_BYTES / 3) * 4;

export const PICTURE_MIMES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export type PictureMime = (typeof PICTURE_MIMES)[number];

export type PictureCheck =
	{ ok: true; mime: PictureMime; bytes: number; data: string } | { ok: false; reason: string };

// -- FUNCTIONS -- //

export const isIconKey = (value: string): value is IconKey =>
	(ICON_KEYS as readonly string[]).includes(value);

/** The kind of picture the first bytes say it is, or null. The phone's claim is never trusted. */
function sniff(bytes: Uint8Array): PictureMime | null {
	const at = (i: number) => bytes[i] ?? -1;
	if (at(0) === 0xff && at(1) === 0xd8 && at(2) === 0xff) return 'image/jpeg';
	if (
		at(0) === 0x89 &&
		at(1) === 0x50 &&
		at(2) === 0x4e &&
		at(3) === 0x47 &&
		at(4) === 0x0d &&
		at(5) === 0x0a &&
		at(6) === 0x1a &&
		at(7) === 0x0a
	)
		return 'image/png';
	// RIFF....WEBP
	if (
		at(0) === 0x52 &&
		at(1) === 0x49 &&
		at(2) === 0x46 &&
		at(3) === 0x46 &&
		at(8) === 0x57 &&
		at(9) === 0x45 &&
		at(10) === 0x42 &&
		at(11) === 0x50
	)
		return 'image/webp';
	return null;
}

/**
 * Checks a picture sent as base64 text: well-formed base64 (no data URL prefix), a size that fits, and a JPEG, PNG or WebP by its first
 * bytes. Returns the kind and the cleaned text, or the reason in plain words.
 */
export function checkPicture(base64: string): PictureCheck {
	const data = base64.trim();
	if (data.length === 0) return { ok: false, reason: 'The picture is empty.' };
	if (data.length > PICTURE_MAX_BASE64)
		return {
			ok: false,
			reason: `The picture is larger than ${PICTURE_MAX_BYTES / 1024} KB. Pick a smaller one.`
		};
	if (!/^[A-Za-z0-9+/]+={0,2}$/.test(data) || data.length % 4 !== 0)
		return { ok: false, reason: 'The picture is not valid base64 text.' };
	const bytes = Uint8Array.from(Buffer.from(data, 'base64'));
	if (bytes.length === 0 || bytes.length > PICTURE_MAX_BYTES)
		return {
			ok: false,
			reason: `The picture is larger than ${PICTURE_MAX_BYTES / 1024} KB. Pick a smaller one.`
		};
	const mime = sniff(bytes);
	if (!mime) return { ok: false, reason: 'The picture must be a JPEG, PNG or WebP image.' };
	return { ok: true, mime, bytes: bytes.length, data };
}
