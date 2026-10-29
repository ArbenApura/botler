// -- DEP-MODULES -- //
import { mkdtemp, mkdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { handleApkDownload, handleUpdateCheck } from './handlers';

// -- CONSTANTS -- //

const BYTES = Buffer.from('0123456789'.repeat(10)); // 100 bytes

// -- STATES -- //

let dir = '';
let empty = '';

const manifest = (over: Record<string, unknown> = {}) =>
	JSON.stringify({
		versionName: '1.0.1',
		versionCode: 2,
		sha256: 'b'.repeat(64),
		size: BYTES.length,
		minSupportedCode: 1,
		notes: '',
		publishedAt: '2026-10-22T10:00:00Z',
		...over
	});

const get = (code: string, range?: string, ifRange?: string) =>
	handleApkDownload({
		dir,
		signedIn: true,
		code,
		request: new Request('http://x/', {
			headers: { ...(range ? { range } : {}), ...(ifRange ? { 'if-range': ifRange } : {}) }
		})
	});

beforeAll(async () => {
	dir = await mkdtemp(join(tmpdir(), 'botler-rel-'));
	empty = await mkdtemp(join(tmpdir(), 'botler-rel-empty-'));
	await writeFile(join(dir, 'botler-1.0.1+2.apk'), BYTES);
	await writeFile(join(dir, 'latest.json'), manifest());
	await writeFile(join(dir, 'secret.txt'), 'nope');
	await mkdir(join(dir, 'sub'));
	await symlink(join(dir, 'secret.txt'), join(dir, 'botler-9.9.9+9.apk')).catch(() => undefined);
});

afterAll(async () => {
	await rm(dir, { recursive: true, force: true });
	await rm(empty, { recursive: true, force: true });
});

describe('update check', () => {
	it('is 401 without a session', async () => {
		const r = await handleUpdateCheck({ dir, signedIn: false, installed: '1' });
		expect(r.status).toBe(401);
	});

	it('refuses a missing or bad versionCode', async () => {
		expect((await handleUpdateCheck({ dir, signedIn: true, installed: null })).status).toBe(400);
		expect((await handleUpdateCheck({ dir, signedIn: true, installed: '1; rm' })).status).toBe(400);
	});

	it('offers the newer build with a download path', async () => {
		const body = (await (
			await handleUpdateCheck({ dir, signedIn: true, installed: '1' })
		).json()) as {
			status: string;
			downloadPath: string;
		};
		expect(body.status).toBe('optional');
		expect(body.downloadPath).toBe('/api/v1/app/update/apk/2');
	});

	it('says none when up to date, and when nothing was published', async () => {
		const same = await handleUpdateCheck({ dir, signedIn: true, installed: '2' });
		expect(((await same.json()) as { status: string }).status).toBe('none');
		const none = await handleUpdateCheck({ dir: empty, signedIn: true, installed: '1' });
		expect(none.status).toBe(200);
		expect(((await none.json()) as { status: string }).status).toBe('none');
	});

	it('says none when the folder does not exist or the file is smaller than promised', async () => {
		const gone = await handleUpdateCheck({
			dir: join(dir, 'nope'),
			signedIn: true,
			installed: '1'
		});
		expect(((await gone.json()) as { status: string }).status).toBe('none');
		const bad = await mkdtemp(join(tmpdir(), 'botler-rel-bad-'));
		await writeFile(join(bad, 'latest.json'), manifest({ size: 5000, minSupportedCode: 2 }));
		await writeFile(join(bad, 'botler-1.0.1+2.apk'), BYTES);
		const r = await handleUpdateCheck({ dir: bad, signedIn: true, installed: '1' });
		expect(((await r.json()) as { status: string }).status).toBe('none');
		await rm(bad, { recursive: true, force: true });
	});

	it('says required below the minimum', async () => {
		const req = await mkdtemp(join(tmpdir(), 'botler-rel-req-'));
		await writeFile(join(req, 'latest.json'), manifest({ minSupportedCode: 2 }));
		await writeFile(join(req, 'botler-1.0.1+2.apk'), BYTES);
		const r = await handleUpdateCheck({ dir: req, signedIn: true, installed: '1' });
		expect(((await r.json()) as { status: string }).status).toBe('required');
		await rm(req, { recursive: true, force: true });
	});

	it('is a calm none for a broken manifest', async () => {
		const bad = await mkdtemp(join(tmpdir(), 'botler-rel-broken-'));
		await writeFile(join(bad, 'latest.json'), '{broken');
		const r = await handleUpdateCheck({ dir: bad, signedIn: true, installed: '1' });
		expect(((await r.json()) as { status: string }).status).toBe('none');
		await rm(bad, { recursive: true, force: true });
	});
});

describe('apk download', () => {
	it('is 401 without a session', async () => {
		const r = await handleApkDownload({
			dir,
			signedIn: false,
			code: '2',
			request: new Request('http://x/')
		});
		expect(r.status).toBe(401);
	});

	it('streams the whole file with its length and type', async () => {
		const r = await get('2');
		expect(r.status).toBe(200);
		expect(r.headers.get('content-length')).toBe('100');
		expect(r.headers.get('content-type')).toBe('application/vnd.android.package-archive');
		expect(r.headers.get('cache-control')).toContain('no-store');
		expect(Buffer.from(await r.arrayBuffer()).equals(BYTES)).toBe(true);
	});

	it('serves open ended and suffix ranges', async () => {
		const open = await get('2', 'bytes=90-');
		expect(open.status).toBe(206);
		expect(open.headers.get('content-range')).toBe('bytes 90-99/100');
		expect(Buffer.from(await open.arrayBuffer()).toString()).toBe('0123456789');
		const suffix = await get('2', 'bytes=-5');
		expect(Buffer.from(await suffix.arrayBuffer()).toString()).toBe('56789');
	});

	it('answers 416 for a range past the end', async () => {
		const r = await get('2', 'bytes=200-');
		expect(r.status).toBe(416);
		expect(r.headers.get('content-range')).toBe('bytes */100');
	});

	it('sends the whole file when If-Range no longer matches', async () => {
		const r = await get('2', 'bytes=10-19', '"old"');
		expect(r.status).toBe(200);
		expect(r.headers.get('content-length')).toBe('100');
	});

	it('refuses traversal and non numeric codes', async () => {
		expect((await get('..%2Flatest')).status).toBe(400);
		expect((await get('../../etc/passwd')).status).toBe(400);
		expect((await get('2.apk')).status).toBe(400);
	});

	it('is 404 for a build that is not there, and for a link out of the folder', async () => {
		expect((await get('7')).status).toBe(404);
		expect((await get('9')).status).toBe(404);
	});

	it('is 404 when the folder does not exist', async () => {
		const r = await handleApkDownload({
			dir: join(dir, 'nope'),
			signedIn: true,
			code: '2',
			request: new Request('http://x/')
		});
		expect(r.status).toBe(404);
	});
});

describe('split builds', () => {
	const ARM64 = Buffer.from('a'.repeat(40));
	const ARM32 = Buffer.from('b'.repeat(30));
	let split = '';

	type Answer = {
		status: string;
		downloadPath: string;
		latest: { size: number; sha256: string };
	};

	const check = async (abis: string | null, over?: string): Promise<Answer> =>
		(await (
			await handleUpdateCheck({ dir: over ?? split, signedIn: true, installed: '1', abis })
		).json()) as Answer;

	beforeAll(async () => {
		split = await mkdtemp(join(tmpdir(), 'botler-rel-split-'));
		await writeFile(join(split, 'botler-1.0.1+2.apk'), BYTES);
		await writeFile(join(split, 'botler-1.0.1+2-arm64-v8a.apk'), ARM64);
		await writeFile(join(split, 'botler-1.0.1+2-armeabi-v7a.apk'), ARM32);
		await writeFile(
			join(split, 'latest.json'),
			manifest({
				apks: {
					'arm64-v8a': { size: ARM64.length, sha256: 'c'.repeat(64) },
					'armeabi-v7a': { size: ARM32.length, sha256: 'd'.repeat(64) },
					// Listed but its file was never uploaded
					x86_64: { size: 10, sha256: 'e'.repeat(64) }
				}
			})
		);
	});

	afterAll(async () => {
		await rm(split, { recursive: true, force: true });
	});

	it('offers the phones own architecture with its own size and hash', async () => {
		const a = await check('arm64-v8a,armeabi-v7a');
		expect(a.downloadPath).toBe('/api/v1/app/update/apk/2?abi=arm64-v8a');
		expect(a.latest.size).toBe(ARM64.length);
		expect(a.latest.sha256).toBe('c'.repeat(64));
		expect((await check('armeabi-v7a')).downloadPath).toBe(
			'/api/v1/app/update/apk/2?abi=armeabi-v7a'
		);
	});

	it('offers the universal build to a phone that sends no architecture or an unknown one', async () => {
		for (const abis of [null, '', 'mips,riscv64']) {
			const a = await check(abis);
			expect(a.downloadPath).toBe('/api/v1/app/update/apk/2');
			expect(a.latest.size).toBe(BYTES.length);
		}
	});

	it('falls back to the universal build when the split file is missing', async () => {
		const a = await check('x86_64');
		expect(a.downloadPath).toBe('/api/v1/app/update/apk/2');
	});

	it('serves exactly the file of the architecture asked for', async () => {
		const res = await handleApkDownload({
			dir: split,
			signedIn: true,
			code: '2',
			abi: 'arm64-v8a',
			request: new Request('http://x/')
		});
		expect(res.status).toBe(200);
		expect(Buffer.from(await res.arrayBuffer()).equals(ARM64)).toBe(true);
		const universal = await handleApkDownload({
			dir: split,
			signedIn: true,
			code: '2',
			request: new Request('http://x/')
		});
		expect(Buffer.from(await universal.arrayBuffer()).equals(BYTES)).toBe(true);
	});

	it('refuses an architecture that is not published and a missing split file', async () => {
		const bad = await handleApkDownload({
			dir: split,
			signedIn: true,
			code: '2',
			abi: '../x',
			request: new Request('http://x/')
		});
		expect(bad.status).toBe(400);
		const gone = await handleApkDownload({
			dir: split,
			signedIn: true,
			code: '2',
			abi: 'x86_64',
			request: new Request('http://x/')
		});
		expect(gone.status).toBe(404);
	});
});
