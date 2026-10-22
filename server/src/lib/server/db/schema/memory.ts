// THE MEMORY TABLES: WHO THE PERSON IS (PERSONA AND PROFILE, ALWAYS IN THE PROMPT), WHAT IS KNOWN (FACTS WITH A TIME RANGE), AND DIGESTS (DAY, WEEK, MONTH)
// The transcript archive is chat_turn (agent.ts). A fact is never overwritten: a changed fact ends the old row (valid_to) and adds a new one.
// A fact the person deleted stays as a tombstone (suppressed) so the extractor cannot bring it back; a wipe removes everything.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import {
	boolean,
	check,
	date,
	index,
	integer,
	jsonb,
	real,
	smallint,
	text,
	timestamp,
	unique,
	uuid,
	vector
} from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, stamps, tsvector, userTable } from './helpers';

// -- CONSTANTS -- //

export const FACT_KINDS = ['fact', 'preference', 'event', 'person', 'money'] as const;
export const FACT_SOURCES = ['user', 'extracted', 'web'] as const;
export const SUMMARY_PERIODS = ['day', 'week', 'month'] as const;
/** The size of the vectors of the chosen embedding model (multilingual-e5-small). */
export const EMBEDDING_DIMENSIONS = 384;

// -- PROFILE -- //

/** One row per person: the words they gave the assistant, who to keep private, and the mood and shared-history state. */
export const memoryProfile = userTable(
	'memory_profile',
	() => user.id,
	{
		id: id(),
		/** How the person wants the assistant to talk. Written and edited by them. */
		persona: text('persona').notNull().default(''),
		/** A few lines about the person, always in the prompt. */
		about: text('about').notNull().default(''),
		/** Names of family and contacts, hidden from the model as placeholders. */
		people: jsonb('people').notNull().default([]),
		/** Tone only, from -100 (low) to 100 (bright). It never changes a finance rule. */
		mood: integer('mood').notNull().default(0),
		/** How much history the two share, a count of days with a chat. Tone only. */
		familiarity: integer('familiarity').notNull().default(0),
		moodUpdatedAt: timestamp('mood_updated_at', { withTimezone: true }).notNull().defaultNow(),
		...stamps()
	},
	(t) => [
		unique('memory_profile_user_uq').on(t.userId),
		check('memory_profile_mood_chk', sql`${t.mood} between -100 and 100`),
		check('memory_profile_familiarity_chk', sql`${t.familiarity} >= 0`),
		check(
			'memory_profile_persona_chk',
			sql`length(${t.persona}) <= 2000 and length(${t.about}) <= 2000`
		)
	]
);

// -- FACTS -- //

export const memoryFact = userTable(
	'memory_fact',
	() => user.id,
	{
		id: id(),
		text: text('text').notNull(),
		/** A hash of the normalised text, so a deleted fact can be recognised when it is offered again. */
		textHash: text('text_hash').notNull(),
		/** What the fact is about, in a few lowercase words ("sister home city"). A new fact on the same subject ends the old one. */
		subject: text('subject'),
		kind: text('kind', { enum: FACT_KINDS }).notNull().default('fact'),
		/** 1 (trivia) to 5 (never forget). */
		importance: smallint('importance').notNull().default(3),
		/** Who said so. A fact the person wrote or edited ("user") is never ended by the extractor. */
		source: text('source', { enum: FACT_SOURCES }).notNull().default('extracted'),
		/** 0 to 100: how sure the extractor was. */
		confidence: smallint('confidence').notNull().default(80),
		validFrom: timestamp('valid_from', { withTimezone: true }).notNull().defaultNow(),
		/** Null while the fact still holds. Set when a newer fact replaced it: the old one is kept, it is history. */
		validTo: timestamp('valid_to', { withTimezone: true }),
		supersededBy: uuid('superseded_by'),
		/** The person deleted it. Kept as a tombstone with its hash, shown nowhere. */
		suppressed: boolean('suppressed').notNull().default(false),
		/** Two facts disagree at similar confidence: waiting for the person to choose. Not used in answers. */
		pending: boolean('pending').notNull().default(false),
		/** Fading lowers how often a stale fact is retrieved. It never deletes, and using the fact restores it. */
		fadeWeight: real('fade_weight').notNull().default(1),
		lastUsedAt: timestamp('last_used_at', { withTimezone: true }),
		/** The chat message it was learned from. */
		turnId: text('turn_id'),
		searchText: tsvector('search_text').generatedAlwaysAs(sql`to_tsvector('simple', text)`),
		embedding: vector('embedding', { dimensions: EMBEDDING_DIMENSIONS }),
		/** Which model made the vector, so a model change can re-embed the rows made by the old one. */
		embeddingModel: text('embedding_model'),
		...stamps()
	},
	(t) => [
		unique('memory_fact_user_id_uq').on(t.userId, t.id),
		index('memory_fact_user_state_idx').on(t.userId, t.suppressed, t.validTo),
		index('memory_fact_user_hash_idx').on(t.userId, t.textHash),
		index('memory_fact_user_subject_idx').on(t.userId, t.subject),
		index('memory_fact_search_idx').using('gin', t.searchText),
		index('memory_fact_embedding_idx').using('hnsw', t.embedding.op('vector_cosine_ops')),
		oneOf('memory_fact_kind_chk', t.kind, FACT_KINDS),
		oneOf('memory_fact_source_chk', t.source, FACT_SOURCES),
		check('memory_fact_text_chk', sql`length(${t.text}) between 1 and 400`),
		check(
			'memory_fact_scores_chk',
			sql`${t.importance} between 1 and 5 and ${t.confidence} between 0 and 100 and ${t.fadeWeight} between 0.1 and 1`
		)
	]
);

// -- SUMMARIES -- //

export const memorySummary = userTable(
	'memory_summary',
	() => user.id,
	{
		id: id(),
		period: text('period', { enum: SUMMARY_PERIODS }).notNull(),
		/** The first day of the period, a Manila calendar date. */
		periodStart: date('period_start', { mode: 'string' }).notNull(),
		text: text('text').notNull(),
		/** The facts the digest was built from, so deleting one can scrub the digest that cites it. */
		factIds: jsonb('fact_ids').notNull().default([]),
		...stamps()
	},
	(t) => [
		unique('memory_summary_period_uq').on(t.userId, t.period, t.periodStart),
		oneOf('memory_summary_period_chk', t.period, SUMMARY_PERIODS),
		check('memory_summary_text_chk', sql`length(${t.text}) <= 4000`)
	]
);
