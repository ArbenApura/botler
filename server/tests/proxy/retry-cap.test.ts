// THE WAIT FOR A FIRST BYTE: ALL TRIES TOGETHER STOP AFTER ABOUT TWO MINUTES, AND THE BODY OF A FAILED ANSWER IS CANCELLED

// -- DEP-MODULES -- //
import { afterEach, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { createCore } from '../../src/lib/server/proxy/core';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';

// -- FUNCTIONS -- //

afterEach(() => {
	vi.restoreAllMocks();
});

const core = (f: typeof fetch, extra: { maxRetries?: number; maxTotalMs?: number } = {}) => {
	const slept: number[] = [];
	const c = createCore({
		provider: 'deepseek',
		model: 'm',
		limits: DEFAULT_LIMITS,
		timeoutMs: 60_000,
		maxRetries: extra.maxRetries ?? 10,
		...(extra.maxTotalMs !== undefined ? { maxTotalMs: extra.maxTotalMs } : {}),
		fetch: f,
		sleep: async (ms) => {
			slept.push(ms);
		}
	});
	return { c, slept };
};

const send = (c: ReturnType<typeof core>['c']) =>
	c.send({ url: 'https://model.test', headers: {}, body: {} });

// -- TESTS -- //

describe('retries of the first byte', () => {
	it('stops once the pauses add up to the total, not after all ten tries', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => undefined);
		let calls = 0;
		const f = (async () => {
			calls++;
			return new Response('busy', { status: 503, headers: { 'retry-after': '5' } });
		}) as unknown as typeof fetch;
		const { c, slept } = core(f, { maxTotalMs: 12_000 });
		await expect(send(c)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
		// 5 s a pause: the third pause would pass 12 s
		expect(calls).toBeLessThanOrEqual(3);
		expect(slept.reduce((a, b) => a + b, 0)).toBeLessThanOrEqual(12_000);
	});

	it('keeps trying up to the retry count while the total allows it', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => undefined);
		let calls = 0;
		const f = (async () => {
			calls++;
			return new Response('busy', { status: 503 });
		}) as unknown as typeof fetch;
		const { c } = core(f, { maxRetries: 2 });
		await expect(send(c)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
		expect(calls).toBe(3);
	});

	it('cancels the body of a failed answer before it tries again', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => undefined);
		let cancelled = 0;
		const f = (async () => {
			const body = new ReadableStream<Uint8Array>({
				cancel() {
					cancelled++;
				}
			});
			return new Response(body, { status: 502 });
		}) as unknown as typeof fetch;
		const { c } = core(f, { maxRetries: 2 });
		await expect(send(c)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
		expect(cancelled).toBe(3);
	});
});
