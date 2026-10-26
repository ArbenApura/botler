// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { ModelConfig } from '../../src/lib/server/proxy/anthropic';
import type { Limits } from '../../src/lib/server/proxy/limits';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { createAnthropicClient } from '../../src/lib/server/proxy/anthropic';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const KEY = 'sk-ant-test-secret-key-0000';
const ACCOUNT = '1234567890123';
const defs = [
	{
		type: 'function' as const,
		function: {
			name: 'log_expense',
			description: 'Record an expense',
			parameters: { type: 'object', properties: { note: { type: 'string' } } }
		}
	}
];

const textAnswer = (text: string, prompt = 40, completion = 10) =>
	new Response(
		JSON.stringify({
			content: [{ type: 'text', text }],
			stop_reason: 'end_turn',
			usage: { input_tokens: prompt, output_tokens: completion }
		}),
		{ status: 200 }
	);

const sseLine = (obj: unknown) => `data: ${JSON.stringify(obj)}\n\n`;

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
	return createAnthropicClient({
		apiKey: KEY,
		baseUrl: 'https://model.test',
		model: 'claude-haiku-5-5',
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

// -- TESTS -- //

describe('anthropic client', () => {
	it('speaks the /v1/messages format with the key in x-api-key only, and translates the system field masked', async () => {
		const f = fakeFetch(() => textAnswer('ok'));
		await client(f.fn).complete(anna, {
			bucket: 'chat',
			names: ['Maria'],
			messages: [
				{ role: 'system', content: `Persona. Account ${ACCOUNT}. Maria is family.` },
				{ role: 'user', content: `hi` }
			]
		});
		const sent = f.calls[0]!;
		expect(sent.url).toBe('https://model.test/v1/messages');
		expect(sent.headers['x-api-key']).toBe(KEY);
		expect(sent.headers['anthropic-version']).toBeTruthy();
		expect(sent.body).not.toContain(KEY);
		expect(sent.body).not.toContain(ACCOUNT);
		expect(sent.body).not.toContain('Maria');
		const body = JSON.parse(sent.body) as {
			model: string;
			system: { type: string; text: string }[];
			max_tokens: number;
			messages: { role: string; content: unknown }[];
		};
		expect(body.model).toBe('claude-haiku-5-5');
		const system = body.system.map((b) => b.text).join(' ');
		expect(system).toContain('[ACCT_1]');
		expect(system).toContain('[NAME_1]');
		// max_tokens is required on /v1/messages, and there is no stream_options on this wire
		expect(body.max_tokens).toBeGreaterThan(0);
		expect(sent.body).not.toContain('stream_options');
	});

	it('gives a chat call the chat ceiling and a memory call the small default', async () => {
		const f = fakeFetch(() => textAnswer('ok'));
		const c = client(f.fn);
		const messages = [{ role: 'user' as const, content: 'hi' }];
		await c.complete(anna, { bucket: 'chat', messages });
		await c.complete(anna, { bucket: 'memory', messages });
		await client(f.fn, {}, { chatMaxTokens: 4000 }).complete(anna, { bucket: 'chat', messages });
		const ceilings = f.calls.map((c) => (JSON.parse(c.body) as { max_tokens: number }).max_tokens);
		expect(ceilings).toEqual([8192, 2048, 4000]);
	});

	it('maps usage with the cached reads into the shared buckets, and restores the reply', async () => {
		const f = fakeFetch(
			() =>
				new Response(
					JSON.stringify({
						content: [{ type: 'text', text: `Sent [NAME_1] to [ACCT_1]` }],
						stop_reason: 'end_turn',
						usage: { input_tokens: 30, output_tokens: 12, cache_read_input_tokens: 10 }
					}),
					{ status: 200 }
				)
		);
		const out = await client(f.fn).complete(ben, {
			bucket: 'memory',
			names: ['Maria'],
			messages: [{ role: 'user', content: `Send to Maria, account ${ACCOUNT}` }]
		});
		expect(out.content).toBe(`Sent Maria to ${ACCOUNT}`);
		// 30 + 10 cached read, 12 written
		expect(out.usage).toMatchObject({
			promptTokens: 40,
			completionTokens: 12,
			cacheReadTokens: 10,
			cacheWriteTokens: 0
		});
	});

	it('offers tools as input_schema, translates stop reasons, and never leaves a placeholder on the wire', async () => {
		const f = fakeFetch(
			() =>
				new Response(
					JSON.stringify({
						content: [
							{ type: 'text', text: 'One moment.' },
							{ type: 'tool_use', id: 'toolu_01ABC', name: 'log_expense', input: { note: 'taxi' } }
						],
						stop_reason: 'tool_use',
						usage: { input_tokens: 31, output_tokens: 9 }
					}),
					{ status: 200 }
				)
		);
		const out = await client(f.fn).complete(ben, {
			bucket: 'chat',
			tools: defs,
			names: ['Maria'],
			messages: [{ role: 'user', content: 'taxi 180' }]
		});
		const body = JSON.parse(f.calls[0]!.body) as {
			tools?: { name: string; description: string; input_schema: unknown }[];
			function?: unknown;
		};
		expect(body.tools?.[0]?.name).toBe('log_expense');
		expect(body.tools?.[0]?.input_schema).toBeTruthy();
		expect(f.calls[0]!.body).toContain('"input_schema"');
		expect(f.calls[0]!.body).not.toContain('"parameters"');
		expect(out.finishReason).toBe('tool_calls');
		expect(out.toolCalls[0]).toMatchObject({
			id: 'toolu_01ABC',
			function: { name: 'log_expense', arguments: '{"note":"taxi"}' }
		});
	});

	it('turns a cut-off answer into the length path', async () => {
		const f = fakeFetch(
			() =>
				new Response(
					JSON.stringify({
						content: [{ type: 'text', text: 'half an answ' }],
						stop_reason: 'max_tokens',
						usage: { input_tokens: 30, output_tokens: 2048 }
					}),
					{ status: 200 }
				)
		);
		const out = await client(f.fn).complete(ben, {
			bucket: 'chat',
			messages: [{ role: 'user', content: 'th' }]
		});
		expect(out.finishReason).toBe('length');
	});

	it('re-sends a tool round with the same ids, as tool_result blocks in one user turn, without reasoning_content', async () => {
		const f = fakeFetch(() => textAnswer('all set'));
		const history = [
			{ role: 'system' as const, content: 'Persona' },
			{ role: 'user' as const, content: 'taxi 180' },
			{
				role: 'assistant' as const,
				content: 'One moment.',
				tool_calls: [
					{
						id: 'toolu_01ABC',
						type: 'function' as const,
						function: { name: 'log_expense', arguments: `{"note":"taxi"}` }
					}
				],
				// What a DeepSeek round keeps: the Anthropic wire must never see it
				reasoning_content: 'a thought about [NAME_1]'
			},
			{
				role: 'tool' as const,
				tool_call_id: 'toolu_01ABC',
				content: '{"ok":true}'
			}
		];
		await client(f.fn).complete(ben, {
			bucket: 'chat',
			tools: defs,
			names: ['Maria'],
			messages: history
		});
		const body = JSON.parse(f.calls[0]!.body) as {
			messages: { role: string; content: unknown }[];
		};
		expect(f.calls[0]!.body).not.toContain('reasoning_content');
		expect(f.calls[0]!.body).not.toContain('a thought about');
		const turns = body.messages;
		// user, assistant (text + tool_use), user (tool_result) - never a role outside these
		const roles = turns.map((m) => m.role);
		expect(roles).toEqual(['user', 'assistant', 'user']);
		const sent = turns[turns.length - 1]!;
		expect(sent.content).toEqual([
			{ type: 'tool_result', tool_use_id: 'toolu_01ABC', content: '{"ok":true}' }
		]);
		const say = turns[1] as { content: { type: string; id?: string; input?: unknown }[] };
		expect(say.content.map((b) => b.type)).toEqual(['text', 'tool_use']);
		expect(say.content[1]).toMatchObject({
			id: 'toolu_01ABC',
			name: 'log_expense',
			input: { note: 'taxi' }
		});
	});

	it('keeps a re-sent masked numeric argument valid JSON in a tool_use input', async () => {
		const f = fakeFetch(() => textAnswer('ok'));
		// An unmasked 9 digit number in the arguments of an earlier round (what deepseek final leaves behind)
		await client(f.fn).complete(ben, {
			bucket: 'chat',
			tools: defs,
			names: [],
			messages: [
				{ role: 'user', content: 'hold' },
				{
					role: 'assistant',
					content: null,
					tool_calls: [
						{
							id: 'toolu_1',
							type: 'function' as const,
							function: {
								name: 'log_expense',
								arguments: `{"account_id":"${ACCOUNT}","seq":123456789}`
							}
						}
					]
				}
			]
		});
		const body = JSON.parse(f.calls[0]!.body) as {
			messages: { role: string; content: { type: string; input?: unknown }[] }[];
		};
		// JSON.parse on the whole sent body succeeded, and the input object stayed an object
		const say = body.messages[body.messages.length - 1];
		expect(typeof say?.content[0]?.input).toBe('object');
		expect(say?.content[0]?.input).toEqual({ account_id: '[ACCT_1]', seq: 123456789 });
	});

	it('keeps the same placeholder in a re-sent tool argument, so it unmaskes back', async () => {
		const f = fakeFetch(() => textAnswer('what ? '));
		// The value the turn loop re-sends: the real name was restored into the arguments by unmaskJson
		await client(f.fn).complete(ben, {
			bucket: 'chat',
			tools: defs,
			names: ['Maria'],
			messages: [
				{ role: 'user', content: `Maria paid 500` },
				{
					role: 'assistant',
					content: null,
					tool_calls: [
						{
							id: 'toolu_2',
							type: 'function' as const,
							function: { name: 'log_expense', arguments: `{"note":"Maria's lunch"}` }
						}
					]
				}
			]
		});
		//-masked once, like the text, and never mangled into a second-pass shape
		expect(f.calls[0]!.body).toContain("[NAME_1]'s lunch");
	});

	it('unmaskes a placeholder in the reply back to the real name', async () => {
		const f = fakeFetch(
			() =>
				new Response(
					JSON.stringify({
						content: [{ type: 'text', text: `Paid [NAME_1]'s bill` }],
						stop_reason: 'end_turn',
						usage: { input_tokens: 30, output_tokens: 10 }
					}),
					{ status: 200 }
				)
		);
		const out = await client(f.fn).complete(ben, {
			bucket: 'chat',
			names: ['Maria'],
			messages: [{ role: 'user', content: 'Maria paid something' }]
		});
		//one masker built the placeholder out of Maria in this same call, and unmask knows it only in that form
		expect(out.content).toBe(`Paid Maria's bill`);
	});

	it('streams text, gathers the tool call from input_json_delta, and reports the stream usage', async () => {
		const parts = [
			sseLine({ type: 'message_start', message: { usage: { input_tokens: 30 } } }),
			sseLine({ type: 'content_block_start', index: 0, content_block: { type: 'text' } }),
			sseLine({
				type: 'content_block_delta',
				index: 0,
				delta: { type: 'text_delta', text: 'Hi [NA' }
			}),
			sseLine({
				type: 'content_block_delta',
				index: 0,
				delta: { type: 'text_delta', text: 'ME_1]!' }
			}),
			sseLine({
				type: 'content_block_start',
				index: 1,
				content_block: { type: 'tool_use', id: 'toolu_9', name: 'log_expense' }
			}),
			sseLine({
				type: 'content_block_delta',
				index: 1,
				delta: { type: 'input_json_delta', partial_json: '{"note":"tax' }
			}),
			sseLine({
				type: 'content_block_delta',
				index: 1,
				delta: { type: 'input_json_delta', partial_json: 'i [NAME_1]"}' }
			}),
			sseLine({
				type: 'message_delta',
				delta: { stop_reason: 'tool_use' },
				usage: { output_tokens: 12 }
			}),
			sseLine({ type: 'message_stop' })
		];
		const f = fakeFetch(
			() =>
				new Response(
					new ReadableStream({
						start(controller) {
							for (const part of parts) controller.enqueue(new TextEncoder().encode(part));
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
			bucket: 'chat',
			tools: defs,
			names: ['Maria'],
			messages: [{ role: 'user', content: 'Hello Maria' }]
		})) {
			if (ev.type === 'delta') text += ev.text;
			else if (ev.type === 'done') done = ev.completion;
		}
		expect(JSON.parse(f.calls[0]!.body).stream).toBe(true);
		expect(text).toBe('Hi Maria!');
		expect(done?.finishReason).toBe('tool_calls');
		expect(done?.toolCalls[0]?.function.arguments).toBe('{"note":"taxi Maria"}');
		// Reported, not the estimate
		expect(done?.usage).toMatchObject({ promptTokens: 30, completionTokens: 12 });
	});

	it('shows the streamed thinking when ANTHROPIC_THINKING is on, and offers no tools while it thinks', async () => {
		const parts = [
			sseLine({ type: 'message_start', message: { usage: { input_tokens: 30 } } }),
			sseLine({ type: 'content_block_start', index: 0, content_block: { type: 'thinking' } }),
			sseLine({
				type: 'content_block_delta',
				index: 0,
				delta: { type: 'thinking_delta', thinking: ' think [NA' }
			}),
			sseLine({
				type: 'content_block_delta',
				index: 0,
				delta: { type: 'thinking_delta', thinking: 'ME_1] hard' }
			}),
			sseLine({ type: 'content_block_start', index: 1, content_block: { type: 'text' } }),
			sseLine({
				type: 'content_block_delta',
				index: 1,
				delta: { type: 'text_delta', text: 'So: done.' }
			}),
			sseLine({
				type: 'message_delta',
				delta: { stop_reason: 'end_turn' },
				usage: { output_tokens: 40 }
			}),
			sseLine({ type: 'message_stop' })
		];
		const f = fakeFetch(
			() =>
				new Response(
					new ReadableStream({
						start(controller) {
							for (const part of parts) controller.enqueue(new TextEncoder().encode(part));
							controller.close();
						}
					}),
					{ status: 200 }
				)
		);
		const c = client(f.fn, {}, { thinking: true });
		let thought = '';
		let text = '';
		let done;
		for await (const ev of c.stream(ben, {
			bucket: 'chat',
			tools: defs,
			names: ['Maria'],
			messages: [{ role: 'user', content: 'Hello Maria' }]
		})) {
			if (ev.type === 'reasoning') thought += ev.text;
			else if (ev.type === 'delta') text += ev.text;
			else if (ev.type === 'done') done = ev.completion;
		}
		const body = JSON.parse(f.calls[0]!.body) as {
			thinking?: unknown;
			tools?: unknown;
			max_tokens: number;
		};
		expect(body.thinking).toBeTruthy();
		// A thinking answer carries no tools in this build: the signed block cannot go back
		expect(body.tools).toBeUndefined();
		// The thinking ceiling applies
		expect(body.max_tokens).toBe(8192);
		expect(f.calls[0]!.body).not.toContain('reasoning_content');
		expect(thought).toBe(' think Maria hard');
		expect(text).toBe('So: done.');
		expect(done?.finishReason).toBe('stop');
		expect(done?.usage).toMatchObject({ promptTokens: 30, completionTokens: 40 });
	});

	it('logs counts only, never the message text or the key', async () => {
		const info = vi.spyOn(console, 'info').mockImplementation(() => undefined);
		const f = fakeFetch(() => textAnswer('a private reply'));
		await client(f.fn).complete(ben, {
			bucket: 'memory',
			messages: [
				{ role: 'system', content: `secret ${KEY}` },
				{ role: 'user', content: 'private rent note' }
			]
		});
		const logged = info.mock.calls.flat().join(' ');
		expect(logged).toContain('model_call');
		expect(logged).not.toContain('private');
		expect(logged).not.toContain('rent');
		expect(logged).not.toContain(KEY.slice(-6));
	});
});
