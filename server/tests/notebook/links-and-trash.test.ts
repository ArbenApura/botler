// LINKS AND THE TRASH: A LINK INSIDE CODE IS NOT A LINK, A PLAIN LINK STAYS IN ITS NOTEBOOK, AND A PAGE OR NOTEBOOK DELETED OVER 30 DAYS AGO CANNOT COME BACK

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import {
	createNotebook,
	deleteNotebook,
	undeleteNotebook
} from '../../src/lib/server/ops/notebook';
import {
	createPage,
	deletePage,
	notebookOutline,
	pageBacklinks,
	undeletePage
} from '../../src/lib/server/ops/notebookPage';
import { linksTo, linkTargets, withoutCode } from '../../src/lib/server/notebook/text';
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
	const id = `user_lnk_${String(++counter).padStart(5, '0')}`;
	await t.handle.db.insert(user).values({ id, name: id, email: `${id}@example.com` });
	return { handle: t.handle, actor: { userId: id, kind: 'person' } };
}

const as = (c: Ctx): Ctx => ({ ...c, requestId: `lnk-req-${String(++rids).padStart(8, '0')}` });

const exec = (c: Ctx, query: ReturnType<typeof sql>) =>
	withUser(t.handle, c.actor.userId, (tx) => tx.execute(query));

async function idOf(c: Ctx, book: string, title: string) {
	const out = await notebookOutline(c, { notebook: book });
	const id = out.notebooks[0]?.pages.find((p) => p.title === title)?.id;
	if (!id) throw new Error(`no page ${title}`);
	return id;
}

const FENCE = '```';

// -- TESTS -- //

describe('reading links', () => {
	it('cuts out inline code and fenced blocks before it looks for links', () => {
		const text = [
			'see [[Real]]',
			'but `[[Span]]` is code',
			FENCE,
			'[[Fenced]]',
			FENCE,
			'~~~',
			'[[Tilde]]',
			'~~~',
			'and [[Last]]'
		].join('\n');
		expect(linkTargets(text)).toEqual(['Real', 'Last']);
		expect(withoutCode(text)).not.toContain('Fenced');
	});

	it('reads a label after the bar and ignores a link that spans lines', () => {
		expect(linkTargets('[[Trip/Plan|the plan]] [[Broken\nlink]]')).toEqual(['Trip/Plan']);
	});

	it('keeps a plain link in its own notebook and lets a full link come from anywhere', () => {
		expect(linksTo('see [[Zed]]', 'Trip', 'Zed', true)).toBe(true);
		expect(linksTo('see [[Zed]]', 'Trip', 'Zed', false)).toBe(false);
		expect(linksTo('see [[trip/zed]]', 'Trip', 'Zed', false)).toBe(true);
		expect(linksTo('see [[Other/Zed]]', 'Trip', 'Zed', true)).toBe(false);
	});
});

describe('the backlinks of a page', () => {
	it('ignores links written inside code spans and fences', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Trip' });
		await createPage(as(c), { notebook: 'Trip', title: 'Zed' });
		await createPage(as(c), { notebook: 'Trip', title: 'Real', text: 'go to [[Zed]]' });
		await createPage(as(c), { notebook: 'Trip', title: 'Span', text: 'type `[[Zed]]` to link' });
		await createPage(as(c), {
			notebook: 'Trip',
			title: 'Fence',
			text: `example:\n${FENCE}\n[[Zed]]\n${FENCE}\n`
		});
		const links = await pageBacklinks(c, { pageId: await idOf(c, 'Trip', 'Zed') });
		expect(links.links.map((l) => l.page)).toEqual(['Real']);
	});

	it('counts a plain link from the same notebook only, and a written-out one from another', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Trip' });
		await createNotebook(as(c), { title: 'Work' });
		await createPage(as(c), { notebook: 'Trip', title: 'Zed' });
		await createPage(as(c), { notebook: 'Work', title: 'Plain', text: 'see [[Zed]]' });
		await createPage(as(c), { notebook: 'Work', title: 'Full', text: 'see [[Trip/Zed]]' });
		await createPage(as(c), { notebook: 'Trip', title: 'Home', text: 'see [[Zed]]' });
		const links = await pageBacklinks(c, { pageId: await idOf(c, 'Trip', 'Zed') });
		expect(links.links.map((l) => `${l.notebook}/${l.page}`)).toEqual(['Trip/Home', 'Work/Full']);
	});
});

describe('the trash keeps things for 30 days', () => {
	it('puts back a page deleted 29 days ago and refuses one deleted 31 days ago', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Trip' });
		await createPage(as(c), { notebook: 'Trip', title: 'Recent' });
		await createPage(as(c), { notebook: 'Trip', title: 'Old' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Recent' });
		await deletePage(as(c), { notebook: 'Trip', page: 'Old' });
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '29 days' where title = 'Recent'`
		);
		await exec(
			c,
			sql`update notebook_page set deleted_at = now() - interval '31 days' where title = 'Old'`
		);
		// The nightly clean-up has not run: the refusal comes from the verb itself
		await expect(undeletePage(as(c), { notebook: 'Trip', page: 'Old' })).rejects.toMatchObject({
			code: 'NOT_FOUND',
			message: expect.stringContaining('30 days')
		});
		expect((await undeletePage(as(c), { notebook: 'Trip', page: 'Recent' })).title).toBe('Recent');
	});

	it('puts back a notebook deleted 29 days ago and refuses one deleted 31 days ago', async () => {
		const c = await newUser();
		await createNotebook(as(c), { title: 'Fresh' });
		await createNotebook(as(c), { title: 'Stale' });
		await deleteNotebook(as(c), { notebook: 'Fresh' });
		await deleteNotebook(as(c), { notebook: 'Stale' });
		await exec(
			c,
			sql`update notebook set deleted_at = now() - interval '29 days' where title = 'Fresh'`
		);
		await exec(
			c,
			sql`update notebook set deleted_at = now() - interval '31 days' where title = 'Stale'`
		);
		await expect(undeleteNotebook(as(c), { notebook: 'Stale' })).rejects.toMatchObject({
			code: 'NOT_FOUND',
			message: expect.stringContaining('30 days')
		});
		expect((await undeleteNotebook(as(c), { notebook: 'Fresh' })).title).toBe('Fresh');
	});
});
