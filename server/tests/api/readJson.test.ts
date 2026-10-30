// THE BODY LIMIT OF A JSON REQUEST: 64 KB UNLESS A ROUTE ASKS FOR MORE, COUNTED AS THE BODY ARRIVES

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { readJson } from '../../src/lib/server/api/http';

// -- FUNCTIONS -- //

const post = (body: BodyInit, headers: Record<string, string> = {}) =>
	new Request('https://botler.test/x', { method: 'POST', body, headers });

/** A body that names no length and arrives in pieces, as a chunked upload does. */
const chunked = (pieces: string[]) =>
	new Request('https://botler.test/x', {
		method: 'POST',
		body: new ReadableStream<Uint8Array>({
			start(c) {
				for (const p of pieces) c.enqueue(new TextEncoder().encode(p));
				c.close();
			}
		}),
		// @ts-expect-error duplex is needed by Node for a streamed request body
		duplex: 'half'
	});

// -- TESTS -- //

describe('readJson', () => {
	it('reads a small body', async () => {
		expect(await readJson(post('{"a":1}'))).toEqual({ a: 1 });
	});

	it('refuses 64 KB and more by default, and allows more when a route asks', async () => {
		const big = JSON.stringify({ text: 'x'.repeat(70_000) });
		await expect(readJson(post(big))).rejects.toMatchObject({ code: 'INVALID' });
		expect(await readJson(post(big), 200_000)).toMatchObject({ text: expect.any(String) });
	});

	it('stops counting a body that names no length as soon as it passes the limit', async () => {
		const piece = 'x'.repeat(30_000);
		await expect(readJson(chunked(['{"t":"', piece, piece, piece, '"}']))).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('refuses text that is not JSON, and an empty body', async () => {
		await expect(readJson(post('not json'))).rejects.toMatchObject({ code: 'INVALID' });
		await expect(readJson(post(''))).rejects.toMatchObject({ code: 'INVALID' });
	});
});
