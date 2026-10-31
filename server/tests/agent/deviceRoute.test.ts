// THE DEVICE-RESULT ROUTE (BTL-20261031-1334): THE PHONE ANSWERS A CALL THE CHAT STREAM ANNOUNCED, AND ONLY THE PERSON IT WAS MADE FOR CAN

// -- TYPES -- //
import type { Fixture } from './support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { createTestDb } from '../support/testDb';
import { seedPerson, stubModel } from './support';

// -- STATES -- //

let t: TestDb;
let f: Fixture;
let other: Fixture;
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
	other = await seedPerson(t);
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

async function chat(userId: string, id: string, scripts: boolean) {
	const { POST } = await import('../../src/routes/api/v1/agent/chat/+server');
	const request = new Request('http://botler.test/api/v1/agent/chat', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ clientMessageId: id, text: 'add 6 times 7', scripts })
	});
	return POST({ locals: { user: { id: userId } }, request } as never);
}

async function answer(userId: string, body: unknown) {
	const { POST } = await import('../../src/routes/api/v1/agent/device-result/+server');
	const request = new Request('http://botler.test/api/v1/agent/device-result', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	return POST({ locals: { user: { id: userId } }, request } as never);
}

/** Reads the stream event by event; calls [onEvent] for each and returns every event once it ends. */
async function readEvents(
	res: Response,
	onEvent: (e: Record<string, unknown>) => Promise<void>
): Promise<Record<string, unknown>[]> {
	const reader = res.body!.getReader();
	const dec = new TextDecoder();
	const all: Record<string, unknown>[] = [];
	let buf = '';
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		buf += dec.decode(value, { stream: true });
		let at: number;
		while ((at = buf.indexOf('\n\n')) !== -1) {
			const chunk = buf.slice(0, at);
			buf = buf.slice(at + 2);
			if (!chunk.startsWith('data: ')) continue;
			const e = JSON.parse(chunk.slice(6)) as Record<string, unknown>;
			all.push(e);
			await onEvent(e);
		}
	}
	return all;
}

// -- TESTS -- //

describe('device-result route', () => {
	it('completes a script call announced in the chat stream', async () => {
		model = stubModel([{ calls: [['script_run', { code: 'print(42)' }]] }, { say: 'It is 42.' }]);
		const res = await chat(f.userId, 'client-device-1111', true);
		let accepted: unknown;
		const events = await readEvents(res, async (e) => {
			if (e.type === 'tool_start' && e.device) {
				const device = e.device as { callId: string; args: Record<string, unknown> };
				expect(device.args).toEqual({ code: 'print(42)' });
				const r = await answer(f.userId, {
					callId: device.callId,
					ok: true,
					result: { ok: true, output: '42' }
				});
				accepted = ((await r.json()) as { accepted: boolean }).accepted;
			}
		});
		expect(accepted).toBe(true);
		const tool = events.find((e) => e.type === 'tool');
		expect(tool).toMatchObject({ name: 'script_run', status: 'ok' });
		expect(events.at(-1)).toMatchObject({ type: 'done', reply: 'It is 42.' });
	});

	it('does not offer the phone tools to an app that did not ask for them', async () => {
		model = stubModel([{ calls: [['script_run', { code: 'print(1)' }]] }, { say: 'no' }]);
		const res = await chat(f.userId, 'client-device-2222', false);
		const events = await readEvents(res, async () => undefined);
		expect(events.some((e) => e.type === 'tool_start' && e.device)).toBe(false);
		expect(events.find((e) => e.type === 'tool')).toMatchObject({ status: 'error' });
	});

	it("does not accept another person's answer", async () => {
		model = stubModel([{ calls: [['script_run', { code: 'print(1)' }]] }, { say: 'done' }]);
		const res = await chat(f.userId, 'client-device-3333', true);
		let intruder: unknown;
		await readEvents(res, async (e) => {
			if (e.type === 'tool_start' && e.device) {
				const device = e.device as { callId: string };
				const r = await answer(other.userId, { callId: device.callId, ok: true, result: 'fake' });
				intruder = ((await r.json()) as { accepted: boolean }).accepted;
				// The real owner then answers, so the stream can finish
				await answer(f.userId, { callId: device.callId, ok: true, result: { ok: true } });
			}
		});
		expect(intruder).toBe(false);
	});

	it('refuses a body that is not a call answer, and an answer for a call nobody waits for', async () => {
		expect((await answer(f.userId, { callId: 'short', ok: true })).status).toBe(400);
		expect((await answer(f.userId, { callId: 'dc_not-waiting-for-this', ok: 'yes' })).status).toBe(
			400
		);
		const late = await answer(f.userId, { callId: 'dc_not-waiting-for-this', ok: true, result: 1 });
		expect(late.status).toBe(200);
		expect(((await late.json()) as { accepted: boolean }).accepted).toBe(false);
	});
});
