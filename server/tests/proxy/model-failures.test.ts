// THE MODEL CLIENT WHEN THINGS GO WRONG: A SLOW START, A STALLED STREAM, A BROKEN BODY, AND THE CEILING ON EVERY CALL.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let anna: Ctx;

const make = (f: typeof fetch, extra: Record<string, unknown> = {}) =>
	createModelClient({
		apiKey: 'sk-test',
		baseUrl: 'https://model.test',
		model: 'm',
		limits: { ...DEFAULT_LIMITS, ratePerMinute: 1000 },
		fetch: f,
		sleep: async () => undefined,
		...extra
	});

const ask = (c: ReturnType<typeof make>) =>
	c.complete(anna, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] });

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values({ id: 'user_anna_0001', name: 'Anna', email: 'a@example.com' });
	anna = { handle: t.handle, actor: { userId: 'user_anna_0001', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('model client failures', () => {
	it('gives every call a token ceiling', async () => {
		let body = '';
		const f = (async (_u: string, init: RequestInit) => {
			body = String(init.body);
			return new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }], usage: {} }));
		}) as unknown as typeof fetch;
		await ask(make(f));
		expect(JSON.parse(body).max_tokens).toBe(2048);
		await make(f, { defaultMaxTokens: 100 }).complete(anna, {
			bucket: 'chat',
			maxTokens: 50,
			messages: [{ role: 'user', content: 'hi' }]
		});
		expect(JSON.parse(body).max_tokens).toBe(50);
	});

	it('turns a slow start into UNAVAILABLE instead of hanging', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => undefined);
		// A network that never answers but honours the abort signal
		const f = ((_u: string, init: RequestInit) =>
			new Promise((_resolve, reject) => {
				init.signal?.addEventListener('abort', () => reject(new DOMException('x', 'AbortError')));
			})) as unknown as typeof fetch;
		const started = Date.now();
		await expect(ask(make(f, { timeoutMs: 40, maxRetries: 1 }))).rejects.toMatchObject({
			code: 'UNAVAILABLE'
		});
		expect(Date.now() - started).toBeLessThan(2000);
		vi.restoreAllMocks();
	});

	it('turns a body that is not JSON into UNAVAILABLE, not a raw error', async () => {
		const f = (async () =>
			new Response('<html>gateway</html>', { status: 200 })) as unknown as typeof fetch;
		await expect(ask(make(f))).rejects.toMatchObject({ code: 'UNAVAILABLE' });
	});

	it('cuts off a stream that goes silent and still records what was used', async () => {
		vi.spyOn(console, 'info').mockImplementation(() => undefined);
		const f = (async () =>
			new Response(
				new ReadableStream({
					start(controller) {
						controller.enqueue(
							new TextEncoder().encode(
								`data: ${JSON.stringify({ choices: [{ delta: { content: 'Hi' } }] })}\n\n`
							)
						);
						// Then nothing: the stream stays open and silent
					}
				}),
				{ status: 200 }
			)) as unknown as typeof fetch;
		const c = make(f, { timeoutMs: 60 });
		const seen: string[] = [];
		await expect(
			(async () => {
				for await (const ev of c.stream(anna, {
					bucket: 'memory',
					messages: [{ role: 'user', content: 'hi' }]
				}))
					if (ev.type === 'delta') seen.push(ev.text);
			})()
		).rejects.toMatchObject({ code: 'UNAVAILABLE' });
		expect(seen.join('')).toBe('Hi');
		vi.restoreAllMocks();
	});

	it('keeps a tool argument valid JSON when a masked name contains a quote', async () => {
		const f = (async () =>
			new Response(
				JSON.stringify({
					choices: [
						{
							message: {
								content: null,
								tool_calls: [
									{
										id: 'c1',
										type: 'function',
										function: { name: 'x', arguments: '{"who":"[NAME_1]"}' }
									}
								]
							},
							finish_reason: 'tool_calls'
						}
					],
					usage: { prompt_tokens: 1, completion_tokens: 1 }
				})
			)) as unknown as typeof fetch;
		const out = await make(f).complete(anna, {
			bucket: 'chat',
			names: ['Maria "Mimi" Cruz'],
			messages: [{ role: 'user', content: 'Send to Maria "Mimi" Cruz' }]
		});
		expect(JSON.parse(out.toolCalls[0]!.function.arguments)).toEqual({ who: 'Maria "Mimi" Cruz' });
	});
});
