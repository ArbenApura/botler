// THE TURN LIMITS: ROOM FOR A LONG MESSAGE, A NOTE WHEN TOOL CALLS RUN LOW, A TOKEN BUDGET, A SIZE GUARD AND NO JUNK FINAL REPLY

// -- TYPES -- //
import type { Fixture } from './support';
import type { TurnEvent, TurnModel } from '../../src/lib/server/agent/turn';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { hasRealWords, LIMITS } from '../../src/lib/server/agent/turn';
import { OpsError } from '../../src/lib/server/ops/context';
import { createTestDb } from '../support/testDb';
import { doneEvent, play, seedPerson, stubModel, toolEvents } from './support';

// -- STATES -- //

let t: TestDb;
let f: Fixture;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	f = await seedPerson(t);
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

const lastUser = (model: ReturnType<typeof stubModel>, n: number) =>
	model.requests[n]!.messages.filter((m) => m.role === 'user').at(-1);

// -- TESTS -- //

describe('room for a long message', () => {
	it('allows 20 model calls and 40 tool calls, 16000 characters per result', () => {
		expect(LIMITS.maxModelCalls).toBe(20);
		expect(LIMITS.maxToolCalls).toBe(40);
		expect(LIMITS.maxResultChars).toBe(16_000);
	});

	it('replays the 12-call failure from the live chat: 15 tool rounds, then a real answer', async () => {
		// The live message called bills_due five times and hit the old cap of 12; its reply was two stray dates
		const model = stubModel((_req, n) =>
			n < 15
				? { calls: [['accounts_list', {}]] }
				: { say: 'The nine weeks add up to 12,300 pesos.' }
		);
		const events = await play({ f, model, text: 'week by week until december' });
		expect(toolEvents(events)).toHaveLength(15);
		expect(toolEvents(events).every((e) => e.status === 'ok')).toBe(true);
		const done = doneEvent(events);
		expect(done?.reply).toBe('The nine weeks add up to 12,300 pesos.');
		expect(done?.stopped).toBeUndefined();
	});

	it('closes tools on the last model call, tells the model to answer, and never loops past 20', async () => {
		const model = stubModel(() => ({ calls: [['accounts_list', {}]] }));
		const events = await play({ f, model, text: 'keep going' });
		expect(model.requests).toHaveLength(20);
		expect(model.requests[18]!.toolChoice).toBeUndefined();
		expect(model.requests[19]!.toolChoice).toBe('none');
		expect(lastUser(model, 19)?.content).toMatch(/No more tools/);
		const done = doneEvent(events);
		expect(done?.stopped).toBe('depth');
		expect(done?.reply).toMatch(/could not finish/);
		expect(done?.reply).toMatch(/accounts_list/);
	});
});

describe('the note on tool calls left', () => {
	it('starts at 75% of the tool calls and counts down', async () => {
		const model = stubModel((_req, n) =>
			n < 8 ? { calls: [['accounts_list', {}]] } : { say: 'Done with it all.' }
		);
		await play({ f, model, text: 'go', limits: { maxToolCalls: 8 } });
		const tools = model.requests[8]!.messages.filter((m) => m.role === 'tool');
		const contents = tools.map((m) => m.content);
		// Calls 1 to 5 are quiet, calls 6, 7 and 8 say 3, 2 and 1 left
		expect(contents.slice(0, 5).some((c) => c.includes('left in this message'))).toBe(false);
		expect(contents[5]).toMatch(/\(2 tool calls left in this message\)$/);
		expect(contents[7]).toMatch(/\(0 tool calls left in this message\)$/);
	});
});

describe('the token budget of one message', () => {
	it('closes tools once the charged tokens pass the budget and asks for the answer', async () => {
		const model = stubModel((_req, n) =>
			n < 4
				? {
						calls: [['accounts_list', {}]],
						usage: { promptTokens: 1000, completionTokens: 1000, charged: 200_000 }
					}
				: { say: 'Here is what I have.' }
		);
		const events = await play({ f, model, text: 'go', limits: { turnTokenBudget: 300_000 } });
		// Two calls cost 400000: the third request is already without tools
		expect(model.requests[1]!.toolChoice).toBeUndefined();
		expect(model.requests[2]!.toolChoice).toBe('none');
		expect(lastUser(model, 2)?.content).toMatch(/Answer now from what you already have/);
		expect(doneEvent(events)?.reply).toBe('Here is what I have.');
	});

	it('uses the usage report when the model gives no charged figure', async () => {
		const model = stubModel((_req, n) =>
			n < 4
				? {
						calls: [['accounts_list', {}]],
						usage: { promptTokens: 90_000, completionTokens: 70_000 }
					}
				: { say: 'ok then' }
		);
		await play({ f, model, text: 'go', limits: { turnTokenBudget: 200_000 } });
		expect(model.requests[2]!.toolChoice).toBe('none');
	});

	it('closes tools when the prompt grew past the size guard', async () => {
		const model = stubModel((_req, n) =>
			n < 3
				? {
						calls: [['accounts_list', {}]],
						usage: { promptTokens: 150_000, completionTokens: 10, charged: 100 }
					}
				: { say: 'Short answer.' }
		);
		await play({ f, model, text: 'go' });
		expect(model.requests[1]!.toolChoice).toBe('none');
	});
});

describe('a final reply with no words', () => {
	it('is replaced by a plain note naming what ran', async () => {
		const model = stubModel([{ calls: [['bills_due', {}]] }, { say: '2026-11-03 2026-11-10' }]);
		const events = await play({ f, model, text: 'bills?' });
		const done = doneEvent(events);
		expect(done?.reply).toMatch(/could not finish/);
		expect(done?.reply).toMatch(/bills_due/);
		expect(done?.reply).not.toContain('2026-11-03');
	});

	it('leaves a real answer, and a short one, alone', async () => {
		const model = stubModel([{ calls: [['bills_due', {}]] }, { say: 'Yes, 2026-11-03.' }]);
		expect(doneEvent(await play({ f, model, text: 'bills?' }))?.reply).toBe('Yes, 2026-11-03.');
	});

	it('knows words from dates, times, numbers and markup', () => {
		expect(hasRealWords('2026-11-03 2026-11-10')).toBe(false);
		expect(hasRealWords('2026-11-03T08:00:00Z')).toBe(false);
		expect(hasRealWords('<dsml>1,200.50</dsml>')).toBe(false);
		expect(hasRealWords('Done.')).toBe(true);
		expect(hasRealWords('Walang laman')).toBe(true);
	});
});

describe('the monthly allowance', () => {
	it('says so in words when the cap stops a call, and ends the message', async () => {
		const model: TurnModel = {
			// eslint-disable-next-line require-yield
			async *stream() {
				throw new OpsError('LIMIT', 'Monthly allowance used.');
			}
		};
		const events: TurnEvent[] = await play({ f, model, text: 'hello' });
		expect(events.some((e) => e.type === 'fallback' && e.reason === 'capped')).toBe(true);
		expect(doneEvent(events)?.reply).toMatch(/allowance for this month is used up/);
	});
});

describe('signed thinking in a tool round', () => {
	it('goes back unchanged with the same assistant message, and is not in the reply', async () => {
		const blocks = [
			{ type: 'thinking' as const, thinking: 'about it', signature: 'sig-1' },
			{ type: 'redacted_thinking' as const, data: 'xyz' }
		];
		const model = stubModel([
			{ calls: [['accounts_list', {}]], wireBlocks: blocks },
			{ say: 'Three accounts.' }
		]);
		const events = await play({ f, model, text: 'accounts?' });
		const assistant = model.requests[1]!.messages.find((m) => m.role === 'assistant');
		expect(assistant && 'wire_blocks' in assistant ? assistant.wire_blocks : null).toEqual(blocks);
		expect(doneEvent(events)?.reply).toBe('Three accounts.');
		expect(JSON.stringify(events)).not.toContain('sig-1');
	});
});
