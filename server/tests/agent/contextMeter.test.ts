// THE CONTEXT METER: THE WINDOW PER HOST, THE LIVE USAGE EVENT (NEVER STORED, NEVER AN ESTIMATE), THE FIGURE KEPT FOR THE CHAT, THIS MONTH'S SHARE,
// AND "SUMMARIZE NOW" (THE PERSON'S OWN VERB, THE SAME BACKGROUND JOB, NO MODEL CALL OF ITS OWN INSIDE THE VERB).

// -- TYPES -- //
import type { Fixture } from './support';
import type { TurnEvent, TurnModel } from '../../src/lib/server/agent/turn';
import type { Completion, StreamEvent } from '../../src/lib/server/proxy/types';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { handleChat } from '../../src/lib/server/agent/chat';
import { contextWindow, windowOverride } from '../../src/lib/server/agent/contextWindow';
import { chat, chatTurn, job } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createChatHandlers } from '../../src/lib/server/jobs/chat';
import { runBatch } from '../../src/lib/server/jobs/queue';
import { chatHistory } from '../../src/lib/server/ops/chatHistory';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { recordUsage } from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';
import { asPerson, seedPerson, stubModel } from './support';

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

async function say(f: Fixture, model: TurnModel, text: string, chatId?: string) {
	const events: TurnEvent[] = [];
	for await (const e of handleChat(
		f.ctx,
		{ clientMessageId: `meter-${++n}-${'x'.repeat(8)}`, text, ...(chatId ? { chatId } : {}) },
		{ model, noMemory: true }
	))
		events.push(e);
	return events;
}

const verb = <T>(who: Fixture, name: string, input: unknown, requestId: string = randomUUID()) =>
	invokeVerb({ ...who.ctx, requestId }, name, input) as Promise<T>;

const chatOf = (f: Fixture) =>
	withUser(t.handle, f.userId, async (tx) => {
		const [c] = await tx.select().from(chat).where(eq(chat.userId, f.userId));
		return c;
	});

const completion = (content: string): Completion => ({
	content,
	toolCalls: [],
	finishReason: 'stop',
	usage: { promptTokens: 10, completionTokens: 5 }
});

/** A model whose one answer reports no usage of its own, so the loop only has an estimate. */
const estimatingModel = (): TurnModel => ({
	async *stream(): AsyncGenerator<StreamEvent> {
		yield { type: 'delta', text: 'ok' };
		yield {
			type: 'done',
			completion: {
				content: 'ok',
				toolCalls: [],
				finishReason: 'stop',
				usage: { promptTokens: 777, completionTokens: 5, estimated: true }
			}
		};
	}
});

// -- TESTS -- //

describe('the context window', () => {
	it('is 1,000,000 tokens for DeepSeek, and an unknown host falls back to it', () => {
		expect(contextWindow('deepseek', undefined)).toBe(1_000_000);
		expect(contextWindow('somewhere', '')).toBe(1_000_000);
		expect(contextWindow(null, undefined)).toBe(1_000_000);
	});

	it('takes CONTEXT_WINDOW_TOKENS when it is set, and stops on a bad value', () => {
		expect(contextWindow('deepseek', '128000')).toBe(128_000);
		expect(windowOverride('  ')).toBeNull();
		for (const bad of ['0', '-5', 'abc', '1.5'])
			expect(() => windowOverride(bad)).toThrow(/CONTEXT_WINDOW_TOKENS/);
	});
});

describe('the usage event', () => {
	it('comes after each model call with the reported prompt size and the window, and on done', async () => {
		const f = await seedPerson(t);
		const model = stubModel([
			{
				calls: [['calc', { expression: '1+1' }]],
				usage: { promptTokens: 82_000, completionTokens: 20 }
			},
			{ say: 'two', usage: { promptTokens: 83_500, completionTokens: 10 } }
		]);
		const events = await say(f, model, 'What is one plus one?');
		const usage = events.filter((e) => e.type === 'usage');
		expect(usage).toEqual([
			{ type: 'usage', promptTokens: 82_000, window: 1_000_000 },
			{ type: 'usage', promptTokens: 83_500, window: 1_000_000 }
		]);
		const done = events.find((e) => e.type === 'done');
		expect(done).toMatchObject({ context: { promptTokens: 83_500, window: 1_000_000 } });
	});

	it('is never stored with the message, and carries no text', async () => {
		const f = await seedPerson(t);
		await say(
			f,
			stubModel([{ say: 'hello', usage: { promptTokens: 5_000, completionTokens: 5 } }]),
			'Hi'
		);
		const rows = await withUser(t.handle, f.userId, (tx) =>
			tx.select({ events: chatTurn.events }).from(chatTurn).where(eq(chatTurn.userId, f.userId))
		);
		expect(JSON.stringify(rows)).not.toContain('usage');
		expect(JSON.stringify(rows)).not.toContain('promptTokens');
	});

	it('is not sent for an estimate, and the chat then keeps no figure', async () => {
		const f = await seedPerson(t);
		const events = await say(f, estimatingModel(), 'Hi');
		expect(events.some((e) => e.type === 'usage')).toBe(false);
		expect(events.find((e) => e.type === 'done')).not.toHaveProperty('context');
		expect((await chatOf(f))?.lastPromptTokens).toBeNull();
	});

	it('is kept for the chat once, from the last answer, and comes back when the chat is restored', async () => {
		const f = await seedPerson(t);
		await say(
			f,
			stubModel([{ say: 'one', usage: { promptTokens: 12_000, completionTokens: 5 } }]),
			'First'
		);
		await say(
			f,
			stubModel([{ say: 'two', usage: { promptTokens: 20_000, completionTokens: 5 } }]),
			'Second'
		);
		expect((await chatOf(f))?.lastPromptTokens).toBe(20_000);
		const h = await chatHistory(f.ctx, {});
		expect(h.chat).toMatchObject({
			contextTokens: 20_000,
			contextWindow: 1_000_000,
			summarizedAt: null
		});
	});

	it('reads as unknown on a chat that never had a figure (the ring stays hidden)', async () => {
		const f = await seedPerson(t);
		const h = await chatHistory(f.ctx, {});
		expect(h.chat).toBeNull();
		await verb(f, 'chat_new', {});
		const fresh = await chatHistory(f.ctx, {});
		expect(fresh.chat).toMatchObject({ contextTokens: null, summarizedAt: null });
	});

	it('leaves the last good figure when a message is cancelled', async () => {
		const f = await seedPerson(t);
		await say(
			f,
			stubModel([{ say: 'one', usage: { promptTokens: 9_000, completionTokens: 5 } }]),
			'First'
		);
		const stop = new AbortController();
		const events: TurnEvent[] = [];
		for await (const e of handleChat(
			f.ctx,
			{ clientMessageId: `meter-${++n}-${'x'.repeat(8)}`, text: 'Second' },
			{
				model: {
					async *stream(): AsyncGenerator<StreamEvent> {
						stop.abort();
						yield { type: 'delta', text: 'half' };
						yield {
							type: 'done',
							// The person stops it while it asks for a tool: the loop ends as cancelled, so this size is not kept
							completion: {
								...completion('half'),
								toolCalls: [
									{
										id: 'call_x',
										type: 'function',
										function: { name: 'calc', arguments: '{"expression":"1+1"}' }
									}
								],
								finishReason: 'tool_calls',
								usage: { promptTokens: 50_000, completionTokens: 1 }
							}
						};
					}
				},
				noMemory: true,
				signal: stop.signal
			}
		))
			events.push(e);
		expect((await chatOf(f))?.lastPromptTokens).toBe(9_000);
		expect(events.find((e) => e.type === 'done')).not.toHaveProperty('context');
	});
});

describe('this month, chat_usage', () => {
	it('sums the charged chat tokens of the person only, with the cap of the chat bucket', async () => {
		const f = await seedPerson(t);
		const other = await seedPerson(t);
		await withUser(t.handle, f.userId, (tx) =>
			recordUsage(tx, f.userId, 'chat', { promptTokens: 1_000, completionTokens: 500 }, 'deepseek')
		);
		await withUser(t.handle, f.userId, (tx) =>
			recordUsage(
				tx,
				f.userId,
				'memory',
				{ promptTokens: 9_000, completionTokens: 9_000 },
				'deepseek'
			)
		);
		await withUser(t.handle, other.userId, (tx) =>
			recordUsage(
				tx,
				other.userId,
				'chat',
				{ promptTokens: 77_000, completionTokens: 1 },
				'deepseek'
			)
		);
		const mine = await verb<{ used: number; cap: number }>(f, 'chat_usage', {});
		expect(mine.used).toBe(1_500);
		expect(mine.cap).toBe(8_000_000);
		expect(Object.keys(mine).sort()).toEqual(['cap', 'used']);
	});

	it('is the person only: the assistant is refused', async () => {
		const f = await seedPerson(t);
		await expect(
			invokeVerb(
				{
					...asPerson(t.handle, f.userId),
					actor: { userId: f.userId, kind: 'agent' },
					requestId: randomUUID()
				},
				'chat_usage',
				{}
			)
		).rejects.toBeDefined();
	});
});

describe('Summarize now, chat_compact', () => {
	const jobsOf = (f: Fixture) =>
		withUser(t.handle, f.userId, (tx) =>
			tx
				.select()
				.from(job)
				.where(and(eq(job.userId, f.userId), eq(job.kind, 'chat.compact')))
		);

	async function chatOfLength(f: Fixture, count: number) {
		for (let i = 0; i < count; i++)
			await say(f, stubModel([{ say: `answer ${i}` }]), `question ${i}`);
		const c = await chatOf(f);
		return c!.id;
	}

	it('refuses a chat with too little to fold, and queues nothing', async () => {
		const f = await seedPerson(t);
		const chatId = await chatOfLength(f, 3);
		expect(await verb(f, 'chat_compact', { chatId })).toEqual({ queued: false, reason: 'short' });
		expect(await jobsOf(f)).toHaveLength(0);
	});

	it('queues the same job at any size, once, and says busy while it waits', async () => {
		const f = await seedPerson(t);
		const chatId = await chatOfLength(f, 5);
		expect(await jobsOf(f)).toHaveLength(0);
		expect(await verb(f, 'chat_compact', { chatId })).toEqual({ queued: true });
		const queued = await jobsOf(f);
		expect(queued).toHaveLength(1);
		expect(queued[0]?.payload).toMatchObject({ chatId, manual: true });
		expect(await verb(f, 'chat_compact', { chatId })).toEqual({ queued: false, reason: 'busy' });
		expect(await jobsOf(f)).toHaveLength(1);
	});

	it('replays the first answer for the same request id and queues nothing twice', async () => {
		const f = await seedPerson(t);
		const chatId = await chatOfLength(f, 5);
		const id = randomUUID();
		const first = await verb(f, 'chat_compact', { chatId }, id);
		const again = await verb(f, 'chat_compact', { chatId }, id);
		expect(again).toEqual(first);
		expect(await jobsOf(f)).toHaveLength(1);
	});

	it('folds a short history into the summary when the job runs, keeping the last two messages', async () => {
		const f = await seedPerson(t);
		const chatId = await chatOfLength(f, 5);
		await verb(f, 'chat_compact', { chatId });
		const handlers = createChatHandlers({
			model: () => ({
				complete: async (ctx) =>
					completion(ctx.actor.userId === f.userId ? 'MANUAL SUMMARY' : 'another person')
			})
		});
		await runBatch(t.handle, handlers, { now: new Date(Date.now() + 120_000) });
		const c = await chatOf(f);
		expect(c?.summary).toBe('MANUAL SUMMARY');
		expect(c?.summaryAt).not.toBeNull();
		const rows = await withUser(t.handle, f.userId, (tx) =>
			tx
				.select({ id: chatTurn.id })
				.from(chatTurn)
				.where(eq(chatTurn.userId, f.userId))
				.orderBy(chatTurn.createdAt, chatTurn.id)
		);
		expect(c?.summaryThroughTurnId).toBe(rows[rows.length - 3]?.id);
		const h = await chatHistory(f.ctx, {});
		expect(h.chat?.summarizedAt).not.toBeNull();
	});

	it("is the person's own: not another person's chat, and not the assistant", async () => {
		const f = await seedPerson(t);
		const other = await seedPerson(t);
		const chatId = await chatOfLength(f, 5);
		await expect(verb(other, 'chat_compact', { chatId })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await expect(
			invokeVerb(
				{ ...f.ctx, actor: { userId: f.userId, kind: 'agent' }, requestId: randomUUID() },
				'chat_compact',
				{ chatId }
			)
		).rejects.toBeDefined();
		expect(await jobsOf(f)).toHaveLength(0);
	});
});
