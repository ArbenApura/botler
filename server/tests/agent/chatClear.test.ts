// A NEW CHAT: THE EARLIER CONVERSATION IS SET ASIDE FOR THE SCREEN AND FOR THE MODEL, NEVER DELETED, ONLY THE PERSON CAN DO IT, A REPLAY DOES NOTHING TWICE.

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
import { invokeVerb } from '../../src/lib/server/ops/registry';
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
	await withUser(t.handle, who.userId, (tx) =>
		tx.insert(chatTurn).values({
			userId: who.userId,
			clientMessageId: randomUUID(),
			userText: text,
			reply: 'ok',
			status
		})
	);
}

const clear = (who: Fixture, requestId: string = randomUUID()) =>
	invokeVerb({ ...who.ctx, requestId }, 'chat_clear', {});

// -- TESTS -- //

describe('chat_clear', () => {
	it('empties the screen history, keeps the rows, and leaves other people alone', async () => {
		await turn(me, 'one');
		await turn(me, 'two');
		await turn(other, 'theirs');
		await expect(clear(me)).resolves.toEqual({ cleared: 2 });
		expect((await chatHistory(me.ctx, {})).turns).toEqual([]);
		expect((await chatHistory(other.ctx, {})).turns).toHaveLength(1);
		// Set aside, not deleted: the memory jobs still read them
		const rows = await withUser(t.handle, me.userId, (tx) =>
			tx.select().from(chatTurn).where(eq(chatTurn.userId, me.userId))
		);
		expect(rows).toHaveLength(2);
		expect(rows.every((r) => r.clearedAt !== null)).toBe(true);
	});

	it('shows only what is said after it, and a second clear takes only the new turns', async () => {
		await turn(me, 'after');
		expect((await chatHistory(me.ctx, {})).turns.map((x) => x.text)).toEqual(['after']);
		await expect(clear(me)).resolves.toEqual({ cleared: 1 });
	});

	it('leaves a turn that is still running, and a replay returns the first answer', async () => {
		const fresh = await seedPerson(t);
		await turn(fresh, 'done one');
		await turn(fresh, 'working', 'running');
		const id = randomUUID();
		await expect(clear(fresh, id)).resolves.toEqual({ cleared: 1 });
		await expect(clear(fresh, id)).resolves.toEqual({ cleared: 1 });
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
