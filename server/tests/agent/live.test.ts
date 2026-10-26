// THE LIVE CHAT EVENTS: START, PHASE, REASONING AND TOOL_START ARE SHOWN WHILE A TURN RUNS AND ARE NEVER STORED, REPLAYED OR LOGGED.
// A reply cut off by the model's limit never runs a tool and never feeds memory.

// -- TYPES -- //
import type { Fixture } from './support';
import type { TurnEvent } from '../../src/lib/server/agent/turn';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { handleChat } from '../../src/lib/server/agent/chat';
import { chatTurn } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createTestDb } from '../support/testDb';
import { doneEvent, play, seedPerson, stubModel } from './support';

// -- STATES -- //

let t: TestDb;
let f: Fixture;
let n = 0;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	f = await seedPerson(t);
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

const types = (events: TurnEvent[]) => events.map((e) => e.type);

async function chat(model: ReturnType<typeof stubModel>, id: string, text = 'hello') {
	const out: TurnEvent[] = [];
	for await (const e of handleChat(f.ctx, { clientMessageId: id, text }, { model, noMemory: true }))
		out.push(e);
	return out;
}

const stored = (id: string) =>
	withUser(t.handle, f.userId, (tx) =>
		tx
			.select()
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, f.userId), eq(chatTurn.clientMessageId, id)))
	).then((rows) => rows[0]);

// -- TESTS -- //

describe('live events', () => {
	it('orders phase, reasoning, tool_start, tool and the answer', async () => {
		const model = stubModel([
			{ think: 'I should look at the accounts.', calls: [['accounts_list', {}]] },
			{ think: 'Now I can answer.', say: 'You have three accounts.' }
		]);
		const events = await play({ f, model, text: 'what accounts do I have?' });
		expect(types(events)).toEqual([
			'phase',
			'reasoning',
			'tool_start',
			'tool',
			'phase',
			'reasoning',
			'phase',
			'delta',
			'done'
		]);
		const start = events.find((e) => e.type === 'tool_start');
		const tool = events.find((e) => e.type === 'tool');
		expect(start && tool && 'id' in tool ? tool.id : null).toBe(
			start && 'id' in start ? start.id : 'x'
		);
		expect(doneEvent(events)?.reply).toBe('You have three accounts.');
	});

	it('gives the thinking back to the model in the next round, and keeps it out of the reply', async () => {
		const model = stubModel([
			{ think: 'masked thought', calls: [['accounts_list', {}]] },
			{ say: 'Done.' }
		]);
		const events = await play({ f, model, text: 'accounts?' });
		const second = model.requests[1]!.messages.find((m) => m.role === 'assistant');
		expect(second && 'reasoning_content' in second ? second.reasoning_content : null).toBe(
			'masked thought'
		);
		expect(doneEvent(events)?.reply).toBe('Done.');
	});

	it('tool_start holds only the id and the name, never the arguments', async () => {
		const model = stubModel([
			{ calls: [['accounts_list', { secret: 'https://private.example/x' }]] },
			{ say: 'ok' }
		]);
		const events = await play({ f, model, text: 'accounts?' });
		const start = events.find((e) => e.type === 'tool_start');
		expect(Object.keys(start ?? {}).sort()).toEqual(['id', 'name', 'type']);
		expect(JSON.stringify(start)).not.toContain('private.example');
	});

	it('starts at once, keeps no live-only event, and replays without them', async () => {
		const id = `client-live-${++n}-aaaa`;
		const model = stubModel([
			{ think: 'secret thinking', calls: [['accounts_list', {}]] },
			{ say: 'Three accounts.' }
		]);
		const first = await chat(model, id);
		expect(first[0]?.type).toBe('start');
		expect(types(first)).toContain('reasoning');
		const row = await stored(id);
		const kept = JSON.stringify(row?.events);
		expect(kept).not.toContain('secret thinking');
		for (const kind of ['reasoning', 'phase', 'tool_start', 'start'])
			expect(kept).not.toContain(`"type":"${kind}"`);
		const again = await chat(stubModel([]), id);
		expect(again[0]?.type).toBe('start');
		expect(types(again)).not.toContain('reasoning');
		expect(types(again)).not.toContain('phase');
		expect(types(again)).not.toContain('tool_start');
	});

	it('logs no thinking text', async () => {
		const spies = [
			vi.spyOn(console, 'info').mockImplementation(() => undefined),
			vi.spyOn(console, 'error').mockImplementation(() => undefined),
			vi.spyOn(console, 'warn').mockImplementation(() => undefined)
		];
		await play({
			f,
			model: stubModel([{ think: 'very private musing', say: 'ok' }]),
			text: 'hello'
		});
		const logged = spies.flatMap((s) => s.mock.calls.flat()).join(' ');
		expect(logged).not.toContain('very private musing');
		vi.restoreAllMocks();
	});
});

describe('a reply cut off by the limit', () => {
	const cut = { finish: 'length' as const };

	it('never runs the tool calls of a cut-off round and says so when the second try is cut too', async () => {
		const model = stubModel([
			{ finish: 'length', think: 'long thought', calls: [['expense_log', '{"accountId": "']] },
			cut
		]);
		const events = await play({ f, model, text: 'log lunch' });
		expect(types(events)).not.toContain('tool_start');
		const done = doneEvent(events);
		expect(done?.stopped).toBe('length');
		expect(done?.reply).toMatch(/more thinking/);
	});

	it('carries on once after a cut-off round and answers, without the apology', async () => {
		const model = stubModel([
			{ finish: 'length', calls: [['expense_log', '{"accountId": "']] },
			{ say: 'Here is the answer.' }
		]);
		const events = await play({ f, model, text: 'log lunch' });
		expect(types(events)).not.toContain('tool_start');
		const done = doneEvent(events);
		expect(done?.stopped).toBeUndefined();
		expect(done?.reply).toBe('Here is the answer.');
		const nudge = model.requests[1]!.messages.at(-1);
		expect(nudge?.role).toBe('user');
	});

	it('keeps what a cut-off answer wrote and asks the model to carry on from there', async () => {
		const model = stubModel([
			{ say: 'The first half of', finish: 'length' },
			{ say: ' the answer.' }
		]);
		const events = await play({ f, model, text: 'explain' });
		const done = doneEvent(events);
		expect(done?.stopped).toBeUndefined();
		expect(done?.reply).toBe('The first half of the answer.');
		const sent = model.requests[1]!.messages;
		expect(sent.at(-2)).toMatchObject({ role: 'assistant', content: 'The first half of' });
		expect(sent.at(-1)?.role).toBe('user');
	});

	it('says so when the answer is cut off again, and keeps what it wrote', async () => {
		const model = stubModel([
			{ say: 'The first half of', finish: 'length' },
			{ say: ' the second', finish: 'length' }
		]);
		const events = await play({ f, model, text: 'explain' });
		const done = doneEvent(events);
		expect(done?.stopped).toBe('length');
		expect(done?.reply).toContain('The first half of the second');
		expect(done?.reply).toMatch(/more thinking/);
		// One carry-on only, never a loop
		expect(model.requests).toHaveLength(2);
	});

	it('does not carry on when no model call is left, and says so', async () => {
		const model = stubModel((_req, n) =>
			n < 5 ? { calls: [['accounts_list', {}]] } : { say: 'Half an answer', finish: 'length' }
		);
		const events = await play({ f, model, text: 'accounts?', limits: { maxModelCalls: 6 } });
		const done = doneEvent(events);
		expect(model.requests).toHaveLength(6);
		expect(done?.stopped).toBe('length');
		expect(done?.reply).toMatch(/more thinking/);
	});

	it('never ends on a blank reply when the model only thought', async () => {
		const model = stubModel([{ think: 'hmm' }]);
		const events = await play({ f, model, text: 'explain' });
		expect(doneEvent(events)?.reply.trim()).not.toBe('');
	});

	it('is stored as failed and is not read for memory when cut off twice', async () => {
		const id = `client-live-${++n}-bbbb`;
		const model = stubModel([cut, cut]);
		await chat(model, id);
		expect((await stored(id))?.status).toBe('failed');
	});
});
