// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { modelSpend, modelUsage, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
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

function fake(script: () => Response) {
	const bodies: string[] = [];
	const fn = (async (_url: string, init: RequestInit) => {
		bodies.push(String(init.body));
		return script();
	}) as unknown as typeof fetch;
	return { fn, bodies };
}

const deepseek = (f: typeof fetch) =>
	createModelClient({
		apiKey: 'k',
		baseUrl: 'https://model.test',
		model: 'deepseek-flash',
		limits: DEFAULT_LIMITS,
		fetch: f,
		sleep: async () => undefined
	});

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

describe('after the tool limit (toolChoice none)', () => {
	const req = {
		bucket: 'chat' as const,
		messages: [system, volatile('10:00')],
		tools: defs,
		stableCount: 1,
		toolChoice: 'none' as const
	};

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
	// A host that charges for cache writes, so the write weights stay tested while DeepSeek is the only host
	const WRITING = { deepseek: { read: 10, write: 125, write1h: 200 } };

	it('weights a cache read per provider and rounds up', () => {
		const u = {
			promptTokens: 13000,
			completionTokens: 100,
			cacheReadTokens: 12000,
			cacheWriteTokens: 0
		};
		// 1000 uncached + 100 output + 12000 read at 2 percent (DeepSeek)
		expect(chargedTokens(u, 'deepseek')).toBe(1000 + 100 + 240);
		expect(chargedTokens(u, 'deepseek', WRITING)).toBe(1000 + 100 + 1200);
		expect(
			chargedTokens(
				{ promptTokens: 1000, completionTokens: 0, cacheWriteTokens: 1000 },
				'deepseek',
				WRITING
			)
		).toBe(1250);
		expect(
			chargedTokens(
				{ promptTokens: 7, completionTokens: 0, cacheReadTokens: 7 },
				'deepseek',
				WRITING
			)
		).toBe(1);
		expect(chargedTokens({ promptTokens: 50, completionTokens: 10 }, 'deepseek')).toBe(60);
		expect(chargedTokens(u, 'unknown')).toBe(13100);
		expect(CACHE_WEIGHTS.deepseek.read).toBe(2);
	});

	it('weights the 1 hour part of a cache write at twice the input price', () => {
		const u = {
			promptTokens: 1000,
			completionTokens: 0,
			cacheWriteTokens: 1000,
			cacheWrite1hTokens: 600
		};
		// 400 at 125 percent and 600 at 200 percent
		expect(chargedTokens(u, 'deepseek', WRITING)).toBe(500 + 1200);
	});

	it('stores the raw breakdown and keeps one row per provider', async () => {
		const month = monthKey();
		await withUser(t.handle, 'user_cach_ben0', async (tx) => {
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
		expect(rows.find((r) => r.provider === 'deepseek')?.chargedTokens).toBe(550);
		// A row with provider unknown (the old rows) counts in full
		expect(rows.find((r) => r.provider === 'unknown')?.chargedTokens).toBe(100);
		const spend = await t.handle.db.select().from(modelSpend).where(eq(modelSpend.month, month));
		expect(spend.map((s) => s.provider)).toEqual(expect.arrayContaining(['deepseek', 'unknown']));
	});

	it('refuses at the cap using the sum over providers, and logs why', async () => {
		const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
		const f = fake(() => deepseekAnswer({ prompt_tokens: 10, completion_tokens: 1 }));
		const c = createModelClient({
			apiKey: 'k',
			baseUrl: 'https://model.test',
			model: 'deepseek-flash',
			limits: { ...DEFAULT_LIMITS, chatTokenCap: 600 },
			fetch: f.fn,
			sleep: async () => undefined
		});
		// Ben holds 550 + 100 = 650 charged tokens across two provider rows
		await expect(
			c.complete(ben, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] })
		).rejects.toMatchObject({ code: 'LIMIT' });
		const lines = warn.mock.calls.map((x) => JSON.parse(String(x[0])) as Record<string, unknown>);
		warn.mockRestore();
		expect(lines.at(-1)).toMatchObject({
			event: 'model_call_refused',
			reason: 'person_cap',
			bucket: 'chat',
			used: 650,
			cap: 600
		});
		expect(f.bodies).toHaveLength(0);
	});
});
