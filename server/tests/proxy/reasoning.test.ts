// THE MODEL'S THINKING: PARSED FROM THE STREAM, UNMASKED FOR THE SCREEN, SENT BACK MASKED, AND ONLY ASKED FOR ON A STREAMED CHAT ANSWER

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { ModelConfig } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { createMasker } from '../../src/lib/server/proxy/mask';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const sse = (obj: unknown) => `data: ${JSON.stringify(obj)}\n\n`;

// -- STATES -- //

const sharedMasker = createMasker(['Maria']);

let t: TestDb;
let cara: Ctx;

// -- FUNCTIONS -- //

function streamOf(parts: string[]) {
	return new Response(
		new ReadableStream({
			start(controller) {
				for (const p of parts) controller.enqueue(new TextEncoder().encode(p));
				controller.close();
			}
		}),
		{ status: 200 }
	);
}

function setup(parts: string[], extra: Partial<ModelConfig> = {}) {
	const bodies: Record<string, unknown>[] = [];
	const fn = (async (_url: string, init: RequestInit) => {
		bodies.push(JSON.parse(String(init.body)) as Record<string, unknown>);
		return streamOf(parts);
	}) as unknown as typeof fetch;
	const client = createModelClient({
		apiKey: 'sk-test-secret-key-0000',
		baseUrl: 'https://model.test',
		model: 'test-model',
		limits: DEFAULT_LIMITS,
		fetch: fn,
		sleep: async () => undefined,
		...extra
	});
	return { client, bodies };
}

const PARTS = [
	sse({ choices: [{ delta: { reasoning_content: 'Maria wants [NA' } }] }),
	sse({ choices: [{ delta: { reasoning_content: 'ME_1] paid.' } }] }),
	sse({ choices: [{ delta: { content: 'Done, ' } }] }),
	sse({ choices: [{ delta: { content: 'Maria.' }, finish_reason: 'stop' }] }),
	sse({ choices: [], usage: { prompt_tokens: 30, completion_tokens: 12 } }),
	'data: [DONE]\n\n'
];

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values({ id: 'user_cara_0001', name: 'Cara', email: 'cara@example.com' });
	cara = { handle: t.handle, actor: { userId: 'user_cara_0001', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('streamed thinking', () => {
	it('yields the thinking before the answer, unmasked, and keeps the raw masked copy', async () => {
		const { client } = setup(PARTS, { thinking: true });
		let thought = '';
		let answer = '';
		const order: string[] = [];
		let done;
		for await (const ev of client.stream(cara, {
			bucket: 'chat',
			names: ['Maria'],
			messages: [{ role: 'user', content: 'Did Maria pay?' }]
		})) {
			if (ev.type === 'reasoning') {
				thought += ev.text;
				order.push('r');
			} else if (ev.type === 'delta') {
				answer += ev.text;
				order.push('d');
			} else done = ev.completion;
		}
		expect(thought).toBe('Maria wants Maria paid.');
		expect(answer).toBe('Done, Maria.');
		expect(order.indexOf('d')).toBeGreaterThan(order.lastIndexOf('r'));
		// Kept like the content (real values restored); maskMessages masks it again on its way back out
		expect(done?.reasoningRaw).toBe('Maria wants Maria paid.');
		expect(done?.content).toBe('Done, Maria.');
	});

	it('asks for thinking only on a streamed chat answer, with room for it and no temperature', async () => {
		const on = setup(PARTS, { thinking: true });
		for await (const _ of on.client.stream(cara, {
			bucket: 'chat',
			temperature: 0.2,
			messages: [{ role: 'user', content: 'hi' }]
		}));
		expect(on.bodies[0]?.thinking).toEqual({ type: 'enabled' });
		expect(on.bodies[0]?.max_tokens).toBe(8192);
		expect(on.bodies[0]).not.toHaveProperty('temperature');

		const memory = setup(PARTS, { thinking: true });
		for await (const _ of memory.client.stream(cara, {
			bucket: 'memory',
			messages: [{ role: 'user', content: 'hi' }]
		}));
		expect(memory.bodies[0]).not.toHaveProperty('thinking');
		expect(memory.bodies[0]?.max_tokens).toBe(2048);
	});

	it('with thinking off the request is as it was', async () => {
		const off = setup(PARTS, { thinking: false });
		for await (const _ of off.client.stream(cara, {
			bucket: 'chat',
			temperature: 0.2,
			messages: [{ role: 'user', content: 'hi' }]
		}));
		expect(off.bodies[0]).not.toHaveProperty('thinking');
		expect(off.bodies[0]?.temperature).toBe(0.2);
		expect(off.bodies[0]?.max_tokens).toBe(8192);
	});

	it('masks the thinking when it goes back to the model', async () => {
		const { client, bodies } = setup(PARTS, { thinking: true });
		for await (const _ of client.stream(cara, {
			bucket: 'chat',
			names: ['Maria'],
			messages: [
				{ role: 'user', content: 'Did Maria pay?' },
				{
					role: 'assistant',
					content: null,
					// A name that slipped in unmasked must still not leave the server
					reasoning_content: 'Maria paid from account 1234567890123',
					tool_calls: []
				},
				{ role: 'user', content: 'ok' }
			]
		}));
		const sent = JSON.stringify(bodies[0]);
		expect(sent).not.toContain('Maria');
		expect(sent).not.toContain('1234567890123');
	});

	it('sends the thinking back with the same placeholders it was given, not altered ones', async () => {
		const { client, bodies } = setup(PARTS, { thinking: true });
		await (async () => {
			const first = [{ role: 'user' as const, content: 'Did Maria pay?' }];
			let completion;
			for await (const ev of client.stream(cara, {
				bucket: 'chat',
				names: ['Maria'],
				masker: sharedMasker,
				messages: first
			}))
				if (ev.type === 'done') completion = ev.completion;
			for await (const _ of client.stream(cara, {
				bucket: 'chat',
				names: ['Maria'],
				masker: sharedMasker,
				messages: [
					...first,
					{
						role: 'assistant',
						content: null,
						reasoning_content: completion?.reasoningRaw,
						tool_calls: []
					},
					{ role: 'user', content: 'ok' }
				]
			}));
		})();
		const second = JSON.stringify(bodies[1]);
		expect(second).toContain('[NAME_1] paid');
		expect(second).not.toContain('[NAME-1]');
		expect(second).not.toContain('Maria');
	});

	it('counts the thinking in the usage estimate when the stream gives no usage', async () => {
		const noUsage = PARTS.filter((p) => !p.includes('usage'));
		const { client } = setup(noUsage, { thinking: true });
		let done;
		for await (const ev of client.stream(cara, {
			bucket: 'chat',
			messages: [{ role: 'user', content: 'hi' }]
		}))
			if (ev.type === 'done') done = ev.completion;
		// "Maria wants [NAME_1] paid." plus "Done, Maria." is 39 characters, about 10 tokens
		expect(done?.usage.completionTokens).toBeGreaterThanOrEqual(10);
	});
});
