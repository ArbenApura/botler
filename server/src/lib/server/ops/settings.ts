// SETTINGS VERBS: THE CURRENCY, THE LANGUAGES AND THE FIRST DAY OF THE WEEK OF ONE PERSON
// A person with no row yet has the defaults, so nothing needs seeding. Only the person changes settings: the assistant can read them (to
// say amounts in the right currency) but a change reaches every screen and every amount, so it is never the assistant's.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { SettingsSetInput } from '../db/zod';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
// -- MODULES -- //
import { DEFAULT_CURRENCY } from '../../finance/currency';
import { userSetting } from '../db/schema';
import { settingsSetInput } from '../db/zod';
import { run, runWrite } from './context';
import { mapped, parse, requirePerson } from './shared';

// -- TYPES -- //

export type SettingsView = {
	currency: string;
	language: 'en' | 'fil';
	replyLanguage: 'auto' | 'en' | 'fil' | 'taglish';
	/** 0 is Sunday, 1 is Monday. */
	weekStartsOn: number;
};

// -- CONSTANTS -- //

export const SETTING_DEFAULTS: SettingsView = {
	currency: DEFAULT_CURRENCY,
	language: 'en',
	replyLanguage: 'auto',
	weekStartsOn: 1
};

// -- FUNCTIONS -- //

/** The settings of a person inside a transaction, the defaults when there is no row. Used by the assistant's turn too. */
export async function readSettings(tx: Tx, userId: string): Promise<SettingsView> {
	const [row] = await tx.select().from(userSetting).where(eq(userSetting.userId, userId));
	return row
		? {
				currency: row.currency,
				language: row.language,
				replyLanguage: row.replyLanguage,
				weekStartsOn: row.weekStartsOn
			}
		: { ...SETTING_DEFAULTS };
}

export async function getSettings(ctx: Ctx): Promise<SettingsView> {
	return run(ctx, (tx, userId) => readSettings(tx, userId));
}

/** Changes the fields given and keeps the rest. A change of currency answers a notice: amounts are relabelled, never converted. */
export async function setSettings(
	ctx: Ctx,
	raw: SettingsSetInput
): Promise<{ settings: SettingsView; notice: string | null }> {
	requirePerson(ctx.actor.kind, 'change the settings');
	const input = parse(settingsSetInput, raw);
	return mapped(() =>
		runWrite(ctx, 'settings.set', input, async (tx, userId) => {
			const before = await readSettings(tx, userId);
			// Only the fields that were given. A zod default here would reset the others on every save
			const changes: Partial<SettingsView> = {};
			if (input.currency !== undefined) changes.currency = input.currency;
			if (input.language !== undefined) changes.language = input.language;
			if (input.replyLanguage !== undefined) changes.replyLanguage = input.replyLanguage;
			if (input.weekStartsOn !== undefined) changes.weekStartsOn = input.weekStartsOn;
			await tx
				.insert(userSetting)
				.values({ userId, ...changes })
				.onConflictDoUpdate({
					target: userSetting.userId,
					set: { ...changes, updatedAt: new Date() }
				});
			const settings = { ...before, ...changes };
			const notice =
				settings.currency !== before.currency
					? `Your amounts now read in ${settings.currency}. Nothing was converted: 100.00 is still 100.00, only the currency changed.`
					: null;
			return { settings, notice };
		})
	);
}
