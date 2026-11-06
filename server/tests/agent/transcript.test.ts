// THE STORED TOOL ROUNDS AS PLAIN FUNCTIONS: WHAT IS KEPT, WHAT COMES BACK, AND THE TOKEN WINDOW

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	buildHistory,
	readTranscript,
	replayRounds,
	RESULT_CHARS,
	shortenResult,
	turnMessages,
	untrustedStub
} from '../../src/lib/server/agent/transcript';

// -- FUNCTIONS -- //

const call = (id: string, name = 'accounts_list') => ({
	id,
	type: 'function' as const,
	function: { name, arguments: '{}' }
});

const rounds = (provider: 'anthropic' | 'deepseek', size = 10) => [
	{
		role: 'assistant',
		content: null,
		provider,
		tool_calls: [call('c1')],
		...(provider === 'deepseek' ? { reasoning_content: 'thought' } : {})
	},
	{ role: 'tool', tool_call_id: 'c1', content: 'r'.repeat(size) }
];

const turn = (i: number, size = 10, transcript: unknown = null) => ({
	userText: `q${i}`,
	reply: `a${i}`,
	transcript: transcript ?? (size ? rounds('anthropic', size) : null)
});

// -- TESTS -- //

describe('what is kept', () => {
	it('shortens a long result with a marker and leaves a short one whole', () => {
		expect(shortenResult('short')).toBe('short');
		const cut = shortenResult('x'.repeat(RESULT_CHARS + 500));
		expect(cut.length).toBeLessThan(RESULT_CHARS + 100);
		expect(cut).toMatch(/shortened: read again/);
		expect(cut.startsWith('x'.repeat(RESULT_CHARS))).toBe(true);
	});

	it('stubs a stranger’s text with the tool name only', () => {
		const stub = untrustedStub('calendar_events');
		expect(JSON.parse(stub)).toMatchObject({ untrusted: true, source: 'calendar_events' });
	});

	it('reads old rows without the thinking they carry, and replays them to DeepSeek without it', () => {
		// Rows written before thinking stopped being stored still have the field: it is dropped on the way in
		const read = readTranscript(rounds('deepseek'));
		expect(read?.[0]).not.toHaveProperty('reasoning_content');
		// A DeepSeek round with no thinking is replayed like any other: it is no longer a reason to fall back to text
		const bare = readTranscript([
			{ role: 'assistant', content: null, provider: 'deepseek', tool_calls: [call('c1')] },
			{ role: 'tool', tool_call_id: 'c1', content: 'r' }
		])!;
		const replayed = replayRounds(bare, 'deepseek');
		expect(replayed).toHaveLength(2);
		expect(JSON.stringify(replayed)).not.toContain('reasoning_content');
	});

	it('reads back only what has the shape it wrote', () => {
		expect(readTranscript(null)).toBeNull();
		expect(readTranscript([])).toBeNull();
		expect(readTranscript('nope')).toBeNull();
		expect(readTranscript([{ role: 'system', content: 'x' }])).toBeNull();
		expect(readTranscript([{ role: 'assistant', content: 'x', tool_calls: [] }])).toBeNull();
		expect(readTranscript([{ role: 'tool', tool_call_id: 1, content: 'x' }])).toBeNull();
		expect(readTranscript(rounds('anthropic'))?.map((m) => m.role)).toEqual(['assistant', 'tool']);
	});
});

describe('what comes back', () => {
	it('replays to the provider that wrote the rounds, and to no other', () => {
		const a = readTranscript(rounds('anthropic'))!;
		expect(replayRounds(a, 'anthropic')).toHaveLength(2);
		expect(replayRounds(a, 'deepseek')).toBeNull();
		expect(replayRounds(a, undefined)).toBeNull();
		const d = readTranscript(rounds('deepseek'))!;
		expect(replayRounds(d, 'deepseek')).toHaveLength(2);
		expect(JSON.stringify(replayRounds(d, 'deepseek'))).not.toContain('thought');
		expect(replayRounds(d, 'anthropic')).toBeNull();
	});

	it('never replays a call without its answer, or an answer without its call', () => {
		const calls = readTranscript(rounds('anthropic'))!;
		expect(replayRounds(calls.slice(0, 1), 'anthropic')).toBeNull();
		expect(replayRounds(calls.slice(1), 'anthropic')).toBeNull();
		const two = readTranscript([
			{
				role: 'assistant',
				content: null,
				provider: 'anthropic',
				tool_calls: [call('a'), call('b')]
			},
			{ role: 'tool', tool_call_id: 'a', content: '1' }
		])!;
		expect(replayRounds(two, 'anthropic')).toBeNull();
	});

	it('turns one message into user, rounds and answer, and leaves out an empty one', () => {
		const t = turn(1);
		expect(turnMessages(t, 'anthropic').map((m) => m.role)).toEqual([
			'user',
			'assistant',
			'tool',
			'assistant'
		]);
		expect(turnMessages(t, 'deepseek').map((m) => m.role)).toEqual(['user', 'assistant']);
		expect(turnMessages(t, 'anthropic', true).map((m) => m.role)).toEqual(['user', 'assistant']);
		expect(turnMessages({ userText: 'q', reply: '', transcript: null }, 'anthropic')).toEqual([]);
		// No answer but work done: the work stays in view
		const unfinished = turnMessages({ ...t, reply: '' }, 'anthropic');
		expect(unfinished.map((m) => m.role)).toEqual(['user', 'assistant', 'tool', 'assistant']);
	});

	it('keeps a failed or stopped message, so it can be referred to', () => {
		const lost = turnMessages(
			{ userText: 'pay rent 500', reply: '', transcript: null, failed: true },
			'deepseek'
		);
		expect(lost.map((m) => m.role)).toEqual(['user', 'assistant']);
		expect(lost[0]?.content).toBe('pay rent 500');
		expect(String(lost[1]?.content)).toContain('no answer');
		// A stopped message with a partial reply keeps that reply as it was
		const partial = turnMessages(
			{ userText: 'q', reply: 'half an', transcript: null, failed: true },
			'deepseek'
		);
		expect(partial[1]?.content).toBe('half an');
		// An empty failed message is still nothing
		expect(
			turnMessages({ userText: ' ', reply: '', transcript: null, failed: true }, 'deepseek')
		).toEqual([]);
	});
});

describe('the token window', () => {
	it('keeps everything under the budget', () => {
		const turns = Array.from({ length: 4 }, (_, i) => turn(i));
		const built = buildHistory(turns, { provider: 'anthropic', budget: 100_000 });
		expect(built.start).toBe(0);
		expect(built.messages).toHaveLength(16);
	});

	it('drops the oldest turns in steps of five', () => {
		const turns = Array.from({ length: 30 }, (_, i) => turn(i, 600));
		const built = buildHistory(turns, { provider: 'anthropic', budget: 2000 });
		expect(built.start % 5).toBe(0);
		expect(built.start).toBeGreaterThan(0);
		const first = built.messages[0];
		expect(first && 'content' in first ? first.content : '').toBe(`q${built.start}`);
	});

	it('replays the two newest as text when even they are over the budget', () => {
		const turns = Array.from({ length: 3 }, (_, i) => turn(i, 20_000));
		const built = buildHistory(turns, { provider: 'anthropic', budget: 500 });
		expect(built.messages.map((m) => m.role)).toEqual(['user', 'assistant', 'user', 'assistant']);
		expect(built.messages.at(-1)).toMatchObject({ content: 'a2' });
	});

	it('is empty for no turns', () => {
		expect(buildHistory([], { provider: 'anthropic', budget: 10 })).toEqual({
			messages: [],
			start: 0
		});
	});
});
