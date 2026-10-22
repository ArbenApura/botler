// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { ModelConfig } from '../../src/lib/server/proxy/deepseek';
import type { Limits } from '../../src/lib/server/proxy/limits';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { modelSpend, modelUsage, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS, monthKey } from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const KEY = 'sk-test-secret-key-0000';
const ACCOUNT = '1234567890123';
const wire = (content: string, prompt = 40, completion = 10) =>
	new Response(
		JSON.stringify({
			choices: [{ message: { content }, finish_reason: 'stop' }],
			usage: { prompt_tokens: prompt, completion_tokens: completion }
		}),
		{ status: 200 }
	);

// -- STATES -- //

let t: TestDb;
let anna: Ctx;
let ben: Ctx;

type Call = { url: string; headers: Record<string, string>; body: string };

/** A fake network: records each call and answers from a script. */
function fakeFetch(script: (call: Call, n: number) => Response | Promise<Response>) {
	const calls: Call[] = [];
	const fn = (async (url: string, init: RequestInit) => {
		const call: Call = {
			url,
			headers: init.headers as Record<string, string>,
			body: String(init.body)
		};
		calls.push(call);
		return script(call, calls.length);
	}) as unknown as typeof fetch;
	return { fn, calls };
}

function client(f: typeof fetch, limits: Partial<Limits> = {}, extra: Partial<ModelConfig> = {}) {
	return createModelClient({
		apiKey: KEY,
		baseUrl: 'https://model.test',
		model: 'test-model',
		limits: { ...DEFAULT_LIMITS, ...limits },
		fetch: f,
		sleep: async () => undefined,
		...extra
	});
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_anna_0001', name: 'Anna', email: 'anna@example.com' },
		{ id: 'user_ben_00001', name: 'Ben', email: 'ben@example.com' }
	]);
	anna = { handle: t.handle, actor: { userId: 'user_anna_0001', kind: 'person' } };
	ben = { handle: t.handle, actor: { userId: 'user_ben_00001', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

afterEach(() => {
	vi.restoreAllMocks();
});

// -- TESTS -- //

describe('model client', () => {
	it('masks the payload, keeps the key in the header only, and restores the reply', async () => {
		const f = fakeFetch(() => wire('Sent to [NAME_1], account [ACCT_1].'));
		const c = client(f.fn);
		const out = await c.complete(anna, {
			bucket: 'chat',
			names: ['Maria'],
			messages: [{ role: 'user', content: `Send 5,000 to Maria at account ${ACCOUNT}` }]
		});
		const sent = f.calls[0]!;
		expect(sent.body).not.toContain(ACCOUNT);
		expect(sent.body).not.toContain('Maria');
		expect(sent.body).toContain('5,000');
		expect(sent.headers.authorization).toBe(`Bearer ${KEY}`);
		expect(sent.body).not.toContain(KEY);
		expect(out.content).toBe(`Sent to Maria, account ${ACCOUNT}.`);
	});

	it('records usage per person and in the global total', async () => {
		// Read inside Anna's context: without it row level security shows the runtime role nothing
		const [mine] = await withUser(t.handle, 'user_anna_0001', (tx) =>
			tx.select().from(modelUsage).where(eq(modelUsage.bucket, 'chat'))
		);
		expect(mine?.promptTokens).toBe(40);
		expect(mine?.completionTokens).toBe(10);
		const [spend] = await t.handle.db.select().from(modelSpend);
		expect(spend?.month).toBe(monthKey());
		expect(Number(spend?.tokens)).toBeGreaterThanOrEqual(50);
	});

	it('retries a 503 and then succeeds', async () => {
		const f = fakeFetch((_c, n) => (n < 3 ? new Response('busy', { status: 503 }) : wire('ok')));
		const out = await client(f.fn).complete(ben, {
			bucket: 'memory',
			messages: [{ role: 'user', content: 'hi' }]
		});
		expect(f.calls).toHaveLength(3);
		expect(out.content).toBe('ok');
	});

	it('gives up after the retries with UNAVAILABLE and shows nothing about the cause', async () => {
		const f = fakeFetch(() => new Response('busy', { status: 503 }));
		await expect(
			client(f.fn).complete(ben, { bucket: 'memory', messages: [{ role: 'user', content: 'hi' }] })
		).rejects.toMatchObject({
			code: 'UNAVAILABLE',
			message: 'The assistant is not available right now.'
		});
		expect(f.calls).toHaveLength(3);
	});

	it('does not retry a rejected key and never leaks it', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const f = fakeFetch(() => new Response('no', { status: 401 }));
		const err = await client(f.fn)
			.complete(ben, { bucket: 'memory', messages: [{ role: 'user', content: 'hi' }] })
			.catch((e: unknown) => e as Error);
		expect(f.calls).toHaveLength(1);
		expect(String((err as Error).message)).not.toContain(KEY);
	});

	it('stops a third call in a minute when the rate is two', async () => {
		const f = fakeFetch(() => wire('ok', 1, 1));
		const c = client(f.fn, { ratePerMinute: 2 });
		const ask = () =>
			c.complete(anna, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] });
		await ask();
		await ask();
		await expect(ask()).rejects.toMatchObject({ code: 'LIMIT' });
		expect(f.calls).toHaveLength(2);
	});

	it('keeps the chat and memory caps separate', async () => {
		// Anna already used 50 chat tokens in the first test; a cap of 50 stops chat but not memory
		const f = fakeFetch(() => wire('ok', 1, 1));
		const c = client(f.fn, { chatTokenCap: 50, memoryTokenCap: 1_000 });
		await expect(
			c.complete(anna, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] })
		).rejects.toMatchObject({ code: 'LIMIT' });
		await expect(
			c.complete(anna, { bucket: 'memory', messages: [{ role: 'user', content: 'hi' }] })
		).resolves.toMatchObject({ content: 'ok' });
	});

	it('stops everyone at the global cap', async () => {
		const f = fakeFetch(() => wire('ok', 1, 1));
		const c = client(f.fn, { globalTokenCap: 10 });
		await expect(
			c.complete(ben, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] })
		).rejects.toMatchObject({ code: 'LIMIT', message: expect.stringContaining('whole service') });
		expect(f.calls).toHaveLength(0);
	});

	it('streams text, restores a placeholder split across chunks, and gathers a tool call', async () => {
		const sse = (obj: unknown) => `data: ${JSON.stringify(obj)}\n\n`;
		const body = [
			sse({ choices: [{ delta: { content: 'Hi [NA' } }] }),
			sse({ choices: [{ delta: { content: 'ME_1]!' } }] }),
			sse({
				choices: [
					{
						delta: {
							tool_calls: [
								{
									index: 0,
									id: 'c1',
									function: { name: 'log_expense', arguments: '{"who":"[NAME' }
								}
							]
						}
					}
				]
			}),
			sse({
				choices: [
					{
						delta: { tool_calls: [{ index: 0, function: { arguments: '_1]"}' } }] },
						finish_reason: 'tool_calls'
					}
				]
			}),
			sse({ choices: [], usage: { prompt_tokens: 30, completion_tokens: 12 } }),
			'data: [DONE]\n\n'
		];
		const f = fakeFetch(
			() =>
				new Response(
					new ReadableStream({
						start(controller) {
							for (const part of body) controller.enqueue(new TextEncoder().encode(part));
							controller.close();
						}
					}),
					{ status: 200 }
				)
		);
		const c = client(f.fn);
		let text = '';
		let done;
		for await (const ev of c.stream(ben, {
			bucket: 'memory',
			names: ['Maria'],
			messages: [{ role: 'user', content: 'Hello Maria' }]
		})) {
			if (ev.type === 'delta') text += ev.text;
			else done = ev.completion;
		}
		expect(JSON.parse(f.calls[0]!.body).stream).toBe(true);
		expect(text).toBe('Hi Maria!');
		expect(done?.finishReason).toBe('tool_calls');
		expect(done?.toolCalls[0]?.function.arguments).toBe('{"who":"Maria"}');
		expect(done?.usage).toEqual({ promptTokens: 30, completionTokens: 12 });
	});

	it('logs counts only, never the message text', async () => {
		const info = vi.spyOn(console, 'info').mockImplementation(() => undefined);
		const f = fakeFetch(() => wire('a private reply'));
		await client(f.fn).complete(ben, {
			bucket: 'memory',
			messages: [{ role: 'user', content: 'a very private sentence about rent' }]
		});
		const logged = info.mock.calls.flat().join(' ');
		expect(logged).toContain('model_call');
		expect(logged).not.toContain('private');
		expect(logged).not.toContain('rent');
		expect(logged).not.toContain('user_ben_00001');
	});
});
