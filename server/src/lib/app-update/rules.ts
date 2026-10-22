// PURE RULES FOR APP UPDATES: THE RELEASE MANIFEST, THE FILE NAME, THE UPDATE DECISION AND HTTP RANGES. NO DATABASE, NO FILES.
// The phone is updated by sideloading, so the server only has to say "a newer build exists" and hand over its file. Android itself
// refuses an install signed with another key or with a lower versionCode; these rules never replace that.

// -- DEP-MODULES -- //
import { z } from 'zod';

// -- CONSTANTS -- //

/** The only file names that are ever served: botler-<versionName>+<versionCode>.apk. */
export const APK_NAME = /^botler-(\d+\.\d+\.\d+)\+(\d+)\.apk$/;

export const manifestSchema = z
	.object({
		versionName: z.string().regex(/^\d+\.\d+\.\d+$/),
		versionCode: z.number().int().positive(),
		sha256: z.string().regex(/^[0-9a-f]{64}$/),
		size: z.number().int().positive(),
		/** Phones older than this must update before they can be used. */
		minSupportedCode: z.number().int().positive(),
		notes: z.string().max(2000),
		publishedAt: z.string().max(40)
	})
	// A minimum above the build itself would lock every phone out for an update that does not exist
	.refine((m) => m.minSupportedCode <= m.versionCode, {
		message: 'minSupportedCode cannot be above versionCode'
	});

// -- TYPES -- //

export type Manifest = z.infer<typeof manifestSchema>;

export type UpdateStatus = 'none' | 'optional' | 'required';

export type ByteRange = { start: number; end: number };

// -- FUNCTIONS -- //

/** The file name a build is stored under. */
export function apkFileName(versionName: string, versionCode: number): string {
	return `botler-${versionName}+${versionCode}.apk`;
}

/** The version code inside a stored file name, or null for any other name. */
export function codeOfFileName(name: string): number | null {
	const m = APK_NAME.exec(name);
	return m ? Number(m[2]) : null;
}

/** Reads latest.json. A bad manifest is null: the caller answers "none" instead of breaking every phone. */
export function parseManifest(text: string): Manifest | null {
	let raw: unknown;
	try {
		raw = JSON.parse(text);
	} catch {
		return null;
	}
	const parsed = manifestSchema.safeParse(raw);
	return parsed.success ? parsed.data : null;
}

/**
 * What the phone should do. "required" needs a build that can really be served (apkOk) and a phone below the minimum;
 * a missing file, an equal or older build, or no manifest is always "none".
 */
export function decideUpdate(
	manifest: Manifest | null,
	installedCode: number,
	apkOk: boolean
): UpdateStatus {
	if (!manifest || !apkOk) return 'none';
	if (manifest.versionCode <= installedCode) return 'none';
	return installedCode < manifest.minSupportedCode ? 'required' : 'optional';
}

/**
 * One byte range from a Range header. null means "send the whole file" (no header, or a form we do not serve, such as
 * several ranges); 'invalid' means 416.
 */
export function parseRange(header: string | null, size: number): ByteRange | null | 'invalid' {
	if (!header) return null;
	// Another unit than bytes is ignored (the whole file is sent), as the standard says
	if (!header.trim().startsWith('bytes=')) return null;
	const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
	if (!m) return header.includes(',') ? null : 'invalid';
	const [, a, b] = m;
	if (a === '' && b === '') return 'invalid';
	// A suffix range: the last N bytes
	if (a === '') {
		const n = Number(b);
		if (n <= 0) return 'invalid';
		return { start: Math.max(0, size - n), end: size - 1 };
	}
	const start = Number(a);
	const end = b === '' ? size - 1 : Math.min(Number(b), size - 1);
	if (start >= size || start > end) return 'invalid';
	return { start, end };
}
