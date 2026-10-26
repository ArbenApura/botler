// MODEL USAGE: HOW MANY TOKENS EACH PERSON USED THIS MONTH PER BUCKET, AND THE TOTAL ACROSS EVERYONE FOR THE GLOBAL SPEND CAP

// -- DEP-MODULES -- //
import { bigint, integer, primaryKey, text, unique } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { USAGE_PROVIDERS } from '../../../providers';
import { user } from './auth';
import { id, oneOf, plainTable, stamps, userTable } from './helpers';

// -- CONSTANTS -- //

/** Chat is what the person asks for. Memory is the background work (extraction, summaries, the night job). They have separate caps. */
export const BUCKETS = ['chat', 'memory'] as const;

/** Which model host the tokens were used on. Rows from before the provider was recorded are 'unknown' and still count in full. */
export const PROVIDERS = USAGE_PROVIDERS;

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
		provider: text('provider', { enum: PROVIDERS }).notNull().default('unknown'),
		/** Input tokens served from the host's cache, and written to it. Both are part of promptTokens. */
		cacheReadTokens: bigint('cache_read_tokens', { mode: 'number' }).notNull().default(0),
		cacheWriteTokens: bigint('cache_write_tokens', { mode: 'number' }).notNull().default(0),
		/** What the cap counts: uncached input + output + the weighted cache read and write (see limits.ts). */
		chargedTokens: bigint('charged_tokens', { mode: 'number' }).notNull().default(0),
		...stamps()
	},
	(t) => [
		unique('model_usage_user_bucket_month_provider_uq').on(t.userId, t.bucket, t.month, t.provider),
		oneOf('model_usage_bucket_chk', t.bucket, BUCKETS),
		oneOf('model_usage_provider_chk', t.provider, PROVIDERS)
	]
);

// -- ACROSS EVERYONE (not user scoped: it holds only totals, never a person's data) -- //

export const modelSpend = plainTable(
	'model_spend',
	{
		month: text('month').notNull(),
		bucket: text('bucket', { enum: BUCKETS }).notNull(),
		calls: integer('calls').notNull().default(0),
		/** The raw prompt + completion total. */
		tokens: bigint('tokens', { mode: 'number' }).notNull().default(0),
		provider: text('provider', { enum: PROVIDERS }).notNull().default('unknown'),
		/** What the global cap counts, weighted like model_usage.charged_tokens. */
		chargedTokens: bigint('charged_tokens', { mode: 'number' }).notNull().default(0)
	},
	(t) => [
		primaryKey({ columns: [t.month, t.bucket, t.provider] }),
		oneOf('model_spend_provider_chk', t.provider, PROVIDERS)
	]
);
