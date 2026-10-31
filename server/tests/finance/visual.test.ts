// MARKS (BTL-20261031-0917): THE ICON KEYS AND THE CHECK OF A PICTURE

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	checkPicture,
	ICON_KEYS,
	isIconKey,
	PICTURE_MAX_BYTES
} from '../../src/lib/finance/visual';

// -- CONSTANTS -- //

const b64 = (bytes: number[]) => Buffer.from(bytes).toString('base64');
const JPEG = b64([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const PNG = b64([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2]);
const WEBP = b64([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 1]);

// -- TESTS -- //

describe('the icon keys', () => {
	it('are unique lowercase keys that fit the database check', () => {
		expect(new Set(ICON_KEYS).size).toBe(ICON_KEYS.length);
		for (const key of ICON_KEYS) expect(key).toMatch(/^[a-z0-9_]{1,24}$/);
		expect(ICON_KEYS).toHaveLength(40);
	});

	it('knows a key from anything else', () => {
		expect(isIconKey('bank')).toBe(true);
		expect(isIconKey('Bank')).toBe(false);
		expect(isIconKey('nope')).toBe(false);
	});
});

describe('checkPicture', () => {
	it('accepts a JPEG, a PNG and a WebP by their first bytes', () => {
		expect(checkPicture(JPEG)).toMatchObject({ ok: true, mime: 'image/jpeg', bytes: 8 });
		expect(checkPicture(PNG)).toMatchObject({ ok: true, mime: 'image/png' });
		expect(checkPicture(WEBP)).toMatchObject({ ok: true, mime: 'image/webp' });
	});

	it('refuses empty text, a data URL, bad base64 and a file of another kind', () => {
		expect(checkPicture('  ').ok).toBe(false);
		expect(checkPicture(`data:image/png;base64,${PNG}`).ok).toBe(false);
		expect(checkPicture('!!!!').ok).toBe(false);
		expect(checkPicture(b64([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])).ok).toBe(false);
	});

	it('refuses a picture over the size cap', () => {
		const big = b64([0xff, 0xd8, 0xff, ...new Array<number>(PICTURE_MAX_BYTES).fill(1)]);
		const result = checkPicture(big);
		expect(result.ok).toBe(false);
		expect(result.ok ? '' : result.reason).toMatch(/24 KB/);
	});
});
