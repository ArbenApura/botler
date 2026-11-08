// THE CHAT ROUTE: THE STREAM BEGINS AT ONCE, NOTHING COMPRESSES IT, A PING KEEPS IT ALIVE, AND NO TIMER OUTLIVES IT.
// A message the server refuses (a reused id for other words) is an ordinary HTTP error, sent before the stream starts.

// -- TYPES -- //
import type { Fixture } from './support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { createTestDb } from '../support/testDb';
import { seedPerson, stubModel } from './support';

// -- STATES -- //

let t: TestDb;
let f: Fixture;
let model = stubModel([{ say: 'hi' }]);

// -- LIFECYCLES -- //

vi.mock('../../src/lib/server/db', () => ({ getDb: async () => t.handle }));
vi.mock('../../src/lib/server/proxy/index', () => ({
	getModelClient: () => model,
	getProviderOf: () => async () => 'deepseek'
}));

beforeAll(async () => {
	t = await createTestDb();
	f = await seedPerson(t);
});

afterAll(async () => {
	await t.close();
});

afterEach(() => {
	vi.useRealTimers();
});

// -- FUNCTIONS -- //

let n = 0;

async function post(id: string, text: string, signal?: AbortSignal) {
	const { POST } = await import('../../src/routes/api/v1/agent/chat/+server');
	const request = new Request('http://botler.test/api/v1/agent/chat', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ clientMessageId: id, text }),
		signal
	});
	return POST({ locals: { user: { id: f.userId } }, request } as never);
}

// -- TESTS -- //

describe('chat route', () => {
	it('starts the stream with a start event and forbids compression and caching', async () => {
		model = stubModel([{ say: 'hi' }]);
		const res = await post(`client-route-${++n}-aaaa`, 'hello');
		expect(res.status).toBe(200);
		expect(res.headers.get('content-type')).toBe('text/event-stream');
		expect(res.headers.get('content-encoding')).toBe('identity');
		expect(res.headers.get('cache-control')).toContain('no-transform');
		const body = await res.text();
		expect(body.startsWith('data: {"type":"start"')).toBe(true);
		// The app learns which message and chat this is
		expect(body).toMatch(
			/^data: \{"type":"start","turnId":"[0-9a-f-]{36}","chatId":"[0-9a-f-]{36}"\}/
		);
		expect(body).toContain('"type":"done"');
	});

	it('answers a reused id for other words with an HTTP error, not a stream', async () => {
		model = stubModel([{ say: 'hi' }]);
		const id = `client-route-${++n}-bbbb`;
		await (await post(id, 'first words')).text();
		const res = await post(id, 'different words');
		expect(res.status).toBe(409);
		expect(res.headers.get('content-type')).not.toContain('text/event-stream');
	});

	it('pings while the model is slow, and no timer is left after a cancel', async () => {
		vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });
		let release: () => void = () => undefined;
		const gate = new Promise<void>((r) => (release = r));
		model = {
			requests: [],
			helperRequests: [],
			async *stream() {
				await gate;
				yield { type: 'delta', text: 'late' };
				yield {
					type: 'done',
					completion: {
						content: 'late',
						toolCalls: [],
						finishReason: 'stop',
						usage: { promptTokens: 1, completionTokens: 1 }
					}
				};
			}
		};
		const res = await post(`client-route-${++n}-cccc`, 'slow one');
		const reader = res.body!.getReader();
		const first = new TextDecoder().decode((await reader.read()).value);
		expect(first).toContain('"type":"start"');
		await vi.advanceTimersByTimeAsync(10_000);
		const second = new TextDecoder().decode((await reader.read()).value);
		expect(second).toContain(': ping');
		await reader.cancel();
		expect(vi.getTimerCount()).toBe(0);
		release();
	});
});
