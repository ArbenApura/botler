// EXCHANGE RATES (BTL-20261023-1407, M3): ONE ROW PER CURRENCY, THE SAME FOR EVERYONE, AND ONE ROW THAT SAYS HOW THE LAST REFRESH WENT
// Rates are not a person's data, so these tables have no user column and no row level security. The runtime role can read, add and update
// them but never delete from them, so a bad refresh can only be overwritten by a good one, never leave the app without rates.

// -- DEP-MODULES -- //
import { check, text, timestamp } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
// -- MODULES -- //
import { plainTable } from './helpers';

// -- CONSTANTS -- //

/** A plain positive decimal with up to 18 decimals, never zero and never written with an exponent. */
const POSITIVE_DECIMAL = '^[0-9]+([.][0-9]{1,18})?$';

// -- RATES -- //

/** Units of a currency that buy one US dollar. The dollar itself is not stored: it is always 1. */
export const fxRate = plainTable(
	'fx_rate',
	{
		code: text('code').primaryKey(),
		/** Decimal text, so the exact value is kept. */
		rate: text('rate').notNull(),
		/** When this rate was fetched from the source. */
		fetchedAt: timestamp('fetched_at', { withTimezone: true }).notNull(),
		source: text('source').notNull()
	},
	(t) => [
		check('fx_rate_code_chk', sql`${t.code} ~ '^[A-Z]{3}$'`),
		check(
			'fx_rate_rate_chk',
			sql`${t.rate} ~ ${sql.raw(`'${POSITIVE_DECIMAL}'`)} and ${t.rate} !~ '^0+([.]0+)?$'`
		)
	],
	{ noDelete: true }
);

/**
 * The refresh bookkeeping, one row: when a refresh was last tried, when one last worked, and how the last try ended. The row is also what
 * a refresh locks, so only one runs at a time and a failing source is not tried on every read.
 */
export const fxRefresh = plainTable(
	'fx_refresh',
	{
		id: text('id').primaryKey().default('main'),
		attemptedAt: timestamp('attempted_at', { withTimezone: true }),
		succeededAt: timestamp('succeeded_at', { withTimezone: true }),
		/** A short reason code of the last failure (never text from the source), or null when the last try worked. */
		lastError: text('last_error')
	},
	(t) => [check('fx_refresh_id_chk', sql`${t.id} = 'main'`)],
	{ noDelete: true }
);
