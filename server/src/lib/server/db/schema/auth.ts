// AUTH TABLES: THE PERSON, AND BETTER AUTH'S SESSION, ACCOUNT, VERIFICATION AND RATE LIMIT, PLUS REGISTERED PHONES FOR PUSH

// -- DEP-MODULES -- //
import { bigint, boolean, index, integer, text, timestamp, unique } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { id, plainTable, stamps, userTable } from './helpers';

// -- PEOPLE AND BETTER AUTH MODELS (not user scoped: a sign in happens before any user is known) -- //

export const user = plainTable('user', {
	id: text('id').primaryKey(),
	name: text('name').notNull(),
	email: text('email').notNull().unique(),
	emailVerified: boolean('email_verified').notNull().default(false),
	image: text('image'),
	/** The time zone dates are shown and bucketed in. Dates that mean a day are calendar dates in this zone. */
	// Unused: the zone a person chose lives in user_setting.time_zone, which is the only source
	timezone: text('timezone').notNull().default('Asia/Manila'),
	...stamps()
});

export const authSession = plainTable(
	'auth_session',
	{
		id: text('id').primaryKey(),
		userId: text('user_id')
			.notNull()
			.references(() => user.id, { onDelete: 'cascade' }),
		token: text('token').notNull().unique(),
		expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
		ipAddress: text('ip_address'),
		userAgent: text('user_agent'),
		...stamps()
	},
	(t) => [index('auth_session_user_idx').on(t.userId)]
);

export const authAccount = plainTable(
	'auth_account',
	{
		id: text('id').primaryKey(),
		userId: text('user_id')
			.notNull()
			.references(() => user.id, { onDelete: 'cascade' }),
		accountId: text('account_id').notNull(),
		providerId: text('provider_id').notNull(),
		/** Provider tokens are encrypted by Better Auth (encryptOAuthTokens, key from BETTER_AUTH_SECRET) and never returned by any API. */
		accessToken: text('access_token'),
		refreshToken: text('refresh_token'),
		idToken: text('id_token'),
		accessTokenExpiresAt: timestamp('access_token_expires_at', { withTimezone: true }),
		refreshTokenExpiresAt: timestamp('refresh_token_expires_at', { withTimezone: true }),
		scope: text('scope'),
		/** Always null: sign in is Google only. Better Auth's account model requires the column to exist. */
		password: text('password'),
		...stamps()
	},
	(t) => [
		index('auth_account_user_idx').on(t.userId),
		unique('auth_account_provider_uq').on(t.providerId, t.accountId)
	]
);

export const authVerification = plainTable(
	'auth_verification',
	{
		id: text('id').primaryKey(),
		identifier: text('identifier').notNull(),
		value: text('value').notNull(),
		expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
		...stamps()
	},
	(t) => [index('auth_verification_identifier_idx').on(t.identifier)]
);

/** Better Auth's request limits, kept in the database so every server process counts the same. */
export const authRateLimit = plainTable('auth_rate_limit', {
	id: text('id').primaryKey(),
	key: text('key').notNull().unique(),
	count: integer('count').notNull(),
	lastRequest: bigint('last_request', { mode: 'number' }).notNull()
});

// -- PHONES (USER SCOPED) -- //

/** A phone that signed in, with the push token the server may notify. Removed on sign out or when push says Unregistered. */
export const device = userTable(
	'device',
	() => user.id,
	{
		id: id(),
		platform: text('platform').notNull().default('android'),
		/** The FCM registration token. Rotates; the newest value replaces the old one. */
		pushToken: text('push_token'),
		label: text('label').notNull(),
		lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
		...stamps()
	},
	// One row per person and token: a token seen under two people is two rows, and each is removed on its own sign out
	(t) => [
		index('device_user_idx').on(t.userId),
		unique('device_user_push_token_uq').on(t.userId, t.pushToken)
	]
);
