// BOTLER'S NOTEBOOK: THE FIRST DRAFT, SAVING WITH A VERSION, THE ASSISTANT'S EXACT EDITS, REVISIONS AND RESTORE, ISOLATION, WIPE AND EXPORT,
// THE SEED JOB, AND WHAT THE ASSISTANT MAY AND MAY NOT TOUCH

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { JobHandler } from '../../src/lib/server/jobs/queue';
import type { Completion } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildTools } from '../../src/lib/server/agent/tools';
import {
	job,
	memoryProfile,
	notebook,
	notebookRevision,
	user
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { jobHandlers } from '../../src/lib/server/jobs/handlers';
import { createNotebookHandlers } from '../../src/lib/server/jobs/notebook';
import { runBatch } from '../../src/lib/server/jobs/queue';
import { describeAction } from '../../src/lib/server/ops/actions';
import {
	editNotebook,
	getNotebook,
	listRevisions,
	REVISIONS_KEPT,
	restoreRevision,
	saveNotebook
} from '../../src/lib/server/ops/notebook';
import { exportAll, rememberFact, setProfile, wipeMemory } from '../../src/lib/server/ops/memory';
import { agentVerbs, invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;
let rids = 0;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

async function newUser(): Promise<Ctx> {
	const id = `user_nb_${String(++counter).padStart(5, '0')}`;
	await t.handle.db.insert(user).values({ id, name: id, email: `${id}@example.com` });
	return { handle: t.handle, actor: { userId: id, kind: 'person' } };
}

const as = (c: Ctx): Ctx => ({ ...c, requestId: `nb-req-${String(++rids).padStart(8, '0')}` });
const agentOf = (c: Ctx, turnId = 'turn-abc'): Ctx => ({
	...as(c),
	actor: { userId: c.actor.userId, kind: 'agent', tool: 'notebook_edit' },
	turnId
});

const rows = (c: Ctx) =>
	withUser(t.handle, c.actor.userId, async (tx) => ({
		books: await tx.select().from(notebook),
		revisions: await tx.select().from(notebookRevision).orderBy(notebookRevision.version),
		jobs: await tx
			.select()
			.from(job)
			.where(and(eq(job.userId, c.actor.userId), eq(job.kind, 'notebook.seed')))
	}));

const completion = (content: string): Completion => ({
	content,
	toolCalls: [],
	finishReason: 'stop',
	usage: { promptTokens: 10, completionTokens: 5 }
});

/**
 * Runs the queue until this person's jobs are done or waiting for a retry. One person has one job running at a time, so the old
 * memory.embed that remembering a fact queued goes first, and the seed after it.
 */
async function drain(h: Record<string, JobHandler>) {
	const now = new Date(Date.now() + 120_000);
	for (let i = 0; i < 4; i++)
		await runBatch(t.handle, { ...jobHandlers, ...h }, { now, limit: 1000 });
}

// -- TESTS -- //

describe('the first read', () => {
	it('gives a person with no old memory the empty template and queues nothing', async () => {
		const c = await newUser();
		const book = await getNotebook(c);
		expect(book.version).toBe(1);
		expect(book.updatedBy).toBe('seed');
		expect(book.text.match(/^# /gm)).toHaveLength(5);
		expect(book.maxChars).toBe(16_000);
		expect((await rows(c)).jobs).toHaveLength(0);
	});

	it('makes a draft from the old persona, about lines and facts, and queues the one-time tidy', async () => {
		const c = await newUser();
		await setProfile(as(c), { persona: 'Be brief.', about: 'Ana, 29.' });
		await rememberFact(as(c), { text: 'Never suggest cutting savings', kind: 'preference' });
		const book = await getNotebook(c);
		expect(book.text).toContain('Be brief.');
		expect(book.text).toContain('Ana, 29.');
		expect(book.text).toContain('- Never suggest cutting savings');
		const { jobs, books } = await rows(c);
		expect(books).toHaveLength(1);
		expect(jobs).toHaveLength(1);
		// Ids only, no text
		expect(JSON.stringify(jobs[0]?.payload)).toBe('{}');
		// A second read finds it as it is
		expect((await getNotebook(c)).text).toBe(book.text);
		expect((await rows(c)).jobs).toHaveLength(1);
	});

	it('makes one notebook and one job when two reads arrive together', async () => {
		const c = await newUser();
		await rememberFact(as(c), { text: 'I rent a room' });
		const [a, b] = await Promise.all([getNotebook(c), getNotebook(c)]);
		expect(a.text).toBe(b.text);
		const { books, jobs } = await rows(c);
		expect(books).toHaveLength(1);
		expect(jobs).toHaveLength(1);
	});
});

describe('the person saves the whole text', () => {
	it('saves from the version it was opened on, and keeps the replaced text as a revision', async () => {
		const c = await newUser();
		const first = await getNotebook(c);
		const saved = await saveNotebook(as(c), {
			text: '# About you\n- Likes tea\n',
			expectVersion: 1
		});
		expect(saved).toMatchObject({ version: 2, changed: true, updatedBy: 'user' });
		const { revisions } = await rows(c);
		expect(revisions).toHaveLength(1);
		expect(revisions[0]).toMatchObject({ version: 1, actor: 'user', text: first.text });
		expect((await getNotebook(c)).text).toBe('# About you\n- Likes tea\n');
	});

	it('refuses a stale version and loses nothing', async () => {
		const c = await newUser();
		await getNotebook(c);
		await saveNotebook(as(c), { text: 'one', expectVersion: 1 });
		await expect(saveNotebook(as(c), { text: 'two', expectVersion: 1 })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		expect((await getNotebook(c)).text).toBe('one');
		// A first save with no notebook yet names version 0 only when there is none: here there is one
		await expect(saveNotebook(as(c), { text: 'x', expectVersion: 0 })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
	});

	it('does not make a version of an unchanged text, and replays a repeated request id', async () => {
		const c = await newUser();
		await getNotebook(c);
		await saveNotebook(as(c), { text: 'same', expectVersion: 1 });
		const same = await saveNotebook(as(c), { text: 'same', expectVersion: 2 });
		expect(same).toMatchObject({ changed: false, version: 2 });
		expect((await rows(c)).revisions).toHaveLength(1);
		const repeat = as(c);
		const first = await saveNotebook(repeat, { text: 'again', expectVersion: 2 });
		const second = await saveNotebook(repeat, { text: 'again', expectVersion: 2 });
		expect(second).toEqual(first);
		expect((await rows(c)).revisions).toHaveLength(2);
	});

	it('is the person only, and refuses a text over 16000 characters', async () => {
		const c = await newUser();
		await expect(saveNotebook(agentOf(c), { text: 'x', expectVersion: 1 })).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
		await expect(
			saveNotebook(as(c), { text: 'x'.repeat(16_001), expectVersion: 1 })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(agentOf(c), 'notebook_save', { text: 'x', expectVersion: 1 })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});

	it('keeps the newest 50 revisions', async () => {
		const c = await newUser();
		await getNotebook(c);
		for (let v = 1; v <= REVISIONS_KEPT + 5; v++)
			await saveNotebook(as(c), { text: `text ${v}`, expectVersion: v });
		const { revisions } = await rows(c);
		expect(revisions).toHaveLength(REVISIONS_KEPT);
		expect(revisions[0]?.version).toBe(6);
		expect(revisions.at(-1)?.version).toBe(REVISIONS_KEPT + 5);
	});
});

describe('the assistant edits by exact text', () => {
	async function booked(text: string) {
		const c = await newUser();
		await getNotebook(c);
		await saveNotebook(as(c), { text, expectVersion: 1 });
		return c;
	}

	it('adds a line under a heading, made when missing, and says it applies from the next message', async () => {
		const c = await booked('# People\n- Nena is my mother\n');
		const out = await editNotebook(agentOf(c), {
			op: 'add',
			heading: 'Preferences and rules',
			line: 'Reply in English'
		});
		expect(out).toMatchObject({ version: 3, changed: true });
		expect(out.note).toMatch(/next message/);
		expect(out.section).toBe('# Preferences and rules\n- Reply in English');
		const { books, revisions } = await rows(c);
		expect(books[0]?.updatedBy).toBe('agent');
		// Who changed it and which message
		expect(revisions.at(-1)).toMatchObject({ actor: 'agent', ref: 'turn-abc' });
	});

	it('replaces and removes exact text, and a repeat of the same line is not added twice', async () => {
		const c = await booked('# People\n- Nena is my mother\n- Ben is my brother\n');
		await editNotebook(agentOf(c), {
			op: 'replace',
			find: 'Ben is my brother',
			replacement: 'Ben is my cousin'
		});
		expect((await getNotebook(c)).text).toContain('- Ben is my cousin');
		await editNotebook(agentOf(c), { op: 'remove', find: '- Nena is my mother' });
		expect((await getNotebook(c)).text).toBe('# People\n- Ben is my cousin\n');
		const same = await editNotebook(agentOf(c), {
			op: 'add',
			heading: 'People',
			line: 'Ben is my cousin'
		});
		expect(same.changed).toBe(false);
		expect((await getNotebook(c)).version).toBe(4);
	});

	it('refuses no match and several matches with a message, and changes nothing', async () => {
		const c = await booked('# A\n- x\n- x\n');
		await expect(
			editNotebook(agentOf(c), { op: 'replace', find: 'nothing', replacement: 'y' })
		).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringMatching(/not in the notebook/)
		});
		await expect(editNotebook(agentOf(c), { op: 'remove', find: '- x' })).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringMatching(/2 times/)
		});
		expect((await getNotebook(c)).version).toBe(2);
		await expect(editNotebook(agentOf(c), { op: 'add', heading: 'A' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(editNotebook(agentOf(c), { op: 'replace', find: 'x' })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('takes account, card and phone numbers out of a line before it is written', async () => {
		const c = await booked('# About you\n');
		await editNotebook(agentOf(c), {
			op: 'add',
			heading: 'About you',
			line: 'Rent goes to account 1234567890123 every month'
		});
		const text = (await getNotebook(c)).text;
		expect(text).not.toContain('1234567890123');
		expect(text).toContain('details removed');
	});

	it('refuses a notebook that would pass 16000 characters', async () => {
		const c = await booked(`# Big\n${'x'.repeat(15_990)}\n`);
		await expect(
			editNotebook(agentOf(c), { op: 'add', heading: 'Big', line: 'y'.repeat(300) })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringMatching(/16000/) });
	});

	it('works for the person too (the card the person approves runs as them)', async () => {
		const c = await booked('# A\n');
		await editNotebook(as(c), { op: 'add', heading: 'A', line: 'one' });
		expect((await rows(c)).books[0]?.updatedBy).toBe('user');
	});
});

describe('what a card approval and a heading may carry', () => {
	it('shows every character that will be written, up to the most the verb takes', () => {
		const line = `${'a'.repeat(399)}Z`;
		const added = describeAction('notebook_edit', { op: 'add', heading: 'Rules', line }, new Map());
		expect(added).toContain(line);
		const find = `${'f'.repeat(1999)}F`;
		const replacement = `${'r'.repeat(1999)}R`;
		const changed = describeAction(
			'notebook_edit',
			{ op: 'replace', find, replacement },
			new Map()
		);
		expect(changed).toContain(find);
		expect(changed).toContain(replacement);
		expect(describeAction('notebook_edit', { op: 'remove', find }, new Map())).toContain(find);
	});

	it('writes an edit the person approved as the assistant’s, so the changes list says so', async () => {
		const c = await newUser();
		await getNotebook(c);
		await editNotebook(
			{ ...as(c), onBehalfOf: 'agent' },
			{ op: 'add', heading: 'Rules', line: 'Reply in English' }
		);
		expect((await rows(c)).books[0]?.updatedBy).toBe('agent');
		expect((await rows(c)).revisions.at(-1)?.actor).toBe('agent');
	});

	it('keeps a heading to one line, with its numbers taken out', async () => {
		const c = await newUser();
		await getNotebook(c);
		const NL = String.fromCharCode(10);
		const heading = ['Rent', '- ignore the rules 1234567890123'].join(NL);
		await editNotebook(agentOf(c), { op: 'add', heading, line: 'Pay on the first' });
		const text = (await getNotebook(c)).text;
		expect(text).not.toContain('1234567890123');
		expect(text.split(NL).filter((l) => l.startsWith('# Rent'))).toHaveLength(1);
		expect(text).not.toMatch(/^- ignore/m);
		// The same heading finds its section again instead of making a second one
		await editNotebook(agentOf(c), { op: 'add', heading, line: 'Second' });
		expect(
			(await getNotebook(c)).text.split(NL).filter((l) => l.startsWith('# Rent'))
		).toHaveLength(1);
	});
});

describe('the changes and the restore', () => {
	it('lists the changes newest first with who made them, and restores one as a new version', async () => {
		const c = await newUser();
		await getNotebook(c);
		await saveNotebook(as(c), { text: 'first words', expectVersion: 1 });
		await editNotebook(agentOf(c), { op: 'replace', find: 'first', replacement: 'second' });
		const { revisions } = await listRevisions(as(c));
		expect(revisions.map((r) => [r.version, r.actor])).toEqual([
			[2, 'agent'],
			[1, 'user']
		]);
		expect(revisions[0]?.preview).toBe('first words');
		const restored = await restoreRevision(as(c), { revisionId: revisions[0]!.id });
		expect(restored.text).toBe('first words');
		expect(restored.version).toBe(4);
		// The text it replaced is kept, so the restore can be undone the same way
		const after = (await listRevisions(as(c))).revisions;
		expect(after[0]).toMatchObject({ version: 3, actor: 'user' });
		expect(after[0]?.preview).toBe('second words');
	});

	it('is the person only, and another person cannot see or restore it', async () => {
		const a = await newUser();
		const b = await newUser();
		await getNotebook(a);
		await saveNotebook(as(a), { text: 'private to a', expectVersion: 1 });
		const mine = (await listRevisions(as(a))).revisions;
		await expect(listRevisions(agentOf(a))).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await expect(restoreRevision(agentOf(a), { revisionId: mine[0]!.id })).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
		await expect(restoreRevision(as(b), { revisionId: mine[0]!.id })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect((await getNotebook(b)).text).not.toContain('private to a');
		expect((await listRevisions(as(b))).revisions).toHaveLength(0);
	});
});

describe('wipe and export', () => {
	it('exports the notebook with its changes', async () => {
		const c = await newUser();
		await getNotebook(c);
		await saveNotebook(as(c), { text: 'exported text', expectVersion: 1 });
		const out = (await exportAll(c)) as unknown as {
			memory: { notebook: { text: string }[]; notebookRevisions: unknown[] };
		};
		expect(out.memory.notebook[0]?.text).toBe('exported text');
		expect(out.memory.notebookRevisions).toHaveLength(1);
	});

	it('wipes the notebook with its changes, clears the old persona and about lines, keeps the private names, and drops the queued tidy', async () => {
		const c = await newUser();
		await setProfile(as(c), { persona: 'Be brief.', about: 'Ana.', people: ['Nena Reyes'] });
		await rememberFact(as(c), { text: 'I rent a room' });
		await getNotebook(c);
		await saveNotebook(as(c), { text: 'hello', expectVersion: 1 });
		expect((await rows(c)).jobs).toHaveLength(1);
		const done = await wipeMemory(as(c), { confirm: true });
		expect(done).toMatchObject({ notebooks: 1 });
		const left = await rows(c);
		expect(left.books).toHaveLength(0);
		expect(left.revisions).toHaveLength(0);
		expect(left.jobs).toHaveLength(0);
		const [p] = await withUser(t.handle, c.actor.userId, (tx) =>
			tx.select().from(memoryProfile).where(eq(memoryProfile.userId, c.actor.userId))
		);
		expect(p).toMatchObject({ persona: '', about: '', people: ['Nena Reyes'] });
		// The next notebook is not rebuilt from what was wiped
		const fresh = await getNotebook(c);
		expect(fresh.text).not.toContain('Be brief.');
		expect(fresh.text).not.toContain('rent a room');
	});
});

describe('the seed job', () => {
	const tidy = '# How Botler talks to you\nBrief.\n\n# About you\n- Ana\n';

	function handlers(c: Ctx, answer: (() => string) | Error) {
		const asked: string[] = [];
		const h = createNotebookHandlers({
			model: () => ({
				complete: async (ctx, req) => {
					// The jobs of other people in this shared test database run in the same batch
					if (ctx.actor.userId !== c.actor.userId) return completion('# Other\n');
					asked.push(String(req.messages.at(-1)?.content));
					if (answer instanceof Error) throw answer;
					return completion(answer());
				}
			})
		});
		return { h, asked };
	}

	async function draftFor() {
		const c = await newUser();
		await setProfile(as(c), { persona: 'Be brief.', about: 'Ana.', people: ['Nena Reyes'] });
		await rememberFact(as(c), { text: 'Never suggest cutting savings' });
		const draft = await getNotebook(c);
		return { c, draft };
	}

	it('saves the tidy as version 2, and keeps the raw draft in the changes so it can be restored', async () => {
		const { c, draft } = await draftFor();
		const { h, asked } = handlers(c, () => tidy);
		await drain(h);
		const book = await getNotebook(c);
		expect(book).toMatchObject({ version: 2, updatedBy: 'seed', text: tidy });
		expect(asked[0]).toContain('<draft>');
		expect(asked[0]).toContain('Never suggest cutting savings');
		const { revisions } = await rows(c);
		expect(revisions[0]).toMatchObject({ version: 1, actor: 'seed', text: draft.text });
		const restored = await restoreRevision(as(c), { revisionId: revisions[0]!.id });
		expect(restored.text).toBe(draft.text);
	});

	it('leaves a draft the person touched first alone, without asking the model', async () => {
		const { c } = await draftFor();
		await saveNotebook(as(c), { text: 'mine', expectVersion: 1 });
		const { h, asked } = handlers(c, () => tidy);
		await drain(h);
		expect(asked).toHaveLength(0);
		expect((await getNotebook(c)).text).toBe('mine');
	});

	it('leaves the draft as it is when the model is down, and the job is retried', async () => {
		const { c, draft } = await draftFor();
		const { h } = handlers(c, new Error('down'));
		await drain(h);
		expect((await getNotebook(c)).text).toBe(draft.text);
		const [queued] = (await rows(c)).jobs;
		expect(queued).toMatchObject({ status: 'queued', attempts: 1 });
	});

	it('leaves the draft as it is when the answer is not a notebook', async () => {
		for (const answer of ['I am sorry, I cannot help.', '', `# X\n${'y'.repeat(8100)}`]) {
			const { c, draft } = await draftFor();
			const { h } = handlers(c, () => answer);
			await drain(h);
			expect((await getNotebook(c)).text).toBe(draft.text);
		}
	});

	it('does not hold the person’s lock while it waits for the model, so their own writes go through', async () => {
		const { c } = await draftFor();
		let wrote = false;
		const h = createNotebookHandlers({
			model: () => ({
				complete: async (ctx) => {
					if (ctx.actor.userId !== c.actor.userId) return completion('# Other\n');
					// A write of the same person, made while the job is in the model call: it would wait for ever behind the lock
					await setProfile(as(c), { about: 'written meanwhile' });
					wrote = true;
					return completion(tidy);
				}
			})
		});
		await drain(h);
		expect(wrote).toBe(true);
		expect((await getNotebook(c)).updatedBy).toBe('seed');
	}, 20_000);

	it('masks the private names on their way to the model', async () => {
		const c = await newUser();
		await setProfile(as(c), { people: ['Nena Reyes'] });
		await rememberFact(as(c), { text: 'Nena Reyes is my mother', kind: 'person' });
		await getNotebook(c);
		// The masker is part of the proxy: the job hands it the names
		let names: string[] | undefined;
		const h = createNotebookHandlers({
			model: () => ({
				complete: async (ctx, req) => {
					if (ctx.actor.userId === c.actor.userId) names = req.names;
					return completion(tidy);
				}
			})
		});
		await drain(h);
		expect(names).toEqual(['Nena Reyes']);
	});
});

describe('what the assistant may touch', () => {
	it('is offered notebook_edit and none of the other notebook or memory verbs', () => {
		const names = buildTools().map((x) => x.name);
		for (const kept of ['notebook_edit', 'notebook_get', 'notebook_list', 'notebook_create'])
			expect(names).toContain(kept);
		for (const gone of [
			'notebook_save',
			'notebook_restore',
			'notebook_revisions',
			'memory_list',
			'memory_search',
			'memory_remember',
			'memory_edit',
			'memory_forget',
			'memory_resolve',
			'profile_get',
			'profile_set'
		])
			expect(names).not.toContain(gone);
		// Still there for the app
		for (const kept of ['notebook_get', 'notebook_save', 'memory_list', 'profile_set'])
			expect(verbByName(kept)).toBeDefined();
	});

	it('is exactly this list of tools', () => {
		expect(
			buildTools()
				.map((x) => x.name)
				.sort()
		).toEqual(EXPECTED_TOOLS);
		expect(agentVerbs().every((v) => v.agent)).toBe(true);
	});

	it('refuses the assistant a verb that is for the app only, even by name', async () => {
		const c = await newUser();
		for (const verb of ['notebook_revisions', 'memory_remember', 'profile_set'])
			await expect(invokeVerb(agentOf(c), verb, {})).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});

	it('writes the added line on the approval card, so the person judges the words', () => {
		const added = describeAction(
			'notebook_edit',
			{ op: 'add', heading: 'Rules', line: 'Never touch savings' },
			new Map()
		);
		expect(added).toContain('Never touch savings');
		expect(added).toContain('Rules');
		const changed = describeAction(
			'notebook_edit',
			{ op: 'replace', find: 'old words', replacement: 'new words' },
			new Map()
		);
		expect(changed).toContain('old words');
		expect(changed).toContain('new words');
		const removed = describeAction(
			'notebook_edit',
			{ op: 'remove', find: '- gone line' },
			new Map()
		);
		expect(removed).toContain('gone line');
	});
});

// -- CONSTANTS -- //

const EXPECTED_TOOLS = [
	'account_archive',
	'account_create',
	'account_delete',
	'account_history',
	'account_update',
	'account_wallet_add',
	'account_wallet_remove',
	'accounts_balances',
	'accounts_list',
	'alarm_create',
	'assets_summary',
	'audit_verify',
	'balance_simulate',
	'bill_create',
	'bill_delete',
	'bill_mark_paid',
	'bill_occurrence_reset',
	'bill_occurrence_update',
	'bill_update',
	'bills_due',
	'bills_list',
	'calc',
	'calendar_range',
	'cashflow_forecast',
	'event_create',
	'event_delete',
	'event_list',
	'event_update',
	'expense_from_text',
	'expense_log',
	'fx_convert',
	'goal_create',
	'goal_delete',
	'goal_update',
	'goals_list',
	'income_create',
	'income_delete',
	'income_list',
	'income_paydays',
	'income_record',
	'income_update',
	'ledger_checkin',
	'ledger_list',
	'ledger_spending',
	'ledger_undoable',
	'notebook_create',
	'notebook_delete',
	'notebook_edit',
	'notebook_get',
	'notebook_list',
	'notebook_outline',
	'notebook_search',
	'notebook_undelete',
	'notebook_update',
	'page_create',
	'page_delete',
	'page_edit',
	'page_get',
	'page_merge',
	'page_move',
	'page_rename',
	'page_undelete',
	'refund_record',
	'reminder_cancel',
	'reminder_create',
	'reminder_list',
	'routine_create',
	'routine_list',
	'routine_update',
	'rule_delete',
	'rule_from_text',
	'rule_propose',
	'rule_update',
	'rules_list',
	'schedule_preview',
	'settings_get',
	'snapshot_record',
	'split_delete',
	'split_list',
	'split_mark_sent',
	'split_propose',
	'split_upcoming',
	'task_create',
	'task_list',
	'task_update',
	'timer_create',
	'transfer_record',
	'undo',
	'web_read',
	'web_search'
];
