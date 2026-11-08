// THE LONG CHAT: A MESSAGE KEEPS ITS TOOL ROUNDS, HISTORY REPLAYS THEM TO THE SAME PROVIDER ONLY, A BACKGROUND SUMMARY HOLDS THE EARLIER PART,
// AND NOTHING OF IT REACHES THE APP

// -- TYPES -- //
import type { Fixture } from './support';
import type { TurnEvent } from '../../src/lib/server/agent/turn';
import type { Completion, CompletionRequest } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { handleChat } from '../../src/lib/server/agent/chat';
import { buildHistory, readTranscript } from '../../src/lib/server/agent/transcript';
import { chat, chatTurn, job } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { runBatch } from '../../src/lib/server/jobs/queue';
import { createChatHandlers } from '../../src/lib/server/jobs/chat';
import { chatFork } from '../../src/lib/server/ops/chats';
import { wipeMemory } from '../../src/lib/server/ops/memory';
import { createTestDb } from '../support/testDb';
import { fakeWeb, seedPerson, stubModel } from './support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

type Provider = 'anthropic' | 'deepseek';

async function say(
	f: Fixture,
	model: ReturnType<typeof stubModel>,
	text: string,
	extra: Partial<Parameters<typeof handleChat>[2]> = {},
	chatId?: string
) {
	const events: TurnEvent[] = [];
	for await (const e of handleChat(
		f.ctx,
		{ clientMessageId: `long-${++n}-${'x'.repeat(8)}`, text, ...(chatId ? { chatId } : {}) },
		{ model, noMemory: true, ...extra }
	))
		events.push(e);
	return events;
}

const asProvider = (p: Provider) => async () => p;

const turnsOf = (f: Fixture) =>
	withUser(t.handle, f.userId, (tx) =>
		tx.select().from(chatTurn).where(eq(chatTurn.userId, f.userId)).orderBy(chatTurn.createdAt)
	);

const chatsOf = (f: Fixture) =>
	withUser(t.handle, f.userId, (tx) => tx.select().from(chat).where(eq(chat.userId, f.userId)));

const roles = (req: CompletionRequest) => req.messages.map((m) => m.role);

// -- TESTS -- //

describe('the stored tool rounds', () => {
	it('keeps the rounds with a finished message, shortened, and never sends them to the app', async () => {
		const f = await seedPerson(t);
		const model = stubModel([
			{ calls: [['accounts_list', {}]], provider: 'anthropic' },
			{ say: 'Three accounts.' }
		]);
		const events = await say(f, model, 'accounts?');
		const done = events.find((e) => e.type === 'done');
		expect(done).toBeDefined();
		expect(JSON.stringify(events)).not.toContain('transcript');
		const [row] = await turnsOf(f);
		const rounds = readTranscript(row?.transcript);
		expect(rounds?.map((m) => m.role)).toEqual(['assistant', 'tool']);
		expect(rounds?.[0]).toMatchObject({ provider: 'anthropic' });
		expect(row?.status).toBe('done');
	});

	it('shortens a long result with a marker, and stubs web text and drops the words around it', async () => {
		const f = await seedPerson(t);
		const web = fakeWeb({});
		const model = stubModel([
			{
				say: 'Let me look.',
				calls: [['research', { question: 'peso rate today' }]],
				provider: 'anthropic'
			},
			{ say: 'Done.' }
		]);
		await say(f, model, 'search the rate', { web: web.deps });
		const [row] = await turnsOf(f);
		const rounds = readTranscript(row?.transcript);
		const call = rounds?.[0];
		expect(call && 'content' in call ? call.content : 'x').toBeNull();
		const result = rounds?.[1];
		const text = result && result.role === 'tool' ? result.content : '';
		expect(text).toContain('"untrusted":true');
		expect(text).toContain('research');
		// Not a word of the page or the hit
		expect(text).not.toContain('untrusted SYSTEM');
		expect(text).not.toContain('news.example');
	});

	it('stores none for a message that was cut off, and keeps the text of the reply', async () => {
		const f = await seedPerson(t);
		const cut = { finish: 'length' as const, say: 'half' };
		await say(f, stubModel([{ calls: [['accounts_list', {}]] }, cut, cut]), 'long one');
		const [row] = await turnsOf(f);
		expect(row?.status).toBe('failed');
		expect(row?.transcript).toBeNull();
	});
});

describe('replaying the rounds', () => {
	async function twoMessages(
		written: Provider,
		live: Provider,
		think?: string
	): Promise<CompletionRequest> {
		const f = await seedPerson(t);
		await say(
			f,
			stubModel([
				{ calls: [['accounts_list', {}]], provider: written, ...(think ? { think } : {}) },
				{ say: 'Three accounts.', provider: written }
			]),
			'accounts?',
			{ provider: asProvider(live) }
		);
		const second = stubModel([{ say: 'ok', provider: live }]);
		await say(f, second, 'and now?', { provider: asProvider(live) });
		return second.requests[0]!;
	}

	it('replays the tool call and its result to the provider that wrote them', async () => {
		const req = await twoMessages('anthropic', 'anthropic');
		// prefix, user, assistant(tool call), tool, assistant(reply), new user
		expect(roles(req)).toEqual(['system', 'user', 'assistant', 'tool', 'assistant', 'user']);
		const call = req.messages[2];
		expect(call && 'tool_calls' in call ? call.tool_calls?.[0]?.function.name : '').toBe(
			'accounts_list'
		);
		// No thinking and no signed block ever comes from history
		expect(JSON.stringify(req.messages)).not.toContain('wire_blocks');
		expect(JSON.stringify(req.messages)).not.toContain('reasoning_content');
	});

	it('falls back to the two texts when the live provider is not the one that wrote the rounds', async () => {
		const req = await twoMessages('anthropic', 'deepseek', 'some thinking');
		expect(roles(req)).toEqual(['system', 'user', 'assistant', 'user']);
		const req2 = await twoMessages('deepseek', 'anthropic', 'some thinking');
		expect(roles(req2)).toEqual(['system', 'user', 'assistant', 'user']);
	});

	it('replays a DeepSeek message with tool calls without any thinking, and stores none', async () => {
		const req = await twoMessages('deepseek', 'deepseek', 'check the accounts');
		const call = req.messages.find((m) => m.role === 'assistant' && 'tool_calls' in m);
		expect(call).toBeDefined();
		expect(JSON.stringify(req.messages)).not.toContain('reasoning_content');
		expect(JSON.stringify(req.messages)).not.toContain('check the accounts');
		// With or without thinking the rounds come back the same way
		const bare = await twoMessages('deepseek', 'deepseek');
		expect(roles(bare)).toEqual(roles(req));
	});

	it('replays as text when history has no provider to name', async () => {
		const f = await seedPerson(t);
		await say(f, stubModel([{ calls: [['accounts_list', {}]], provider: 'anthropic' }]), 'a?');
		const second = stubModel([{ say: 'ok' }]);
		await say(f, second, 'b?');
		expect(roles(second.requests[0]!)).toEqual(['system', 'user', 'assistant', 'user']);
	});

	it('never replays an orphan tool call', () => {
		const orphan = {
			userText: 'q',
			reply: 'a',
			transcript: [
				{
					role: 'assistant',
					content: null,
					provider: 'anthropic',
					tool_calls: [
						{ id: 'c1', type: 'function', function: { name: 'accounts_list', arguments: '{}' } }
					]
				}
			]
		};
		const built = buildHistory([orphan], { provider: 'anthropic', budget: 10_000 });
		expect(built.messages.map((m) => m.role)).toEqual(['user', 'assistant']);
	});

	it('keeps the work of a message that ended with no answer', async () => {
		const f = await seedPerson(t);
		await say(
			f,
			stubModel([{ calls: [['accounts_list', {}]], provider: 'anthropic' }]),
			'accounts?',
			{ provider: asProvider('anthropic') }
		);
		// The stand-in ends on "ok" after the script, so make the reply blank by hand: the rounds must stay in view
		await withUser(t.handle, f.userId, (tx) =>
			tx.update(chatTurn).set({ reply: '' }).where(eq(chatTurn.userId, f.userId))
		);
		const second = stubModel([{ say: 'ok' }]);
		await say(f, second, 'again?', { provider: asProvider('anthropic') });
		expect(roles(second.requests[0]!)).toEqual([
			'system',
			'user',
			'assistant',
			'tool',
			'assistant',
			'user'
		]);
	});
});

describe('the token budget and the summary', () => {
	it('puts the chat summary in as a system message and sends only the messages after it', async () => {
		const f = await seedPerson(t);
		for (const q of ['one', 'two', 'three', 'four'])
			await say(f, stubModel([{ say: `answer ${q}` }]), q);
		const rows = await turnsOf(f);
		const [c] = await chatsOf(f);
		await withUser(t.handle, f.userId, (tx) =>
			tx
				.update(chat)
				.set({ summary: 'They are planning rent.', summaryThroughTurnId: rows[1]!.id })
				.where(eq(chat.id, c!.id))
		);
		const model = stubModel([{ say: 'ok' }]);
		await say(f, model, 'five');
		const messages = model.requests[0]!.messages;
		expect(roles(model.requests[0]!).slice(0, 2)).toEqual(['system', 'system']);
		expect(String(messages[1]?.content)).toContain('They are planning rent.');
		const texts = messages.filter((m) => m.role === 'user').map((m) => String(m.content));
		// The two messages the summary covers are gone; the two after it stay
		expect(texts.some((x) => x.includes('one'))).toBe(false);
		expect(texts.some((x) => x.startsWith('three'))).toBe(true);
	});

	it('ignores a summary whose last message was erased', async () => {
		const f = await seedPerson(t);
		await say(f, stubModel([{ say: 'a' }]), 'first');
		const [c] = await chatsOf(f);
		await withUser(t.handle, f.userId, (tx) =>
			tx
				.update(chat)
				.set({
					summary: 'stale words',
					summaryThroughTurnId: '11111111-1111-4111-8111-111111111111'
				})
				.where(eq(chat.id, c!.id))
		);
		const model = stubModel([{ say: 'ok' }]);
		await say(f, model, 'second');
		expect(JSON.stringify(model.requests[0]!.messages)).not.toContain('stale words');
		expect(roles(model.requests[0]!)).toEqual(['system', 'user', 'assistant', 'user']);
	});
});

describe('compaction', () => {
	const completion = (content: string): Completion => ({
		content,
		toolCalls: [],
		finishReason: 'stop',
		usage: { promptTokens: 10, completionTokens: 5 }
	});

	/** A chat of long messages under a tiny budget, so each finished message wants a compaction. */
	async function longChat(f: Fixture, count: number, budget = 300, from = 0) {
		for (let i = from; i < from + count; i++)
			await say(
				f,
				stubModel([{ say: `reply ${i} ${'r'.repeat(900)}` }]),
				`question ${i} ${'q'.repeat(900)}`,
				{
					historyTokens: budget
				}
			);
	}

	const jobsOf = (f: Fixture) =>
		withUser(t.handle, f.userId, (tx) =>
			tx
				.select()
				.from(job)
				.where(and(eq(job.userId, f.userId), eq(job.kind, 'chat.compact')))
		);

	it('queues one compaction once the history is over the budget, and not a second while it waits', async () => {
		const f = await seedPerson(t);
		await longChat(f, 3);
		const queued = await jobsOf(f);
		expect(queued).toHaveLength(1);
		expect(queued[0]?.status).toBe('queued');
		// Ids only in the payload
		expect(Object.keys(queued[0]!.payload as object).sort()).toEqual(['chatId', 'turnId']);
	});

	it('queues nothing for a short chat', async () => {
		const f = await seedPerson(t);
		await longChat(f, 3, 100_000);
		expect(await jobsOf(f)).toHaveLength(0);
	});

	it('writes a summary of everything but the last two messages, and does it again from the old summary', async () => {
		const f = await seedPerson(t);
		await longChat(f, 6);
		const seen: string[] = [];
		const handlers = createChatHandlers({
			historyTokens: 300,
			model: () => ({
				complete: async (ctx, req) => {
					// Jobs of other people in this shared test database run in the same batch: only this person's are counted
					if (ctx.actor.userId !== f.userId) return completion('another person');
					seen.push(String(req.messages.at(-1)?.content));
					return completion(seen.length === 1 ? 'FIRST SUMMARY about the rent' : 'SECOND SUMMARY');
				}
			})
		});
		const later = new Date(Date.now() + 120_000);
		await runBatch(t.handle, handlers, { now: later });
		const rows = await turnsOf(f);
		let [c] = await chatsOf(f);
		expect(c?.summary).toBe('FIRST SUMMARY about the rent');
		// Everything but the last two messages
		expect(c?.summaryThroughTurnId).toBe(rows[rows.length - 3]!.id);
		expect(seen[0]).toContain('question 0');
		expect(seen[0]).toContain('(none)');
		expect(seen[0]).not.toContain('question 5');

		// More messages, then the next compaction starts from the first summary
		await longChat(f, 3, 300, 6);
		await runBatch(t.handle, handlers, { now: new Date(later.getTime() + 600_000) });
		[c] = await chatsOf(f);
		expect(c?.summary).toBe('SECOND SUMMARY');
		expect(seen[1]).toContain('FIRST SUMMARY about the rent');
		expect(seen[1]).not.toContain('question 0 ');
		expect(c?.summaryThroughTurnId).not.toBe(rows[rows.length - 3]!.id);
	});

	it('leaves the window sliding when the model is down, and tries again later', async () => {
		const f = await seedPerson(t);
		await longChat(f, 4);
		let calls = 0;
		const handlers = createChatHandlers({
			historyTokens: 300,
			model: () => ({
				complete: async (ctx) => {
					if (ctx.actor.userId !== f.userId) return completion('another person');
					calls++;
					throw new Error('down');
				}
			})
		});
		await runBatch(t.handle, handlers, { now: new Date(Date.now() + 120_000) });
		expect(calls).toBe(1);
		const [c] = await chatsOf(f);
		expect(c?.summary).toBeNull();
		const [row] = await jobsOf(f);
		expect(row?.status).toBe('queued');
		expect(row?.attempts).toBe(1);
		// The next message still gets a bounded history
		const model = stubModel([{ say: 'ok' }]);
		await say(f, model, 'still there?', { historyTokens: 300 });
		// Down to the newest two messages, not the whole chat: prefix, two exchanges, the new question
		expect(model.requests[0]!.messages.length).toBeLessThanOrEqual(6);
		expect(JSON.stringify(model.requests[0]!.messages)).not.toContain('question 0 ');
	});

	it('does nothing for a chat or a message that was erased meanwhile', async () => {
		const f = await seedPerson(t);
		await longChat(f, 4);
		await wipeMemory({ ...f.ctx, requestId: `wipe-${++n}-xxxxxxxx` }, { confirm: true });
		// The wipe also drops the queued compaction itself
		expect(await jobsOf(f)).toHaveLength(0);
		const handlers = createChatHandlers({
			historyTokens: 300,
			model: () => ({
				complete: async (ctx) => {
					if (ctx.actor.userId === f.userId) throw new Error('must not be called');
					return completion('another person');
				}
			})
		});
		expect(
			await runBatch(t.handle, handlers, { now: new Date(Date.now() + 120_000) })
		).toBeGreaterThanOrEqual(0);
	});
});

describe('a fork', () => {
	it('copies the tool rounds with the messages and starts with no summary', async () => {
		const f = await seedPerson(t);
		await say(
			f,
			stubModel([{ calls: [['accounts_list', {}]], provider: 'anthropic' }]),
			'accounts?'
		);
		const [c] = await chatsOf(f);
		await withUser(t.handle, f.userId, (tx) =>
			tx.update(chat).set({ summary: 'old summary' }).where(eq(chat.id, c!.id))
		);
		const forked = await chatFork(
			{ ...f.ctx, requestId: `fork-${++n}-xxxxxxxx` },
			{ chatId: c!.id }
		);
		const turns = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(chatTurn).where(eq(chatTurn.chatId, forked.chatId))
		);
		expect(readTranscript(turns[0]?.transcript)?.map((m) => m.role)).toEqual(['assistant', 'tool']);
		const [copy] = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(chat).where(eq(chat.id, forked.chatId))
		);
		expect(copy?.summary).toBeNull();
		expect(copy?.summaryThroughTurnId).toBeNull();
	});
});
