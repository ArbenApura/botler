// BOTLER'S NOTEBOOK: ONE MARKDOWN DOCUMENT PER PERSON, ALWAYS IN THE PROMPT, AND THE REVISIONS OF IT
// The person edits it in the app (the whole text, version checked) and the assistant edits it with notebook_edit (add a line under a heading,
// replace or remove exact text). Every change keeps the replaced text as a revision, so nothing the person wrote is lost to an edit; the
// newest 50 revisions are kept. Both tables hold personal text with their own history and are erased by a memory wipe and a data reset,
// so they are kept out of the audit trail like the chat transcript.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import {
	check,
	foreignKey,
	index,
	integer,
	text,
	timestamp,
	unique,
	uniqueIndex,
	uuid
} from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, stamps, userTable } from './helpers';

// -- CONSTANTS -- //

/** Who wrote a version: the person, the assistant, or the seed that built the first draft from the old memory. */
export const NOTEBOOK_ACTORS = ['user', 'agent', 'seed'] as const;

/** The longest notebook text, in characters. The main notebook is always sent to the model, so it stays short. */
export const NOTEBOOK_MAX_CHARS = 16_000;

/** The main notebook is the original one, always in the prompt; an extra one holds other information and is read on demand. */
export const NOTEBOOK_KINDS = ['main', 'extra'] as const;

/** The longest title and one-line summary of an extra notebook. */
export const NOTEBOOK_TITLE_MAX = 80;
export const NOTEBOOK_SUMMARY_MAX = 200;

/** The most live extra notebooks one person has, so the index in the prompt stays short. */
export const NOTEBOOK_MAX_EXTRA = 40;

/** The longest text of one page, in characters. A page is read on demand, so it can be long. */
export const NOTEBOOK_PAGE_MAX_CHARS = 30_000;

/** The most live pages one person has over all notebooks. Deleted pages do not count. */
export const NOTEBOOK_MAX_PAGES = 500;

/** The most live sub-pages under one top-level page. A sub-page cannot have sub-pages of its own. */
export const NOTEBOOK_MAX_SUBPAGES = 20;

/** The longest page title. */
export const NOTEBOOK_PAGE_TITLE_MAX = 80;

/** Days a deleted notebook can still be restored before the daily job erases it. */
export const NOTEBOOK_TRASH_DAYS = 30;

// -- NOTEBOOK -- //

export const notebook = userTable(
	'notebook',
	() => user.id,
	{
		id: id(),
		text: text('text').notNull().default(''),
		/** Starts at 1 and goes up with every change. A save names the version it was made from, and a stale one is refused. */
		version: integer('version').notNull().default(1),
		updatedBy: text('updated_by', { enum: NOTEBOOK_ACTORS }).notNull().default('seed'),
		/** The original notebook is the main one; the others are extra. */
		kind: text('kind', { enum: NOTEBOOK_KINDS }).notNull().default('main'),
		/** The name of an extra notebook (empty for the main one). Unique among a person's live extras, ignoring case. */
		title: text('title').notNull().default(''),
		/** One line saying what an extra notebook holds, shown in the index under the main notebook. */
		summary: text('summary').notNull().default(''),
		/** Set when the notebook was deleted: it is hidden, can be restored for a while, and is erased later. */
		deletedAt: timestamp('deleted_at', { withTimezone: true }),
		/** Set when the person pins the notebook to the top of the library. */
		pinnedAt: timestamp('pinned_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [
		uniqueIndex('notebook_main_uq')
			.on(t.userId)
			.where(sql`${t.kind} = 'main'`),
		uniqueIndex('notebook_title_uq')
			.on(t.userId, sql`lower(${t.title})`)
			.where(sql`${t.kind} = 'extra' and ${t.deletedAt} is null`),
		oneOf('notebook_kind_chk', t.kind, NOTEBOOK_KINDS),
		check(
			'notebook_shape_chk',
			sql`length(${t.title}) <= ${sql.raw(String(NOTEBOOK_TITLE_MAX))} and length(${t.summary}) <= ${sql.raw(String(NOTEBOOK_SUMMARY_MAX))} and (${t.kind} = 'extra' or (${t.title} = '' and ${t.deletedAt} is null))`
		),
		unique('notebook_user_id_uq').on(t.userId, t.id),
		oneOf('notebook_updated_by_chk', t.updatedBy, NOTEBOOK_ACTORS),
		check('notebook_text_chk', sql`length(${t.text}) <= ${sql.raw(String(NOTEBOOK_MAX_CHARS))}`),
		check('notebook_version_chk', sql`${t.version} >= 1`)
	]
);

// -- REVISIONS -- //

/** The text a change replaced. `version` is the version that was replaced, `actor` who made the change, `ref` the chat message or request. */
export const notebookRevision = userTable(
	'notebook_revision',
	() => user.id,
	{
		id: id(),
		notebookId: uuid('notebook_id').notNull(),
		version: integer('version').notNull(),
		text: text('text').notNull(),
		actor: text('actor', { enum: NOTEBOOK_ACTORS }).notNull(),
		ref: text('ref'),
		...stamps()
	},
	(t) => [
		foreignKey({
			name: 'notebook_revision_notebook_fk',
			columns: [t.userId, t.notebookId],
			foreignColumns: [notebook.userId, notebook.id]
		}).onDelete('cascade'),
		unique('notebook_revision_user_id_uq').on(t.userId, t.id),
		unique('notebook_revision_version_uq').on(t.userId, t.notebookId, t.version),
		index('notebook_revision_recent_idx').on(t.userId, t.notebookId, t.createdAt),
		oneOf('notebook_revision_actor_chk', t.actor, NOTEBOOK_ACTORS),
		check(
			'notebook_revision_text_chk',
			sql`length(${t.text}) <= ${sql.raw(String(NOTEBOOK_MAX_CHARS))}`
		)
	]
);

// -- PAGES -- //

/**
 * A page of an extra notebook. The text of an extra notebook lives in its pages (migration 0037 turned each old extra text into a page
 * titled "Overview"); the main notebook has none. A page may sit under one top-level page of the same notebook, never deeper. A
 * deleted page is hidden and can be restored for 30 days. `seenVersion` is the last version the person looked at, so the app can show
 * what the assistant changed since; it never changes `version` or `updatedAt`.
 */
export const notebookPage = userTable(
	'notebook_page',
	() => user.id,
	{
		id: id(),
		notebookId: uuid('notebook_id').notNull(),
		/** The top-level page this one sits under; null for a top-level page. */
		parentPageId: uuid('parent_page_id'),
		title: text('title').notNull(),
		text: text('text').notNull().default(''),
		/** Starts at 1 and goes up with every change of the text. A save names the version it was made from, and a stale one is refused. */
		version: integer('version').notNull().default(1),
		/** The order among the pages that share a parent (or among the top-level pages of a notebook). */
		position: integer('position').notNull().default(0),
		pinnedAt: timestamp('pinned_at', { withTimezone: true }),
		/** The newest version the person has looked at. Only goes up. */
		seenVersion: integer('seen_version').notNull().default(0),
		updatedBy: text('updated_by', { enum: NOTEBOOK_ACTORS }).notNull().default('user'),
		deletedAt: timestamp('deleted_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [
		foreignKey({
			name: 'notebook_page_notebook_fk',
			columns: [t.userId, t.notebookId],
			foreignColumns: [notebook.userId, notebook.id]
		}).onDelete('cascade'),
		// The parent is in the same notebook (the notebook id is part of the key). Restrict: a parent is soft-deleted, never removed under its children.
		foreignKey({
			name: 'notebook_page_parent_fk',
			columns: [t.userId, t.notebookId, t.parentPageId],
			foreignColumns: [t.userId, t.notebookId, t.id]
		}).onDelete('restrict'),
		unique('notebook_page_user_id_uq').on(t.userId, t.id),
		unique('notebook_page_notebook_id_uq').on(t.userId, t.notebookId, t.id),
		// Live siblings never share a title, ignoring case; no parent counts as one shared parent
		uniqueIndex('notebook_page_title_uq')
			.on(
				t.userId,
				t.notebookId,
				sql`coalesce(${t.parentPageId}, '00000000-0000-0000-0000-000000000000'::uuid)`,
				sql`lower(${t.title})`
			)
			.where(sql`${t.deletedAt} is null`),
		index('notebook_page_tree_idx').on(t.userId, t.notebookId, t.parentPageId, t.position),
		index('notebook_page_updated_idx').on(t.userId, t.updatedAt),
		oneOf('notebook_page_updated_by_chk', t.updatedBy, NOTEBOOK_ACTORS),
		check(
			'notebook_page_shape_chk',
			sql`length(${t.title}) between 1 and ${sql.raw(String(NOTEBOOK_PAGE_TITLE_MAX))} and length(${t.text}) <= ${sql.raw(String(NOTEBOOK_PAGE_MAX_CHARS))} and ${t.version} >= 1 and ${t.seenVersion} >= 0 and ${t.position} >= 0`
		)
	]
);

/** The text a change to a page replaced. `version` is the version that was replaced. The newest 50 are kept for each page. */
export const notebookPageRevision = userTable(
	'notebook_page_revision',
	() => user.id,
	{
		id: id(),
		pageId: uuid('page_id').notNull(),
		version: integer('version').notNull(),
		text: text('text').notNull(),
		actor: text('actor', { enum: NOTEBOOK_ACTORS }).notNull(),
		ref: text('ref'),
		...stamps()
	},
	(t) => [
		foreignKey({
			name: 'notebook_page_revision_page_fk',
			columns: [t.userId, t.pageId],
			foreignColumns: [notebookPage.userId, notebookPage.id]
		}).onDelete('cascade'),
		unique('notebook_page_revision_user_id_uq').on(t.userId, t.id),
		unique('notebook_page_revision_version_uq').on(t.userId, t.pageId, t.version),
		index('notebook_page_revision_recent_idx').on(t.userId, t.pageId, t.createdAt),
		oneOf('notebook_page_revision_actor_chk', t.actor, NOTEBOOK_ACTORS),
		check(
			'notebook_page_revision_text_chk',
			sql`length(${t.text}) <= ${sql.raw(String(NOTEBOOK_PAGE_MAX_CHARS))}`
		)
	]
);
