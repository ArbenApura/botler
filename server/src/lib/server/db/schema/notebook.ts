// BOTLER'S NOTEBOOK: ONE MARKDOWN DOCUMENT PER PERSON, ALWAYS IN THE PROMPT, AND THE REVISIONS OF IT
// The person edits it in the app (the whole text, version checked) and the assistant edits it with notebook_edit (add a line under a heading,
// replace or remove exact text). Every change keeps the replaced text as a revision, so nothing the person wrote is lost to an edit; the
// newest 50 revisions are kept. Both tables hold personal text with their own history and are erased by a memory wipe and a data reset,
// so they are kept out of the audit trail like the chat transcript.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { check, foreignKey, index, integer, text, unique, uuid } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, stamps, userTable } from './helpers';

// -- CONSTANTS -- //

/** Who wrote a version: the person, the assistant, or the seed that built the first draft from the old memory. */
export const NOTEBOOK_ACTORS = ['user', 'agent', 'seed'] as const;

/** The longest notebook text, in characters. It is always sent to the model, so it stays short. */
export const NOTEBOOK_MAX_CHARS = 16_000;

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
		...stamps()
	},
	(t) => [
		unique('notebook_user_uq').on(t.userId),
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
