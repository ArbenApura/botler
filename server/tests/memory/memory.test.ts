// MEMORY AGAINST A REAL (THROWAWAY) DATABASE: FACTS IN TIME, WHO MAY END A FACT, TOMBSTONES, RETRIEVAL AND ITS BUDGET, THE JOBS, MOOD AND FADING,
// MASKING OF NAMES, LOGS WITHOUT MESSAGE TEXT, EXPORT AND WIPE, AND ISOLATION BETWEEN PEOPLE

// -- TYPES -- //
import type { JobRow } from '../../src/lib/server/jobs/queue';
import type { Ctx } from '../../src/lib/server/ops/context';
import type { Completion, CompletionRequest } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { and, eq, isNull } from 'drizzle-orm';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { handleChat } from '../../src/lib/server/agent/chat';
import {
	chatTurn,
	job,
	memoryFact,
	memoryProfile,
	memorySummary,
	user
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createMemoryHandlers } from '../../src/lib/server/jobs/memory';
import { loadMemoryContext } from '../../src/lib/server/memory/retrieve';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import {
	editFact,
	exportAll,
	forgetFact,
	getProfile,
	listFacts,
	rememberFact,
	resolveConflict,
	searchMemory,
	setProfile,
	upsertFact,
	wipeMemory
} from '../../src/lib/server/ops/memory';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { fakeEmbedder } from '../support/embed';
import { chatOf } from '../support/chats';
import { createTestDb } from '../support/testDb';
import { stubModel } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let counter = 0;
const embedder = fakeEmbedder();

// -- FUNCTIONS -- //

const rid = () => `req-mem-${String(++counter).padStart(6, '0')}`;
async function newUser(): Promise<Ctx> {
	const id = `user_mem_${String(++counter).padStart(5, '0')}`;
	await t.handle.db.insert(user).values({ id, name: id, email: `${id}@example.com` });
	return { handle: t.handle, actor: { userId: id, kind: 'person' } };
}
const as = (c: Ctx): Ctx => ({ ...c, requestId: rid() });
const agentOf = (c: Ctx): Ctx => ({
	handle: c.handle,
	actor: { userId: c.actor.userId, kind: 'agent' }
});

type Answers = string[];
/** A model whose complete() returns the next canned text and records what it was asked. */
function completer(answers: Answers) {
	const asked: CompletionRequest[] = [];
	return {
		asked,
		complete: async (_ctx: Ctx, req: CompletionRequest): Promise<Completion> => {
			asked.push(req);
			return {
				content: answers[asked.length - 1] ?? '{"facts":[],"mood_delta":0}',
				toolCalls: [],
				finishReason: 'stop',
				usage: { promptTokens: 1, completionTokens: 1 }
			};
		}
	};
}

function handlersFor(
	model: ReturnType<typeof completer>,
	opts: { now?: Date; embedder?: typeof embedder | null } = {}
) {
	return createMemoryHandlers({
		model: () => model,
		embedder: () => (opts.embedder === undefined ? embedder : opts.embedder),
		now: () => opts.now ?? new Date()
	});
}

async function runJob(
	handlers: ReturnType<typeof handlersFor>,
	kind: string,
	c: Ctx,
	payload: Record<string, unknown> = {}
) {
	const userId = c.actor.userId;
	const row: JobRow = {
		id: 'job-test',
		userId,
		kind,
		key: 'k',
		payload,
		attempts: 1,
		maxAttempts: 5
	};
	const handler = handlers[kind];
	if (!handler) throw new Error(`no handler ${kind}`);
	await withUser(t.handle, userId, (tx) =>
		handler(row, tx, { handle: t.handle, actor: { userId, kind: 'agent', tool: `job:${kind}` } })
	);
}

const facts = (c: Ctx, include?: { history?: boolean; pending?: boolean }) =>
	listFacts(c, include ?? {});
const texts = async (c: Ctx) => (await facts(c)).map((f) => f.text).sort();

async function addTurn(
	c: Ctx,
	values: { id: string; userText: string; reply?: string; at?: string }
) {
	const [row] = await withUser(t.handle, c.actor.userId, async (tx) =>
		tx
			.insert(chatTurn)
			.values({
				userId: c.actor.userId,
				chatId: await chatOf(tx, c.actor.userId),
				clientMessageId: values.id,
				userText: values.userText,
				reply: values.reply ?? '',
				status: 'done',
				...(values.at ? { createdAt: new Date(values.at) } : {})
			})
			.returning({ id: chatTurn.id })
	);
	return row?.id ?? '';
}

const setFact = (c: Ctx, id: string, patch: Partial<typeof memoryFact.$inferInsert>) =>
	withUser(t.handle, c.actor.userId, (tx) =>
		tx.update(memoryFact).set(patch).where(eq(memoryFact.id, id))
	);

const rawFact = (c: Ctx, id: string) =>
	withUser(
		t.handle,
		c.actor.userId,
		async (tx) => (await tx.select().from(memoryFact).where(eq(memoryFact.id, id)))[0]
	);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

afterEach(() => {
	vi.restoreAllMocks();
});

// -- TESTS -- //

describe('facts in time', () => {
	it('ends the old fact when a newer one on the same subject arrives, and keeps it as history', async () => {
		const c = await newUser();
		const a = await rememberFact(as(c), {
			text: 'My sister lives in Manila',
			subject: 'sister home city'
		});
		const b = await rememberFact(as(c), {
			text: 'My sister lives in Cebu',
			subject: 'Sister Home City'
		});
		expect(b).toMatchObject({
			status: 'created',
			supersededId: a.status === 'created' ? a.id : ''
		});
		expect(await texts(c)).toEqual(['My sister lives in Cebu']);
		const history = await facts(c, { history: true });
		expect(history.map((f) => f.text).sort()).toEqual([
			'My sister lives in Cebu',
			'My sister lives in Manila'
		]);
		const old = history.find((f) => f.text.endsWith('Manila'));
		expect(old?.validTo).toBeTruthy();
		expect(old?.supersededBy).toBe(b.status === 'created' ? b.id : '');
	});

	it('does not store the same words twice', async () => {
		const c = await newUser();
		await rememberFact(as(c), { text: 'I like green tea' });
		expect(await rememberFact(as(c), { text: ' i LIKE green tea! ' })).toMatchObject({
			status: 'duplicate'
		});
		expect(await facts(c)).toHaveLength(1);
	});

	it("edits by ending the old wording and adding the new as the person's own", async () => {
		const c = await newUser();
		const a = await rememberFact(as(c), { text: 'I wake up at 6', subject: 'wake time' });
		const id = a.status === 'created' ? a.id : '';
		const edit = await editFact(as(c), { factId: id, text: 'I wake up at 5:30' });
		expect(edit).toMatchObject({ status: 'created', supersededId: id });
		expect((await facts(c))[0]).toMatchObject({ text: 'I wake up at 5:30', source: 'user' });
		await expect(editFact(as(c), { factId: id, text: 'again' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
	});

	it('takes account and card numbers out before storing', async () => {
		const c = await newUser();
		await rememberFact(as(c), {
			text: 'My RCBC account number is 1234567890123 and I pay rent from it'
		});
		const [f] = await facts(c);
		expect(f?.text).not.toMatch(/\d{6,}/);
		expect(f?.text).toContain('(details removed)');
	});
});

describe('who may end a fact', () => {
	it('keeps a fact the person wrote when the extractor disagrees, and asks the person', async () => {
		const c = await newUser();
		const mine = await rememberFact(as(c), { text: 'I live in Quezon City', subject: 'home city' });
		const outcome = await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, {
				text: 'The person lives in Makati',
				subject: 'home city',
				source: 'extracted',
				confidence: 95
			})
		);
		expect(outcome).toMatchObject({
			status: 'conflict',
			againstId: mine.status === 'created' ? mine.id : ''
		});
		expect(await texts(c)).toEqual(['I live in Quezon City']);
		const waiting = await facts(c, { pending: true });
		expect(waiting.map((f) => f.text)).toEqual(['The person lives in Makati']);

		// The person keeps the new one: it becomes theirs and the old one ends
		const pendingId = waiting[0]?.id ?? '';
		expect(await resolveConflict(as(c), { factId: pendingId, keep: 'new' })).toMatchObject({
			kept: 'new'
		});
		expect(await texts(c)).toEqual(['The person lives in Makati']);
		expect((await facts(c))[0]?.source).toBe('user');
	});

	it('declines a conflicting fact for good when the person keeps the old one', async () => {
		const c = await newUser();
		await rememberFact(as(c), { text: 'I take coffee black', subject: 'coffee' });
		const o = await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, {
				text: 'The person takes coffee with milk',
				subject: 'coffee',
				source: 'extracted'
			})
		);
		const id = o.status === 'conflict' ? o.id : '';
		await resolveConflict(as(c), { factId: id, keep: 'old' });
		expect(await texts(c)).toEqual(['I take coffee black']);
		const again = await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, {
				text: 'The person takes coffee with milk',
				subject: 'coffee',
				source: 'extracted'
			})
		);
		expect(again.status).toBe('tombstoned');
	});

	it('lets the extractor change its own facts when it is sure, and asks when it is not', async () => {
		const c = await newUser();
		const u = c.actor.userId;
		const first = await withUser(t.handle, u, (tx) =>
			upsertFact(tx, u, {
				text: 'The person works at Acme',
				subject: 'employer',
				source: 'extracted',
				confidence: 70
			})
		);
		const firstId = first.status === 'created' ? first.id : '';
		// An explicit change with good confidence ends the old fact
		const changed = await withUser(t.handle, u, (tx) =>
			upsertFact(tx, u, {
				text: 'The person now works at Globex',
				subject: 'employer',
				source: 'extracted',
				confidence: 85,
				replaces: firstId
			})
		);
		expect(changed).toMatchObject({ status: 'created', supersededId: firstId });
		// The same subject with no stated change and similar confidence is a question
		const unsure = await withUser(t.handle, u, (tx) =>
			upsertFact(tx, u, {
				text: 'The person works at Initech',
				subject: 'employer',
				source: 'extracted',
				confidence: 80
			})
		);
		expect(unsure.status).toBe('conflict');
		expect(await texts(c)).toEqual(['The person now works at Globex']);
	});
});

describe('after the person edits', () => {
	it('does not bring the old wording back when the extractor offers it again', async () => {
		const c = await newUser();
		const a = await rememberFact(as(c), { text: 'I wake up at 6', subject: 'wake time' });
		await editFact(as(c), {
			factId: a.status === 'created' ? a.id : '',
			text: 'I wake up at 5:30'
		});
		const again = await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, {
				text: 'I wake up at 6',
				subject: 'wake time',
				source: 'extracted',
				confidence: 99
			})
		);
		expect(again.status).toBe('conflict');
		expect(await texts(c)).toEqual(['I wake up at 5:30']);
	});
});

describe('mood and the money rules', () => {
	it('is never read by anything that decides money, approves a change or gates a tool', () => {
		const root = join(process.cwd(), 'src/lib');
		const files = [
			...readdirSync(join(root, 'finance')).map((f) => join(root, 'finance', f)),
			...['accounts', 'bills', 'ledger', 'planning', 'rules', 'split', 'actions', 'registry'].map(
				(n) => join(root, 'server/ops', `${n}.ts`)
			),
			join(root, 'server/agent/turn.ts'),
			join(root, 'server/agent/tools.ts')
		];
		for (const f of files)
			expect(readFileSync(f, 'utf8'), f).not.toMatch(/\bmood\b|memoryProfile|memory\/pure/i);
	});
});

describe('deleting', () => {
	it('leaves a tombstone with no words, takes older versions with it, and is not learned again', async () => {
		const c = await newUser();
		const a = await rememberFact(as(c), { text: 'My dog is called Brownie', subject: 'dog name' });
		const b = await rememberFact(as(c), { text: 'My dog is called Choco', subject: 'dog name' });
		const bid = b.status === 'created' ? b.id : '';
		expect(await forgetFact(as(c), { factId: bid })).toEqual({ forgotten: 2 });
		expect(await facts(c, { history: true })).toHaveLength(0);
		const row = await rawFact(c, a.status === 'created' ? a.id : '');
		expect(row).toMatchObject({ suppressed: true, text: '[deleted]', subject: null });
		await expect(forgetFact(as(c), { factId: bid })).rejects.toMatchObject({ code: 'NOT_FOUND' });
		// Not learned again from the extractor, in the same words
		const again = await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, { text: 'My dog is called Choco', source: 'extracted' })
		);
		expect(again.status).toBe('tombstoned');
		// The person can say it again on purpose
		expect(await rememberFact(as(c), { text: 'My dog is called Choco' })).toMatchObject({
			status: 'created'
		});
	});

	it('does not learn it again when the same thing is said in other words (M13)', async () => {
		const c = await newUser();
		const handlers = handlersFor(
			completer([
				'{"facts":[{"text":"allergic to shrimp","subject":"allergy","kind":"fact","importance":4,"confidence":90,"replaces":null}],"mood_delta":0}'
			])
		);
		const a = await rememberFact(as(c), { text: 'I am allergic to shrimp', subject: 'allergy' });
		await runJob(handlers, 'memory.embed', c);
		await forgetFact(as(c), { factId: a.status === 'created' ? a.id : '' });
		const turn = await addTurn(c, {
			id: 'msg-m13-000001',
			userText: 'Reminder: I cannot eat shrimp, I am allergic!'
		});
		await runJob(handlers, 'memory.extract', c, { turnId: turn });
		expect(await facts(c)).toHaveLength(0);
	});

	it('removes the digests that cited a deleted fact', async () => {
		const c = await newUser();
		const a = await rememberFact(as(c), { text: 'I am saving for a trip to Japan' });
		const id = a.status === 'created' ? a.id : '';
		await withUser(t.handle, c.actor.userId, async (tx) => {
			await tx.insert(memorySummary).values([
				{
					userId: c.actor.userId,
					period: 'day',
					periodStart: '2026-10-01',
					text: 'Talked about Japan.',
					factIds: [id]
				},
				{
					userId: c.actor.userId,
					period: 'day',
					periodStart: '2026-10-02',
					text: 'Talked about work.',
					factIds: []
				}
			]);
		});
		await forgetFact(as(c), { factId: id });
		const left = await withUser(t.handle, c.actor.userId, (tx) => tx.select().from(memorySummary));
		expect(left.map((s) => s.text)).toEqual(['Talked about work.']);
	});
});

describe('retrieval', () => {
	it('ranks the fact that answers the question first, with vectors and without', async () => {
		const c = await newUser();
		const handlers = handlersFor(completer([]));
		for (const text of [
			'My sister Liza birthday is on March 3',
			'I pay the rent every first of the month',
			'My dog Brownie is afraid of thunder',
			'I commute to Makati by train'
		])
			await rememberFact(as(c), { text });
		await runJob(handlers, 'memory.embed', c);
		const withVectors = await loadMemoryContext(c, {
			query: 'when is the birthday of my sister',
			embedder
		});
		expect(withVectors.lines[0]).toBe('- My sister Liza birthday is on March 3');
		const keywordsOnly = await loadMemoryContext(c, {
			query: 'when is the birthday of my sister',
			embedder: null
		});
		expect(keywordsOnly.lines[0]).toBe('- My sister Liza birthday is on March 3');
		const found = await searchMemory(c, { query: 'thunder dog' });
		expect(found[0]?.text).toBe('My dog Brownie is afraid of thunder');
	});

	it('stays inside the token budget, core block and digests first', async () => {
		const c = await newUser();
		await setProfile(as(c), { about: 'Ana, 29, works in Makati and supports her parents.' });
		await withUser(t.handle, c.actor.userId, (tx) =>
			tx.insert(memorySummary).values({
				userId: c.actor.userId,
				period: 'month',
				periodStart: '2026-10-01',
				text: 'A busy month with a new job.'
			})
		);
		for (let i = 0; i < 40; i++)
			await rememberFact(as(c), {
				text: `Note ${i}: I like trying new coffee shops near the office on Fridays`
			});
		const ctxt = await loadMemoryContext(c, {
			query: 'coffee shops office',
			embedder: null,
			budgetTokens: 100
		});
		expect(ctxt.tokens).toBeLessThanOrEqual(100);
		expect(ctxt.lines[0]).toBe(
			'About the person: Ana, 29, works in Makati and supports her parents.'
		);
		expect(ctxt.lines[1]).toBe('This month so far: A busy month with a new job.');
		expect(ctxt.lines.length).toBeGreaterThan(3);
		expect(ctxt.lines.length).toBeLessThan(10);
	});

	it('never returns a deleted, replaced or waiting fact', async () => {
		const c = await newUser();
		await rememberFact(as(c), { text: 'I live in Taguig now', subject: 'city' });
		const gone = await rememberFact(as(c), { text: 'I live in Pasig', subject: 'old city' });
		await forgetFact(as(c), { factId: gone.status === 'created' ? gone.id : '' });
		await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, {
				text: 'The person lives in Cavite',
				subject: 'city',
				source: 'extracted',
				confidence: 80
			})
		);
		const ctxt = await loadMemoryContext(c, { query: 'where do I live city', embedder: null });
		expect(ctxt.lines).toEqual(['- I live in Taguig now']);
	});

	it('always brings the facts marked never-forget', async () => {
		const c = await newUser();
		await rememberFact(as(c), { text: 'I take insulin every morning', importance: 5 });
		await rememberFact(as(c), { text: 'I like jazz' });
		const ctxt = await loadMemoryContext(c, {
			query: 'what should I cook tonight',
			embedder: null
		});
		expect(ctxt.lines).toContain('- I take insulin every morning');
		expect(ctxt.lines).not.toContain('- I like jazz');
	});
});

describe('fading and mood', () => {
	it('fades unimportant stale facts in steps, never deletes them, and restores them when they are used', async () => {
		const c = await newUser();
		const now = new Date('2026-10-21T04:00:00Z');
		const handlers = handlersFor(completer([]), { now });
		const a = await rememberFact(as(c), {
			text: 'I once tried the pottery class on Sundays',
			importance: 1
		});
		const id = a.status === 'created' ? a.id : '';
		await setFact(c, id, { validFrom: new Date('2026-01-01T00:00:00Z') });
		const weights: number[] = [];
		for (let i = 0; i < 5; i++) {
			await runJob(handlers, 'memory.night', c, { day: '2026-10-20' });
			weights.push(Number((await rawFact(c, id))?.fadeWeight));
		}
		expect(weights).toEqual([0.5, 0.25, 0.125, 0.1, 0.1]);
		expect((await rawFact(c, id))?.suppressed).toBe(false);
		// Still found when the question matches strongly, ranked lower, and using it lifts the fade
		const ctxt = await loadMemoryContext(c, {
			query: 'pottery class on Sundays',
			embedder: null,
			now
		});
		expect(ctxt.lines).toContain('- I once tried the pottery class on Sundays');
		expect(Number((await rawFact(c, id))?.fadeWeight)).toBeCloseTo(0.2, 5);
	});

	it('does not fade important facts or recently used ones', async () => {
		const c = await newUser();
		const now = new Date('2026-10-21T04:00:00Z');
		const handlers = handlersFor(completer([]), { now });
		const important = await rememberFact(as(c), {
			text: 'I am allergic to penicillin',
			importance: 4
		});
		const used = await rememberFact(as(c), { text: 'I like early morning swims', importance: 1 });
		for (const r of [important, used])
			await setFact(c, r.status === 'created' ? r.id : '', {
				validFrom: new Date('2026-01-01T00:00:00Z')
			});
		await setFact(c, used.status === 'created' ? used.id : '', {
			lastUsedAt: new Date('2026-10-10T00:00:00Z')
		});
		await runJob(handlers, 'memory.night', c, { day: '2026-10-20' });
		expect(
			Number((await rawFact(c, important.status === 'created' ? important.id : ''))?.fadeWeight)
		).toBe(1);
		expect(Number((await rawFact(c, used.status === 'created' ? used.id : ''))?.fadeWeight)).toBe(
			1
		);
	});

	it("moves the mood at most ten a turn from the extractor, and only the extractor's reading of the person's own words", async () => {
		const c = await newUser();
		const model = completer(Array.from({ length: 3 }, () => '{"facts":[],"mood_delta":50}'));
		const handlers = handlersFor(model);
		for (let i = 0; i < 3; i++) {
			const turn = await addTurn(c, {
				id: `msg-mood-00000${i}`,
				userText: `I am so happy today, everything went well ${i}`,
				reply: 'SECRET-REPLY-TEXT'
			});
			await runJob(handlers, 'memory.extract', c, { turnId: turn });
		}
		expect((await getProfile(c)).mood).toBe(30);
		// The assistant's own reply never reaches the extractor
		for (const asked of model.asked)
			expect(JSON.stringify(asked.messages)).not.toContain('SECRET-REPLY-TEXT');
	});

	it('lets the mood drift back to zero while nobody talks, and counts shared days', async () => {
		const c = await newUser();
		const now = new Date('2026-10-21T04:00:00Z');
		await withUser(t.handle, c.actor.userId, (tx) =>
			tx.insert(memoryProfile).values({
				userId: c.actor.userId,
				mood: 50,
				moodUpdatedAt: new Date('2026-10-18T04:00:00Z')
			})
		);
		await addTurn(c, {
			id: 'msg-day-0000001',
			userText: 'hello there',
			at: '2026-10-20T03:00:00Z'
		});
		await runJob(handlersFor(completer([]), { now }), 'memory.night', c, { day: '2026-10-20' });
		const p = await getProfile(c);
		expect(p.mood).toBe(36);
		expect(p.familiarity).toBe(1);
	});

	it('ends a duplicate that got in by another route, keeping the earliest', async () => {
		const c = await newUser();
		const u = c.actor.userId;
		const base = { userId: u, text: 'I like long walks', textHash: 'dup-hash-1' };
		await withUser(t.handle, u, (tx) =>
			tx.insert(memoryFact).values([
				{ ...base, createdAt: new Date('2026-10-01T00:00:00Z') },
				{ ...base, createdAt: new Date('2026-10-02T00:00:00Z') }
			])
		);
		await runJob(handlersFor(completer([])), 'memory.night', c, { day: '2026-10-20' });
		const active = await withUser(t.handle, u, (tx) =>
			tx
				.select()
				.from(memoryFact)
				.where(and(eq(memoryFact.userId, u), isNull(memoryFact.validTo)))
		);
		expect(active).toHaveLength(1);
		expect(active[0]?.createdAt.toISOString()).toBe('2026-10-01T00:00:00.000Z');
	});
});

describe('the jobs', () => {
	it('makes vectors for facts that have none, and again when the model changes', async () => {
		const c = await newUser();
		await rememberFact(as(c), { text: 'I like quiet cafes' });
		await runJob(
			handlersFor(completer([]), { embedder: fakeEmbedder('model-a') }),
			'memory.embed',
			c
		);
		const get = async () =>
			(
				await withUser(t.handle, c.actor.userId, (tx) =>
					tx.select({ m: memoryFact.embeddingModel, e: memoryFact.embedding }).from(memoryFact)
				)
			)[0];
		expect((await get())?.m).toBe('model-a');
		expect((await get())?.e).toHaveLength(384);
		await runJob(
			handlersFor(completer([]), { embedder: fakeEmbedder('model-b') }),
			'memory.embed',
			c
		);
		expect((await get())?.m).toBe('model-b');
		// Without an embedder it quietly does nothing
		await runJob(handlersFor(completer([]), { embedder: null }), 'memory.embed', c);
		expect((await get())?.m).toBe('model-b');
	});

	it("learns facts from the person's own words, with the turn as the source", async () => {
		const c = await newUser();
		const model = completer([
			'```json\n{"facts":[{"text":"The person supports their parents every payday","subject":"parents support","kind":"money","importance":4,"confidence":90,"replaces":null},{"text":"The person drinks coffee without sugar","subject":"coffee","kind":"preference","importance":2,"confidence":80,"replaces":null}],"mood_delta":0}\n```'
		]);
		const turn = await addTurn(c, {
			id: 'msg-learn-00001',
			userText: 'Every payday I send money to my parents, and I take my coffee without sugar'
		});
		await runJob(handlersFor(model), 'memory.extract', c, { turnId: turn });
		const learned = await facts(c);
		expect(learned.map((f) => f.text).sort()).toEqual([
			'The person drinks coffee without sugar',
			'The person supports their parents every payday'
		]);
		expect(learned.every((f) => f.source === 'extracted' && f.turnId === 'msg-learn-00001')).toBe(
			true
		);
		expect(model.asked[0]?.bucket).toBe('memory');
	});

	it('ignores a model answer that is not what was asked for, and short messages', async () => {
		const c = await newUser();
		const model = completer(['Sorry, I cannot do that.', '{"facts":"nope"}']);
		const t1 = await addTurn(c, {
			id: 'msg-bad-0000001',
			userText: 'a message long enough to be read'
		});
		const t2 = await addTurn(c, { id: 'msg-bad-0000002', userText: 'another message long enough' });
		const t3 = await addTurn(c, { id: 'msg-short-00001', userText: 'ok' });
		for (const turn of [t1, t2, t3])
			await runJob(handlersFor(model), 'memory.extract', c, { turnId: turn });
		expect(await facts(c)).toHaveLength(0);
		expect(model.asked).toHaveLength(2);
	});

	it('learns nothing from a turn that a branch copied, and counts it nowhere', async () => {
		const c = await newUser();
		const model = completer(['{"facts":[],"mood_delta":0}']);
		const original = await addTurn(c, {
			id: 'msg-copy-orig-01',
			userText: 'I always pay the rent on the first of the month'
		});
		const copy = await addTurn(c, {
			id: 'msg-copy-copy-01',
			userText: 'I always pay the rent on the first of the month'
		});
		await withUser(t.handle, c.actor.userId, (tx) =>
			tx.update(chatTurn).set({ copiedFromTurnId: original }).where(eq(chatTurn.id, copy))
		);
		await runJob(handlersFor(model), 'memory.extract', c, { turnId: copy });
		expect(model.asked).toHaveLength(0);
		await runJob(handlersFor(model), 'memory.extract', c, { turnId: original });
		expect(model.asked).toHaveLength(1);
	});

	it('writes the day, week and month digests and cites the facts learned that day', async () => {
		const c = await newUser();
		// The answers in the order they are asked: the 14th writes its day and the month so far; the 18th its day, then the week (a Sunday), then the month
		const model = completer([
			'Day one digest.',
			'Month digest.',
			'Day two digest.',
			'Week digest.',
			'Month digest again.'
		]);
		const handlers = handlersFor(model);
		// Monday 2026-10-12 to Sunday 2026-10-18. The 14th is a Wednesday
		await addTurn(c, {
			id: 'msg-dig-0000001',
			userText: 'I started a new job on Monday',
			reply: 'Congrats!',
			at: '2026-10-14T02:00:00Z'
		});
		await addTurn(c, {
			id: 'msg-dig-0000002',
			userText: 'The new job pays on the 15th',
			reply: 'Noted.',
			at: '2026-10-18T02:00:00Z'
		});
		const learned = await withUser(t.handle, c.actor.userId, (tx) =>
			upsertFact(tx, c.actor.userId, {
				text: 'The person started a new job',
				source: 'extracted',
				turnId: 'msg-dig-0000001'
			})
		);
		await runJob(handlers, 'memory.digest', c, { day: '2026-10-14' });
		await runJob(handlers, 'memory.digest', c, { day: '2026-10-18' });
		const all = await withUser(t.handle, c.actor.userId, (tx) => tx.select().from(memorySummary));
		const by = (period: string, start: string) =>
			all.find((s) => s.period === period && s.periodStart === start);
		expect(by('day', '2026-10-14')?.text).toBe('Day one digest.');
		expect(by('day', '2026-10-18')?.text).toBe('Day two digest.');
		expect(by('week', '2026-10-12')?.text).toBe('Week digest.');
		expect(by('month', '2026-10-01')?.text).toBe('Month digest again.');
		expect(by('day', '2026-10-14')?.factIds).toEqual([
			learned.status === 'created' ? learned.id : ''
		]);
		// The conversation went to the model as data, with the day's words in it
		expect(JSON.stringify(model.asked[0]?.messages)).toContain('I started a new job on Monday');
		// A day with no chat costs nothing
		await runJob(handlers, 'memory.digest', c, { day: '2026-10-19' });
		expect(model.asked).toHaveLength(5);
	});
});

describe('the assistant uses memory', () => {
	it('puts the notebook, made from the old memory, in the second system message and nothing of memory in the context', async () => {
		const c = await newUser();
		await setProfile(as(c), {
			persona: 'Talk like a friendly older sister.',
			about: 'Ana, 29, Makati.'
		});
		await rememberFact(as(c), { text: 'My mother Nena has diabetes' });
		const model = stubModel([{ say: 'Hi.' }]);
		for await (const _ of handleChat(
			c,
			{ clientMessageId: 'msg-prompt-0001', text: 'how is my mother doing?' },
			{ model }
		));
		const messages = model.requests[0]!.messages;
		const system = String(messages[1]?.content);
		expect(messages[1]?.role).toBe('system');
		expect(system).toContain('<notebook>');
		expect(system).toContain('# How Botler talks to you');
		expect(system).toContain('Talk like a friendly older sister.');
		expect(system).toContain('Ana, 29, Makati.');
		expect(system).toContain('- My mother Nena has diabetes');
		// The facts are no longer fetched for the message: its context block holds none of them
		const last = String(messages.at(-1)?.content);
		expect(last).not.toContain('Nena');
		expect(last).not.toContain('What you remember');
	});

	it('hides the names the person listed, from the persona and the facts too', async () => {
		const c = await newUser();
		await setProfile(as(c), {
			persona: 'Call me Maria Santos in jokes.',
			people: ['Maria Santos', 'Nena Reyes']
		});
		await rememberFact(as(c), { text: 'Nena Reyes is my mother' });
		const bodies: string[] = [];
		const fakeFetch = (async (_u: string, init: { body: string }) => {
			bodies.push(init.body);
			return new Response(
				'data: ' +
					JSON.stringify({
						choices: [{ delta: { content: 'Hello [NAME_1]' }, finish_reason: 'stop' }],
						usage: { prompt_tokens: 3, completion_tokens: 3 }
					}) +
					'\n\ndata: [DONE]\n\n',
				{ status: 200 }
			);
		}) as unknown as typeof fetch;
		const model = createModelClient({
			apiKey: 'k',
			baseUrl: 'https://model.test',
			model: 'm',
			limits: DEFAULT_LIMITS,
			fetch: fakeFetch,
			sleep: async () => undefined
		});
		for await (const _ of handleChat(
			c,
			{ clientMessageId: 'msg-names-0001', text: 'tell Nena Reyes I said hi' },
			{ model }
		));
		expect(bodies).toHaveLength(1);
		expect(bodies[0]).not.toContain('Maria Santos');
		expect(bodies[0]).not.toContain('Nena Reyes');
		expect(bodies[0]).toContain('[NAME_');
	});

	it('no longer queues the reading of what the person said: Botler writes the notebook during the chat', async () => {
		const c = await newUser();
		for await (const _ of handleChat(
			c,
			{ clientMessageId: 'msg-queue-0001', text: 'I always pay the rent on the first' },
			{ model: stubModel([{ say: 'Ok.' }]) }
		));
		// The job table is shared by everyone (it holds ids only), so this person's jobs are picked out by user
		const jobs = await withUser(t.handle, c.actor.userId, (tx) =>
			tx
				.select()
				.from(job)
				.where(and(eq(job.kind, 'memory.extract'), eq(job.userId, c.actor.userId)))
		);
		expect(jobs).toHaveLength(0);
	});

	it('writes no message text to any log, in a chat or in the jobs', async () => {
		const c = await newUser();
		const spies = (['log', 'info', 'warn', 'error'] as const).map((m) =>
			vi.spyOn(console, m).mockImplementation(() => undefined)
		);
		const secret = 'ZXQ-PRIVATE-WORDS-4412';
		const fakeFetch = (async (_u: string, init: { body: string }) => {
			const stream = (JSON.parse(init.body) as { stream?: boolean }).stream;
			const answer = stream
				? 'data: ' +
					JSON.stringify({
						choices: [{ delta: { content: 'Noted.' }, finish_reason: 'stop' }],
						usage: { prompt_tokens: 3, completion_tokens: 3 }
					}) +
					'\n\ndata: [DONE]\n\n'
				: JSON.stringify({
						choices: [
							{ message: { content: '{"facts":[],"mood_delta":0}' }, finish_reason: 'stop' }
						],
						usage: { prompt_tokens: 3, completion_tokens: 3 }
					});
			return new Response(answer, { status: 200 });
		}) as unknown as typeof fetch;
		const model = createModelClient({
			apiKey: 'k',
			baseUrl: 'https://model.test',
			model: 'm',
			limits: DEFAULT_LIMITS,
			fetch: fakeFetch,
			sleep: async () => undefined
		});
		for await (const _ of handleChat(
			c,
			{ clientMessageId: 'msg-logs-00001', text: `Remember ${secret} for me please` },
			{ model }
		));
		const turn = await withUser(t.handle, c.actor.userId, (tx) =>
			tx
				.select({ id: chatTurn.id })
				.from(chatTurn)
				.where(eq(chatTurn.clientMessageId, 'msg-logs-00001'))
		);
		await runJob(
			createMemoryHandlers({ model: () => model, embedder: () => null }),
			'memory.extract',
			c,
			{ turnId: turn[0]?.id }
		);
		const logged = spies.flatMap((s) => s.mock.calls.map((call) => JSON.stringify(call)));
		expect(logged.length).toBeGreaterThan(0);
		for (const line of logged) expect(line).not.toContain(secret);
	});
});

describe('persona, export and wipe', () => {
	it('keeps the persona the person sets and leaves fields they leave out', async () => {
		const c = await newUser();
		await setProfile(as(c), { persona: 'Short answers.', about: 'Ben.' });
		await setProfile(as(c), { people: ['Mama', 'Papa', 'Mama'] });
		expect(await getProfile(c)).toMatchObject({
			persona: 'Short answers.',
			about: 'Ben.',
			people: ['Mama', 'Papa']
		});
	});

	it('exports memory and finance together, without deleted words or vectors, and only to the person', async () => {
		const c = await newUser();
		await createAccount(as(c), { name: 'GCash', kind: 'ewallet' });
		await rememberFact(as(c), { text: 'I like jazz' });
		const gone = await rememberFact(as(c), { text: 'Secret to forget' });
		await forgetFact(as(c), { factId: gone.status === 'created' ? gone.id : '' });
		await addTurn(c, { id: 'msg-export-0001', userText: 'hello', reply: 'hi' });
		const out = await exportAll(c);
		const json = JSON.stringify(out);
		expect(out.finance.accounts.map((a) => a.name)).toEqual(['GCash']);
		expect(out.memory.facts.map((f) => f.text)).toEqual(['I like jazz']);
		expect(out.memory.conversations).toHaveLength(1);
		expect(json).not.toContain('Secret to forget');
		expect(json).not.toContain('"embedding":');
		await expect(exportAll(agentOf(c))).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await expect(invokeVerb(agentOf(c), 'memory_export', {})).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
	});

	it('wipes facts, tombstones, digests, transcripts and waiting jobs, keeps settings and money, and only for the person', async () => {
		const c = await newUser();
		await createAccount(as(c), { name: 'Maya', kind: 'ewallet' });
		await setProfile(as(c), { persona: 'Be brief.' });
		await rememberFact(as(c), { text: 'I like jazz' });
		const gone = await rememberFact(as(c), { text: 'Forget me' });
		await forgetFact(as(c), { factId: gone.status === 'created' ? gone.id : '' });
		await addTurn(c, { id: 'msg-wipe-000001', userText: 'hello', reply: 'hi' });
		await withUser(t.handle, c.actor.userId, (tx) =>
			tx
				.insert(memorySummary)
				.values({ userId: c.actor.userId, period: 'day', periodStart: '2026-10-01', text: 'x' })
		);

		await expect(wipeMemory(as(agentOf(c)), { confirm: true })).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
		await expect(wipeMemory(as(c), { confirm: false })).rejects.toMatchObject({ code: 'INVALID' });
		const done = await wipeMemory(as(c), { confirm: true });
		expect(done).toMatchObject({ facts: 2, summaries: 1, conversations: 1 });
		const left = await withUser(t.handle, c.actor.userId, async (tx) => ({
			facts: await tx.select().from(memoryFact),
			turns: await tx.select().from(chatTurn),
			queued: await tx
				.select()
				.from(job)
				.where(and(eq(job.kind, 'memory.embed'), eq(job.userId, c.actor.userId)))
		}));
		expect(left.facts).toHaveLength(0);
		expect(left.turns).toHaveLength(0);
		expect(left.queued).toHaveLength(0);
		// The persona and about lines now live in the notebook, which the wipe erases, so they are cleared with it; the names stay
		expect(await getProfile(c)).toMatchObject({ persona: '', about: '', mood: 0, familiarity: 0 });
		expect((await exportAll(c)).finance.accounts).toHaveLength(1);
	});
});

describe('isolation between people', () => {
	it("keeps one person's memory out of another's reach", async () => {
		const anna = await newUser();
		const ben = await newUser();
		const a = await rememberFact(as(anna), { text: 'Anna keeps her savings in a tin' });
		const id = a.status === 'created' ? a.id : '';
		expect(await facts(ben)).toHaveLength(0);
		expect(await searchMemory(ben, { query: 'savings tin' })).toHaveLength(0);
		expect((await loadMemoryContext(ben, { query: 'savings tin', embedder: null })).lines).toEqual(
			[]
		);
		await expect(forgetFact(as(ben), { factId: id })).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await expect(editFact(as(ben), { factId: id, text: 'changed' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect(await texts(anna)).toEqual(['Anna keeps her savings in a tin']);
		// The same words are a separate fact for each person
		expect(await rememberFact(as(ben), { text: 'Anna keeps her savings in a tin' })).toMatchObject({
			status: 'created'
		});
	});
});

describe('the assistant and memory writes', () => {
	it('is refused the old memory verbs, which are for the app only now, as well as wipe and export', async () => {
		const c = await newUser();
		for (const [verb, args] of [
			['memory_remember', { text: 'I prefer tea' }],
			['memory_forget', { factId: '11111111-1111-4111-8111-111111111111' }],
			['profile_set', { persona: 'x' }],
			['memory_wipe', { confirm: true }],
			['memory_export', {}]
		] as const)
			await expect(
				invokeVerb({ ...agentOf(c), requestId: rid() }, verb, args)
			).rejects.toMatchObject({ code: 'FORBIDDEN' });
		// The person still can, over the API, for an older app
		const r = (await invokeVerb({ ...c, requestId: rid() }, 'memory_remember', {
			text: 'I prefer tea'
		})) as { status: string; id: string };
		expect(r.status).toBe('created');
		await invokeVerb({ ...c, requestId: rid() }, 'memory_forget', { factId: r.id });
	});
});
