// THE PICTURES A PERSON ATTACHES TO A CHAT MESSAGE: WHAT THE SERVER ACCEPTS, AND PROOF THAT EACH ONE IS REALLY A PICTURE.
// The phone sends JPEGs it made itself, but nothing here trusts that: the type is read from the bytes (never from what the client says), the
// base64 is checked, and the size in pixels is read from the header so a picture the host would refuse is turned away here, once, instead of
// failing the whole message at the host. Pictures are never stored, logged or put in an error: a refusal says nothing about the content.

// -- TYPES -- //
import type { ChatImage } from '../proxy/types';
// -- DEP-MODULES -- //
import { z } from 'zod';
// -- MODULES -- //
import { OpsError } from '../ops/context';

// -- CONSTANTS -- //

/** Pictures in one message, base64 characters of one and of all of them together, decoded bytes of one, and pixels on a side. */
export const MAX_IMAGES = 6;
export const MAX_IMAGE_CHARS = 1_700_000;
export const MAX_IMAGES_TOTAL_CHARS = 8_000_000;
export const MAX_IMAGE_BYTES = 2_000_000;
export const MAX_IMAGE_SIDE = 8000;

/** The shape of the field in the chat body. The type the client may name is ignored: it is read from the bytes. */
export const imagesInput = z
	.array(
		z.strictObject({
			data: z.string().min(16).max(MAX_IMAGE_CHARS),
			mediaType: z.string().max(40).optional()
		})
	)
	.max(MAX_IMAGES)
	.refine((l) => l.reduce((n, i) => n + i.data.length, 0) <= MAX_IMAGES_TOTAL_CHARS, {
		message: 'The pictures are too large together.'
	});

const REFUSED = 'One of the pictures could not be read.';

// -- FUNCTIONS -- //

/** True when the text is only base64 characters with at most two = at its end. A plain scan: no pattern that could backtrack on a long text. */
export function isBase64(text: string): boolean {
	const n = text.length;
	if (n === 0 || n % 4 === 1) return false;
	let end = n;
	while (end > 0 && text.charCodeAt(end - 1) === 61 && n - end < 2) end--;
	for (let i = 0; i < end; i++) {
		const c = text.charCodeAt(i);
		const ok =
			(c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 43 || c === 47;
		if (!ok) return false;
	}
	return true;
}

type Sniffed = { mediaType: ChatImage['mediaType']; width: number; height: number };

/** The JPEG start-of-frame marker holds the size; the markers before it are skipped by their lengths. */
function jpegSize(b: Buffer): { width: number; height: number } | null {
	let i = 2;
	while (i + 9 < b.length) {
		if (b[i] !== 0xff) return null;
		let marker = b[i + 1] ?? 0;
		// Fill bytes between segments
		while (marker === 0xff && i + 2 < b.length) {
			i++;
			marker = b[i + 1] ?? 0;
		}
		// Frame headers: SOF0 to SOF15 except the table markers C4, C8 and CC
		if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc)
			return { height: b.readUInt16BE(i + 5), width: b.readUInt16BE(i + 7) };
		// Markers with no length: restart, start and end of image, temporary
		if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
			i += 2;
			continue;
		}
		i += 2 + b.readUInt16BE(i + 2);
	}
	return null;
}

function pngSize(b: Buffer): { width: number; height: number } | null {
	return b.length >= 24 ? { width: b.readUInt32BE(16), height: b.readUInt32BE(20) } : null;
}

function webpSize(b: Buffer): { width: number; height: number } | null {
	if (b.length < 30) return null;
	const kind = b.toString('latin1', 12, 16);
	if (kind === 'VP8 ')
		return { width: b.readUInt16LE(26) & 0x3fff, height: b.readUInt16LE(28) & 0x3fff };
	if (kind === 'VP8L') {
		const bits = b.readUInt32LE(21);
		return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >>> 14) & 0x3fff) };
	}
	if (kind === 'VP8X') return { width: 1 + b.readUIntLE(24, 3), height: 1 + b.readUIntLE(27, 3) };
	return null;
}

/** What the bytes are, and their size in pixels. Null when they are not a JPEG, PNG or WebP with a readable header. */
export function sniffImage(bytes: Buffer): Sniffed | null {
	if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
		const size = jpegSize(bytes);
		return size ? { mediaType: 'image/jpeg', ...size } : null;
	}
	if (
		bytes.length > 8 &&
		bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
	) {
		const size = pngSize(bytes);
		return size ? { mediaType: 'image/png', ...size } : null;
	}
	if (
		bytes.length > 16 &&
		bytes.toString('latin1', 0, 4) === 'RIFF' &&
		bytes.toString('latin1', 8, 12) === 'WEBP'
	) {
		const size = webpSize(bytes);
		return size ? { mediaType: 'image/webp', ...size } : null;
	}
	return null;
}

/**
 * Checks every picture of a message and answers them with the type read from their own bytes. A picture that is not base64, is too large
 * in bytes or pixels, or is not a JPEG, PNG or WebP turns the whole message away, so the person can send it again without it.
 */
export function readImages(
	input: readonly { data: string; mediaType?: string | undefined }[] | undefined
): ChatImage[] {
	const out: ChatImage[] = [];
	for (const item of input ?? []) {
		if (!isBase64(item.data)) throw new OpsError('INVALID', REFUSED);
		const bytes = Buffer.from(item.data, 'base64');
		if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES)
			throw new OpsError('INVALID', REFUSED);
		let sniffed: Sniffed | null;
		try {
			sniffed = sniffImage(bytes);
		} catch {
			// A header cut short reads past its end
			sniffed = null;
		}
		if (
			!sniffed ||
			sniffed.width < 1 ||
			sniffed.height < 1 ||
			sniffed.width > MAX_IMAGE_SIDE ||
			sniffed.height > MAX_IMAGE_SIDE
		)
			throw new OpsError('INVALID', REFUSED);
		// Sent on as the decoder wrote it back, so odd padding or a missing one never reaches the host
		out.push({ mediaType: sniffed.mediaType, data: bytes.toString('base64') });
	}
	return out;
}
