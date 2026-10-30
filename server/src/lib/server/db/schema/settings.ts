// SETTINGS OF ONE PERSON: THE CURRENCY AMOUNTS ARE SHOWN IN, THE LANGUAGE OF THE APP, HOW THE ASSISTANT REPLIES, AND THE FIRST DAY OF THE WEEK

// -- DEP-MODULES -- //
import { boolean, check, integer, text, unique } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
// -- MODULES -- //
import { CURRENCY_CODES, DEFAULT_CURRENCY } from '../../../finance/currency';
import { SELECTABLE_PROVIDERS } from '../../../providers';
import { user } from './auth';
import { id, oneOf, stamps, userTable } from './helpers';

// -- CONSTANTS -- //

export const APP_LANGUAGES = ['en', 'fil'] as const;
/** auto is English and mirrors Filipino or Taglish only when the person writes it; the others are fixed. */
export const REPLY_LANGUAGES = ['auto', 'en', 'fil', 'taglish'] as const;

/** What the assistant gets from a photo: the picture itself, or only the text the phone read from it. */
export const PHOTO_MODES = ['image', 'text'] as const;

export type PhotoMode = (typeof PHOTO_MODES)[number];

// -- SETTINGS -- //

/**
 * One row per person. A person with no row yet has the defaults below (settings_get answers them), so nothing needs seeding.
 * The currency only relabels amounts: they are integers in its minor unit and are never converted.
 */
export const userSetting = userTable(
	'user_setting',
	() => user.id,
	{
		id: id(),
		currency: text('currency').notNull().default(DEFAULT_CURRENCY),
		language: text('language', { enum: APP_LANGUAGES }).notNull().default('en'),
		replyLanguage: text('reply_language', { enum: REPLY_LANGUAGES }).notNull().default('auto'),
		/** 0 is Sunday, 1 is Monday. */
		weekStartsOn: integer('week_starts_on').notNull().default(1),
		/** The model host this person chose. Null means the server default (MODEL_PROVIDER). */
		modelProvider: text('model_provider', { enum: SELECTABLE_PROVIDERS }),
		/** Balances lead with net (what is not owed to bills or goals) and show gross smaller. Display only. */
		showNetBalance: boolean('show_net_balance').notNull().default(false),
		/** image sends the picture to a host that can read it; text sends only what the phone read from it. */
		photoMode: text('photo_mode', { enum: PHOTO_MODES }).notNull().default('image'),
		...stamps()
	},
	(t) => [
		unique('user_setting_user_uq').on(t.userId),
		oneOf('user_setting_currency_chk', t.currency, CURRENCY_CODES),
		oneOf('user_setting_language_chk', t.language, APP_LANGUAGES),
		oneOf('user_setting_reply_language_chk', t.replyLanguage, REPLY_LANGUAGES),
		oneOf('user_setting_photo_mode_chk', t.photoMode, PHOTO_MODES),
		check('user_setting_week_chk', sql`${t.weekStartsOn} in (0, 1)`),
		// A null passes a CHECK, so "use the server default" needs no special case
		oneOf('user_setting_model_provider_chk', t.modelProvider, SELECTABLE_PROVIDERS)
	]
);
