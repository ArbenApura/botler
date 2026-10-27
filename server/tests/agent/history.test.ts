// THE RECENT CONVERSATION VERB: ONLY MY OWN TURNS, OLDEST FIRST, NOTHING STILL RUNNING, CARDS WITH THEIR STATUS NOW, ODD STORED EVENTS SKIPPED,
// A SIZE BUDGET, PERSON-ONLY, AND NO EFFECT ON WHAT THE MODEL IS SENT.

// -- TYPES -- //
import type { Fixture } from './support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { handleChat } from '../../src/lib/server/agent/chat';
import { buildTools } from '../../src/lib/server/agent/tools';
import { agentAction, chatTurn } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { chatHistory } from '../../src/lib/server/ops/chatHistory';
import { OpsError } from '../../src/lib/server/ops/context';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { chatOf } from '../support/chats';
import { createTestDb } from '../support/testDb';
import { seedPerson, stubModel } from './support';

// -- STATES -- //

let t: TestDb;
let me: Fixture;
let other: Fixture;
let n = 0;

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

type Seed = {
	who?: Fixture;
	text?: string;
	reply?: string;
	status?: 'running' | 'done' | 'failed';
	events?: unknown;
	minutesAgo?: number;
};

async function turn(s: Seed = {}) {
	const who = s.who ?? me;
	const id = `hist-${++n}-${'x'.repeat(8)}`;
	await withUser(t.handle, who.userId, async (tx) =>
		tx.insert(chatTurn).values({
			userId: who.userId,
			chatId: await chatOf(tx, who.userId),
			clientMessageId: id,
			userText: s.text ?? `question ${n}`,
			reply: s.reply ?? `answer ${n}`,
			status: s.status ?? 'done',
			events: s.events ?? [],
			createdAt: new Date(Date.now() - (s.minutesAgo ?? 1) * 60_000)
		})
	);
	return id;
}

async function card(who: Fixture, status: 'pending' | 'applied', expiresInMs: number) {
	const [row] = await withUser(t.handle, who.userId, (tx) =>
		tx
			.insert(agentAction)
			.values({
				userId: who.userId,
				verb: 'bill_create',
				args: {},
				summary: 'Add the bill "Gym".',
				status,
				expiresAt: new Date(Date.now() + expiresInMs)
			})
			.returning({ id: agentAction.id })
	);
	return row!.id;
}

const history = (who: Fixture, limit?: number) =>
	chatHistory(who.ctx, limit === undefined ? {} : { limit });

// -- TESTS -- //

describe('chat_history', () => {
	it('returns only my own turns, oldest first, and honours the limit', async () => {
		const fresh = await seedPerson(t);
		await turn({ who: fresh, text: 'first', minutesAgo: 30 });
		await turn({ who: fresh, text: 'second', minutesAgo: 20 });
		await turn({ who: fresh, text: 'third', minutesAgo: 10 });
		await turn({ who: other, text: 'not yours', minutesAgo: 5 });
		const all = await history(fresh);
		expect(all.turns.map((x) => x.text)).toEqual(['first', 'second', 'third']);
		const two = await history(fresh, 2);
		// The newest two, still oldest first
		expect(two.turns.map((x) => x.text)).toEqual(['second', 'third']);
		expect((await history(other)).turns.some((x) => x.text === 'first')).toBe(false);
	});

	it('leaves out a turn still running, keeps a failed one without an answer, and gives the message id', async () => {
		const p = await seedPerson(t);
		await turn({ who: p, text: 'busy', status: 'running', minutesAgo: 3 });
		const id = await turn({ who: p, text: 'broke', status: 'failed', reply: '', minutesAgo: 2 });
		const { turns } = await history(p);
		expect(turns.map((x) => x.text)).toEqual(['broke']);
		expect(turns[0]?.status).toBe('failed');
		expect(turns[0]?.clientMessageId).toBe(id);
	});

	it('skips odd stored events instead of failing the whole answer', async () => {
		const p = await seedPerson(t);
		await turn({
			who: p,
			events: [
				{ type: 'tool', name: 'accounts_list', status: 'ok', data: { a: 1 } },
				{ type: 'tool', id: 'c1', name: 'x', status: 'nonsense' },
				{ type: 'mystery' },
				'a string',
				null,
				{ type: 'fallback', reason: 'down', form: 'expense' }
			]
		});
		await turn({ who: p, events: null });
		await turn({ who: p, events: { not: 'a list' } });
		const { turns } = await history(p);
		expect(turns).toHaveLength(3);
		const kinds = turns.flatMap((x) => x.events.map((e) => e.type));
		expect(kinds.sort()).toEqual(['fallback', 'tool']);
		// An old tool event has no id and is kept
		expect(turns.flatMap((x) => x.events).find((e) => e.type === 'tool')).not.toHaveProperty('id');
	});

	it('drops tool data over 4000 characters, shortens a long message and keeps 12 events', async () => {
		const p = await seedPerson(t);
		const events = Array.from({ length: 15 }, (_, i) => ({
			type: 'tool',
			name: `tool_${i}`,
			status: 'ok',
			message: 'm'.repeat(1000),
			data: i === 0 ? { big: 'z'.repeat(5000) } : { small: i }
		}));
		await turn({ who: p, events });
		const [first] = (await history(p)).turns;
		expect(first?.events).toHaveLength(12);
		const tool0 = first?.events[0];
		expect(tool0 && 'data' in tool0).toBe(false);
		expect(tool0 && 'message' in tool0 ? tool0.message?.length : 0).toBe(300);
		expect(first?.events[1] && 'data' in first.events[1]).toBe(true);
	});

	it('tells the status a card has now', async () => {
		const p = await seedPerson(t);
		const live = await card(p, 'pending', 3_600_000);
		const lapsed = await card(p, 'pending', -3_600_000);
		const done = await card(p, 'applied', 3_600_000);
		const gone = '11111111-1111-4111-8111-111111111111';
		await turn({
			who: p,
			events: [live, lapsed, done, gone].map((actionId) => ({
				type: 'card',
				actionId,
				summary: 'Add the bill "Gym".'
			}))
		});
		const [first] = (await history(p)).turns;
		const by = Object.fromEntries(
			(first?.events ?? []).flatMap((e) => (e.type === 'card' ? [[e.actionId, e.status]] : []))
		);
		expect(by[live]).toBe('pending');
		expect(by[lapsed]).toBe('expired');
		expect(by[done]).toBe('applied');
		expect(by[gone]).toBe('gone');
	});

	it('does not show another person the status of a card that is not theirs', async () => {
		const p = await seedPerson(t);
		const theirs = await card(other, 'applied', 3_600_000);
		await turn({
			who: p,
			events: [{ type: 'card', actionId: theirs, summary: 'x' }]
		});
		const [first] = (await history(p)).turns;
		expect(first?.events[0]).toMatchObject({ type: 'card', status: 'gone' });
	});

	it('shows a turn left running long ago as failed, and one running just now not at all', async () => {
		const p = await seedPerson(t);
		const old = await turn({ who: p, text: 'left behind', status: 'running', minutesAgo: 30 });
		await turn({ who: p, text: 'busy now', status: 'running', minutesAgo: 0 });
		// updated_at is what marks it stale: make the first one old
		await withUser(t.handle, p.userId, (tx) =>
			tx
				.update(chatTurn)
				.set({ updatedAt: new Date(Date.now() - 10 * 60_000) })
				.where(eq(chatTurn.clientMessageId, old))
		);
		const { turns } = await history(p);
		expect(turns.map((x) => [x.text, x.status])).toEqual([['left behind', 'failed']]);
	});

	it('keeps a card with a very long summary and cuts a huge reply', async () => {
		const p = await seedPerson(t);
		const live = await card(p, 'pending', 3_600_000);
		await turn({
			who: p,
			reply: 'r'.repeat(50_000),
			events: [{ type: 'card', actionId: live, summary: 's'.repeat(5_000) }]
		});
		const [first] = (await history(p)).turns;
		expect(first?.reply.length).toBe(20_000);
		expect(first?.events[0]).toMatchObject({ type: 'card', status: 'pending' });
	});

	it('stays under the size budget by dropping old tool data and then old turns', async () => {
		const p = await seedPerson(t);
		for (let i = 0; i < 30; i++)
			await turn({
				who: p,
				text: `t${i}`,
				reply: 'r'.repeat(12000),
				minutesAgo: 100 - i,
				events: Array.from({ length: 12 }, (_, j) => ({
					type: 'tool',
					name: `tool_${j}`,
					status: 'ok',
					data: { v: 'd'.repeat(3500) }
				}))
			});
		const out = await history(p, 30);
		expect(JSON.stringify(out).length).toBeLessThanOrEqual(200_000);
		// Old turns went first; the newest is the last to lose anything
		expect(out.turns.length).toBeLessThan(30);
		expect(out.turns.at(-1)?.text).toBe('t29');
	});
});

describe('who may ask', () => {
	it('is for the person only: the assistant is refused, and it is not an assistant tool', async () => {
		await expect(
			chatHistory({ ...me.ctx, actor: { ...me.ctx.actor, kind: 'agent' } }, {})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await expect(
			invokeVerb({ ...me.ctx, actor: { ...me.ctx.actor, kind: 'agent' } }, 'chat_history', {})
		).rejects.toBeInstanceOf(OpsError);
		expect(buildTools().map((x) => x.name)).not.toContain('chat_history');
	});

	it('refuses odd arguments', async () => {
		await expect(chatHistory(me.ctx, { limit: 0 })).rejects.toMatchObject({ code: 'INVALID' });
		await expect(chatHistory(me.ctx, { limit: 31 })).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			chatHistory(me.ctx, { limit: 5, userId: 'someone-else' } as never)
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('the model prompt', () => {
	it('is held under the history token budget however long the stored conversation is', async () => {
		const p = await seedPerson(t);
		for (let i = 0; i < 40; i++)
			await turn({ who: p, text: 'q'.repeat(3000), reply: 'a'.repeat(3000), minutesAgo: 200 - i });
		const model = stubModel([{ say: 'ok' }]);
		for await (const _ of handleChat(
			p.ctx,
			{ clientMessageId: `hist-prompt-${++n}-aaaa`, text: 'and now?' },
			// About 1500 tokens a turn: a 20000 token budget keeps nine turns, in steps of five from the start
			{ model, noMemory: true, historyTokens: 20_000 }
		));
		const sent = model.requests[0]!.messages.filter(
			(m) => m.role === 'user' || m.role === 'assistant'
		);
		const tokens = sent
			.slice(0, -1)
			.reduce(
				(sum, m) => sum + Math.ceil((typeof m.content === 'string' ? m.content.length : 0) / 4),
				0
			);
		expect(tokens).toBeLessThanOrEqual(20_000);
		// Replies are no longer cut at 1500 characters
		expect(sent.some((m) => m.role === 'assistant' && String(m.content).length === 3000)).toBe(
			true
		);
		expect(sent.length).toBeGreaterThan(4);
		expect(sent.at(-1)?.role).toBe('user');
	});
});
