// THE TWO APP UPDATE ENDPOINTS, AS PLAIN FUNCTIONS OVER A RELEASES FOLDER: THE VERSION CHECK AND THE APK DOWNLOAD.
// Outside the ops layer and the tenant registry on purpose: nothing here is a person's data, it is the build the owner published.
// The routes pass the folder in, so the tests use a temporary one. Logs hold codes only, never a path, a token or a header.

// -- TYPES -- //
import type { Manifest } from '../../app-update/rules';
// -- DEP-MODULES -- //
import { createReadStream } from 'node:fs';
import { lstat, readdir, readFile, realpath } from 'node:fs/promises';
import { join, sep } from 'node:path';
import { Readable } from 'node:stream';
// -- MODULES -- //
import {
	apkFileName,
	codeOfFileName,
	decideUpdate,
	parseManifest,
	parseRange
} from '../../app-update/rules';
import { OpsError } from '../ops/context';
import { fail, json } from '../api/http';

// -- CONSTANTS -- //

const APK_TYPE = 'application/vnd.android.package-archive';

// -- FUNCTIONS -- //

function unauthenticated(): Response {
	return json({ error: { code: 'UNAUTHENTICATED', message: 'Sign in first' } }, 401);
}

/** latest.json, or null when none was published yet or it is not valid. An unreadable folder is UNAVAILABLE. */
async function readManifest(dir: string): Promise<Manifest | null> {
	let text: string;
	try {
		text = await readFile(join(dir, 'latest.json'), 'utf8');
	} catch (e) {
		const code = (e as NodeJS.ErrnoException).code;
		if (code === 'ENOENT' || code === 'ENOTDIR') return null;
		console.error('App update: the releases folder cannot be read', code ?? 'unknown');
		throw new OpsError('UNAVAILABLE', 'Updates are not available right now');
	}
	const manifest = parseManifest(text);
	if (!manifest) console.error('App update: latest.json is not a valid manifest');
	return manifest;
}

/** Does the file the manifest names exist with the size it promises? */
async function apkMatches(dir: string, manifest: Manifest): Promise<boolean> {
	try {
		// lstat, like the download: a link is never a build
		const s = await lstat(join(dir, apkFileName(manifest.versionName, manifest.versionCode)));
		return s.isFile() && s.size === manifest.size;
	} catch {
		return false;
	}
}

/** The version check. The caller sends the versionCode the phone is running. */
export async function handleUpdateCheck(input: {
	dir: string;
	signedIn: boolean;
	installed: string | null;
}): Promise<Response> {
	if (!input.signedIn) return unauthenticated();
	if (!input.installed || !/^\d{1,9}$/.test(input.installed))
		return fail(new OpsError('INVALID', 'versionCode must be a whole number'));
	const installedCode = Number(input.installed);
	try {
		const manifest = await readManifest(input.dir);
		const apkOk = manifest ? await apkMatches(input.dir, manifest) : false;
		const status = decideUpdate(manifest, installedCode, apkOk);
		if (status === 'none' || !manifest) return json({ status: 'none', installedCode });
		return json({
			status,
			installedCode,
			latest: manifest,
			downloadPath: `/api/v1/app/update/apk/${manifest.versionCode}`
		});
	} catch (e) {
		return fail(e);
	}
}

/** The APK itself, streamed with byte ranges so an interrupted download can be restarted cheaply. */
export async function handleApkDownload(input: {
	dir: string;
	signedIn: boolean;
	code: string;
	request: Request;
}): Promise<Response> {
	if (!input.signedIn) return unauthenticated();
	if (!/^\d{1,9}$/.test(input.code))
		return fail(new OpsError('INVALID', 'versionCode must be a whole number'));
	const code = Number(input.code);
	try {
		// The file is found by listing the folder, never by putting the parameter into a path
		let names: string[];
		try {
			names = await readdir(input.dir);
		} catch (e) {
			const errno = (e as NodeJS.ErrnoException).code;
			if (errno === 'ENOENT' || errno === 'ENOTDIR')
				throw new OpsError('NOT_FOUND', 'That build is not available');
			console.error('App update: the releases folder cannot be read', errno ?? 'unknown');
			throw new OpsError('UNAVAILABLE', 'Updates are not available right now');
		}
		const name = names.find((n) => codeOfFileName(n) === code);
		if (!name) throw new OpsError('NOT_FOUND', 'That build is not available');
		const path = join(input.dir, name);
		// A link or a path that leaves the folder is never served
		const [root, real, info] = await Promise.all([
			realpath(input.dir),
			realpath(path),
			lstat(path)
		]);
		if (info.isSymbolicLink() || !info.isFile() || info.size === 0 || !real.startsWith(root + sep))
			throw new OpsError('NOT_FOUND', 'That build is not available');

		const size = info.size;
		const etag = `"${size}-${Math.floor(info.mtimeMs)}"`;
		const headers: Record<string, string> = {
			'content-type': APK_TYPE,
			'accept-ranges': 'bytes',
			'cache-control': 'private, no-store',
			etag
		};
		// If-Range with another validator means the file was replaced: send all of it, never a piece of the new file
		const ifRange = input.request.headers.get('if-range');
		const range =
			ifRange && ifRange !== etag ? null : parseRange(input.request.headers.get('range'), size);
		if (range === 'invalid')
			return new Response(null, {
				status: 416,
				headers: { ...headers, 'content-range': `bytes */${size}` }
			});

		const start = range ? range.start : 0;
		const end = range ? range.end : size - 1;
		const stream = Readable.toWeb(createReadStream(path, { start, end })) as ReadableStream;
		return new Response(stream, {
			status: range ? 206 : 200,
			headers: {
				...headers,
				'content-length': String(end - start + 1),
				...(range ? { 'content-range': `bytes ${start}-${end}/${size}` } : {})
			}
		});
	} catch (e) {
		return fail(e);
	}
}
