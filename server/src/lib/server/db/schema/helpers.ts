// SCHEMA HELPERS: EVERY TABLE IS REGISTERED AS PLAIN OR USER OWNED, SO ROW LEVEL SECURITY IS GENERATED FOR ALL OF THEM AND A TEST FAILS ON A TABLE NOBODY REGISTERED

// -- DEP-TYPES -- //
import type {
	AnyPgColumn,
	ExtraConfigColumn,
	PgColumnBuilderBase,
	PgTableExtraConfigValue
} from 'drizzle-orm/pg-core';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import {
	bigint,
	check,
	customType,
	integer,
	pgTable,
	text,
	timestamp,
	uuid
} from 'drizzle-orm/pg-core';

// -- TYPES -- //

export type UserTableEntry = {
	name: string;
	/** The column that holds the owner. It is always user_id. */
	userColumn: string;
	/** Tables whose rows only ever grow. No UPDATE or DELETE is granted to the runtime role. */
	appendOnly?: boolean;
};

// -- CONSTANTS -- //

/** Every table that holds one person's data. Row level security policies are generated from this list. */
export const USER_TABLES: UserTableEntry[] = [];

/**
 * Tables outside any person's data: the people themselves and the authentication machinery. A sign in happens before any
 * user is known, so these have no row level security. Request code never reads them except through the auth verbs.
 */
export const PLAIN_TABLES: string[] = [];

/** Plain tables the runtime role may read, insert into and update but never delete from (the exchange rates must survive a bad refresh). */
export const PLAIN_NO_DELETE: Set<string> = new Set();

/** Plain tables the runtime role may only read: shared reference data that holds nothing of anyone. The loader writes them as the owner. */
export const PLAIN_READ_ONLY: Set<string> = new Set();

// -- FUNCTIONS -- //

/** A PostgreSQL full text search column, always generated from the row's own text columns. */
export const tsvector = customType<{ data: string }>({ dataType: () => 'tsvector' });

export const id = () => uuid('id').primaryKey().defaultRandom();

export const stamps = () => ({
	createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
	updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
});

/** The optimistic concurrency column. Every write that changes the row bumps it. */
export const version = () => integer('version').notNull().default(1);

/** Money is always an integer in the minor unit of its currency, in a 64 bit column read back as a safe integer. A column of this kind never holds a float. */
export const centavos = (name: string) => bigint(name, { mode: 'number' });

/** An ISO 4217 code. The catalogue is checked at the edge (Zod) and in user_setting, so a new currency needs no migration here. */
export const currencyCode = (name: string) => text(name);

/** A CHECK constraint that a currency column holds three capital letters. */
export const currencyShape = (name: string, column: AnyPgColumn) =>
	check(name, sql`${column} ~ '^[A-Z]{3}$'`);

/** A CHECK constraint limiting a text column to a fixed set of values. */
export const oneOf = (name: string, column: AnyPgColumn, values: readonly string[]) =>
	// The values are constants from this codebase, written as literals because DDL cannot take parameters
	check(
		name,
		sql`${column} in (${sql.raw(values.map((v) => `'${v.replaceAll("'", "''")}'`).join(', '))})`
	);

/** Defines a table outside any person's data and registers it. */
export function plainTable<T extends Record<string, PgColumnBuilderBase>>(
	name: string,
	columns: T,
	extra?: (self: { [K in keyof T]: ExtraConfigColumn }) => PgTableExtraConfigValue[],
	options: { noDelete?: boolean; readOnly?: boolean } = {}
) {
	PLAIN_TABLES.push(name);
	if (options.noDelete) PLAIN_NO_DELETE.add(name);
	if (options.readOnly) PLAIN_READ_ONLY.add(name);
	// The array form of the extra config is supported at runtime, its type is wider than the overloads accept
	return pgTable(name, columns, extra as never);
}

/**
 * Defines a table of one person's data and registers it. The user_id column is added here, so no table can forget it,
 * and its policy is generated from the registry. `userRef` is the user table's id column.
 */
export function userTable<T extends Record<string, PgColumnBuilderBase>>(
	name: string,
	userRef: () => AnyPgColumn,
	columns: T,
	extra?: (self: { [K in keyof T | 'userId']: ExtraConfigColumn }) => PgTableExtraConfigValue[],
	options: Partial<Pick<UserTableEntry, 'appendOnly'>> = {}
) {
	USER_TABLES.push({ name, userColumn: 'user_id', ...options });
	const withOwner = {
		...columns,
		userId: text('user_id').notNull().references(userRef, { onDelete: 'cascade' })
	};
	return pgTable(name, withOwner, extra as never);
}
