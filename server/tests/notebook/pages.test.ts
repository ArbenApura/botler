// NOTEBOOK PAGES: CREATE, READ, EDIT, SAVE, RENAME, MOVE, MERGE, DELETE AND PUT BACK, THE LIMITS (500 PAGES, 20 SUB-PAGES, 40 NOTEBOOKS), ISOLATION
// BETWEEN PEOPLE, THE NEWEST 50 CHANGES OF A PAGE, REPLAYS BY REQUEST ID, SEARCH AND OUTLINE THAT HIDE A DELETED NOTEBOOK, THE OLDER-APP CONTRACT OF
// AN EXTRA NOTEBOOK (ITS OVERVIEW PAGE), THE 30 DAY PURGE, THE WIPE, THE EXPORT, THE DATA RESET AND THE RACES THE PERSON LOCK AND THE TRIGGER CLOSE

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { JobHandler } from '../../src/lib/server/jobs/queue';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq, sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	notebook,
	notebookPage,
	notebookPageRevision,
	NOTEBOOK_MAX_EXTRA,
	NOTEBOOK_MAX_PAGES,
	NOTEBOOK_MAX_SUBPAGES,
	user
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { purgeOld } from '../../src/lib/server/jobs/handlers';
import {
	createNotebook,
	deleteNotebook,
	editNotebook,
	getNotebook,
	listNotebooks,
	listRevisions,
	loadNotebookContext,
	restoreRevision,
	saveNotebook,
	undeleteNotebook
} from '../../src/lib/server/ops/notebook';
import { exportAll, wipeMemory } from '../../src/lib/server/ops/memory';
import {
	createPage,
	deletePage,
	editPage,
	getPage,
	mergePages,
	movePage,
	notebookOutline,
	notebookSearch,
	pageActivity,
	pageBacklinks,
	pageRevisionGet,
	pageRevisions,
	pageSeen,
	pinNotebook,
	pinPage,
	renamePage,
	restorePage,
	savePage,
	undeletePage
} from '../../src/lib/server/ops/notebookPage';
import { previewDataReset, resetData } from '../../src/lib/server/ops/dataReset';
import { livePageCount } from '../../src/lib/server/ops/pageStore';
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
	const id = `user_pg_${String(++counter).padStart(5, '0')}`;
	await t.handle.db.insert(user).values({ id, name: id, email: `${id}@example.com` });
	return { handle: t.handle, actor: { userId: id, kind: 'person' } };
}

const as = (c: Ctx): Ctx => ({ ...c, requestId: `pg-req-${String(++rids).padStart(8, '0')}` });
const agentOf = (c: Ctx, turnId = 'turn-pages'): Ctx => ({
	...as(c),
	actor: { userId: c.actor.userId, kind: 'agent', tool: 'page_create' },
	turnId
});

/** A person with one notebook called Trip. */
async function withTrip(): Promise<Ctx> {
	const c = await newUser();
	await createNotebook(as(c), { title: 'Trip', summary: 'Plans' });
	return c;
}

const asAgent = async (c: Ctx, notebookTitle: string, title: string, text = '', parent?: string) =>
	createPage(agentOf(c), { notebook: notebookTitle, title, text, ...(parent ? { parent } : {}) });

/** The titles of one notebook's pages in outline order, a sub-page with a dash in front. */
async function shape(c: Ctx, book = 'Trip') {
	const out = await notebookOutline(c, { notebook: book });
	return (out.notebooks[0]?.pages ?? []).map((p) => (p.parentPageId ? `- ${p.title}` : p.title));
}

/** Runs a statement as the person, for what a verb does not offer (ageing a row). */
const exec = (c: Ctx, query: ReturnType<typeof sql>) =>
	withUser(t.handle, c.actor.userId, (tx) => tx.execute(query));

/** Puts many live pages straight into the table (as the owner), so a limit can be reached without hundreds of calls. */
async function fillPages(c: Ctx, notebookId: string, count: number, prefix = 'Filler') {
	const rows = Array.from({ length: count }, (_, i) => ({
		userId: c.actor.userId,
		notebookId,
		title: `${prefix} ${i}`,
		position: i + 1
	}));
	for (let i = 0; i < rows.length; i += 200)
		await withUser(t.handle, c.actor.userId, (tx) =>
			tx.insert(notebookPage).values(rows.slice(i, i + 200))
		);
}

/** The message of the database error under a failed query. */
const causeOf = (e: unknown) =>
	e instanceof Error ? String((e.cause as Error | undefined)?.message ?? e.message) : String(e);

const idOf = async (c: Ctx, book: string, page: string) =>
	(await getPage(c, { notebook: book, page })).id;

// -- TESTS -- //

describe('making and reading pages', () => {
	it('makes pages and sub-pages, reads them by titles for the assistant and by id for the app', async () => {
		const c = await withTrip();
		const flights = await createPage(as(c), {
			notebook: 'Trip',
			title: 'Flights',
			text: '# Flights\n- Leave 3 March'
		});
		expect(flights.version).toBe(1);
		expect(flights.updatedBy).toBe('user');
		expect(flights.seenVersion).toBe(1);
		const day = await asAgent(c, 'Trip', 'Day 1', 'Arrive', 'Flights');
		expect(day.parent).toBe('Flights');
		expect(day.updatedBy).toBe('agent');
		expect(day.seenVersion).toBe(0);
		const got = await getPage(agentOf(c), { notebook: 'trip', page: 'FLIGHTS' });
		expect(got.id).toBe(flights.id);
		expect(got.path).toBe('Trip/Flights');
		expect(got.subpages.map((s) => s.title)).toEqual(['Day 1']);
		expect((await getPage(c, { pageId: day.id })).path).toBe('Trip/Flights/Day 1');
		expect(await shape(c)).toEqual(['Overview', 'Flights', '- Day 1']);
	});

	it('refuses the main notebook, a missing notebook and a page that is not there with the names that exist', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Hotels' });
		await expect(createPage(as(c), { notebook: 'main', title: 'A' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(createPage(as(c), { notebook: 'Cars', title: 'A' })).rejects.toMatchObject({
			code: 'NOT_FOUND',
			message: expect.stringContaining('"Trip"')
		});
		await expect(createPage(as(c), { title: 'A' })).rejects.toMatchObject({ code: 'INVALID' });
		await expect(getPage(c, { notebook: 'Trip', page: 'Visa' })).rejects.toMatchObject({
			code: 'NOT_FOUND',
			message: expect.stringContaining('"Hotels"')
		});
		const hotels = await idOf(c, 'Trip', 'Hotels');
		await expect(
			getPage(c, { pageId: hotels, notebook: 'Trip', page: 'Hotels' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('keeps a title unique among its siblings ignoring case, and allows the same title under two parents', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Food' });
		await createPage(as(c), { notebook: 'Trip', title: 'Plans' });
		await expect(createPage(as(c), { notebook: 'Trip', title: 'food' })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
		await createPage(as(c), { notebook: 'Trip', title: 'Notes', parent: 'Food' });
		await createPage(as(c), { notebook: 'Trip', title: 'Notes', parent: 'Plans' });
		await expect(getPage(c, { notebook: 'Trip', page: 'Notes' })).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('Name the parent')
		});
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes', parent: 'plans' })).parent).toBe(
			'Plans'
		);
		await expect(
			createPage(as(c), { notebook: 'Trip', title: 'NOTES', parent: 'Food' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		// Rename clashes the same way, but a change of case alone is fine
		await expect(
			renamePage(as(c), { notebook: 'Trip', page: 'Plans', newTitle: 'FOOD' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		const renamed = await renamePage(as(c), { notebook: 'Trip', page: 'Plans', newTitle: 'PLANS' });
		expect(renamed.title).toBe('PLANS');
	});

	it('takes account, card and phone numbers out of everything the assistant writes, and keeps the person words', async () => {
		const c = await withTrip();
		const made = await createPage(agentOf(c), {
			notebook: 'Trip',
			title: 'Card 4111 1111 1111 1111',
			text: 'visa 4111 1111 1111 1111\n\nplain line'
		});
		expect(made.title).not.toContain('4111');
		expect(made.text).not.toContain('4111');
		expect(made.text).toContain('plain line');
		const kept = await createPage(as(c), {
			notebook: 'Trip',
			title: 'Mine',
			text: 'my number 4111 1111 1111 1111'
		});
		expect(kept.text).toContain('4111 1111 1111 1111');
		await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Mine',
			op: 'add',
			heading: 'Cards 4111 1111 1111 1111',
			line: 'call 0917 123 4567 now'
		});
		const after = await getPage(c, { notebook: 'Trip', page: 'Mine' });
		expect(after.text).not.toContain('0917 123 4567');
		expect(after.text).not.toContain('Cards 4111');
		await renamePage(agentOf(c), {
			notebook: 'Trip',
			page: 'Mine',
			newTitle: 'Visa 5500 0000 0000 0004'
		}).then((p) => expect(p.title).not.toContain('5500'));
	});

	it('limits the title and the text', async () => {
		const c = await withTrip();
		await expect(
			createPage(as(c), { notebook: 'Trip', title: 'x'.repeat(81) })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			createPage(as(c), { notebook: 'Trip', title: 'Long', text: 'x'.repeat(30_001) })
		).rejects.toMatchObject({ code: 'INVALID' });
		const ok = await createPage(as(c), {
			notebook: 'Trip',
			title: 'Long',
			text: 'x'.repeat(30_000)
		});
		expect(ok.chars).toBe(30_000);
	});
});

describe('editing a page', () => {
	it('adds, replaces and removes by exact text, bumping the version and keeping the old text', async () => {
		const c = await withTrip();
		await createPage(as(c), {
			notebook: 'Trip',
			title: 'Flights',
			text: '# Flights\n- Leave 3 March'
		});
		const added = await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Flights',
			op: 'add',
			heading: 'Hotels',
			line: 'Book near the station'
		});
		expect(added).toMatchObject({ changed: true, version: 2, page: 'Flights', notebook: 'Trip' });
		const replaced = await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Flights',
			op: 'replace',
			find: 'Leave 3 March',
			replacement: 'Leave 4 March'
		});
		expect(replaced.version).toBe(3);
		await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Flights',
			op: 'remove',
			find: '- Book near the station'
		});
		const now = await getPage(c, { notebook: 'Trip', page: 'Flights' });
		expect(now.text).toContain('Leave 4 March');
		expect(now.text).not.toContain('station');
		expect(now.version).toBe(4);
		expect(now.updatedBy).toBe('agent');
		const revs = await pageRevisions(c, { pageId: now.id });
		expect(revs.revisions.map((r) => r.version)).toEqual([3, 2, 1]);
		const first = revs.revisions.at(-1);
		expect((await pageRevisionGet(c, { revisionId: first?.id ?? '' })).text).toBe(
			'# Flights\n- Leave 3 March'
		);
		// A change that matches nothing, or twice, is refused with a message the assistant can act on
		await expect(
			editPage(agentOf(c), { notebook: 'Trip', page: 'Flights', op: 'remove', find: 'not there' })
		).rejects.toMatchObject({ code: 'INVALID' });
		// Saying what is already there changes nothing
		const same = await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Flights',
			op: 'add',
			heading: 'Hotels',
			line: 'Book near the station'
		});
		expect(same.changed).toBe(true);
		const again = await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Flights',
			op: 'add',
			heading: 'Hotels',
			line: 'Book near the station'
		});
		expect(again.changed).toBe(false);
	});

	it('saves the whole text for the person from the version they opened, and refuses a stale one', async () => {
		const c = await withTrip();
		const page = await createPage(as(c), { notebook: 'Trip', title: 'Flights', text: 'one' });
		await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Flights',
			op: 'replace',
			find: 'one',
			replacement: 'two'
		});
		await expect(
			savePage(as(c), { pageId: page.id, text: 'mine', expectVersion: 1 })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		const saved = await savePage(as(c), { pageId: page.id, text: 'mine', expectVersion: 2 });
		expect(saved).toMatchObject({ changed: true, version: 3, text: 'mine', updatedBy: 'user' });
		expect(saved.seenVersion).toBe(3);
		expect(
			(await savePage(as(c), { pageId: page.id, text: 'mine', expectVersion: 3 })).changed
		).toBe(false);
		// The assistant cannot save
		await expect(
			invokeVerb(agentOf(c), 'page_save', { pageId: page.id, text: 'x', expectVersion: 3 })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});

	it('keeps only the newest 50 changes of a page', async () => {
		const c = await withTrip();
		const page = await createPage(as(c), { notebook: 'Trip', title: 'Log', text: 'v1' });
		let version = 1;
		for (let i = 2; i <= 56; i++) {
			await savePage(as(c), { pageId: page.id, text: `v${i}`, expectVersion: version });
			version = i;
		}
		const revs = (await pageRevisions(c, { pageId: page.id })).revisions;
		expect(revs).toHaveLength(50);
		expect(revs[0]?.version).toBe(55);
		expect(revs.at(-1)?.version).toBe(6);
		const text = (await pageRevisionGet(c, { revisionId: revs[0]?.id ?? '' })).text;
		expect(text).toBe('v55');
	});

	it('puts an earlier text back and keeps the text it replaced', async () => {
		const c = await withTrip();
		const page = await createPage(as(c), { notebook: 'Trip', title: 'Log', text: 'first' });
		await savePage(as(c), { pageId: page.id, text: 'second', expectVersion: 1 });
		const rev = (await pageRevisions(c, { pageId: page.id })).revisions[0];
		const back = await restorePage(as(c), { revisionId: rev?.id ?? '' });
		expect(back.text).toBe('first');
		expect(back.version).toBe(3);
		expect((await pageRevisions(c, { pageId: page.id })).revisions.map((r) => r.version)).toEqual([
			2, 1
		]);
	});

	it('never lets looking at a page make a save stale, and only moves the seen mark up', async () => {
		const c = await withTrip();
		const page = await asAgent(c, 'Trip', 'Agent page', 'hello');
		expect(page.seenVersion).toBe(0);
		const seen = await pageSeen(c, { pageId: page.id, version: 1 });
		expect(seen).toMatchObject({ seenVersion: 1, version: 1 });
		const after = await getPage(c, { pageId: page.id });
		expect(after.updatedAt).toBe(page.updatedAt);
		expect(after.version).toBe(1);
		// A lower mark does not move it back, a higher one stops at the page version
		expect((await pageSeen(c, { pageId: page.id, version: 1 })).seenVersion).toBe(1);
		expect((await pageSeen(c, { pageId: page.id, version: 9 })).seenVersion).toBe(1);
		const saved = await savePage(as(c), { pageId: page.id, text: 'ok', expectVersion: 1 });
		expect(saved.changed).toBe(true);
		// The assistant cannot call it, and it is not kept in the request log
		await expect(
			invokeVerb(agentOf(c), 'page_seen', { pageId: page.id, version: 1 })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		const logged = await withUser(t.handle, c.actor.userId, (tx) =>
			tx.execute(sql`select count(*)::int as n from request_log where verb = 'page.seen'`)
		);
		expect((logged as unknown as { rows: { n: number }[] }).rows[0]?.n).toBe(0);
	});
});

describe('moving, merging, deleting and putting back', () => {
	it('moves a page under another, to another place, back to the top and to another notebook with its sub-pages', async () => {
		const c = await withTrip();
		await createNotebook(as(c), { title: 'Work' });
		for (const title of ['A', 'B', 'C']) await createPage(as(c), { notebook: 'Trip', title });
		expect(await shape(c)).toEqual(['Overview', 'A', 'B', 'C']);
		await movePage(as(c), { notebook: 'Trip', page: 'C', position: 0 });
		expect(await shape(c)).toEqual(['C', 'Overview', 'A', 'B']);
		await movePage(as(c), { notebook: 'Trip', page: 'B', toParent: 'A' });
		expect(await shape(c)).toEqual(['C', 'Overview', 'A', '- B']);
		await movePage(as(c), { notebook: 'Trip', page: 'B' });
		expect(await shape(c)).toEqual(['C', 'Overview', 'A', 'B']);
		await movePage(as(c), { notebook: 'Trip', page: 'B', toParent: 'A' });
		// The page with its sub-pages changes notebook, and the sub-page keeps its parent
		await movePage(as(c), { notebook: 'Trip', page: 'A', toNotebook: 'Work' });
		expect(await shape(c, 'Work')).toEqual(['Overview', 'A', '- B']);
		expect(await shape(c, 'Trip')).toEqual(['C', 'Overview']);
		const b = await getPage(c, { notebook: 'Work', page: 'B' });
		expect(b.parent).toBe('A');
		expect(b.notebook).toBe('Work');
	});

	it('refuses a second level, a loop, a title clash and a full parent when moving', async () => {
		const c = await withTrip();
		for (const title of ['A', 'B', 'C']) await createPage(as(c), { notebook: 'Trip', title });
		await movePage(as(c), { notebook: 'Trip', page: 'B', toParent: 'A' });
		// B is a sub-page: nothing can go under it
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'C', toParent: 'B' })
		).rejects.toMatchObject({ code: 'INVALID' });
		// A has a sub-page: it cannot become one
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'A', toParent: 'C' })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('sub-pages') });
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'C', toParent: 'C' })
		).rejects.toMatchObject({ code: 'INVALID' });
		// A title already used where it goes: the top-level page wins the name over the sub-page that shares it
		await createPage(as(c), { notebook: 'Trip', title: 'Dup', parent: 'A' });
		await createPage(as(c), { notebook: 'Trip', title: 'Dup' });
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'Dup', toParent: 'A' })
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('already exists')
		});
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'Dup', parent: 'A', toParent: '' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		// The same clash across notebooks
		await createNotebook(as(c), { title: 'Work' });
		await createPage(as(c), { notebook: 'Trip', title: 'Shared', text: 'trip' });
		await createPage(as(c), { notebook: 'Work', title: 'Shared', text: 'work' });
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'Shared', toNotebook: 'Work' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		expect((await getPage(c, { notebook: 'Trip', page: 'Shared' })).text).toBe('trip');
	});

	it('refuses to fill a parent past 20 sub-pages by creating or by moving', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent' });
		for (let i = 0; i < NOTEBOOK_MAX_SUBPAGES; i++)
			await createPage(as(c), { notebook: 'Trip', title: `Sub ${i}`, parent: 'Parent' });
		await expect(
			createPage(as(c), { notebook: 'Trip', title: 'One too many', parent: 'Parent' })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('20') });
		await createPage(as(c), { notebook: 'Trip', title: 'Loose' });
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'Loose', toParent: 'Parent' })
		).rejects.toMatchObject({ code: 'INVALID' });
		// A deleted sub-page makes room
		await deletePage(as(c), { notebook: 'Trip', page: 'Sub 3' });
		await movePage(as(c), { notebook: 'Trip', page: 'Loose', toParent: 'Parent' });
	});

	it('merges pages in one change: text added under their titles, the target keeps its old text, the sources are deleted', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Target', text: 'base' });
		await createPage(as(c), { notebook: 'Trip', title: 'One', text: 'first text' });
		await createPage(as(c), { notebook: 'Trip', title: 'Two', text: 'second text' });
		const out = await mergePages(agentOf(c), {
			notebook: 'Trip',
			page: 'Target',
			sources: [{ page: 'One' }, { page: 'Two' }]
		});
		expect(out.page.text).toBe('base\n\n## One\nfirst text\n\n## Two\nsecond text');
		expect(out.page.version).toBe(2);
		expect(out.merged.map((m) => m.title)).toEqual(['One', 'Two']);
		expect(await shape(c)).toEqual(['Overview', 'Target']);
		const revs = (await pageRevisions(c, { pageId: out.page.id })).revisions;
		expect((await pageRevisionGet(c, { revisionId: revs[0]?.id ?? '' })).text).toBe('base');
		// The merged pages are only hidden
		const deleted = await notebookOutline(c, { notebook: 'Trip', deleted: true });
		expect(deleted.notebooks[0]?.pages.map((p) => p.title).sort()).toEqual(['One', 'Two']);
		const back = await undeletePage(as(c), { notebook: 'Trip', page: 'One' });
		expect(back.text).toBe('first text');
	});

	it('refuses a merge that is too long, into itself, from a page with sub-pages, or of a page and its own parent', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Big', text: 'x'.repeat(20_000) });
		await createPage(as(c), { notebook: 'Trip', title: 'Bigger', text: 'y'.repeat(20_000) });
		await expect(
			mergePages(as(c), { notebook: 'Trip', page: 'Big', sources: [{ page: 'Bigger' }] })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('30000') });
		await expect(
			mergePages(as(c), { notebook: 'Trip', page: 'Big', sources: [{ page: 'Big' }] })
		).rejects.toMatchObject({ code: 'INVALID' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid', parent: 'Big' });
		await createPage(as(c), { notebook: 'Trip', title: 'Small', text: 's' });
		await expect(
			mergePages(as(c), { notebook: 'Trip', page: 'Small', sources: [{ page: 'Big' }] })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('sub-pages') });
		await expect(
			mergePages(as(c), { notebook: 'Trip', page: 'Kid', sources: [{ page: 'Big' }] })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(mergePages(as(c), { notebook: 'Trip', page: 'Small' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		// Nothing was changed by the refusals
		expect((await getPage(c, { notebook: 'Trip', page: 'Small' })).version).toBe(1);
	});

	it('deletes a page with its sub-pages together and puts them back together, at the old place', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent', text: 'p' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid 1', parent: 'Parent' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid 2', parent: 'Parent' });
		const removed = await deletePage(agentOf(c), { notebook: 'Trip', page: 'Parent' });
		expect(removed.alsoRemoved).toEqual(['Kid 1', 'Kid 2']);
		expect(await shape(c)).toEqual(['Overview']);
		await expect(getPage(c, { notebook: 'Trip', page: 'Kid 1' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		const back = await undeletePage(agentOf(c), { notebook: 'Trip', page: 'Parent' });
		expect(back.title).toBe('Parent');
		expect(await shape(c)).toEqual(['Overview', 'Parent', '- Kid 1', '- Kid 2']);
		// One deleted on its own comes back under its parent while the parent lives
		await deletePage(as(c), { notebook: 'Trip', page: 'Kid 2' });
		const kid = await undeletePage(as(c), { notebook: 'Trip', page: 'Kid 2' });
		expect(kid.parent).toBe('Parent');
	});

	it('puts a sub-page back at the top level when its parent is deleted, and numbers a title that was taken meanwhile', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid', parent: 'Parent' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Kid' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Parent' });
		const kid = await undeletePage(as(c), { notebook: 'Trip', page: 'Kid' });
		expect(kid.parentPageId).toBeNull();
		expect(kid.title).toBe('Kid');
		// A new page took the title meanwhile
		await deletePage(as(c), { notebook: 'Trip', page: 'Kid' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid' });
		const second = await undeletePage(as(c), { notebook: 'Trip', page: 'Kid' });
		expect(second.title).toBe('Kid (restored)');
		await expect(undeletePage(as(c), { notebook: 'Trip', page: 'Never' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await expect(undeletePage(as(c), {})).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('the limits', () => {
	it('stops at 500 live pages, and a deleted page does not count', async () => {
		const c = await withTrip();
		const trip = await getNotebook(c, { notebook: 'Trip' });
		// The Overview page of Trip is the first one
		await fillPages(c, trip.id, NOTEBOOK_MAX_PAGES - 1);
		await createPage(as(c), { notebook: 'Trip', title: 'Number 500' }).then(
			() => {
				throw new Error('The 500th page should have been refused, one page is already there');
			},
			(e: unknown) => expect(e).toMatchObject({ code: 'INVALID' })
		);
		await deletePage(as(c), { notebook: 'Trip', page: 'Filler 0' });
		await createPage(as(c), { notebook: 'Trip', title: 'Number 500' });
		await expect(
			createPage(as(c), { notebook: 'Trip', title: 'Number 501' })
		).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('500')
		});
		// A restore past the limit is refused too, and a new notebook with its first page as well
		await expect(undeletePage(as(c), { notebook: 'Trip', page: 'Filler 0' })).rejects.toMatchObject(
			{
				code: 'INVALID'
			}
		);
		await expect(createNotebook(as(c), { title: 'Another' })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('lets only one of two creates at once through at 500 pages, 20 sub-pages and 40 notebooks', async () => {
		const settle = async (calls: Promise<unknown>[]) => {
			const out = await Promise.allSettled(calls);
			return out.filter((o) => o.status === 'fulfilled').length;
		};
		// 500 pages: 498 fillers and the Overview leave room for one more
		const c = await withTrip();
		const trip = await getNotebook(c, { notebook: 'Trip' });
		await fillPages(c, trip.id, NOTEBOOK_MAX_PAGES - 2);
		expect(
			await settle([
				createPage(as(c), { notebook: 'Trip', title: 'Race A' }),
				createPage(as(c), { notebook: 'Trip', title: 'Race B' })
			])
		).toBe(1);
		expect(
			(await withUser(t.handle, c.actor.userId, (tx) =>
				tx.execute(sql`select count(*)::int as n from notebook_page where deleted_at is null`)
			)) as unknown as { rows: { n: number }[] }
		).toMatchObject({ rows: [{ n: NOTEBOOK_MAX_PAGES }] });
		// 20 sub-pages
		const d = await withTrip();
		await createPage(as(d), { notebook: 'Trip', title: 'Parent' });
		for (let i = 0; i < NOTEBOOK_MAX_SUBPAGES - 1; i++)
			await createPage(as(d), { notebook: 'Trip', title: `Sub ${i}`, parent: 'Parent' });
		expect(
			await settle([
				createPage(as(d), { notebook: 'Trip', title: 'Race A', parent: 'Parent' }),
				createPage(as(d), { notebook: 'Trip', title: 'Race B', parent: 'Parent' })
			])
		).toBe(1);
		// 40 notebooks (Trip is one of them)
		const e = await withTrip();
		for (let i = 1; i < NOTEBOOK_MAX_EXTRA - 1; i++)
			await createNotebook(as(e), { title: `Book ${i}` });
		expect(
			await settle([
				createNotebook(as(e), { title: 'Race A' }),
				createNotebook(as(e), { title: 'Race B' })
			])
		).toBe(1);
		expect((await listNotebooks(e)).notebooks.filter((n) => n.kind === 'extra')).toHaveLength(
			NOTEBOOK_MAX_EXTRA
		);
	});
});

describe('races the person lock and the trigger close', () => {
	it('lets only one of two moves that would make a loop or a second level through', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'A' });
		await createPage(as(c), { notebook: 'Trip', title: 'B' });
		const out = await Promise.allSettled([
			movePage(as(c), { notebook: 'Trip', page: 'A', toParent: 'B' }),
			movePage(as(c), { notebook: 'Trip', page: 'B', toParent: 'A' })
		]);
		expect(out.filter((o) => o.status === 'fulfilled')).toHaveLength(1);
		const shapes = await shape(c);
		expect(shapes.filter((s) => s.startsWith('- '))).toHaveLength(1);
	});

	it('is closed by the database itself: a second level, a loop and a page with sub-pages becoming one are refused below the verbs', async () => {
		const c = await withTrip();
		const a = await createPage(as(c), { notebook: 'Trip', title: 'A' });
		const b = await createPage(as(c), { notebook: 'Trip', title: 'B', parent: 'A' });
		const cc = await createPage(as(c), { notebook: 'Trip', title: 'C' });
		const raw = (text: ReturnType<typeof sql>) =>
			withUser(t.handle, c.actor.userId, (tx) => tx.execute(text));
		// C under B (B is a sub-page): a second level
		await expect(
			raw(sql`update notebook_page set parent_page_id = ${b.id} where id = ${cc.id}`)
		).rejects.toSatisfy((e: unknown) => /sub-page/.test(causeOf(e)));
		// A (which has B under it) under C: a page with sub-pages becoming one
		await expect(
			raw(sql`update notebook_page set parent_page_id = ${cc.id} where id = ${a.id}`)
		).rejects.toThrow();
		// A under itself
		await expect(
			raw(sql`update notebook_page set parent_page_id = ${a.id} where id = ${a.id}`)
		).rejects.toThrow();
		// A parent in another notebook is refused by the key
		await createNotebook(as(c), { title: 'Other' });
		const other = await getNotebook(c, { notebook: 'Other' });
		await expect(
			raw(sql`update notebook_page set notebook_id = ${other.id} where id = ${b.id}`)
		).rejects.toThrow();
		// The parent cannot be erased from under its sub-page
		await expect(raw(sql`delete from notebook_page where id = ${a.id}`)).rejects.toThrow();
	});

	it('does not make a save stale however many times the pages are looked at at once', async () => {
		const c = await withTrip();
		const page = await createPage(as(c), { notebook: 'Trip', title: 'Busy', text: 'v1' });
		let version = 1;
		for (let round = 0; round < 5; round++) {
			const out = await Promise.allSettled([
				savePage(as(c), { pageId: page.id, text: `v${version + 1}`, expectVersion: version }),
				...Array.from({ length: 6 }, () => pageSeen(c, { pageId: page.id, version }))
			]);
			expect(out.every((o) => o.status === 'fulfilled')).toBe(true);
			version += 1;
		}
		expect((await getPage(c, { pageId: page.id })).version).toBe(6);
	});
});

describe('replays and isolation', () => {
	it('returns the first answer to a request id used again, and writes nothing twice', async () => {
		const c = await withTrip();
		const same = { ...as(c), requestId: 'replay-page-0001' };
		const first = await createPage(same, { notebook: 'Trip', title: 'Once', text: 'a' });
		const second = await createPage(same, { notebook: 'Trip', title: 'Once', text: 'a' });
		expect(second.id).toBe(first.id);
		expect((await shape(c)).filter((x) => x === 'Once')).toHaveLength(1);
		// The same id for another request is refused
		await expect(
			createPage(same, { notebook: 'Trip', title: 'Other', text: 'a' })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		// A write needs a request id at all
		await expect(createPage({ ...c }, { notebook: 'Trip', title: 'No id' })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('keeps one person pages from another: by id, by title, in a search, an outline and a backlink', async () => {
		const anna = await withTrip();
		const ben = await withTrip();
		const secret = await createPage(as(anna), {
			notebook: 'Trip',
			title: 'Secret plans',
			text: 'the treasure is under the stairs'
		});
		await createPage(as(ben), { notebook: 'Trip', title: 'Mine', text: 'nothing here' });
		await expect(getPage(ben, { pageId: secret.id })).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await expect(getPage(ben, { notebook: 'Trip', page: 'Secret plans' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect((await notebookSearch(ben, { query: 'treasure' })).results).toEqual([]);
		expect(
			(await notebookOutline(ben)).notebooks.flatMap((n) => n.pages.map((p) => p.title))
		).not.toContain('Secret plans');
		await expect(
			savePage(as(ben), { pageId: secret.id, text: 'hacked', expectVersion: 1 })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await expect(deletePage(as(ben), { pageId: secret.id })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await expect(pageBacklinks(ben, { pageId: secret.id })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect((await getPage(anna, { pageId: secret.id })).text).toContain('treasure');
	});
});

describe('searching, the outline, links, pins and activity', () => {
	it('searches titles and texts case-insensitively with a snippet, titles first, and takes % and _ literally', async () => {
		const c = await withTrip();
		await createNotebook(as(c), { title: 'Recipes' });
		await createPage(as(c), {
			notebook: 'Trip',
			title: 'Flights',
			text: `${'a'.repeat(200)} Leave from MANILA at dawn ${'b'.repeat(200)}`
		});
		await createPage(as(c), { notebook: 'Recipes', title: 'Manila rice', text: 'Rice' });
		await createPage(as(c), { notebook: 'Recipes', title: 'Percent', text: 'a 100% sure_thing' });
		const hits = await notebookSearch(agentOf(c), { query: 'manila' });
		expect(hits.results.map((r) => `${r.notebook}/${r.page}:${r.matchIn}`)).toEqual([
			'Recipes/Manila rice:title',
			'Trip/Flights:text'
		]);
		const text = hits.results[1];
		expect(text?.snippet).toContain('MANILA');
		expect(text?.snippet.length).toBeLessThan(260);
		expect(text?.snippet.startsWith('…')).toBe(true);
		expect(text?.pageId).toBeTruthy();
		expect(text?.notebookId).toBeTruthy();
		expect((await notebookSearch(c, { query: 'manila', notebook: 'Trip' })).results).toHaveLength(
			1
		);
		expect((await notebookSearch(c, { query: '100%' })).results).toHaveLength(1);
		expect((await notebookSearch(c, { query: '%%' })).results).toHaveLength(0);
		expect((await notebookSearch(c, { query: 'sure_t' })).results).toHaveLength(1);
		expect((await notebookSearch(c, { query: 'sureXthing' })).results).toHaveLength(0);
		expect((await notebookSearch(c, { query: 'manila', limit: 1 })).more).toBe(true);
	});

	it('hides everything of a deleted notebook from search, outline, get, links and activity, and brings it back with the notebook', async () => {
		const c = await withTrip();
		const page = await createPage(agentOf(c), {
			notebook: 'Trip',
			title: 'Hidden',
			text: 'findable words'
		});
		await createPage(as(c), { notebook: 'Trip', title: 'Pointer', text: 'see [[Hidden]]' });
		expect((await notebookSearch(c, { query: 'findable' })).results).toHaveLength(1);
		expect((await pageActivity(c)).pages.map((p) => p.page)).toContain('Hidden');
		await deleteNotebook(as(c), { notebook: 'Trip' });
		expect((await notebookSearch(c, { query: 'findable' })).results).toHaveLength(0);
		expect((await notebookOutline(c)).notebooks).toEqual([]);
		expect((await pageActivity(c)).pages).toEqual([]);
		await expect(getPage(c, { pageId: page.id })).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await expect(getPage(c, { notebook: 'Trip', page: 'Hidden' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await expect(
			editPage(as(c), { pageId: page.id, op: 'remove', find: 'findable' })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		await expect(createPage(as(c), { notebook: 'Trip', title: 'New' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		const pointer = await withUser(t.handle, c.actor.userId, (tx) =>
			tx.select({ id: notebookPage.id }).from(notebookPage).where(eq(notebookPage.title, 'Pointer'))
		);
		await expect(pageBacklinks(c, { pageId: pointer[0]?.id ?? '' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await undeleteNotebook(as(c), { notebook: 'Trip' });
		expect((await notebookSearch(c, { query: 'findable' })).results).toHaveLength(1);
	});

	it('lists the outline in tree order, with the deleted pages on request, and the backlinks of a page', async () => {
		const c = await withTrip();
		await createNotebook(as(c), { title: 'Work', summary: 'Jobs' });
		await createPage(as(c), { notebook: 'Trip', title: 'Zed' });
		await createPage(as(c), { notebook: 'Trip', title: 'Alpha' });
		await createPage(as(c), { notebook: 'Trip', title: 'Sub', parent: 'Zed' });
		const outline = await notebookOutline(c);
		expect(outline.notebooks.map((n) => n.title)).toEqual(['Trip', 'Work']);
		expect(outline.notebooks[0]?.pages.map((p) => p.title)).toEqual([
			'Overview',
			'Zed',
			'Sub',
			'Alpha'
		]);
		expect(outline.notebooks[0]?.pages[2]).toMatchObject({ parent: 'Zed', chars: 0 });
		await deletePage(as(c), { notebook: 'Trip', page: 'Alpha' });
		const gone = await notebookOutline(c, { deleted: true });
		expect(gone.notebooks[0]?.pages.map((p) => p.title)).toEqual(['Alpha']);
		expect(gone.notebooks[0]?.pages[0]?.deletedAt).toBeTruthy();
		// Links by title, and by notebook and title
		const zed = await idOf(c, 'Trip', 'Zed');
		await createPage(as(c), { notebook: 'Work', title: 'Plan', text: 'see [[Zed]] and more' });
		await createPage(as(c), { notebook: 'Work', title: 'Plan 2', text: 'also [[trip/zed]]' });
		await createPage(as(c), { notebook: 'Work', title: 'Plan 3', text: 'no link [[Zeds]]' });
		const links = await pageBacklinks(c, { pageId: zed });
		expect(links.links.map((l) => `${l.notebook}/${l.page}`)).toEqual(['Work/Plan', 'Work/Plan 2']);
		expect(links.links[0]?.snippet).toContain('[[Zed]]');
		await expect(pageBacklinks(agentOf(c), { pageId: zed })).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
	});

	it('pins pages and notebooks for the person and lists what the assistant changed', async () => {
		const c = await withTrip();
		const page = await asAgent(c, 'Trip', 'By agent', 'x');
		const mine = await createPage(as(c), { notebook: 'Trip', title: 'By me' });
		const pinned = await pinPage(as(c), { pageId: page.id, pinned: true });
		expect(pinned.pinnedAt).toBeTruthy();
		expect((await pinPage(as(c), { pageId: page.id, pinned: false })).pinnedAt).toBeNull();
		const trip = await getNotebook(c, { notebook: 'Trip' });
		expect((await pinNotebook(as(c), { notebookId: trip.id, pinned: true })).pinnedAt).toBeTruthy();
		expect(
			(await listNotebooks(c)).notebooks.find((n) => n.title === 'Trip')?.pinnedAt
		).toBeTruthy();
		const activity = await pageActivity(c);
		expect(activity.pages.map((p) => p.page)).toContain('By agent');
		expect(activity.pages.map((p) => p.page)).not.toContain('By me');
		expect(activity.pages.find((p) => p.page === 'By agent')).toMatchObject({
			notebook: 'Trip',
			version: 1,
			seenVersion: 0
		});
		expect(mine.updatedBy).toBe('user');
		// Older than 14 days is left out
		await exec(
			c,
			sql`update notebook_page set updated_at = now() - interval '15 days' where id = ${page.id}`
		);
		expect((await pageActivity(c)).pages).toEqual([]);
	});

	it('tells in the activity list what the assistant did: made the page, changed its text, or only renamed or moved it', async () => {
		const c = await withTrip();
		await createNotebook(as(c), { title: 'Work' });
		const flags = async (title: string) => {
			const e = (await pageActivity(c)).pages.find((p) => p.page === title);
			return e ? { created: e.created, textChanged: e.textChanged, version: e.version } : undefined;
		};
		// The assistant made it
		await asAgent(c, 'Trip', 'Made by Botler', 'x');
		expect(await flags('Made by Botler')).toEqual({
			created: true,
			textChanged: false,
			version: 1
		});
		// The assistant changed the text of a page it made
		await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Made by Botler',
			op: 'add',
			heading: 'Notes',
			line: 'more'
		});
		expect(await flags('Made by Botler')).toEqual({
			created: false,
			textChanged: true,
			version: 2
		});
		// The assistant only renamed or moved a page the person made, at version 1 and at a later version
		await createPage(as(c), { notebook: 'Trip', title: 'Mine one', text: 'mine' });
		await renamePage(agentOf(c), { notebook: 'Trip', page: 'Mine one', newTitle: 'Renamed one' });
		expect(await flags('Renamed one')).toEqual({ created: false, textChanged: false, version: 1 });
		const two = await createPage(as(c), { notebook: 'Trip', title: 'Mine two', text: 'mine' });
		await savePage(as(c), { pageId: two.id, text: 'mine, edited', expectVersion: 1 });
		await movePage(agentOf(c), { notebook: 'Trip', page: 'Mine two', toNotebook: 'Work' });
		expect(await flags('Mine two')).toEqual({ created: false, textChanged: false, version: 2 });
		// The assistant changed the text over the person's, and then the person changed it back: the person's change is the latest
		const three = await createPage(as(c), { notebook: 'Trip', title: 'Both', text: 'mine' });
		await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Both',
			op: 'add',
			heading: 'Notes',
			line: 'bot'
		});
		expect(await flags('Both')).toMatchObject({ textChanged: true, version: 2 });
		await savePage(as(c), { pageId: three.id, text: 'mine again', expectVersion: 2 });
		await renamePage(agentOf(c), { notebook: 'Trip', page: 'Both', newTitle: 'Both renamed' });
		expect(await flags('Both renamed')).toEqual({ created: false, textChanged: false, version: 3 });
		// A page the assistant made and then renamed is no longer a pristine creation either
		await asAgent(c, 'Trip', 'Botler page two', 'y');
		await renamePage(agentOf(c), {
			notebook: 'Trip',
			page: 'Botler page two',
			newTitle: 'Botler 2'
		});
		expect(await flags('Botler 2')).toEqual({ created: false, textChanged: false, version: 1 });
	});
});

describe('the verbs of the assistant and the person', () => {
	it('offers the assistant titles only, and keeps the person verbs away from it', () => {
		const names = agentVerbs().map((v) => v.name);
		for (const n of [
			'page_create',
			'page_get',
			'page_edit',
			'page_rename',
			'page_move',
			'page_merge',
			'page_delete',
			'page_undelete',
			'notebook_outline',
			'notebook_search'
		]) {
			expect(names).toContain(n);
			const shapeKeys = Object.keys(
				verbByName(n)?.agentInput?.shape ?? verbByName(n)?.input.shape ?? {}
			);
			for (const forbidden of [
				'userId',
				'user_id',
				'pageId',
				'notebookId',
				'parentPageId',
				'toNotebookId',
				'toParentPageId',
				'sourceIds'
			])
				expect(shapeKeys, `${n} ${forbidden}`).not.toContain(forbidden);
		}
		for (const n of [
			'page_save',
			'page_seen',
			'page_pin',
			'page_revisions',
			'page_revision_get',
			'page_restore',
			'page_backlinks',
			'page_activity',
			'notebook_pin'
		])
			expect(names, n).not.toContain(n);
		expect(verbByName('page_delete')?.kind).toBe('free');
		expect(verbByName('notebook_outline')?.kind).toBe('read');
	});

	it('refuses the assistant an id even by hand, and the person verbs by name', async () => {
		const c = await withTrip();
		const page = await createPage(as(c), { notebook: 'Trip', title: 'Secret' });
		for (const [verb, args] of [
			['page_get', { pageId: page.id }],
			['page_edit', { pageId: page.id, op: 'remove', find: 'x' }],
			['page_delete', { pageId: page.id }],
			['page_create', { notebookId: page.notebookId, title: 'X' }],
			['page_move', { notebook: 'Trip', page: 'Secret', toParentPageId: page.id }]
		] as const)
			await expect(invokeVerb(agentOf(c), verb, args), verb).rejects.toMatchObject({
				code: 'INVALID'
			});
		for (const verb of ['page_save', 'page_seen', 'page_pin', 'page_revisions', 'page_restore'])
			await expect(invokeVerb(agentOf(c), verb, {}), verb).rejects.toMatchObject({
				code: 'FORBIDDEN'
			});
		for (const [fn, name] of [
			[pageRevisions, 'page_revisions'],
			[pageRevisionGet, 'page_revision_get']
		] as const)
			await expect(
				fn(agentOf(c), { pageId: page.id, revisionId: page.id }),
				name
			).rejects.toMatchObject({
				code: 'FORBIDDEN'
			});
	});

	it('runs page verbs as the assistant through the registry', async () => {
		const c = await withTrip();
		await invokeVerb(agentOf(c), 'page_create', { notebook: 'Trip', title: 'Hotels', text: 'Inn' });
		await invokeVerb(agentOf(c), 'page_edit', {
			notebook: 'Trip',
			page: 'Hotels',
			op: 'add',
			heading: 'Booked',
			line: 'Station inn'
		});
		const got = (await invokeVerb(agentOf(c), 'page_get', {
			notebook: 'Trip',
			page: 'Hotels'
		})) as {
			text: string;
		};
		expect(got.text).toContain('Station inn');
		await invokeVerb(agentOf(c), 'page_delete', { notebook: 'Trip', page: 'Hotels' });
		expect(await shape(c)).toEqual(['Overview']);
	});
});

describe('an extra notebook for an older app: its Overview page', () => {
	it('makes the notebook with an Overview page holding the first text, and reads and lists it from the page', async () => {
		const c = await newUser();
		const made = await createNotebook(agentOf(c), {
			title: 'Ideas',
			summary: 'Gifts',
			text: '# Gifts\n- a book'
		});
		expect(made).toMatchObject({ version: 1, text: '# Gifts\n- a book', pageCount: 1 });
		expect((await shape(c, 'Ideas'))[0]).toBe('Overview');
		// The text of the notebook row itself is empty: it lives in the page
		const row = await withUser(t.handle, c.actor.userId, (tx) =>
			tx.select().from(notebook).where(eq(notebook.id, made.id))
		);
		expect(row[0]?.text).toBe('');
		await createPage(as(c), { notebook: 'Ideas', title: 'Second', text: 'x'.repeat(100) });
		const listed = (await listNotebooks(c)).notebooks.find((n) => n.title === 'Ideas');
		expect(listed?.chars).toBe('# Gifts\n- a book'.length + 100);
		expect(listed?.pageCount).toBe(2);
		// What an older app reads is still the Overview text and version
		const old = await getNotebook(c, { notebook: 'Ideas' });
		expect(old).toMatchObject({ text: '# Gifts\n- a book', version: 1, kind: 'extra' });
		const ctx = await loadNotebookContext(c);
		expect(ctx.others.find((o) => o.title === 'Ideas')?.chars).toBe(
			'# Gifts\n- a book'.length + 100
		);
		expect(ctx.outline[0]?.pages.map((p) => p.title)).toEqual(['Overview', 'Second']);
	});

	it('edits, saves, lists the changes of and restores the Overview page, and refuses a save or restore once there are other pages', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Ideas', text: 'one' });
		await editNotebook(agentOf(c), {
			notebook: 'Ideas',
			op: 'add',
			heading: 'More',
			line: 'two'
		});
		const edited = await getNotebook(c, { notebook: 'Ideas' });
		expect(edited.text).toContain('two');
		expect(edited.version).toBe(2);
		expect(edited.updatedBy).toBe('agent');
		const saved = await saveNotebook(as(c), { notebook: 'Ideas', text: 'three', expectVersion: 2 });
		expect(saved).toMatchObject({ changed: true, version: 3, text: 'three' });
		await expect(
			saveNotebook(as(c), { notebook: 'Ideas', text: 'stale', expectVersion: 2 })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		const revs = (await listRevisions(c, { notebook: 'Ideas' })).revisions;
		expect(revs.map((r) => r.version)).toEqual([2, 1]);
		const back = await restoreRevision(as(c), { revisionId: revs[1]?.id ?? '' });
		expect(back.text).toBe('one');
		// The older app cannot show a second page, so it may not overwrite the notebook
		await createPage(as(c), { notebook: 'Ideas', title: 'Another', text: 'keep me' });
		const now = await getNotebook(c, { notebook: 'Ideas' });
		await expect(
			saveNotebook(as(c), { notebook: 'Ideas', text: 'wipe', expectVersion: now.version })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('Update') });
		await expect(restoreRevision(as(c), { revisionId: revs[0]?.id ?? '' })).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('Update')
		});
		expect((await getPage(c, { notebook: 'Ideas', page: 'Another' })).text).toBe('keep me');
		// An edit by the assistant still works on the Overview page
		await editNotebook(agentOf(c), {
			notebook: 'Ideas',
			op: 'replace',
			find: 'one',
			replacement: 'uno'
		});
		expect((await getPage(c, { notebook: 'Ideas', page: 'Overview' })).text).toBe('uno');
	});

	it('treats only a page titled Overview as the notebook text: no other page stands in, and the assistant is pointed to the page verbs', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Ideas', text: 'old' });
		await renamePage(as(c), { notebook: 'Ideas', page: 'Overview', newTitle: 'Front' });
		await createPage(as(c), { notebook: 'Ideas', title: 'Second', text: 'two' });
		// An older app opening it sees an empty notebook at version 0, and cannot save over the pages it cannot show
		expect(await getNotebook(as(c), { notebook: 'Ideas' })).toMatchObject({
			text: '',
			version: 0,
			pageCount: 2
		});
		await expect(
			saveNotebook(as(c), { notebook: 'Ideas', text: 'wipe', expectVersion: 0 })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('Update') });
		// The assistant is told which verbs to use, and no page is touched
		for (const run of [
			() => getNotebook(agentOf(c), { notebook: 'Ideas' }),
			() =>
				editNotebook(agentOf(c), {
					notebook: 'Ideas',
					op: 'add',
					heading: 'New',
					line: 'again'
				})
		])
			await expect(run()).rejects.toMatchObject({
				code: 'INVALID',
				message: expect.stringMatching(/notebook_outline.*page_get.*page_edit/)
			});
		expect((await getPage(c, { notebook: 'Ideas', page: 'Front' })).text).toBe('old');
		expect((await getPage(c, { notebook: 'Ideas', page: 'Second' })).text).toBe('two');
		expect(await shape(c, 'Ideas')).toEqual(['Front', 'Second']);
		// The person's older app can still list the changes (none for an Overview that is not there)
		expect((await listRevisions(c, { notebook: 'Ideas' })).revisions).toEqual([]);
		// With every page gone the notebook is empty: an edit makes the Overview page
		await deletePage(as(c), { notebook: 'Ideas', page: 'Front' });
		await deletePage(as(c), { notebook: 'Ideas', page: 'Second' });
		expect(await getNotebook(c, { notebook: 'Ideas' })).toMatchObject({
			text: '',
			version: 0,
			pageCount: 0
		});
		await editNotebook(agentOf(c), { notebook: 'Ideas', op: 'add', heading: 'New', line: 'again' });
		expect((await getPage(c, { notebook: 'Ideas', page: 'Overview' })).text).toContain('again');
		// Delete and put back the notebook: its pages come with it
		await deleteNotebook(as(c), { notebook: 'Ideas' });
		expect(await shape(c, 'Ideas').catch(() => 'gone')).toBe('gone');
		await undeleteNotebook(as(c), { notebook: 'Ideas' });
		expect(await shape(c, 'Ideas')).toEqual(['Overview']);
	});

	it('lets an older app save a notebook whose only page is the Overview, and creates the Overview on a save into an empty notebook', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Solo', text: 'first' });
		expect(
			await saveNotebook(as(c), { notebook: 'Solo', text: 'second', expectVersion: 1 })
		).toMatchObject({ changed: true, version: 2, text: 'second' });
		await deletePage(as(c), { notebook: 'Solo', page: 'Overview' });
		const made = await saveNotebook(as(c), { notebook: 'Solo', text: 'again', expectVersion: 0 });
		expect(made).toMatchObject({ changed: true, text: 'again', pageCount: 1 });
		expect(await shape(c, 'Solo')).toEqual(['Overview']);
	});

	it('tells the assistant the Overview is not the whole notebook, and keeps the list in step with the pages', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Ideas', text: 'one' });
		const before = (await listNotebooks(c)).notebooks.find((n) => n.title === 'Ideas');
		await createPage(as(c), { notebook: 'Ideas', title: 'Second', text: 'x' });
		const read = await getNotebook(agentOf(c), { notebook: 'Ideas' });
		expect(read.text).toBe('one');
		expect(read.note).toContain('notebook_outline');
		await editNotebook(agentOf(c), { notebook: 'Ideas', op: 'add', heading: 'H', line: 'two' });
		await editPage(agentOf(c), {
			notebook: 'Ideas',
			page: 'Second',
			op: 'add',
			heading: 'H',
			line: 'y'
		});
		const after = (await listNotebooks(c)).notebooks.find((n) => n.title === 'Ideas');
		// The list agrees with the Overview page and with the newest page change, not with the notebook row
		expect(after?.version).toBe(2);
		expect(after?.version).toBe((await getNotebook(c, { notebook: 'Ideas' })).version);
		expect(after?.updatedBy).toBe('agent');
		expect(new Date(after?.updatedAt ?? 0).getTime()).toBeGreaterThan(
			new Date(before?.updatedAt ?? 0).getTime()
		);
		const second = await getPage(c, { notebook: 'Ideas', page: 'Second' });
		expect(new Date(after?.updatedAt ?? 0).getTime()).toBeGreaterThanOrEqual(
			new Date(second.updatedAt).getTime()
		);
		// The main notebook is listed as before
		const main = (await listNotebooks(c)).notebooks.find((n) => n.kind === 'main');
		expect(main?.version).toBeGreaterThanOrEqual(1);
	});
});

describe('the 30 day purge', () => {
	const purge = (c: Ctx) =>
		withUser(t.handle, c.actor.userId, (tx) =>
			(purgeOld as JobHandler)({} as never, tx, {} as never)
		);
	const rows = (c: Ctx) =>
		withUser(t.handle, c.actor.userId, (tx) => tx.select().from(notebookPage));
	const revisionRows = (c: Ctx) =>
		withUser(t.handle, c.actor.userId, (tx) => tx.select().from(notebookPageRevision));

	it('erases pages deleted over 30 days ago with their changes, children before parents, and keeps the recent ones', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Old parent', text: 'a' });
		await createPage(as(c), {
			notebook: 'Trip',
			title: 'Old kid',
			parent: 'Old parent',
			text: 'b'
		});
		await createPage(as(c), { notebook: 'Trip', title: 'Recent', text: 'c' });
		const oldParent = await idOf(c, 'Trip', 'Old parent');
		await savePage(as(c), { pageId: oldParent, text: 'a2', expectVersion: 1 });
		await deletePage(as(c), { notebook: 'Trip', page: 'Old parent' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Recent' });
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '31 days' where title in ('Old parent', 'Old kid')`
		);
		await purge(c);
		const left = (await rows(c)).map((p) => p.title).sort();
		expect(left).toEqual(['Overview', 'Recent']);
		// No change of an erased page is left behind
		const ids = new Set((await rows(c)).map((p) => p.id));
		for (const r of await revisionRows(c)) expect(ids.has(r.pageId)).toBe(true);
		// The recent one can still be restored
		expect((await undeletePage(as(c), { notebook: 'Trip', page: 'Recent' })).title).toBe('Recent');
	});

	it('never removes a page from under a sub-page that stays, live or not yet old enough', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent' });
		await createPage(as(c), { notebook: 'Trip', title: 'Live kid', parent: 'Parent' });
		await createPage(as(c), { notebook: 'Trip', title: 'Fresh kid', parent: 'Parent' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Parent' });
		// A live page cannot sit under a deleted parent (the trigger refuses it), so the kid that stays is one deleted only recently
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '1 day' where title = 'Live kid'`
		);
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '40 days' where title in ('Parent')`
		);
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '2 days' where title = 'Fresh kid'`
		);
		await purge(c);
		const left = (await rows(c)).map((p) => p.title).sort();
		expect(left).toEqual(['Fresh kid', 'Live kid', 'Overview', 'Parent']);
		// Once the sub-pages are gone or old, the parent goes too
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '40 days' where title in ('Live kid', 'Fresh kid')`
		);
		await purge(c);
		expect((await rows(c)).map((p) => p.title)).toEqual(['Overview']);
	});

	it('erases an expired notebook with its pages and their changes through the key, leaving no orphan', async () => {
		const c = await withTrip();
		await createNotebook(as(c), { title: 'Keep' });
		await createPage(as(c), { notebook: 'Trip', title: 'Parent', text: 'a' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid', parent: 'Parent', text: 'b' });
		const kid = await idOf(c, 'Trip', 'Kid');
		await savePage(as(c), { pageId: kid, text: 'b2', expectVersion: 1 });
		const trip = await getNotebook(c, { notebook: 'Trip' });
		await deleteNotebook(as(c), { notebook: 'Trip' });
		await exec(
			c,
			sql`update notebook set deleted_at = now() - interval '31 days' where id = ${trip.id}`
		);
		await purge(c);
		const left = await withUser(t.handle, c.actor.userId, async (tx) => ({
			books: await tx.select().from(notebook).where(eq(notebook.id, trip.id)),
			pages: await tx.select().from(notebookPage).where(eq(notebookPage.notebookId, trip.id)),
			revisions: (await tx.select().from(notebookPageRevision)).length
		}));
		expect(left.books).toHaveLength(0);
		expect(left.pages).toHaveLength(0);
		expect(left.revisions).toBe(0);
		// The other notebook and its Overview page are untouched
		expect(await shape(c, 'Keep')).toEqual(['Overview']);
	});
});

describe('the wipe, the export and the data reset', () => {
	async function filled(): Promise<Ctx> {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent', text: 'a' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid', parent: 'Parent', text: 'b' });
		const kid = await idOf(c, 'Trip', 'Kid');
		await savePage(as(c), { pageId: kid, text: 'b2', expectVersion: 1 });
		await deletePage(as(c), { notebook: 'Trip', page: 'Kid' });
		return c;
	}
	const counts = (c: Ctx) =>
		withUser(t.handle, c.actor.userId, async (tx) => ({
			books: (await tx.select().from(notebook)).length,
			pages: (await tx.select().from(notebookPage)).length,
			revisions: (await tx.select().from(notebookPageRevision)).length
		}));

	it('puts the pages, their parent links and their changes in the export, without the owner', async () => {
		const c = await filled();
		const out = (await exportAll(c)) as {
			memory: {
				notebook: { id: string; kind: string }[];
				notebookPages: {
					id: string;
					title: string;
					parentPageId: string | null;
					deletedAt: unknown;
					userId: string;
				}[];
				notebookPageRevisions: { pageId: string; version: number; text: string }[];
			};
		};
		const titles = out.memory.notebookPages.map((p) => p.title).sort();
		expect(titles).toEqual(['Kid', 'Overview', 'Parent']);
		const kid = out.memory.notebookPages.find((p) => p.title === 'Kid');
		const parent = out.memory.notebookPages.find((p) => p.title === 'Parent');
		expect(kid?.parentPageId).toBe(parent?.id);
		expect(kid?.deletedAt).toBeTruthy();
		expect(out.memory.notebookPageRevisions.map((r) => r.text)).toContain('b');
		const bookIds = new Set(out.memory.notebook.map((n) => n.id));
		expect(
			out.memory.notebookPages.every((p) =>
				bookIds.has((p as unknown as { notebookId: string }).notebookId)
			)
		).toBe(true);
	});

	it('wipes the pages and their changes with the notebooks and leaves nothing behind', async () => {
		const c = await filled();
		const other = await filled();
		const before = await counts(c);
		expect(before.pages).toBeGreaterThan(0);
		expect(before.revisions).toBeGreaterThan(0);
		const done = (await wipeMemory(as(c), { confirm: true })) as {
			pages: number;
			notebooks: number;
		};
		expect(done.pages).toBe(before.pages);
		expect(await counts(c)).toEqual({ books: 0, pages: 0, revisions: 0 });
		// Another person is untouched
		expect((await counts(other)).pages).toBeGreaterThan(0);
	});

	it('erases the pages in a reset of memory and chats, and in a reset of everything', async () => {
		for (const scope of ['memory_and_chat', 'everything'] as const) {
			const c = await filled();
			expect((await counts(c)).pages).toBeGreaterThan(0);
			const preview = await previewDataReset(as(c), { scope });
			expect(preview.counts).toMatchObject({ notebook_page: expect.any(Number) });
			expect(preview.counts.notebook_page).toBeGreaterThan(0);
			await resetData(as(c), { scope, token: preview.token, typed: 'RESET' });
			expect(await counts(c)).toEqual({ books: 0, pages: 0, revisions: 0 });
		}
	});

	it('keeps the page tables out of the audit trail but behind forced row level security', async () => {
		const flags = await t.handle.db.execute(
			sql`select relname, relrowsecurity, relforcerowsecurity from pg_class where relname in ('notebook_page', 'notebook_page_revision') order by relname`
		);
		expect((flags as unknown as { rows: Record<string, unknown>[] }).rows).toEqual([
			{ relname: 'notebook_page', relrowsecurity: true, relforcerowsecurity: true },
			{ relname: 'notebook_page_revision', relrowsecurity: true, relforcerowsecurity: true }
		]);
	});
});

describe('naming a page when the same title is used twice', () => {
	/** Trip holds a top-level page Notes and a page Parent with a sub-page that is also called Notes. */
	async function withClash(): Promise<Ctx> {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Notes', text: 'top one' });
		await createPage(as(c), { notebook: 'Trip', title: 'Parent' });
		await createPage(as(c), {
			notebook: 'Trip',
			title: 'Notes',
			parent: 'Parent',
			text: 'sub one'
		});
		return c;
	}

	it('reads the top-level page by its title, the sub-page with its parent, and either on purpose with "top level"', async () => {
		const c = await withClash();
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes' })).text).toBe('top one');
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes', parent: 'Parent' })).text).toBe(
			'sub one'
		);
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes', parent: 'top level' })).text).toBe(
			'top one'
		);
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes', parent: '' })).text).toBe(
			'top one'
		);
		// A top-level selector for a page that only exists as a sub-page finds nothing
		await createPage(as(c), { notebook: 'Trip', title: 'Only sub', parent: 'Parent' });
		await expect(
			getPage(c, { notebook: 'Trip', page: 'Only sub', parent: 'top level' })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
	});

	it('edits, renames, moves and deletes the top-level page by its title and leaves the sub-page alone', async () => {
		const c = await withClash();
		await editPage(agentOf(c), {
			notebook: 'Trip',
			page: 'Notes',
			op: 'replace',
			find: 'top one',
			replacement: 'top two'
		});
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes' })).text).toBe('top two');
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes', parent: 'Parent' })).text).toBe(
			'sub one'
		);
		await movePage(agentOf(c), { notebook: 'Trip', page: 'Notes', position: 0 });
		expect((await shape(c))[0]).toBe('Notes');
		await renamePage(agentOf(c), { notebook: 'Trip', page: 'Notes', newTitle: 'Top notes' });
		expect((await getPage(c, { notebook: 'Trip', page: 'Top notes' })).text).toBe('top two');
		// The sub-page keeps its name, and is now the only page called Notes
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes' })).parent).toBe('Parent');
		await renamePage(agentOf(c), { notebook: 'Trip', page: 'Top notes', newTitle: 'Notes' });
		const gone = await deletePage(agentOf(c), { notebook: 'Trip', page: 'Notes' });
		expect(gone.removed.text).toBe('top two');
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes' })).text).toBe('sub one');
	});

	it('moves and deletes the sub-page when its parent is named, and the top-level one when "top level" is', async () => {
		const c = await withClash();
		const removed = await deletePage(agentOf(c), {
			notebook: 'Trip',
			page: 'Notes',
			parent: 'Parent'
		});
		expect(removed.removed.text).toBe('sub one');
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes' })).text).toBe('top one');
		const again = await withClash();
		await deletePage(agentOf(again), { notebook: 'Trip', page: 'Notes', parent: 'top level' });
		expect((await getPage(again, { notebook: 'Trip', page: 'Notes' })).parent).toBe('Parent');
	});

	it('merges into the top-level target and from either source, and still asks for the parent when only sub-pages share a title', async () => {
		const c = await withClash();
		await createPage(as(c), { notebook: 'Trip', title: 'Other', text: 'other text' });
		// The target is the top-level Notes; the source is the sub-page of Parent
		await mergePages(agentOf(c), {
			notebook: 'Trip',
			page: 'Notes',
			sources: [{ page: 'Notes', parent: 'Parent' }]
		});
		expect((await getPage(c, { notebook: 'Trip', page: 'Notes' })).text).toContain('sub one');
		expect((await shape(c)).filter((x) => x === '- Notes')).toEqual([]);
		// The source named by a title alone is the top-level page
		const d = await withClash();
		await createPage(as(d), { notebook: 'Trip', title: 'Sink', text: 'sink' });
		await mergePages(agentOf(d), { notebook: 'Trip', page: 'Sink', sources: [{ page: 'Notes' }] });
		expect((await getPage(d, { notebook: 'Trip', page: 'Sink' })).text).toContain('top one');
		expect((await getPage(d, { notebook: 'Trip', page: 'Notes' })).parent).toBe('Parent');
		// The target is the sub-page when its parent is named
		const e = await withClash();
		await mergePages(agentOf(e), {
			notebook: 'Trip',
			page: 'Notes',
			parent: 'Parent',
			sources: [{ page: 'Notes', parent: 'top level' }]
		});
		expect((await getPage(e, { notebook: 'Trip', page: 'Notes' })).text).toContain('top one');
		// Two sub-pages with one title and no top-level page: the parent must be named
		const f = await withTrip();
		for (const parent of ['P1', 'P2']) {
			await createPage(as(f), { notebook: 'Trip', title: parent });
			await createPage(as(f), { notebook: 'Trip', title: 'Same', parent });
		}
		await expect(getPage(f, { notebook: 'Trip', page: 'Same' })).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('Name the parent page too')
		});
		expect((await getPage(f, { notebook: 'Trip', page: 'Same', parent: 'p2' })).parent).toBe('P2');
	});
});

describe('what the assistant merges, and the places a page cannot go', () => {
	it('adds the text of the pages that exist as it is and cleans only the headings the assistant writes', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Target', text: 'base' });
		await createPage(as(c), {
			notebook: 'Trip',
			title: 'Source',
			text: 'Call me on 0917 123 4567'
		});
		const out = await mergePages(agentOf(c), {
			notebook: 'Trip',
			page: 'Target',
			sources: [{ page: 'Source' }]
		});
		expect(out.page.text).toContain('0917 123 4567');
		expect(out.note).not.toContain('numbers');
		// New text the assistant writes is still cleaned
		const made = await createPage(agentOf(c), {
			notebook: 'Trip',
			title: 'Fresh',
			text: 'Call me on 0917 123 4567'
		});
		expect(made.text).toContain('(details removed)');
	});

	it('hides a deleted page from search and does not count the pages of a deleted notebook', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Zebra', text: 'a unique zebra word' });
		expect((await notebookSearch(c, { query: 'zebra' })).results).toHaveLength(1);
		await deletePage(as(c), { notebook: 'Trip', page: 'Zebra' });
		expect((await notebookSearch(c, { query: 'zebra' })).results).toEqual([]);
		const count = () =>
			withUser(t.handle, c.actor.userId, (tx) => livePageCount(tx, c.actor.userId));
		await createNotebook(as(c), { title: 'Bulk', text: 'x' });
		for (const title of ['One', 'Two']) await createPage(as(c), { notebook: 'Bulk', title });
		const before = await count();
		await deleteNotebook(as(c), { notebook: 'Bulk' });
		expect(await count()).toBe(before - 3);
		await undeleteNotebook(as(c), { notebook: 'Bulk' });
		expect(await count()).toBe(before);
	});

	it('refuses to move a page into a deleted notebook', async () => {
		const c = await withTrip();
		await createNotebook(as(c), { title: 'Old' });
		await createPage(as(c), { notebook: 'Trip', title: 'Wanderer' });
		await deleteNotebook(as(c), { notebook: 'Old' });
		await expect(
			movePage(as(c), { notebook: 'Trip', page: 'Wanderer', toNotebook: 'Old' })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		expect(await shape(c)).toContain('Wanderer');
	});

	it('keeps a change of one person out of reach of another', async () => {
		const c = await withTrip();
		const other = await newUser();
		await createPage(as(c), { notebook: 'Trip', title: 'Mine', text: 'v1' });
		const id = await idOf(c, 'Trip', 'Mine');
		await savePage(as(c), { pageId: id, text: 'v2', expectVersion: 1 });
		const rev = (await pageRevisions(as(c), { pageId: id })).revisions[0];
		expect(rev?.id).toBeTruthy();
		await expect(pageRevisionGet(as(other), { revisionId: rev?.id ?? '' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		await expect(restorePage(as(other), { revisionId: rev?.id ?? '' })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
		expect((await getPage(c, { notebook: 'Trip', page: 'Mine' })).text).toBe('v2');
	});

	it('puts a sub-page first among its siblings when its parent is named', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent' });
		for (const title of ['S1', 'S2', 'S3'])
			await createPage(as(c), { notebook: 'Trip', title, parent: 'Parent' });
		await movePage(as(c), {
			notebook: 'Trip',
			page: 'S3',
			parent: 'Parent',
			toParent: 'Parent',
			position: 0
		});
		expect(await shape(c)).toEqual(['Overview', 'Parent', '- S3', '- S1', '- S2']);
	});

	it('refuses, in the database, a live page under a deleted parent, and brings a lone sub-page back to the top level', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Parent' });
		await createPage(as(c), { notebook: 'Trip', title: 'Kid', parent: 'Parent' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Parent' });
		const outcome = await exec(
			c,
			sql`update notebook_page set deleted_at = null where title = 'Kid'`
		).then(
			() => 'allowed',
			(e: unknown) => causeOf(e)
		);
		expect(outcome).toContain('deleted page');
		const back = await undeletePage(as(c), { notebook: 'Trip', page: 'Kid' });
		expect(back.parentPageId).toBeNull();
		expect(await shape(c)).toEqual(['Overview', 'Kid']);
		// Putting the parent back brings the rest of its family with it, and the trigger does not get in the way
		const parent = await undeletePage(as(c), { notebook: 'Trip', page: 'Parent' });
		expect(parent.parentPageId).toBeNull();
	});

	it('refuses a seen mark past what a version can be', async () => {
		const c = await withTrip();
		await createPage(as(c), { notebook: 'Trip', title: 'Seen' });
		const id = await idOf(c, 'Trip', 'Seen');
		await expect(pageSeen(as(c), { pageId: id, version: 2 ** 31 })).rejects.toMatchObject({
			code: 'INVALID'
		});
		expect(await pageSeen(as(c), { pageId: id, version: 2 ** 31 - 1 })).toMatchObject({
			version: 1,
			seenVersion: 1
		});
	});
});
