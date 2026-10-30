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
