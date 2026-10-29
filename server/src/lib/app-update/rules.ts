// PURE RULES FOR APP UPDATES: THE RELEASE MANIFEST, THE FILE NAME, THE UPDATE DECISION AND HTTP RANGES. NO DATABASE, NO FILES.
// The phone is updated by sideloading, so the server only has to say "a newer build exists" and hand over its file. Android itself
// refuses an install signed with another key or with a lower versionCode; these rules never replace that.

// -- DEP-MODULES -- //
import { z } from 'zod';

// -- CONSTANTS -- //

/** The architectures a split build can be published for. */
export const ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64'] as const;

/**
 * The only file names that are ever served: botler-<versionName>+<versionCode>.apk (the universal build, for phones that
 * do not say their architecture) or botler-<versionName>+<versionCode>-<abi>.apk (one architecture).
 */
export const APK_NAME = /^botler-(\d+\.\d+\.\d+)\+(\d+)(?:-(arm64-v8a|armeabi-v7a|x86_64))?\.apk$/;

const fileSchema = z.object({
	size: z.number().int().positive(),
	sha256: z.string().regex(/^[0-9a-f]{64}$/)
});

/**
 * Keeps the entries of `apks` that name a known architecture and hold a valid size and hash. One odd entry (an architecture this server
 * does not know yet, a bad hash) must never invalidate the manifest and so stop every phone from updating: it is only left out.
 */
function keepKnownBuilds(value: unknown): unknown {
	if (typeof value !== 'object' || value === null || Array.isArray(value)) return undefined;
	const kept: Record<string, unknown> = {};
	for (const abi of ABIS) {
		const entry = (value as Record<string, unknown>)[abi];
		if (fileSchema.safeParse(entry).success) kept[abi] = entry;
	}
	return kept;
}

export const manifestSchema = z
	.object({
		versionName: z.string().regex(/^\d+\.\d+\.\d+$/),
		versionCode: z.number().int().positive(),
		/** Size and hash of the universal build: what a phone that sends no architecture downloads. */
		sha256: z.string().regex(/^[0-9a-f]{64}$/),
		size: z.number().int().positive(),
		/** Size and hash of each single-architecture build. Absent for a release published before split builds. */
		apks: z
			.preprocess(keepKnownBuilds, z.partialRecord(z.enum(ABIS), fileSchema))
			.optional()
			.catch(undefined),
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

export type Abi = (typeof ABIS)[number];

export type UpdateStatus = 'none' | 'optional' | 'required';

export type ByteRange = { start: number; end: number };

// -- FUNCTIONS -- //

/** The file name a build is stored under; with an architecture, the single-architecture build. */
export function apkFileName(versionName: string, versionCode: number, abi?: Abi): string {
	return `botler-${versionName}+${versionCode}${abi ? `-${abi}` : ''}.apk`;
}

/** The version code inside a stored file name, or null for any other name. */
export function codeOfFileName(name: string): number | null {
	const m = APK_NAME.exec(name);
	return m ? Number(m[2]) : null;
}

/** The architecture inside a stored file name: null for the universal build and for any other name. */
export function abiOfFileName(name: string): Abi | null {
	const m = APK_NAME.exec(name);
	return m?.[3] ? (m[3] as Abi) : null;
}

/** One architecture word from the query, or null when it is not one we publish. */
export function parseAbi(value: string | null): Abi | null {
	return (ABIS as readonly string[]).includes(value ?? '') ? (value as Abi) : null;
}

/** The phone's architectures, most preferred first, as it sends them ("arm64-v8a,armeabi-v7a"). Unknown words are dropped. */
export function parseAbiList(value: string | null): Abi[] {
	if (!value) return [];
	const list: Abi[] = [];
	for (const word of value.split(',')) {
		const abi = parseAbi(word.trim());
		if (abi && !list.includes(abi)) list.push(abi);
	}
	return list;
}

/** The first of the phone's architectures that has a published build, or null: the phone then takes the universal build. */
export function pickAbi(manifest: Manifest, phoneAbis: Abi[]): Abi | null {
	return phoneAbis.find((a) => manifest.apks?.[a]) ?? null;
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
