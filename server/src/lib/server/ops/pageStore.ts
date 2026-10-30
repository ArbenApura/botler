// NOTEBOOK PAGE STORAGE: THE ROWS, THE VIEW OF A PAGE, THE REVISIONS AND THE COUNTS THE LIMITS NEED.
// The page verbs (ops/notebookPage.ts) and the older notebook verbs of an extra notebook (ops/notebook.ts, which now read and write its
// "Overview" page) both use this file, so neither imports the other. Everything here runs inside the caller's transaction, with the person
// already locked for a write. A page is live when it and its notebook are not deleted.

// -- TYPES -- //
import type { Tx } from '../db/client';
// -- DEP-MODULES -- //
import { and, asc, eq, isNull, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	notebook,
	notebookPage,
	notebookPageRevision,
	NOTEBOOK_PAGE_MAX_CHARS
} from '../db/schema';
import { OpsError } from './context';

// -- TYPES -- //

export type PageActor = 'user' | 'agent' | 'seed';

export type PageRow = typeof notebookPage.$inferSelect;

/** A page as the app and the assistant read it. */
export type PageView = {
	id: string;
	notebookId: string;
	notebook: string;
	parentPageId: string | null;
	parent: string | null;
	title: string;
	text: string;
	version: number;
	position: number;
	pinnedAt: string | null;
	seenVersion: number;
	updatedBy: PageActor;
	updatedAt: string;
	createdAt: string;
	chars: number;
	maxChars: number;
};

/** One line of a notebook's outline. */
export type OutlinePage = {
	id: string;
	parentPageId: string | null;
	/** The title of the parent page, or null for a top-level page. */
	parent: string | null;
	title: string;
	position: number;
	chars: number;
	version: number;
	seenVersion: number;
	pinnedAt: string | null;
	updatedBy: PageActor;
	updatedAt: string;
	/** Set only in the list of deleted pages. */
	deletedAt: string | null;
};

/** The pages the prompt shows under a notebook: top-level titles with their sizes, and the titles of their sub-pages. */
export type PromptOutlineBook = {
	title: string;
	summary: string;
	pages: { title: string; chars: number; subpages: { title: string; chars: number }[] }[];
};

// -- CONSTANTS -- //

/** The newest revisions kept for each page. */
export const PAGE_REVISIONS_KEPT = 50;

export const PAGE_MAX_CHARS = NOTEBOOK_PAGE_MAX_CHARS;

// -- FUNCTIONS -- //

export const pageView = (
	r: PageRow,
	notebookTitle: string,
	parentTitle: string | null
): PageView => ({
	id: r.id,
	notebookId: r.notebookId,
	notebook: notebookTitle,
	parentPageId: r.parentPageId,
	parent: parentTitle,
	title: r.title,
	text: r.text,
	version: r.version,
	position: r.position,
	pinnedAt: r.pinnedAt?.toISOString() ?? null,
	seenVersion: r.seenVersion,
	updatedBy: r.updatedBy,
	updatedAt: r.updatedAt.toISOString(),
	createdAt: r.createdAt.toISOString(),
	chars: r.text.length,
	maxChars: PAGE_MAX_CHARS
});

/** A page with the title of its notebook and of its parent, read back after a change. */
export async function loadPageView(tx: Tx, userId: string, pageId: string): Promise<PageView> {
	const [row] = await tx
		.select()
		.from(notebookPage)
		.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, pageId)));
	if (!row) throw new OpsError('NOT_FOUND', 'The page is gone.');
	const [book] = await tx
		.select({ title: notebook.title })
		.from(notebook)
		.where(and(eq(notebook.userId, userId), eq(notebook.id, row.notebookId)));
	let parent: string | null = null;
	if (row.parentPageId) {
		const [p] = await tx
			.select({ title: notebookPage.title })
			.from(notebookPage)
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, row.parentPageId)));
		parent = p?.title ?? null;
	}
	return pageView(row, book?.title ?? '', parent);
}

/**
 * Replaces the text of a page and keeps the old text as a revision, then drops the revisions past the newest 50. The person's own change is
 * marked as seen. Runs inside the caller's transaction, with the person already locked.
 */
export async function applyPageChange(
	tx: Tx,
	userId: string,
	row: PageRow,
	text: string,
	actor: PageActor,
	ref: string | null
): Promise<PageRow> {
	await tx.insert(notebookPageRevision).values({
		userId,
		pageId: row.id,
		version: row.version,
		text: row.text,
		actor,
		ref
	});
	const [next] = await tx
		.update(notebookPage)
		.set({
			text,
			version: row.version + 1,
			updatedBy: actor,
			updatedAt: sql`now()`,
			...(actor === 'user' ? { seenVersion: row.version + 1 } : {})
		})
		.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, row.id)))
		.returning();
	if (!next) throw new OpsError('NOT_FOUND', 'The page is gone.');
	await tx.execute(sql`
		delete from notebook_page_revision
		where user_id = ${userId} and page_id = ${row.id}
		  and id not in (
			select id from notebook_page_revision
			where user_id = ${userId} and page_id = ${row.id}
			order by version desc limit ${PAGE_REVISIONS_KEPT})`);
	return next;
}

/** The live pages of the person over all live notebooks: the count the 500 limit is judged on. Deleted pages and pages of deleted notebooks do not count. */
export async function livePageCount(tx: Tx, userId: string): Promise<number> {
	const [r] = await tx
		.select({ n: sql<number>`count(*)::int` })
		.from(notebookPage)
		.innerJoin(
			notebook,
			and(eq(notebook.userId, notebookPage.userId), eq(notebook.id, notebookPage.notebookId))
		)
		.where(
			and(
				eq(notebookPage.userId, userId),
				isNull(notebookPage.deletedAt),
				isNull(notebook.deletedAt)
			)
		);
	return Number(r?.n ?? 0);
}

/** The live sub-pages under one top-level page. */
export async function liveSubpageCount(tx: Tx, userId: string, parentId: string): Promise<number> {
	const [r] = await tx
		.select({ n: sql<number>`count(*)::int` })
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.parentPageId, parentId),
				isNull(notebookPage.deletedAt)
			)
		);
	return Number(r?.n ?? 0);
}

/**
 * The page an older app (and the assistant's older notebook verbs) read and write as the text of an extra notebook: the live top-level page
 * titled Overview, ignoring case. Null when there is none; no other page ever stands in for it.
 */
export async function overviewOf(
	tx: Tx,
	userId: string,
	notebookId: string
): Promise<PageRow | null> {
	const rows = await tx
		.select()
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.notebookId, notebookId),
				isNull(notebookPage.deletedAt),
				isNull(notebookPage.parentPageId),
				sql`lower(${notebookPage.title}) = 'overview'`
			)
		)
		.orderBy(asc(notebookPage.position), asc(notebookPage.createdAt), asc(notebookPage.id))
		.limit(1);
	return rows[0] ?? null;
}

/** How many live pages a notebook has. */
export async function livePagesIn(tx: Tx, userId: string, notebookId: string): Promise<number> {
	const [r] = await tx
		.select({ n: sql<number>`count(*)::int` })
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.notebookId, notebookId),
				isNull(notebookPage.deletedAt)
			)
		);
	return Number(r?.n ?? 0);
}

/** The ids of the live pages that share a parent (null: the top level of a notebook), in their order, without the page named in `except`. */
export async function siblingIds(
	tx: Tx,
	userId: string,
	notebookId: string,
	parentId: string | null,
	except?: string
): Promise<string[]> {
	const rows = await tx
		.select({ id: notebookPage.id, position: notebookPage.position })
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.notebookId, notebookId),
				parentId ? eq(notebookPage.parentPageId, parentId) : isNull(notebookPage.parentPageId),
				isNull(notebookPage.deletedAt)
			)
		)
		.orderBy(
			asc(notebookPage.position),
			asc(sql`lower(${notebookPage.title})`),
			asc(notebookPage.id)
		);
	return rows.map((r) => r.id).filter((i) => i !== except);
}

/** Puts a page at a place among its siblings (0 is first; left out, last) and numbers them again 0, 1, 2. Only a row whose number changed is written. */
export async function placeAt(
	tx: Tx,
	userId: string,
	notebookId: string,
	parentId: string | null,
	pageId: string,
	position?: number
): Promise<void> {
	const others = await siblingIds(tx, userId, notebookId, parentId, pageId);
	const at = position === undefined ? others.length : Math.min(position, others.length);
	others.splice(at, 0, pageId);
	const current = await tx
		.select({ id: notebookPage.id, position: notebookPage.position })
		.from(notebookPage)
		.where(and(eq(notebookPage.userId, userId), eq(notebookPage.notebookId, notebookId)));
	const has = new Map(current.map((r) => [r.id, r.position]));
	for (const [index, id] of others.entries()) {
		if (has.get(id) === index) continue;
		await tx
			.update(notebookPage)
			.set({ position: index })
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, id)));
	}
}
