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
export const REPLY_LANGUAGES = [
	'auto',
	'en',
	'fil',
	'taglish',
	'es',
	'fr',
	'de',
	'pt',
	'zh',
	'ja',
	'ko',
	'hi',
	'id',
	'ar'
] as const;

export type ReplyLanguage = (typeof REPLY_LANGUAGES)[number];

/** What the assistant gets from a photo: the picture itself, or only the text the phone read from it. */
export const PHOTO_MODES = ['image', 'text'] as const;

export type PhotoMode = (typeof PHOTO_MODES)[number];

/** How a clock reads: auto follows the phone, the others are fixed. */
export const TIME_FORMATS = ['auto', '12', '24'] as const;

export type TimeFormat = (typeof TIME_FORMATS)[number];

/** How a date is ordered: auto follows the app language, the others are fixed. */
export const DATE_STYLES = ['auto', 'dmy', 'mdy', 'ymd'] as const;

export type DateStyle = (typeof DATE_STYLES)[number];

/** The zone of a person who has not chosen one. */
export const DEFAULT_TIME_ZONE = 'Asia/Manila';

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
		/** The IANA zone that decides what "today" is and how clock times are shown. Checked against the real zone list when it is written; the column only bounds its length. */
		timeZone: text('time_zone').notNull().default(DEFAULT_TIME_ZONE),
		/** auto follows the phone's 12 or 24 hour choice. */
		timeFormat: text('time_format', { enum: TIME_FORMATS }).notNull().default('auto'),
		/** auto follows the app language. */
		dateStyle: text('date_style', { enum: DATE_STYLES }).notNull().default('auto'),
		...stamps()
	},
	(t) => [
		unique('user_setting_user_uq').on(t.userId),
		oneOf('user_setting_currency_chk', t.currency, CURRENCY_CODES),
		oneOf('user_setting_language_chk', t.language, APP_LANGUAGES),
		oneOf('user_setting_reply_language_chk', t.replyLanguage, REPLY_LANGUAGES),
		oneOf('user_setting_photo_mode_chk', t.photoMode, PHOTO_MODES),
		oneOf('user_setting_time_format_chk', t.timeFormat, TIME_FORMATS),
		oneOf('user_setting_date_style_chk', t.dateStyle, DATE_STYLES),
		check('user_setting_time_zone_chk', sql`char_length(${t.timeZone}) between 1 and 64`),
		check('user_setting_week_chk', sql`${t.weekStartsOn} in (0, 1)`),
		// A null passes a CHECK, so "use the server default" needs no special case
		oneOf('user_setting_model_provider_chk', t.modelProvider, SELECTABLE_PROVIDERS)
	]
);
