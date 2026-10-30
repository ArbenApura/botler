// NOTEBOOK PAGE VERBS: THE LIBRARY OF PAGES INSIDE THE EXTRA NOTEBOOKS.
// Each extra notebook holds pages; a page may have sub-pages one level deep. The main notebook has no pages. A verb names a page by id (the app)
// or by the title of its notebook and its own title (the assistant, which never sees an id). Rules that hold for every writer:
// - A change to the text never loses text: the replaced text is kept as a revision (newest 50), with who made it.
// - The person's save names the version it was made from; a stale one is refused. Looking at a page (page_seen) only moves a seen mark, so it can
//   never make a save stale.
// - Limits: 500 live pages per person, 20 sub-pages under a page, 80 characters in a title, 30000 in a text. Deleted pages do not count. Every
//   write runs under the person's lock, so two requests at once cannot both pass a limit or make a loop; the database trigger refuses a second level.
// - A delete hides a page (and its sub-pages together) for 30 days; an undelete puts it back where it was, or at the top level when its parent is gone.
// - Every read joins the notebook and shows only live pages of live notebooks.
// - Everything new that the assistant writes (titles, text, headings) has account, card and phone numbers taken out first. A merge adds the text of
//   pages that already exist as it is; only the headings it writes are cleaned.
// - A title names a page when it is the only one with that title; a top-level page wins over sub-pages that share its title, and the parent
//   "top level" (or an empty one) names the top-level page on purpose.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { OutlinePage, PageRow, PageView } from './pageStore';
// -- DEP-MODULES -- //
import { and, asc, desc, eq, ilike, inArray, isNotNull, isNull, or, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	notebook,
	notebookPage,
	notebookPageRevision,
	NOTEBOOK_MAX_PAGES,
	NOTEBOOK_MAX_SUBPAGES,
	NOTEBOOK_PAGE_MAX_CHARS,
	NOTEBOOK_PAGE_TITLE_MAX,
	NOTEBOOK_TRASH_DAYS
} from '../db/schema';
import {
	notebookOutlineInput,
	notebookPinInput,
	notebookSearchInput,
	pageCreateInput,
	pageEditInput,
	pageIdInput,
	pageMergeInput,
	pageMoveInput,
	pagePinInput,
	pageRenameInput,
	pageRevisionInput,
	pageSaveInput,
	pageSeenInput,
	pageTargetInput,
	pageUndeleteInput
} from '../db/zod';
import { redactSecrets } from '../memory/pure';
import { addLine, EditError, removeOnce, replaceOnce } from '../notebook/text';
import { OpsError, run, runWrite } from './context';
import { actorOf, redactText, refOf, resolveNotebook } from './notebook';
import {
	applyPageChange,
	liveSubpageCount,
	livePageCount,
	loadPageView,
	PAGE_REVISIONS_KEPT,
	placeAt,
	siblingIds
} from './pageStore';
import { parse, requirePerson } from './shared';

// -- TYPES -- //

type NotebookRow = typeof notebook.$inferSelect;

/** How a verb names a page: by id, or by the title of its notebook and its own title (and its parent's, when the title is used twice). */
type Target = {
	pageId?: string | undefined;
	notebook?: string | undefined;
	page?: string | undefined;
	parent?: string | undefined;
};

/** A page as title matching needs it: no text. */
type Light = { id: string; title: string; parentPageId: string | null; deletedAt: Date | null };

/** The notebooks and page titles one verb has already read, so a merge of many pages reads each notebook once. */
type TitleCache = Map<string, { book: NotebookRow; light: Light[] }>;

// -- CONSTANTS -- //

/** The parent a title-named page is given to say "the top-level one". An empty parent means the same. */
const TOP_LEVEL = 'top level';

/** The most pages a refusal lists, so a long library does not flood the assistant. */
const LIST_IN_REFUSAL = 30;

/** The longest snippet around a search match. */
const SNIPPET_BEFORE = 60;
const SNIPPET_AFTER = 120;

// -- FUNCTIONS -- //

const isAgent = (ctx: Ctx) => actorOf(ctx) === 'agent';

/** Text the assistant wrote has its numbers taken out; the person's own words are kept as they typed them. */
const cleanText = (ctx: Ctx, text: string) => (isAgent(ctx) ? redactText(text) : text);

/** A title on one line, at most 80 characters. The assistant's title also has its numbers taken out. */
function cleanTitle(ctx: Ctx, raw: string): string {
	const collapsed = raw.replace(/\s+/g, ' ').trim();
	const one = isAgent(ctx) ? (redactSecrets(collapsed) ?? '') : collapsed;
	const title = one.slice(0, NOTEBOOK_PAGE_TITLE_MAX).trim();
	if (!title) throw new OpsError('INVALID', 'Give the page a title.');
	return title;
}

const lower = (s: string) => s.toLowerCase();

/** A LIKE pattern that matches the text anywhere, with the wildcard characters in it taken literally. */
const likeAround = (s: string) => `%${s.replace(/[\\%_]/g, '\\$&')}%`;

/**
 * The extra notebook a verb works in: by id or by title. The main notebook has no pages and a deleted notebook is not found, so nothing in it can
 * be read or changed.
 */
async function bookOf(
	tx: Tx,
	userId: string,
	t: { notebookId?: string | undefined; notebook?: string | undefined }
): Promise<NotebookRow> {
	if (!t.notebookId && !t.notebook?.trim())
		throw new OpsError('INVALID', 'Name the notebook the page belongs to.');
	const book = await resolveNotebook(tx, userId, t);
	if (book.kind === 'main')
		throw new OpsError(
			'INVALID',
			'The main notebook has no pages. Pages belong to the other notebooks; edit the main notebook with notebook_edit.'
		);
	return book;
}

/** The live pages of a notebook as titles, to name them in a refusal the assistant can act on. */
async function titlesIn(tx: Tx, userId: string, notebookId: string): Promise<string> {
	const rows = await tx
		.select({ title: notebookPage.title, parentPageId: notebookPage.parentPageId })
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.notebookId, notebookId),
				isNull(notebookPage.deletedAt)
			)
		)
		.orderBy(asc(sql`lower(${notebookPage.title})`))
		.limit(LIST_IN_REFUSAL + 1);
	if (rows.length === 0) return ' It has no pages yet.';
	const shown = rows.slice(0, LIST_IN_REFUSAL).map((r) => `"${r.title}"`);
	return ` The pages are: ${shown.join(', ')}${rows.length > LIST_IN_REFUSAL ? ', and more' : ''}.`;
}

/**
 * The page a verb is about, with its notebook. By id or by titles. A live page of a live notebook is found unless `deleted` says the page is
 * to be a deleted one (to put it back); the notebook must be live either way. A title used by a top-level page and by sub-pages names the
 * top-level page; the parent "top level" says so on purpose.
 */
async function resolvePage(
	tx: Tx,
	userId: string,
	t: Target,
	opts: { deleted?: boolean; cache?: TitleCache } = {}
): Promise<{ page: PageRow; book: NotebookRow }> {
	const wantDeleted = Boolean(opts.deleted);
	if (t.pageId && (t.notebook || t.page || t.parent))
		throw new OpsError('INVALID', 'Name the page by its id or by its titles, not both.');
	if (t.pageId) {
		const [page] = await tx
			.select()
			.from(notebookPage)
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, t.pageId)));
		if (!page || (page.deletedAt !== null) !== wantDeleted)
			throw new OpsError('NOT_FOUND', 'That page is gone or was deleted.');
		const [book] = await tx
			.select()
			.from(notebook)
			.where(and(eq(notebook.userId, userId), eq(notebook.id, page.notebookId)));
		if (!book || book.deletedAt !== null)
			throw new OpsError('NOT_FOUND', 'That page is gone or its notebook was deleted.');
		return { page, book };
	}
	if (!t.page) throw new OpsError('INVALID', 'Name the page by its notebook and its title.');
	const cacheKey = lower(t.notebook?.trim() ?? '');
	let known = opts.cache?.get(cacheKey);
	if (!known) {
		const found = await bookOf(tx, userId, { notebook: t.notebook });
		// Only what title matching needs, never the text of every page
		const light = await tx
			.select({
				id: notebookPage.id,
				title: notebookPage.title,
				parentPageId: notebookPage.parentPageId,
				deletedAt: notebookPage.deletedAt
			})
			.from(notebookPage)
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.notebookId, found.id)));
		known = { book: found, light };
		opts.cache?.set(cacheKey, known);
	}
	const { book, light: all } = known;
	const titleOf = new Map(all.map((p) => [p.id, p.title]));
	let hits = all.filter(
		(p) => lower(p.title) === lower(t.page ?? '') && (p.deletedAt !== null) === wantDeleted
	);
	if (t.parent !== undefined && (t.parent.trim() === '' || lower(t.parent.trim()) === TOP_LEVEL)) {
		// The top level is named on purpose
		hits = hits.filter((p) => p.parentPageId === null);
	} else if (t.parent) {
		const want = lower(t.parent);
		hits = hits.filter((p) => p.parentPageId && lower(titleOf.get(p.parentPageId) ?? '') === want);
	} else if (hits.length > 1 && !wantDeleted) {
		// A top-level page wins over sub-pages that share its title (there is at most one, and the sub-pages can be named by their parent)
		const tops = hits.filter((p) => p.parentPageId === null);
		if (tops.length === 1) hits = tops;
	}
	if (wantDeleted)
		hits.sort((a, b) => (b.deletedAt?.getTime() ?? 0) - (a.deletedAt?.getTime() ?? 0));
	if (hits.length > 1 && !wantDeleted) {
		const where = hits.map((p) =>
			p.parentPageId ? `under "${titleOf.get(p.parentPageId) ?? ''}"` : 'at the top level'
		);
		throw new OpsError(
			'INVALID',
			`Several pages in "${book.title}" are called "${t.page}" (${where.join(', ')}). Name the parent page too.`
		);
	}
	const hit = hits[0];
	if (!hit) {
		if (wantDeleted)
			throw new OpsError(
				'NOT_FOUND',
				`There is no deleted page called "${t.page}" in "${book.title}".`
			);
		throw new OpsError(
			'NOT_FOUND',
			`There is no page called "${t.page}" in the notebook "${book.title}".${await titlesIn(tx, userId, book.id)}`
		);
	}
	const [page] = await tx
		.select()
		.from(notebookPage)
		.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, hit.id)));
	if (!page) throw new OpsError('NOT_FOUND', 'That page is gone or was deleted.');
	return { page, book };
}

/** A top-level live page of a notebook named by id or by title, to be a parent. */
async function resolveParent(
	tx: Tx,
	userId: string,
	book: NotebookRow,
	t: { parentPageId?: string | undefined; parent?: string | undefined }
): Promise<PageRow | null> {
	if (!t.parentPageId && !t.parent) return null;
	if (t.parentPageId && t.parent)
		throw new OpsError('INVALID', 'Name the parent page by its id or by its title, not both.');
	const rows = await tx
		.select()
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.notebookId, book.id),
				isNull(notebookPage.deletedAt),
				t.parentPageId
					? eq(notebookPage.id, t.parentPageId)
					: sql`lower(${notebookPage.title}) = lower(${t.parent ?? ''})`
			)
		);
	const tops = rows.filter((r) => r.parentPageId === null);
	const parent = tops[0];
	if (!parent) {
		if (rows.length > 0)
			throw new OpsError(
				'INVALID',
				'A sub-page cannot have sub-pages: the parent must be a top-level page.'
			);
		throw new OpsError(
			'NOT_FOUND',
			`There is no top-level page "${t.parent ?? ''}" in "${book.title}" to put it under.${await titlesIn(tx, userId, book.id)}`
		);
	}
	return parent;
}

/** A page with the same title among the live pages that share a parent, other than the page itself. */
async function titleTaken(
	tx: Tx,
	userId: string,
	notebookId: string,
	parentId: string | null,
	title: string,
	except?: string
): Promise<boolean> {
	const rows = await tx
		.select({ id: notebookPage.id })
		.from(notebookPage)
		.where(
			and(
				eq(notebookPage.userId, userId),
				eq(notebookPage.notebookId, notebookId),
				parentId ? eq(notebookPage.parentPageId, parentId) : isNull(notebookPage.parentPageId),
				isNull(notebookPage.deletedAt),
				sql`lower(${notebookPage.title}) = lower(${title})`
			)
		);
	return rows.some((r) => r.id !== except);
}

const clashMessage = (title: string, book: string, parent: PageRow | null) =>
	`A page called "${title}" already exists ${parent ? `under "${parent.title}"` : 'at the top level'} of "${book}". Use it, or choose another title.`;

const pageLimit = () =>
	`There are already ${NOTEBOOK_MAX_PAGES} pages. Delete or merge some pages first.`;

const subpageLimit = (parent: string) =>
	`"${parent}" already has ${NOTEBOOK_MAX_SUBPAGES} sub-pages. Put the page somewhere else, or merge some of them first.`;

// -- READS -- //

/** A page: its text, version, who wrote it last, and its sub-pages. */
export async function getPage(ctx: Ctx, raw: unknown) {
	const input = parse(pageTargetInput, raw);
	return run(ctx, async (tx, userId) => {
		const { page } = await resolvePage(tx, userId, input);
		const view = await loadPageView(tx, userId, page.id);
		const kids = await tx
			.select()
			.from(notebookPage)
			.where(
				and(
					eq(notebookPage.userId, userId),
					eq(notebookPage.parentPageId, page.id),
					isNull(notebookPage.deletedAt)
				)
			)
			.orderBy(asc(notebookPage.position), asc(sql`lower(${notebookPage.title})`));
		return {
			...view,
			path: view.parent
				? `${view.notebook}/${view.parent}/${view.title}`
				: `${view.notebook}/${view.title}`,
			subpages: kids.map((k) => ({
				id: k.id,
				title: k.title,
				chars: k.text.length,
				version: k.version,
				position: k.position,
				updatedAt: k.updatedAt.toISOString()
			}))
		};
	});
}

/**
 * The outline of the library: every live extra notebook with its pages in tree order (a page, then its sub-pages), or one notebook. With
 * `deleted` true, the deleted pages of live notebooks that can still be restored, newest first.
 */
export async function notebookOutline(ctx: Ctx, raw: unknown = {}) {
	const input = parse(notebookOutlineInput, raw);
	return run(ctx, async (tx, userId) => {
		let only: NotebookRow | null = null;
		if (input.notebookId || input.notebook) only = await bookOf(tx, userId, input);
		const books = await tx
			.select()
			.from(notebook)
			.where(
				and(
					eq(notebook.userId, userId),
					eq(notebook.kind, 'extra'),
					isNull(notebook.deletedAt),
					only ? eq(notebook.id, only.id) : undefined
				)
			)
			.orderBy(asc(sql`lower(${notebook.title})`));
		const pages = await tx
			.select({ page: notebookPage })
			.from(notebookPage)
			.innerJoin(
				notebook,
				and(eq(notebook.userId, notebookPage.userId), eq(notebook.id, notebookPage.notebookId))
			)
			.where(
				and(
					eq(notebookPage.userId, userId),
					isNull(notebook.deletedAt),
					eq(notebook.kind, 'extra'),
					input.deleted ? isNotNull(notebookPage.deletedAt) : isNull(notebookPage.deletedAt)
				)
			);
		const all = pages.map((r) => r.page);
		const titleOf = new Map<string, string>();
		for (const p of await tx
			.select({ id: notebookPage.id, title: notebookPage.title })
			.from(notebookPage)
			.where(eq(notebookPage.userId, userId)))
			titleOf.set(p.id, p.title);
		const line = (p: PageRow): OutlinePage => ({
			id: p.id,
			parentPageId: p.parentPageId,
			parent: p.parentPageId ? (titleOf.get(p.parentPageId) ?? null) : null,
			title: p.title,
			position: p.position,
			chars: p.text.length,
			version: p.version,
			seenVersion: p.seenVersion,
			pinnedAt: p.pinnedAt?.toISOString() ?? null,
			updatedBy: p.updatedBy,
			updatedAt: p.updatedAt.toISOString(),
			deletedAt: p.deletedAt?.toISOString() ?? null
		});
		const byOrder = (a: PageRow, b: PageRow) =>
			a.position - b.position ||
			lower(a.title).localeCompare(lower(b.title)) ||
			(a.id < b.id ? -1 : 1);
		const notebooks = books.map((b) => {
			const mine = all.filter((p) => p.notebookId === b.id);
			let ordered: PageRow[];
			if (input.deleted)
				ordered = mine.sort(
					(a, c) => (c.deletedAt?.getTime() ?? 0) - (a.deletedAt?.getTime() ?? 0)
				);
			else {
				ordered = [];
				for (const top of mine.filter((p) => p.parentPageId === null).sort(byOrder)) {
					ordered.push(top);
					ordered.push(...mine.filter((p) => p.parentPageId === top.id).sort(byOrder));
				}
			}
			return {
				id: b.id,
				title: b.title,
				summary: b.summary,
				pinnedAt: b.pinnedAt?.toISOString() ?? null,
				pageCount: mine.length,
				pages: ordered.map(line)
			};
		});
		return { notebooks, deleted: Boolean(input.deleted), maxPages: NOTEBOOK_MAX_PAGES };
	});
}

/** A snippet of the text around the first match, on one line. */
function snippetOf(text: string, query: string): string {
	const at = lower(text).indexOf(lower(query));
	if (at < 0)
		return text
			.slice(0, SNIPPET_BEFORE + SNIPPET_AFTER)
			.replace(/\s+/g, ' ')
			.trim();
	const from = Math.max(0, at - SNIPPET_BEFORE);
	const to = Math.min(text.length, at + query.length + SNIPPET_AFTER);
	return `${from > 0 ? '…' : ''}${text.slice(from, to).replace(/\s+/g, ' ').trim()}${to < text.length ? '…' : ''}`;
}

/** Searches the titles and texts of the live pages of live notebooks, case-insensitively. Title matches come first, then the newest. */
export async function notebookSearch(ctx: Ctx, raw: unknown) {
	const input = parse(notebookSearchInput, raw);
	const limit = input.limit ?? 20;
	return run(ctx, async (tx, userId) => {
		const only =
			input.notebook || input.notebookId
				? await bookOf(tx, userId, { notebook: input.notebook, notebookId: input.notebookId })
				: null;
		const pattern = likeAround(input.query);
		const rows = await tx
			.select({
				page: notebookPage,
				book: notebook.title,
				inTitle: sql<boolean>`${notebookPage.title} ilike ${pattern}`
			})
			.from(notebookPage)
			.innerJoin(
				notebook,
				and(eq(notebook.userId, notebookPage.userId), eq(notebook.id, notebookPage.notebookId))
			)
			.where(
				and(
					eq(notebookPage.userId, userId),
					isNull(notebookPage.deletedAt),
					isNull(notebook.deletedAt),
					eq(notebook.kind, 'extra'),
					only ? eq(notebook.id, only.id) : undefined,
					or(ilike(notebookPage.title, pattern), ilike(notebookPage.text, pattern))
				)
			)
			.orderBy(desc(sql`${notebookPage.title} ilike ${pattern}`), desc(notebookPage.updatedAt))
			.limit(limit + 1);
		const parents = new Map<string, string>();
		const parentIds = [
			...new Set(rows.map((r) => r.page.parentPageId).filter((x): x is string => !!x))
		];
		if (parentIds.length)
			for (const p of await tx
				.select({ id: notebookPage.id, title: notebookPage.title })
				.from(notebookPage)
				.where(and(eq(notebookPage.userId, userId), inArray(notebookPage.id, parentIds))))
				parents.set(p.id, p.title);
		return {
			results: rows.slice(0, limit).map((r) => ({
				pageId: r.page.id,
				notebookId: r.page.notebookId,
				notebook: r.book,
				page: r.page.title,
				parent: r.page.parentPageId ? (parents.get(r.page.parentPageId) ?? null) : null,
				matchIn: r.inTitle ? ('title' as const) : ('text' as const),
				snippet: snippetOf(r.inTitle ? r.page.title : r.page.text, input.query),
				updatedAt: r.page.updatedAt.toISOString()
			})),
			more: rows.length > limit
		};
	});
}

/** The live pages of the library whose text points at a page with [[Title]] or [[Notebook/Title]]. */
export async function pageBacklinks(ctx: Ctx, raw: unknown) {
	requirePerson(ctx.actor.kind, 'see the links to a page');
	const input = parse(pageIdInput, raw);
	return run(ctx, async (tx, userId) => {
		const { page, book } = await resolvePage(tx, userId, { pageId: input.pageId });
		const plain = `[[${page.title}]]`;
		const full = `[[${book.title}/${page.title}]]`;
		const rows = await tx
			.select({ page: notebookPage, book: notebook.title })
			.from(notebookPage)
			.innerJoin(
				notebook,
				and(eq(notebook.userId, notebookPage.userId), eq(notebook.id, notebookPage.notebookId))
			)
			.where(
				and(
					eq(notebookPage.userId, userId),
					isNull(notebookPage.deletedAt),
					isNull(notebook.deletedAt),
					sql`${notebookPage.id} <> ${page.id}`,
					or(
						ilike(notebookPage.text, likeAround(plain)),
						ilike(notebookPage.text, likeAround(full))
					)
				)
			)
			.orderBy(asc(sql`lower(${notebook.title})`), asc(sql`lower(${notebookPage.title})`))
			.limit(50);
		return {
			links: rows.map((r) => ({
				pageId: r.page.id,
				notebookId: r.page.notebookId,
				notebook: r.book,
				page: r.page.title,
				snippet: snippetOf(r.page.text, lower(r.page.text).includes(lower(full)) ? full : plain)
			}))
		};
	});
}

/**
 * The pages the assistant touched in the last 14 days, newest first, for the app's "what changed" list. Two flags say what an undo may do, both
 * worked out from facts so a rename or a move (which keep the version) is never taken for a text change:
 * - created: the assistant made the page and nothing has touched it since (never changed, renamed or moved: its updated time is still its created
 *   time, microsecond for microsecond), so undoing it means deleting it. A page the person made and the assistant later renamed is not created.
 * - textChanged: the assistant made the latest change to the text. A revision keeps the text a change replaced, under the version that text had,
 *   with who replaced it; so the revision of version - 1 is the latest text change, and it is the assistant's.
 * When both are false (a rename or a move) the entry is for looking at only.
 */
export async function pageActivity(ctx: Ctx) {
	requirePerson(ctx.actor.kind, 'see what the assistant changed');
	return run(ctx, async (tx, userId) => {
		const rows = await tx
			.select({
				page: notebookPage,
				book: notebook.title,
				untouched: sql<boolean>`${notebookPage.updatedAt} = ${notebookPage.createdAt}`
			})
			.from(notebookPage)
			.innerJoin(
				notebook,
				and(eq(notebook.userId, notebookPage.userId), eq(notebook.id, notebookPage.notebookId))
			)
			.where(
				and(
					eq(notebookPage.userId, userId),
					isNull(notebookPage.deletedAt),
					isNull(notebook.deletedAt),
					eq(notebookPage.updatedBy, 'agent'),
					sql`${notebookPage.updatedAt} > now() - interval '14 days'`
				)
			)
			.orderBy(desc(notebookPage.updatedAt))
			.limit(50);
		// The actor of each page's latest text change: the revision of version - 1
		const latest = new Map<string, string>();
		const withText = rows.filter((r) => r.page.version > 1);
		if (withText.length) {
			const revs = await tx
				.select({
					pageId: notebookPageRevision.pageId,
					version: notebookPageRevision.version,
					actor: notebookPageRevision.actor
				})
				.from(notebookPageRevision)
				.where(
					and(
						eq(notebookPageRevision.userId, userId),
						inArray(
							notebookPageRevision.pageId,
							withText.map((r) => r.page.id)
						)
					)
				);
			const versionOf = new Map(withText.map((r) => [r.page.id, r.page.version]));
			for (const rev of revs)
				if (rev.version === (versionOf.get(rev.pageId) ?? 0) - 1) latest.set(rev.pageId, rev.actor);
		}
		return {
			pages: rows.map((r) => ({
				pageId: r.page.id,
				notebookId: r.page.notebookId,
				notebook: r.book,
				page: r.page.title,
				version: r.page.version,
				seenVersion: r.page.seenVersion,
				updatedAt: r.page.updatedAt.toISOString(),
				created: r.page.version === 1 && r.untouched,
				textChanged: latest.get(r.page.id) === 'agent'
			}))
		};
	});
}

/** The changes made to a page, newest first: who, when, and the start of the text each one replaced. */
export async function pageRevisions(ctx: Ctx, raw: unknown) {
	requirePerson(ctx.actor.kind, 'see the changes to a page');
	const input = parse(pageIdInput, raw);
	return run(ctx, async (tx, userId) => {
		const { page } = await resolvePage(tx, userId, { pageId: input.pageId });
		const rows = await tx
			.select()
			.from(notebookPageRevision)
			.where(and(eq(notebookPageRevision.userId, userId), eq(notebookPageRevision.pageId, page.id)))
			.orderBy(desc(notebookPageRevision.version))
			.limit(PAGE_REVISIONS_KEPT);
		return {
			revisions: rows.map((r) => ({
				id: r.id,
				version: r.version,
				actor: r.actor,
				at: r.createdAt.toISOString(),
				chars: r.text.length,
				preview: r.text.slice(0, 160)
			}))
		};
	});
}

/** The full text of one earlier version of a page. */
export async function pageRevisionGet(ctx: Ctx, raw: unknown) {
	requirePerson(ctx.actor.kind, 'read an earlier version of a page');
	const input = parse(pageRevisionInput, raw);
	return run(ctx, async (tx, userId) => {
		const [rev] = await tx
			.select()
			.from(notebookPageRevision)
			.where(
				and(eq(notebookPageRevision.userId, userId), eq(notebookPageRevision.id, input.revisionId))
			);
		if (!rev) throw new OpsError('NOT_FOUND', 'That change is not there any more.');
		// The page and its notebook must be live
		await resolvePage(tx, userId, { pageId: rev.pageId });
		return {
			id: rev.id,
			pageId: rev.pageId,
			version: rev.version,
			actor: rev.actor,
			at: rev.createdAt.toISOString(),
			text: rev.text,
			chars: rev.text.length
		};
	});
}

// -- WRITES -- //

/** A new page in an extra notebook, at the top level or under a top-level page. */
export async function createPage(ctx: Ctx, raw: unknown): Promise<PageView> {
	const input = parse(pageCreateInput, raw);
	return runWrite(ctx, 'page.create', input, async (tx, userId) => {
		const book = await bookOf(tx, userId, input);
		const title = cleanTitle(ctx, input.title);
		const text = cleanText(ctx, input.text ?? '');
		if (text.length > NOTEBOOK_PAGE_MAX_CHARS)
			throw new OpsError(
				'INVALID',
				`The text would be longer than ${NOTEBOOK_PAGE_MAX_CHARS} characters. Make it shorter, or split it over two pages.`
			);
		const parent = await resolveParent(tx, userId, book, input);
		if ((await livePageCount(tx, userId)) >= NOTEBOOK_MAX_PAGES)
			throw new OpsError('INVALID', pageLimit());
		if (parent && (await liveSubpageCount(tx, userId, parent.id)) >= NOTEBOOK_MAX_SUBPAGES)
			throw new OpsError('INVALID', subpageLimit(parent.title));
		if (await titleTaken(tx, userId, book.id, parent?.id ?? null, title))
			throw new OpsError('CONFLICT', clashMessage(title, book.title, parent));
		const actor = actorOf(ctx);
		const [made] = await tx
			.insert(notebookPage)
			.values({
				userId,
				notebookId: book.id,
				parentPageId: parent?.id ?? null,
				title,
				text,
				position: 0,
				updatedBy: actor,
				// The person's own page is seen; a page the assistant wrote waits to be looked at
				seenVersion: actor === 'user' ? 1 : 0
			})
			.returning();
		if (!made) throw new OpsError('CONFLICT', 'The page could not be made. Try again.');
		await placeAt(tx, userId, book.id, parent?.id ?? null, made.id, input.position);
		return loadPageView(tx, userId, made.id);
	});
}

/** One edit to a page by exact text, for the assistant (and for the person's approval of a card made from it). */
export async function editPage(ctx: Ctx, raw: unknown) {
	const input = parse(pageEditInput, raw);
	return runWrite(ctx, 'page.edit', input, async (tx, userId) => {
		const { page, book } = await resolvePage(tx, userId, input);
		let result: { text: string; section: string; changed?: boolean };
		try {
			if (input.op === 'add') {
				if (!input.heading || !input.line)
					throw new OpsError('INVALID', 'To add a line give the heading and the line.');
				const line = cleanText(ctx, input.line);
				if (!line.trim()) throw new OpsError('INVALID', 'The line is empty.');
				const heading = isAgent(ctx)
					? redactSecrets(input.heading.replace(/\s+/g, ' '))
					: input.heading.replace(/\s+/g, ' ');
				if (!heading) throw new OpsError('INVALID', 'The heading is empty.');
				result = addLine(page.text, heading, line, NOTEBOOK_PAGE_MAX_CHARS);
			} else if (input.op === 'replace') {
				if (!input.find || input.replacement === undefined)
					throw new OpsError('INVALID', 'To replace text give the exact text and its replacement.');
				const replacement = input.replacement ? cleanText(ctx, input.replacement) : '';
				result = replaceOnce(page.text, input.find, replacement, NOTEBOOK_PAGE_MAX_CHARS);
			} else {
				if (!input.find) throw new OpsError('INVALID', 'To remove text give the exact text.');
				result = removeOnce(page.text, input.find);
			}
		} catch (e) {
			// A refused edit reads as a plain message the assistant can act on
			if (e instanceof EditError) throw new OpsError('INVALID', e.message);
			throw e;
		}
		if (result.changed === false || result.text === page.text)
			return {
				notebook: book.title,
				page: page.title,
				version: page.version,
				section: result.section,
				changed: false,
				note: 'It was already there.'
			};
		const next = await applyPageChange(tx, userId, page, result.text, actorOf(ctx), refOf(ctx));
		return {
			notebook: book.title,
			page: page.title,
			version: next.version,
			section: result.section,
			changed: true,
			note: 'The change is saved.'
		};
	});
}

/** The person saves the whole text of a page, made from the version they opened. A stale version is refused and nothing is lost. */
export async function savePage(ctx: Ctx, raw: unknown): Promise<PageView & { changed: boolean }> {
	requirePerson(ctx.actor.kind, 'save a page');
	const input = parse(pageSaveInput, raw);
	return runWrite(ctx, 'page.save', input, async (tx, userId) => {
		const { page } = await resolvePage(tx, userId, { pageId: input.pageId });
		if (input.expectVersion !== page.version)
			throw new OpsError(
				'CONFLICT',
				'The page changed since you opened it. Open it again to see the new version.'
			);
		if (input.text === page.text)
			return { ...(await loadPageView(tx, userId, page.id)), changed: false };
		await applyPageChange(tx, userId, page, input.text, 'user', refOf(ctx));
		return { ...(await loadPageView(tx, userId, page.id)), changed: true };
	});
}

/** Gives a page another title. Two live pages that share a parent cannot share a title, ignoring case. */
export async function renamePage(ctx: Ctx, raw: unknown): Promise<PageView> {
	const input = parse(pageRenameInput, raw);
	return runWrite(ctx, 'page.rename', input, async (tx, userId) => {
		const { page, book } = await resolvePage(tx, userId, input);
		const title = cleanTitle(ctx, input.newTitle);
		if (title === page.title) return loadPageView(tx, userId, page.id);
		if (await titleTaken(tx, userId, book.id, page.parentPageId, title, page.id)) {
			const parent = page.parentPageId
				? ((
						await tx
							.select()
							.from(notebookPage)
							.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.parentPageId)))
					)[0] ?? null)
				: null;
			throw new OpsError('CONFLICT', clashMessage(title, book.title, parent));
		}
		await tx
			.update(notebookPage)
			.set({ title, updatedBy: actorOf(ctx), updatedAt: sql`now()` })
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.id)));
		return loadPageView(tx, userId, page.id);
	});
}

/** Moves a page to another place: another notebook, another parent or another position. A page with sub-pages cannot become a sub-page. */
export async function movePage(ctx: Ctx, raw: unknown): Promise<PageView> {
	const input = parse(pageMoveInput, raw);
	return runWrite(ctx, 'page.move', input, async (tx, userId) => {
		const { page, book } = await resolvePage(tx, userId, input);
		const toBook =
			input.toNotebookId || input.toNotebook
				? await bookOf(tx, userId, { notebookId: input.toNotebookId, notebook: input.toNotebook })
				: book;
		const parent = await resolveParent(tx, userId, toBook, {
			parentPageId: input.toParentPageId,
			parent: input.toParent
		});
		if (parent) {
			if (parent.id === page.id)
				throw new OpsError('INVALID', 'A page cannot be put under itself.');
			const kids = await tx
				.select({ id: notebookPage.id })
				.from(notebookPage)
				.where(
					and(
						eq(notebookPage.userId, userId),
						eq(notebookPage.parentPageId, page.id),
						isNull(notebookPage.deletedAt)
					)
				);
			if (kids.length > 0)
				throw new OpsError(
					'INVALID',
					`"${page.title}" has sub-pages, so it cannot become a sub-page (pages go one level deep). Move or merge its sub-pages first.`
				);
			const siblings = await siblingIds(tx, userId, toBook.id, parent.id, page.id);
			if (siblings.length >= NOTEBOOK_MAX_SUBPAGES)
				throw new OpsError('INVALID', subpageLimit(parent.title));
		}
		if (await titleTaken(tx, userId, toBook.id, parent?.id ?? null, page.title, page.id))
			throw new OpsError('CONFLICT', clashMessage(page.title, toBook.title, parent));
		const actor = actorOf(ctx);
		if (toBook.id !== page.notebookId) {
			// The page and its sub-pages (hidden ones too) change notebook in one statement, so the key to the parent holds at its end
			await tx
				.update(notebookPage)
				.set({
					notebookId: toBook.id,
					parentPageId: sql`case when ${notebookPage.id} = ${page.id} then ${parent?.id ?? null}::uuid else ${notebookPage.parentPageId} end`
				})
				.where(
					and(
						eq(notebookPage.userId, userId),
						or(eq(notebookPage.id, page.id), eq(notebookPage.parentPageId, page.id))
					)
				);
		} else if ((parent?.id ?? null) !== page.parentPageId) {
			await tx
				.update(notebookPage)
				.set({ parentPageId: parent?.id ?? null })
				.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.id)));
		}
		await tx
			.update(notebookPage)
			.set({ updatedBy: actor, updatedAt: sql`now()` })
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.id)));
		await placeAt(tx, userId, toBook.id, parent?.id ?? null, page.id, input.position);
		return loadPageView(tx, userId, page.id);
	});
}

/**
 * Merges pages into one. The text of each source is added at the end of the target under a heading with the source's title, in one change that
 * keeps the old text of the target as a revision, and the sources are deleted (restorable). One merge counts as one delete.
 */
export async function mergePages(ctx: Ctx, raw: unknown) {
	const input = parse(pageMergeInput, raw);
	return runWrite(ctx, 'page.merge', input, async (tx, userId) => {
		const { page: target, book } = await resolvePage(tx, userId, input);
		if (!input.sources && !input.sourceIds)
			throw new OpsError('INVALID', 'Name the pages to merge into this one (sources).');
		if (input.sources && input.sourceIds)
			throw new OpsError(
				'INVALID',
				'Name the pages to merge by their titles or by their ids, not both.'
			);
		const sources: PageRow[] = [];
		// The notebooks are read once, not once per source
		const cache: TitleCache = new Map();
		for (const s of input.sourceIds ?? [])
			sources.push((await resolvePage(tx, userId, { pageId: s })).page);
		for (const s of input.sources ?? [])
			sources.push(
				(
					await resolvePage(
						tx,
						userId,
						{ notebook: s.notebook ?? book.title, page: s.page, parent: s.parent },
						{ cache }
					)
				).page
			);
		if (new Set(sources.map((s) => s.id)).size !== sources.length)
			throw new OpsError('INVALID', 'A page is named twice in the pages to merge.');
		for (const s of sources) {
			if (s.id === target.id) throw new OpsError('INVALID', 'A page cannot be merged into itself.');
			if (target.parentPageId === s.id)
				throw new OpsError(
					'INVALID',
					`"${target.title}" is a sub-page of "${s.title}", which would be deleted by the merge. Merge into "${s.title}" instead.`
				);
		}
		// One read for the sub-pages of all the sources
		const withKids = await tx
			.select({ parentPageId: notebookPage.parentPageId })
			.from(notebookPage)
			.where(
				and(
					eq(notebookPage.userId, userId),
					inArray(
						notebookPage.parentPageId,
						sources.map((s) => s.id)
					),
					isNull(notebookPage.deletedAt)
				)
			);
		const hasKids = new Set(withKids.map((k) => k.parentPageId));
		for (const s of sources)
			if (hasKids.has(s.id))
				throw new OpsError(
					'INVALID',
					`"${s.title}" has sub-pages. Move or merge its sub-pages first, so nothing is hidden by the merge.`
				);
		// The text of pages that already exist is added as it is; only the headings the merge writes are cleaned
		const added = sources
			.map((s) => `## ${cleanText(ctx, s.title)}\n${s.text.trim()}`)
			.join('\n\n');
		const base = target.text.trimEnd();
		const text = base ? `${base}\n\n${added}` : added;
		if (text.length > NOTEBOOK_PAGE_MAX_CHARS)
			throw new OpsError(
				'INVALID',
				`The merged page would be ${text.length} characters, over the ${NOTEBOOK_PAGE_MAX_CHARS} a page can hold. Merge fewer pages, or keep some apart.`
			);
		const next = await applyPageChange(tx, userId, target, text, actorOf(ctx), refOf(ctx));
		await tx
			.update(notebookPage)
			.set({ deletedAt: sql`now()`, updatedBy: actorOf(ctx), updatedAt: sql`now()` })
			.where(
				and(
					eq(notebookPage.userId, userId),
					inArray(
						notebookPage.id,
						sources.map((s) => s.id)
					)
				)
			);
		return {
			page: await loadPageView(tx, userId, next.id),
			merged: sources.map((s) => ({ title: s.title, chars: s.text.length })),
			note: `The pages are merged into "${target.title}" and the merged ones are deleted. They can be restored for ${NOTEBOOK_TRASH_DAYS} days.`
		};
	});
}

/**
 * Deletes a page with its sub-pages: they are hidden together, their text and changes are kept, and they can be restored for 30 days. The
 * answer holds the removed page.
 */
export async function deletePage(ctx: Ctx, raw: unknown) {
	const input = parse(pageTargetInput, raw);
	return runWrite(ctx, 'page.delete', input, async (tx, userId) => {
		const { page } = await resolvePage(tx, userId, input);
		const removed = await loadPageView(tx, userId, page.id);
		const kids = await tx
			.select({ title: notebookPage.title })
			.from(notebookPage)
			.where(
				and(
					eq(notebookPage.userId, userId),
					eq(notebookPage.parentPageId, page.id),
					isNull(notebookPage.deletedAt)
				)
			)
			.orderBy(asc(notebookPage.position));
		await tx
			.update(notebookPage)
			.set({ deletedAt: sql`now()`, updatedAt: sql`now()` })
			.where(
				and(
					eq(notebookPage.userId, userId),
					isNull(notebookPage.deletedAt),
					or(eq(notebookPage.id, page.id), eq(notebookPage.parentPageId, page.id))
				)
			);
		return {
			removed,
			alsoRemoved: kids.map((k) => k.title),
			note: `The page${kids.length ? ' and its sub-pages are' : ' is'} deleted. ${kids.length ? 'They' : 'It'} can be restored for ${NOTEBOOK_TRASH_DAYS} days.`
		};
	});
}

/** A title not used by a live sibling: the title itself, else "title (restored)", "title (restored 2)" and so on. */
async function freeTitle(
	tx: Tx,
	userId: string,
	notebookId: string,
	parentId: string | null,
	title: string,
	except: string
): Promise<string> {
	let out = title;
	for (let n = 1; await titleTaken(tx, userId, notebookId, parentId, out, except); n++) {
		const tag = n === 1 ? ' (restored)' : ` (restored ${n})`;
		out = `${title.slice(0, NOTEBOOK_PAGE_TITLE_MAX - tag.length)}${tag}`;
	}
	return out;
}

/**
 * Puts a deleted page back, with the sub-pages that were deleted together with it. It returns under its old parent when that is still a live
 * top-level page, else at the top level. A title that is taken meanwhile gets a number: "title (restored)".
 */
export async function undeletePage(ctx: Ctx, raw: unknown): Promise<PageView> {
	const input = parse(pageUndeleteInput, raw);
	if (!input.pageId && !input.page)
		throw new OpsError('INVALID', 'Name the deleted page to restore.');
	return runWrite(ctx, 'page.undelete', input, async (tx, userId) => {
		const { page, book } = await resolvePage(tx, userId, input, { deleted: true });
		const together =
			page.parentPageId === null && page.deletedAt
				? await tx
						.select()
						.from(notebookPage)
						.where(
							and(
								eq(notebookPage.userId, userId),
								eq(notebookPage.parentPageId, page.id),
								// Compared in the database, which keeps microseconds that a JavaScript date drops
								sql`${notebookPage.deletedAt} = (select p.deleted_at from notebook_page p where p.user_id = ${userId} and p.id = ${page.id})`
							)
						)
						.orderBy(asc(notebookPage.position))
				: [];
		if ((await livePageCount(tx, userId)) + 1 + together.length > NOTEBOOK_MAX_PAGES)
			throw new OpsError('INVALID', pageLimit());
		// The old parent, when it is a live top-level page of the notebook with room for one more
		let parent: PageRow | null = null;
		if (page.parentPageId) {
			const [p] = await tx
				.select()
				.from(notebookPage)
				.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.parentPageId)));
			if (
				p &&
				p.deletedAt === null &&
				p.parentPageId === null &&
				p.notebookId === page.notebookId &&
				(await liveSubpageCount(tx, userId, p.id)) < NOTEBOOK_MAX_SUBPAGES
			)
				parent = p;
		}
		const title = await freeTitle(tx, userId, book.id, parent?.id ?? null, page.title, page.id);
		await tx
			.update(notebookPage)
			.set({
				deletedAt: null,
				parentPageId: parent?.id ?? null,
				title,
				updatedAt: sql`now()`
			})
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.id)));
		for (const kid of together) {
			const kidTitle = await freeTitle(tx, userId, book.id, page.id, kid.title, kid.id);
			await tx
				.update(notebookPage)
				.set({ deletedAt: null, title: kidTitle, updatedAt: sql`now()` })
				.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, kid.id)));
		}
		await placeAt(tx, userId, book.id, parent?.id ?? null, page.id);
		return loadPageView(tx, userId, page.id);
	});
}

/** The person pins a page to the top of its notebook, or unpins it. */
export async function pinPage(ctx: Ctx, raw: unknown): Promise<PageView> {
	requirePerson(ctx.actor.kind, 'pin a page');
	const input = parse(pagePinInput, raw);
	return runWrite(ctx, 'page.pin', input, async (tx, userId) => {
		const { page } = await resolvePage(tx, userId, { pageId: input.pageId });
		await tx
			.update(notebookPage)
			.set({ pinnedAt: input.pinned ? sql`now()` : null })
			.where(and(eq(notebookPage.userId, userId), eq(notebookPage.id, page.id)));
		return loadPageView(tx, userId, page.id);
	});
}

/** The person pins a notebook to the top of the library, or unpins it. */
export async function pinNotebook(ctx: Ctx, raw: unknown) {
	requirePerson(ctx.actor.kind, 'pin a notebook');
	const input = parse(notebookPinInput, raw);
	return runWrite(ctx, 'notebook.pin', input, async (tx, userId) => {
		const book = await bookOf(tx, userId, { notebookId: input.notebookId });
		const [next] = await tx
			.update(notebook)
			.set({ pinnedAt: input.pinned ? sql`now()` : null })
			.where(and(eq(notebook.userId, userId), eq(notebook.id, book.id)))
			.returning({ id: notebook.id, pinnedAt: notebook.pinnedAt });
		return { id: next?.id ?? book.id, pinnedAt: next?.pinnedAt?.toISOString() ?? null };
	});
}

/**
 * The person has looked at a page up to a version. Only the seen mark moves, and only up (never past the page's own version). It does not
 * touch the version or the time of the page, takes no person lock and is not kept in the request log, so it can never make a save stale. It is
 * deliberately exempt from the request log (a verb without a requestId): the mark only goes up, so a replay is harmless.
 */
export async function pageSeen(ctx: Ctx, raw: unknown) {
	requirePerson(ctx.actor.kind, 'mark a page as seen');
	const input = parse(pageSeenInput, raw);
	return run(ctx, async (tx, userId) => {
		const rows = await tx.execute(sql`
			update notebook_page p
			set seen_version = greatest(p.seen_version, least(${input.version}::int, p.version))
			from notebook n
			where p.user_id = ${userId} and p.id = ${input.pageId}
			  and p.deleted_at is null
			  and n.user_id = p.user_id and n.id = p.notebook_id and n.deleted_at is null
			returning p.id as id, p.seen_version as seen_version, p.version as version`);
		const row = (
			rows as unknown as { rows: { id: string; seen_version: number; version: number }[] }
		).rows[0];
		if (!row) throw new OpsError('NOT_FOUND', 'That page is gone or was deleted.');
		return { pageId: row.id, seenVersion: Number(row.seen_version), version: Number(row.version) };
	});
}

/** The person puts an earlier text of a page back. The text it replaces is kept as a revision of its own, so a restore can be undone the same way. */
export async function restorePage(ctx: Ctx, raw: unknown): Promise<PageView> {
	requirePerson(ctx.actor.kind, 'restore a page');
	const input = parse(pageRevisionInput, raw);
	return runWrite(ctx, 'page.restore', input, async (tx, userId) => {
		const [rev] = await tx
			.select()
			.from(notebookPageRevision)
			.where(
				and(eq(notebookPageRevision.userId, userId), eq(notebookPageRevision.id, input.revisionId))
			);
		if (!rev) throw new OpsError('NOT_FOUND', 'That change is not there any more.');
		const { page } = await resolvePage(tx, userId, { pageId: rev.pageId });
		if (rev.text !== page.text)
			await applyPageChange(tx, userId, page, rev.text, 'user', `restore:${rev.version}`);
		return loadPageView(tx, userId, page.id);
	});
}
