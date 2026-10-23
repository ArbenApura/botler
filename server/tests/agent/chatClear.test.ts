// A NEW CHAT: THE EARLIER CONVERSATION STAYS IN THE LIST (NEVER DELETED), THE SCREEN AND THE ASSISTANT START FRESH, ONLY THE PERSON CAN DO IT, A REPLAY DOES NOTHING TWICE.

// -- TYPES -- //
import type { Fixture } from './support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { chatTurn } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { chatHistory } from '../../src/lib/server/ops/chatHistory';
import { chatList } from '../../src/lib/server/ops/chats';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { chatOf } from '../support/chats';
import { createTestDb } from '../support/testDb';
import { seedPerson } from './support';

// -- STATES -- //

let t: TestDb;
let me: Fixture;
let other: Fixture;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	me = await seedPerson(t);
	other = await seedPerson(t);
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

async function turn(who: Fixture, text: string, status: 'running' | 'done' = 'done') {
	await withUser(t.handle, who.userId, async (tx) =>
		tx.insert(chatTurn).values({
			userId: who.userId,
			chatId: await chatOf(tx, who.userId),
			clientMessageId: randomUUID(),
			userText: text,
			reply: 'ok',
			status
		})
	);
}

const clear = (who: Fixture, requestId: string = randomUUID()) =>
	invokeVerb({ ...who.ctx, requestId }, 'chat_clear', {}) as Promise<{
		cleared: number;
		chatId: string;
	}>;

// -- TESTS -- //

describe('chat_clear (a new chat)', () => {
	it('empties the screen, keeps the old chat in the list, and leaves other people alone', async () => {
		await turn(me, 'one');
		await turn(me, 'two');
		await turn(other, 'theirs');
		const first = await clear(me);
		expect(first.cleared).toBe(2);
		expect((await chatHistory(me.ctx, {})).turns).toEqual([]);
		expect((await chatHistory(other.ctx, {})).turns).toHaveLength(1);
		// Set aside, not deleted: it is a chat of its own in the list, and its turns stay for memory
		const listed = (await chatList(me.ctx, {})).chats;
		expect(listed).toHaveLength(1);
		expect(listed[0]).toMatchObject({ turns: 2 });
		const rows = await withUser(t.handle, me.userId, (tx) =>
			tx.select().from(chatTurn).where(eq(chatTurn.userId, me.userId))
		);
		expect(rows).toHaveLength(2);
	});

	it('shows only what is said after it, and two quick taps make one chat', async () => {
		await turn(me, 'after');
		expect((await chatHistory(me.ctx, {})).turns.map((x) => x.text)).toEqual(['after']);
		const a = await clear(me);
		const b = await clear(me);
		expect(a.cleared).toBe(1);
		// The new chat is still empty, so it is used again
		expect(b.chatId).toBe(a.chatId);
		expect(b.cleared).toBe(0);
	});

	it('leaves a turn that is still running in its chat, and a replay returns the first answer', async () => {
		const fresh = await seedPerson(t);
		await turn(fresh, 'done one');
		await turn(fresh, 'working', 'running');
		const id = randomUUID();
		const first = await clear(fresh, id);
		expect(first.cleared).toBe(2);
		await expect(clear(fresh, id)).resolves.toEqual(first);
	});

	it('is for the person only', async () => {
		await expect(
			invokeVerb(
				{ ...me.ctx, requestId: randomUUID(), actor: { ...me.ctx.actor, kind: 'agent' } },
				'chat_clear',
				{}
			)
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});
});
