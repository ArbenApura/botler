// ONE MESSAGE AT A TIME IN A CHAT: A NEW MESSAGE WAITS (A RETRYABLE BUSY_CHAT) WHILE ANOTHER ONE OF THE SAME CHAT IS BEING ANSWERED, A STUCK TURN DOES NOT HOLD IT,
// AND ANOTHER CHAT IS NEVER BLOCKED. NO LOCK IS HELD ACROSS THE MODEL CALL.

// -- TYPES -- //
import type { Fixture } from './support';
import type { TurnEvent, TurnModel } from '../../src/lib/server/agent/turn';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { handleChat } from '../../src/lib/server/agent/chat';
import { chatTurn } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';
import { doneEvent, seedPerson } from './support';

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

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));
const newId = (tag: string) => `${tag}-${++n}-${'z'.repeat(8)}`;

/** A model that waits `ms` and then answers. */
const slowModel = (ms: number, say = 'slow answer'): TurnModel => ({
	async *stream() {
		await sleep(ms);
		yield { type: 'delta', text: say };
		yield {
			type: 'done',
			completion: {
				content: say,
				toolCalls: [],
				finishReason: 'stop',
				usage: { promptTokens: 1, completionTokens: 1 }
			}
		};
	}
});

async function drain(
	f: Fixture,
	clientMessageId: string,
	model: TurnModel,
	chatId?: string,
	extra: Partial<Parameters<typeof handleChat>[2]> = {}
): Promise<TurnEvent[]> {
	const events: TurnEvent[] = [];
	for await (const e of handleChat(
		f.ctx,
		{ clientMessageId, text: 'hello there', ...(chatId ? { chatId } : {}) },
		{ model, noMemory: true, ...extra }
	))
		events.push(e);
	return events;
}

/** Starts a message and waits until the server has taken it (its start event), without finishing it. */
async function begin(f: Fixture, id: string, ms: number, chatId?: string) {
	const events: TurnEvent[] = [];
	const gen = handleChat(
		f.ctx,
		{ clientMessageId: id, text: 'hello there', ...(chatId ? { chatId } : {}) },
		{ model: slowModel(ms), noMemory: true, heartbeatMs: 40 }
	);
	const running = (async () => {
		for await (const e of gen) events.push(e);
		return events;
	})();
	while (!events.some((e) => e.type === 'start')) await sleep(10);
	const start = events.find((e) => e.type === 'start') as { chatId: string };
	return { running, chatId: start.chatId };
}

// -- TESTS -- //

describe('one message at a time in a chat', () => {
	it('refuses a second message of the same chat while the first runs, and takes it once the first is done', async () => {
		const f = await seedPerson(t);
		const first = await begin(f, newId('one'), 400);
		await expect(drain(f, newId('two'), slowModel(5), first.chatId)).rejects.toMatchObject({
			code: 'BUSY_CHAT'
		});
		const events = await first.running;
		expect(doneEvent(events)?.reply).toBe('slow answer');
		// The same id the app used for its refused try is accepted now
		const again = await drain(f, newId('three'), slowModel(5, 'second'), first.chatId);
		expect(doneEvent(again)?.reply).toBe('second');
	});

	it('never blocks another chat of the same person', async () => {
		const f = await seedPerson(t);
		const first = await begin(f, newId('one'), 300);
		const other = (await invokeVerb({ ...f.ctx, requestId: newId('chatnew') }, 'chat_new', {})) as {
			chatId: string;
		};
		expect(other.chatId).not.toBe(first.chatId);
		const events = await drain(f, newId('other'), slowModel(5, 'elsewhere'), other.chatId);
		expect(doneEvent(events)?.reply).toBe('elsewhere');
		await first.running;
	});

	it('does not let a turn that stopped heartbeating hold the chat', async () => {
		const f = await seedPerson(t);
		const first = await begin(f, newId('one'), 150);
		await first.running;
		// A row left "running" long ago: the app that sent it is gone
		await withUser(t.handle, f.userId, (tx) =>
			tx.insert(chatTurn).values({
				userId: f.userId,
				chatId: first.chatId,
				clientMessageId: newId('stuck'),
				userText: 'left behind',
				status: 'running',
				updatedAt: sql`now() - interval '5 minutes'`
			})
		);
		const events = await drain(f, newId('after'), slowModel(5, 'fine'), first.chatId);
		expect(doneEvent(events)?.reply).toBe('fine');
	});

	it('still answers the repeat of the running message itself with CONFLICT, not BUSY_CHAT', async () => {
		const f = await seedPerson(t);
		const id = newId('same');
		const first = await begin(f, id, 300);
		await expect(drain(f, id, slowModel(5), first.chatId)).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		await first.running;
	});
});
