// A TOOL CALL THE MODEL WRITES AS TEXT (DSML) THROUGH THE REAL MODEL CLIENT AND THE TURN: IT RUNS LIKE A NORMAL CALL AND IS NEVER SHOWN

// -- TYPES -- //
import type { Fixture } from './support';
import type { TurnEvent } from '../../src/lib/server/agent/turn';
import type { Completion } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { runTurn } from '../../src/lib/server/agent/turn';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';
import { doneEvent, seedPerson, toolEvents } from './support';

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

const BAR = '｜';
const written = `<${BAR}DSML${BAR}function_calls><${BAR}DSML${BAR}invoke name="ledger_list"></${BAR}DSML${BAR}invoke></${BAR}DSML${BAR}function_calls>`;

const sse = (obj: unknown) => `data: ${JSON.stringify(obj)}\n\n`;

/** A model that answers each call from a list of content pieces, as a stream cut into small chunks. */
function modelSaying(rounds: string[][]) {
	let call = 0;
	const sent: string[] = [];
	const fakeFetch = (async (_url: string, init: { body: string }) => {
		sent.push(init.body);
		const pieces = rounds[call++] ?? ['ok'];
		const body =
			pieces.map((content) => sse({ choices: [{ delta: { content } }] })).join('') +
			sse({
				choices: [{ delta: {}, finish_reason: 'stop' }],
				usage: { prompt_tokens: 5, completion_tokens: 5 }
			}) +
			'data: [DONE]\n\n';
		return new Response(body, { status: 200 });
	}) as unknown as typeof fetch;
	const model = createModelClient({
		apiKey: 'test-key',
		baseUrl: 'https://model.test',
		model: 'm',
		limits: DEFAULT_LIMITS,
		fetch: fakeFetch,
		sleep: async () => undefined
	});
	return { model, sent };
}

async function run(model: ReturnType<typeof createModelClient>, text: string) {
	const events: TurnEvent[] = [];
	for await (const e of runTurn({
		ctx: f.ctx,
		model,
		history: [],
		userText: text,
		turnKey: `dsml-turn-${Math.random().toString(36).slice(2, 10)}`,
		now: new Date('2026-10-21T04:00:00Z')
	}))
		events.push(e);
	return events;
}

const shownText = (events: TurnEvent[]) =>
	events.flatMap((e) => (e.type === 'delta' ? [e.text] : [])).join('');

describe('a tool call written as text', () => {
	it('runs like a real call and its markup is never shown, however the stream is cut', async () => {
		const cut: string[] = [];
		const text = `Let me check. ${written}`;
		for (let i = 0; i < text.length; i += 6) cut.push(text.slice(i, i + 6));
		const { model, sent } = modelSaying([cut, ['All done.']]);
		const events = await run(model, 'what did I spend?');
		expect(toolEvents(events).map((e) => [e.name, e.status])).toEqual([['ledger_list', 'ok']]);
		expect(shownText(events)).toBe('Let me check. All done.');
		expect(JSON.stringify(events)).not.toMatch(/DSML/);
		expect(doneEvent(events)?.reply).toBe('Let me check. All done.');
		expect(doneEvent(events)?.toolsRun).toEqual(['ledger_list']);
		// The second request carries a real tool round, with no markup in the assistant message
		expect(sent).toHaveLength(2);
		const second = JSON.parse(sent[1] ?? '{}') as {
			messages: {
				role: string;
				content: string | null;
				tool_calls?: { function: { name: string } }[];
			}[];
		};
		const assistant = second.messages.find((m) => m.role === 'assistant');
		expect(assistant?.tool_calls?.[0]?.function.name).toBe('ledger_list');
		expect(assistant?.content ?? '').not.toMatch(/DSML/);
		expect(second.messages.some((m) => m.role === 'tool')).toBe(true);
	});

	it('an unknown tool written as text is refused like any unknown tool, and still not shown', async () => {
		const unknown = written.replace('ledger_list', 'not_a_real_tool');
		const { model } = modelSaying([[unknown], ['Sorry, I could not.']]);
		const events = await run(model, 'do the thing');
		expect(toolEvents(events).every((e) => e.status !== 'ok')).toBe(true);
		expect(JSON.stringify(events)).not.toMatch(/DSML/);
	});

	it('a cut-off block never runs and never shows, and the person still gets a reply', async () => {
		const cut = written.slice(0, written.length - 60);
		const { model } = modelSaying([[cut]]);
		const events = await run(model, 'what did I spend?');
		expect(toolEvents(events)).toHaveLength(0);
		expect(JSON.stringify(events)).not.toMatch(/DSML|invoke/);
		expect(doneEvent(events)?.reply).toMatch(/did not come up with an answer/);
	});
});

// -- THE MODEL CLIENT ALONE -- //

const toolDef = {
	type: 'function' as const,
	function: { name: 'ledger_list', description: 'List entries.', parameters: {} }
};

/** A client whose one answer is the given response body. */
function clientAnswering(body: string, contentType: string) {
	const fakeFetch = (async () =>
		new Response(body, {
			status: 200,
			headers: { 'content-type': contentType }
		})) as unknown as typeof fetch;
	return createModelClient({
		apiKey: 'test-key',
		baseUrl: 'https://model.test',
		model: 'm',
		limits: DEFAULT_LIMITS,
		fetch: fakeFetch,
		sleep: async () => undefined
	});
}

const usage = { prompt_tokens: 5, completion_tokens: 5 };

/** What a streamed answer ends as: the deltas shown and the completion. */
async function streamed(
	body: string,
	opts: { tools?: boolean } = {}
): Promise<{ shown: string; done: Completion }> {
	const model = clientAnswering(body, 'text/event-stream');
	let shown = '';
	let done: Completion | undefined;
	for await (const e of model.stream(f.ctx, {
		bucket: 'chat',
		messages: [{ role: 'user', content: 'hi' }],
		...(opts.tools === false ? {} : { tools: [toolDef] })
	})) {
		if (e.type === 'delta') shown += e.text;
		if (e.type === 'done') done = e.completion;
	}
	if (!done) throw new Error('no completion');
	return { shown, done };
}

describe('the model client reads a call written as text', () => {
	it('in a plain (not streamed) answer too', async () => {
		const model = clientAnswering(
			JSON.stringify({
				choices: [{ message: { content: `Ok. ${written}` }, finish_reason: 'stop' }],
				usage
			}),
			'application/json'
		);
		const out = await model.complete(f.ctx, {
			bucket: 'chat',
			messages: [{ role: 'user', content: 'hi' }],
			tools: [toolDef]
		});
		expect(out.toolCalls.map((c) => c.function.name)).toEqual(['ledger_list']);
		expect(out.finishReason).toBe('tool_calls');
		expect(out.content).toBe('Ok. ');
	});

	it('a real tool call wins when the answer also holds markup, and the markup is still removed', async () => {
		const body =
			sse({
				choices: [
					{
						delta: {
							content: `Checking. ${written}`,
							tool_calls: [
								{ index: 0, id: 'real1', function: { name: 'goals_list', arguments: '{}' } }
							]
						},
						finish_reason: 'tool_calls'
					}
				],
				usage
			}) + 'data: [DONE]\n\n';
		const { shown, done } = await streamed(body);
		expect(done.toolCalls.map((c) => [c.id, c.function.name])).toEqual([['real1', 'goals_list']]);
		expect(done.content).toBe('Checking. ');
		expect(shown).toBe('Checking. ');
	});

	it('a cut-off answer (length) never runs a text call and never shows it', async () => {
		const body =
			sse({
				choices: [{ delta: { content: `Hmm. ${written}` }, finish_reason: 'length' }],
				usage
			}) + 'data: [DONE]\n\n';
		const { shown, done } = await streamed(body);
		expect(done.toolCalls).toEqual([]);
		expect(done.finishReason).toBe('length');
		expect(`${shown}${done.content}`).not.toMatch(/DSML/);
	});

	it('with no tools offered the markup is removed and nothing is read from it', async () => {
		const body =
			sse({ choices: [{ delta: { content: `Done. ${written}` }, finish_reason: 'stop' }], usage }) +
			'data: [DONE]\n\n';
		const { shown, done } = await streamed(body, { tools: false });
		expect(done.toolCalls).toEqual([]);
		expect(done.finishReason).toBe('stop');
		expect(shown).toBe('Done. ');
		expect(done.content).toBe('Done. ');
	});

	it('two blocks in one answer give every call, and the words around them stay', async () => {
		const second = written.replace('ledger_list', 'goals_list');
		const body =
			sse({
				choices: [{ delta: { content: `A ${written} B ${second} C` }, finish_reason: 'stop' }],
				usage
			}) + 'data: [DONE]\n\n';
		const { shown, done } = await streamed(body);
		expect(done.toolCalls.map((c) => c.function.name)).toEqual(['ledger_list', 'goals_list']);
		expect(shown).toBe('A  B  C');
		expect(done.content).toBe('A  B  C');
	});
});
