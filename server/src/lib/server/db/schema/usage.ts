// MODEL USAGE: HOW MANY TOKENS EACH PERSON USED THIS MONTH PER BUCKET, AND THE TOTAL ACROSS EVERYONE FOR THE GLOBAL SPEND CAP

// -- DEP-MODULES -- //
import { bigint, integer, primaryKey, text, unique } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, plainTable, stamps, userTable } from './helpers';

// -- CONSTANTS -- //

/** Chat is what the person asks for. Memory is the background work (extraction, summaries, the night job). They have separate caps. */
export const BUCKETS = ['chat', 'memory'] as const;

// -- PER PERSON (user scoped) -- //

export const modelUsage = userTable(
	'model_usage',
	() => user.id,
	{
		id: id(),
		bucket: text('bucket', { enum: BUCKETS }).notNull(),
		/** The Asia/Manila month, YYYY-MM. */
		month: text('month').notNull(),
		calls: integer('calls').notNull().default(0),
		promptTokens: bigint('prompt_tokens', { mode: 'number' }).notNull().default(0),
		completionTokens: bigint('completion_tokens', { mode: 'number' }).notNull().default(0),
		...stamps()
	},
	(t) => [
		unique('model_usage_user_bucket_month_uq').on(t.userId, t.bucket, t.month),
		oneOf('model_usage_bucket_chk', t.bucket, BUCKETS)
	]
);

// -- ACROSS EVERYONE (not user scoped: it holds only totals, never a person's data) -- //

export const modelSpend = plainTable(
	'model_spend',
	{
		month: text('month').notNull(),
		bucket: text('bucket', { enum: BUCKETS }).notNull(),
		calls: integer('calls').notNull().default(0),
		tokens: bigint('tokens', { mode: 'number' }).notNull().default(0)
	},
	(t) => [primaryKey({ columns: [t.month, t.bucket] })]
);
