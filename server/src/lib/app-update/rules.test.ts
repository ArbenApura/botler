// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { apkFileName, codeOfFileName, decideUpdate, parseManifest, parseRange } from './rules';

// -- CONSTANTS -- //

const manifest = {
	versionName: '1.0.1',
	versionCode: 2,
	sha256: 'a'.repeat(64),
	size: 1000,
	minSupportedCode: 1,
	notes: 'Fixes',
	publishedAt: '2026-10-22T10:00:00Z'
};
const parsed = () => parseManifest(JSON.stringify(manifest));

describe('manifest', () => {
	it('accepts a valid manifest', () => {
		expect(parsed()?.versionCode).toBe(2);
	});

	it('refuses malformed json, missing fields and a bad hash', () => {
		expect(parseManifest('{nope')).toBeNull();
		expect(parseManifest('{}')).toBeNull();
		expect(parseManifest(JSON.stringify({ ...manifest, sha256: 'xyz' }))).toBeNull();
	});

	it('refuses a minimum above the build itself', () => {
		expect(parseManifest(JSON.stringify({ ...manifest, minSupportedCode: 3 }))).toBeNull();
	});
});

describe('file names', () => {
	it('round trips a name and refuses anything else', () => {
		expect(apkFileName('1.0.1', 2)).toBe('botler-1.0.1+2.apk');
		expect(codeOfFileName('botler-1.0.1+2.apk')).toBe(2);
		expect(codeOfFileName('../botler-1.0.1+2.apk')).toBeNull();
		expect(codeOfFileName('botler-1.0.1+2.apk.part')).toBeNull();
		expect(codeOfFileName('latest.json')).toBeNull();
	});
});

describe('update decision', () => {
	it('is none without a manifest or without the file', () => {
		expect(decideUpdate(null, 1, true)).toBe('none');
		expect(decideUpdate(parsed(), 1, false)).toBe('none');
	});

	it('ignores an equal build and a downgrade', () => {
		expect(decideUpdate(parsed(), 2, true)).toBe('none');
		expect(decideUpdate(parsed(), 5, true)).toBe('none');
	});

	it('is optional for an older phone above the minimum', () => {
		expect(decideUpdate(parsed(), 1, true)).toBe('optional');
	});

	it('is required below the minimum, and never when the file is missing', () => {
		const m = parseManifest(JSON.stringify({ ...manifest, minSupportedCode: 2 }));
		expect(decideUpdate(m, 1, true)).toBe('required');
		expect(decideUpdate(m, 1, false)).toBe('none');
	});
});

describe('byte ranges', () => {
	it('sends everything without a header or for several ranges', () => {
		expect(parseRange(null, 100)).toBeNull();
		expect(parseRange('bytes=0-1,5-6', 100)).toBeNull();
	});

	it('reads closed, open ended and suffix ranges', () => {
		expect(parseRange('bytes=0-9', 100)).toEqual({ start: 0, end: 9 });
		expect(parseRange('bytes=90-', 100)).toEqual({ start: 90, end: 99 });
		expect(parseRange('bytes=-10', 100)).toEqual({ start: 90, end: 99 });
		expect(parseRange('bytes=-500', 100)).toEqual({ start: 0, end: 99 });
		expect(parseRange('bytes=50-500', 100)).toEqual({ start: 50, end: 99 });
	});

	it('refuses ranges outside the file or malformed', () => {
		expect(parseRange('bytes=100-', 100)).toBe('invalid');
		expect(parseRange('bytes=60-50', 100)).toBe('invalid');
		expect(parseRange('bytes=-', 100)).toBe('invalid');
		expect(parseRange('bytes=-0', 100)).toBe('invalid');
		expect(parseRange('items=0-5', 100)).toBeNull();
	});
});
