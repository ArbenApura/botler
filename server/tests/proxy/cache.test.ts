// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { modelSpend, modelUsage, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createAnthropicClient } from '../../src/lib/server/proxy/anthropic';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import {
	CACHE_WEIGHTS,
	chargedTokens,
	DEFAULT_LIMITS,
	monthKey,
	recordUsage
} from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const BAR = '｜';
const WRITTEN_CALL = `<${BAR}DSML${BAR}function_calls><${BAR}DSML${BAR}invoke name="a_tool"></${BAR}DSML${BAR}invoke></${BAR}DSML${BAR}function_calls>`;

const big = 'x'.repeat(4000);
const defs = [
	{
		type: 'function' as const,
		function: { name: 'a_tool', description: big, parameters: { type: 'object', properties: {} } }
	},
	{
		type: 'function' as const,
		function: { name: 'b_tool', description: big, parameters: { type: 'object', properties: {} } }
	}
];
const system = { role: 'system' as const, content: `You are Botler. ${big}` };
const history = [
	{ role: 'user' as const, content: 'first question' },
	{ role: 'assistant' as const, content: 'first answer' }
];
const volatile = (clock: string) => ({
	role: 'user' as const,
	content: `<context>\nNow is ${clock}\n</context>\n\nnext question`
});

const anthropicAnswer = (usage: Record<string, number>) =>
	new Response(
		JSON.stringify({ content: [{ type: 'text', text: 'ok' }], stop_reason: 'end_turn', usage }),
		{ status: 200 }
	);
const deepseekAnswer = (usage: Record<string, number>) =>
	new Response(
		JSON.stringify({
			choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }],
			usage
		}),
		{ status: 200 }
	);

// -- STATES -- //

let t: TestDb;
let anna: Ctx;
let ben: Ctx;

type Sent = {
	system?: { text: string; cache_control?: { type: string; ttl?: string } }[];
	tools?: { name: string; cache_control?: { type: string; ttl?: string } }[];
	tool_choice?: unknown;
	messages: { role: string; content: { type: string; cache_control?: unknown }[] }[];
};

function fake(script: () => Response) {
	const bodies: string[] = [];
	const fn = (async (_url: string, init: RequestInit) => {
		bodies.push(String(init.body));
		return script();
	}) as unknown as typeof fetch;
	return { fn, bodies };
}

const anthropic = (f: typeof fetch, extra: Record<string, unknown> = {}) =>
	createAnthropicClient({
		apiKey: 'k',
		baseUrl: 'https://model.test',
		model: 'claude-haiku-5-5',
		limits: DEFAULT_LIMITS,
		fetch: f,
		sleep: async () => undefined,
		...extra
	});

const deepseek = (f: typeof fetch) =>
	createModelClient({
		apiKey: 'k',
		baseUrl: 'https://model.test',
		model: 'deepseek-flash',
		limits: DEFAULT_LIMITS,
		fetch: f,
		sleep: async () => undefined
	});

/** Every cache_control marker in a body, as a label in wire order. */
function markers(body: Sent): string[] {
	const out: string[] = [];
	body.tools?.forEach((tool, i) => tool.cache_control && out.push(`tool${i}`));
	body.system?.forEach((b, i) => b.cache_control && out.push(`system${i}`));
	body.messages.forEach((m, i) =>
		m.content.forEach((b, j) => b.cache_control && out.push(`message${i}.${j}`))
	);
	return out;
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_cach_anna', name: 'Anna', email: 'cache-anna@example.com' },
		{ id: 'user_cach_ben0', name: 'Ben', email: 'cache-ben@example.com' }
	]);
	anna = { handle: t.handle, actor: { userId: 'user_cach_anna', kind: 'person' } };
	ben = { handle: t.handle, actor: { userId: 'user_cach_ben0', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('anthropic cache markers', () => {
	const chat = (clock: string, extra: Record<string, unknown> = {}) => ({
		bucket: 'chat' as const,
		messages: [system, ...history, volatile(clock)],
		tools: defs,
		stableCount: 1 + history.length,
		...extra
	});

	it('marks the last tool, the stable system block, the end of the history and the last block, in order', async () => {
		const f = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		await anthropic(f.fn).complete(anna, chat('10:00'));
		const body = JSON.parse(f.bodies[0]!) as Sent;
		expect(markers(body)).toEqual(['tool1', 'system0', 'message1.0', 'message2.0']);
		expect(Array.isArray(body.system)).toBe(true);
		expect(body.tool_choice).toBeUndefined();
	});

	it('sends an identical bytes prefix up to the history on two calls with different clocks', async () => {
		const f = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		const c = anthropic(f.fn);
		await c.complete(anna, chat('10:00'));
		await c.complete(anna, chat('10:01'));
		const [a, b] = f.bodies.map((s) => JSON.parse(s) as Sent);
		const prefix = (x: Sent) =>
			JSON.stringify({ tools: x.tools, system: x.system, m: x.messages.slice(0, 2) });
		expect(prefix(a!)).toBe(prefix(b!));
		expect(JSON.stringify(a!.messages[2])).not.toBe(JSON.stringify(b!.messages[2]));
	});

	it('uses the 1h lifetime only on the tool and system markers', async () => {
		const f = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		await anthropic(f.fn, { cacheTtl: '1h' }).complete(anna, chat('10:00'));
		const body = JSON.parse(f.bodies[0]!) as Sent;
		expect(body.tools?.[1]?.cache_control?.ttl).toBe('1h');
		expect(body.system?.[0]?.cache_control?.ttl).toBe('1h');
		expect(body.messages[1]?.content[0]?.cache_control).toEqual({ type: 'ephemeral' });
		expect(body.messages[2]?.content[0]?.cache_control).toEqual({ type: 'ephemeral' });
	});

	it('sends no marker under the model minimum, and none on a request without a stable prefix', async () => {
		const f = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		const c = anthropic(f.fn);
		await c.complete(anna, {
			bucket: 'chat',
			messages: [
				{ role: 'system', content: 'short' },
				{ role: 'user', content: 'hi' }
			],
			stableCount: 1
		});
		await c.complete(anna, {
			bucket: 'memory',
			messages: [system, volatile('10:00')],
			tools: defs
		});
		for (const raw of f.bodies) expect(markers(JSON.parse(raw) as Sent)).toEqual([]);
	});

	it('gives the first turn of a chat no history marker and no duplicate', async () => {
		const f = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		await anthropic(f.fn).complete(anna, {
			bucket: 'chat',
			messages: [system, volatile('10:00')],
			tools: defs,
			stableCount: 1
		});
		expect(markers(JSON.parse(f.bodies[0]!) as Sent)).toEqual(['tool1', 'system0', 'message0.0']);
	});

	it('keeps the tools and sends tool_choice none, but never tool_choice without tools', async () => {
		const f = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		await anthropic(f.fn).complete(anna, chat('10:00', { toolChoice: 'none' }));
		const body = JSON.parse(f.bodies[0]!) as Sent;
		expect(body.tools).toHaveLength(2);
		expect(body.tool_choice).toEqual({ type: 'none' });
		const g = fake(() => anthropicAnswer({ input_tokens: 10, output_tokens: 1 }));
		await anthropic(g.fn).complete(anna, {
			bucket: 'chat',
			messages: [system, volatile('10:00')],
			toolChoice: 'none'
		});
		expect((JSON.parse(g.bodies[0]!) as Sent).tool_choice).toBeUndefined();
	});

	it('records a full cache hit from the reported fields, not the estimate', async () => {
		const f = fake(() =>
			anthropicAnswer({
				input_tokens: 0,
				cache_read_input_tokens: 12000,
				cache_creation_input_tokens: 0,
				output_tokens: 7
			})
		);
		const out = await anthropic(f.fn).complete(anna, chat('10:00'));
		expect(out.usage).toMatchObject({
			promptTokens: 12000,
			completionTokens: 7,
			cacheReadTokens: 12000,
			cacheWriteTokens: 0
		});
	});

	it('keeps the cache figures from message_start when a later message_delta repeats only some of them', async () => {
		const line = (o: unknown) => `data: ${JSON.stringify(o)}

`;
		const f = fake(
			() =>
				new Response(
					line({
						type: 'message_start',
						message: {
							usage: {
								input_tokens: 40,
								cache_read_input_tokens: 9000,
								cache_creation_input_tokens: 500
							}
						}
					}) +
						line({
							type: 'content_block_start',
							index: 0,
							content_block: { type: 'text', text: '' }
						}) +
						line({
							type: 'content_block_delta',
							index: 0,
							delta: { type: 'text_delta', text: 'ok' }
						}) +
						line({
							type: 'message_delta',
							delta: { stop_reason: 'end_turn' },
							usage: { input_tokens: 40, output_tokens: 80 }
						}) +
						line({ type: 'message_stop' }),
					{ status: 200 }
				)
		);
		let usage;
		for await (const ev of anthropic(f.fn).stream(anna, chat('10:00')))
			if (ev.type === 'done') usage = ev.completion.usage;
		expect(usage).toMatchObject({
			promptTokens: 9540,
			completionTokens: 80,
			cacheReadTokens: 9000,
			cacheWriteTokens: 500
		});
	});

	it('logs counts only on the model_call line', async () => {
		const spy = vi.spyOn(console, 'info').mockImplementation(() => undefined);
		const f = fake(() =>
			anthropicAnswer({ input_tokens: 100, cache_read_input_tokens: 900, output_tokens: 5 })
		);
		await anthropic(f.fn).complete(anna, chat('10:00', { toolChoice: 'none' }));
		const line = String(spy.mock.calls.at(-1)?.[0]);
		spy.mockRestore();
		const parsed = JSON.parse(line) as Record<string, unknown>;
		expect(parsed).toMatchObject({
			event: 'model_call',
			provider: 'anthropic',
			model: 'claude-haiku-5-5',
			cacheRead: 900,
			cacheWrite: 0,
			miss: 100,
			charged: 100 + 5 + 90,
			toolsOff: true
		});
		expect(Number(parsed.stableTokens)).toBeGreaterThan(1000);
		expect(line).not.toContain('next question');
		expect(line).not.toContain('first answer');
	});
});

describe('after the tool limit (toolChoice none)', () => {
	const req = {
		bucket: 'chat' as const,
		messages: [system, volatile('10:00')],
		tools: defs,
		stableCount: 1,
		toolChoice: 'none' as const
	};

	it('strips a call written as text and runs nothing, on Anthropic', async () => {
		const f = fake(
			() =>
				new Response(
					JSON.stringify({
						content: [{ type: 'text', text: `Done. ${WRITTEN_CALL}` }],
						stop_reason: 'end_turn',
						usage: { input_tokens: 10, output_tokens: 1 }
					}),
					{ status: 200 }
				)
		);
		const out = await anthropic(f.fn).complete(anna, req);
		expect(out.toolCalls).toEqual([]);
		expect(out.content).not.toContain('DSML');
		expect(out.finishReason).toBe('stop');
	});

	it('strips a call written as text and runs nothing, on DeepSeek', async () => {
		const f = fake(
			() =>
				new Response(
					JSON.stringify({
						choices: [{ message: { content: `Done. ${WRITTEN_CALL}` }, finish_reason: 'stop' }],
						usage: { prompt_tokens: 10, completion_tokens: 1 }
					}),
					{ status: 200 }
				)
		);
		const out = await deepseek(f.fn).complete(anna, req);
		expect(out.toolCalls).toEqual([]);
		expect(out.content).not.toContain('DSML');
	});
});

describe('deepseek caching', () => {
	it('sends no cache_control, keeps the order and the tools, and reads hit and miss tokens', async () => {
		const f = fake(() =>
			deepseekAnswer({
				prompt_tokens: 1000,
				completion_tokens: 5,
				prompt_cache_hit_tokens: 800,
				prompt_cache_miss_tokens: 200
			})
		);
		const c = deepseek(f.fn);
		const req = {
			bucket: 'chat' as const,
			messages: [system, ...history, volatile('10:00')],
			tools: defs,
			stableCount: 3
		};
		const out = await c.complete(anna, req);
		await c.complete(anna, { ...req, messages: [system, ...history, volatile('10:01')] });
		expect(f.bodies[0]).not.toContain('cache_control');
		const [a, b] = f.bodies.map(
			(s) => JSON.parse(s) as { messages: { role: string }[]; tools: unknown }
		);
		expect(a!.messages.map((m) => m.role)).toEqual(['system', 'user', 'assistant', 'user']);
		expect(JSON.stringify(a!.tools)).toBe(JSON.stringify(b!.tools));
		expect(out.usage).toEqual({
			promptTokens: 1000,
			completionTokens: 5,
			cacheReadTokens: 800,
			cacheWriteTokens: 0
		});
	});

	it('sends tool_choice none with the tools when asked', async () => {
		const f = fake(() => deepseekAnswer({ prompt_tokens: 10, completion_tokens: 1 }));
		await deepseek(f.fn).complete(anna, {
			bucket: 'chat',
			messages: [system, volatile('10:00')],
			tools: defs,
			toolChoice: 'none'
		});
		const body = JSON.parse(f.bodies[0]!) as { tools: unknown[]; tool_choice?: string };
		expect(body.tools).toHaveLength(2);
		expect(body.tool_choice).toBe('none');
	});

	it('records zero cache read when the reply carries no cache fields', async () => {
		const f = fake(() => deepseekAnswer({ prompt_tokens: 10, completion_tokens: 1 }));
		const out = await deepseek(f.fn).complete(anna, {
			bucket: 'memory',
			messages: [{ role: 'user', content: 'hi' }]
		});
		expect(out.usage.cacheReadTokens).toBe(0);
	});
});

describe('charged tokens and the cap', () => {
	it('weights a cache read and write per provider and rounds up', () => {
		const u = {
			promptTokens: 13000,
			completionTokens: 100,
			cacheReadTokens: 12000,
			cacheWriteTokens: 0
		};
		// 1000 uncached + 100 output + 12000 read at 10 percent (Anthropic) or 2 percent (DeepSeek)
		expect(chargedTokens(u, 'anthropic')).toBe(1000 + 100 + 1200);
		expect(chargedTokens(u, 'deepseek')).toBe(1000 + 100 + 240);
		expect(
			chargedTokens(
				{ promptTokens: 1000, completionTokens: 0, cacheWriteTokens: 1000 },
				'anthropic'
			)
		).toBe(1250);
		expect(
			chargedTokens({ promptTokens: 7, completionTokens: 0, cacheReadTokens: 7 }, 'anthropic')
		).toBe(1);
		expect(chargedTokens({ promptTokens: 50, completionTokens: 10 }, 'deepseek')).toBe(60);
		expect(chargedTokens(u, 'unknown')).toBe(13100);
		expect(CACHE_WEIGHTS.anthropic.read).toBe(10);
	});

	it('weights the 1 hour part of a cache write at twice the input price', () => {
		const u = {
			promptTokens: 1000,
			completionTokens: 0,
			cacheWriteTokens: 1000,
			cacheWrite1hTokens: 600
		};
		// 400 at 125 percent and 600 at 200 percent
		expect(chargedTokens(u, 'anthropic')).toBe(500 + 1200);
	});

	it('stores the raw breakdown and keeps one row per provider', async () => {
		const month = monthKey();
		await withUser(t.handle, 'user_cach_ben0', async (tx) => {
			await recordUsage(
				tx,
				'user_cach_ben0',
				'chat',
				{ promptTokens: 13000, completionTokens: 100, cacheReadTokens: 12000 },
				'anthropic'
			);
			await recordUsage(
				tx,
				'user_cach_ben0',
				'chat',
				{ promptTokens: 500, completionTokens: 50 },
				'deepseek'
			);
			await recordUsage(tx, 'user_cach_ben0', 'chat', { promptTokens: 100, completionTokens: 0 });
		});
		const rows = await withUser(t.handle, 'user_cach_ben0', (tx) =>
			tx.select().from(modelUsage).where(eq(modelUsage.month, month))
		);
		expect(rows.find((r) => r.provider === 'anthropic')).toMatchObject({
			promptTokens: 13000,
			cacheReadTokens: 12000,
			chargedTokens: 2300
		});
		expect(rows.find((r) => r.provider === 'deepseek')?.chargedTokens).toBe(550);
		// A row with provider unknown (the old rows) counts in full
		expect(rows.find((r) => r.provider === 'unknown')?.chargedTokens).toBe(100);
		const spend = await t.handle.db.select().from(modelSpend).where(eq(modelSpend.month, month));
		expect(spend.map((s) => s.provider)).toEqual(
			expect.arrayContaining(['anthropic', 'deepseek', 'unknown'])
		);
	});

	it('refuses at the cap using the sum over providers, and logs why', async () => {
		const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
		const f = fake(() => deepseekAnswer({ prompt_tokens: 10, completion_tokens: 1 }));
		const c = createModelClient({
			apiKey: 'k',
			baseUrl: 'https://model.test',
			model: 'deepseek-flash',
			limits: { ...DEFAULT_LIMITS, chatTokenCap: 2900 },
			fetch: f.fn,
			sleep: async () => undefined
		});
		// Ben holds 2300 + 550 + 100 = 2950 charged tokens across three providers
		await expect(
			c.complete(ben, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] })
		).rejects.toMatchObject({ code: 'LIMIT' });
		const lines = warn.mock.calls.map((x) => JSON.parse(String(x[0])) as Record<string, unknown>);
		warn.mockRestore();
		expect(lines.at(-1)).toMatchObject({
			event: 'model_call_refused',
			reason: 'person_cap',
			bucket: 'chat',
			used: 2950,
			cap: 2900
		});
		expect(f.bodies).toHaveLength(0);
	});
});
