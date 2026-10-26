// SETTINGS VERBS: THE CURRENCY, THE LANGUAGES AND THE FIRST DAY OF THE WEEK OF ONE PERSON
// A person with no row yet has the defaults, so nothing needs seeding. Only the person changes settings: the assistant can read them (to
// say amounts in the right currency) but a change reaches every screen and every amount, so it is never the assistant's.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { SettingsSetInput } from '../db/zod';
import type { SelectableProvider } from '../../providers';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
// -- MODULES -- //
import { DEFAULT_CURRENCY } from '../../finance/currency';
import { userSetting } from '../db/schema';
import { settingsSetInput } from '../db/zod';
import { effectiveProvider, providerSetup } from '../proxy/provider';
import { OpsError, run, runWrite } from './context';
import { mapped, parse, requirePerson } from './shared';

// -- TYPES -- //

export type SettingsView = {
	currency: string;
	language: 'en' | 'fil';
	replyLanguage: 'auto' | 'en' | 'fil' | 'taglish';
	/** 0 is Sunday, 1 is Monday. */
	weekStartsOn: number;
	/** The host the assistant will run on for this person: their choice when it is still available, else the server default. Null when the server has none set up. */
	modelProvider: SelectableProvider | null;
	/** What the person chose; null means "the server default". It can name a host whose key was removed since. */
	modelProviderChoice: SelectableProvider | null;
	/** The hosts a person may choose from: the ones that have a key on the server. Names only. */
	availableProviders: SelectableProvider[];
};

/** The part of the view that is stored in the table; the rest is worked out from the server's setup. */
type StoredSettings = Pick<
	SettingsView,
	'currency' | 'language' | 'replyLanguage' | 'weekStartsOn' | 'modelProviderChoice'
>;

// -- CONSTANTS -- //

export const SETTING_DEFAULTS: StoredSettings = {
	currency: DEFAULT_CURRENCY,
	language: 'en',
	replyLanguage: 'auto',
	weekStartsOn: 1,
	modelProviderChoice: null
};

// -- FUNCTIONS -- //

/** Adds what depends on the server's setup: who will run and who can be chosen. Nothing set up means nothing offered. */
function withProviders(stored: StoredSettings): SettingsView {
	const setup = providerSetup();
	return {
		...stored,
		modelProvider: setup
			? effectiveProvider(stored.modelProviderChoice, setup.available, setup.fallback)
			: null,
		availableProviders: setup ? [...setup.available] : []
	};
}

/** The defaults as a view, for a turn whose settings could not be read. Only the settings are defaulted; the provider is looked up apart. */
export function defaultSettingsView(): SettingsView {
	return withProviders({ ...SETTING_DEFAULTS });
}

/** The settings of a person inside a transaction, the defaults when there is no row. Used by the assistant's turn too. */
export async function readSettings(tx: Tx, userId: string): Promise<SettingsView> {
	const [row] = await tx.select().from(userSetting).where(eq(userSetting.userId, userId));
	return withProviders(
		row
			? {
					currency: row.currency,
					language: row.language,
					replyLanguage: row.replyLanguage,
					weekStartsOn: row.weekStartsOn,
					modelProviderChoice: row.modelProvider
				}
			: { ...SETTING_DEFAULTS }
	);
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
			const changes: Partial<StoredSettings> = {};
			if (input.currency !== undefined) changes.currency = input.currency;
			if (input.language !== undefined) changes.language = input.language;
			if (input.replyLanguage !== undefined) changes.replyLanguage = input.replyLanguage;
			if (input.weekStartsOn !== undefined) changes.weekStartsOn = input.weekStartsOn;
			// Undefined keeps the choice; null puts the person back on the server default
			if (input.modelProvider !== undefined) {
				if (
					input.modelProvider !== null &&
					!before.availableProviders.includes(input.modelProvider)
				)
					throw new OpsError('INVALID', 'That server is not set up here, so it cannot be chosen.');
				changes.modelProviderChoice = input.modelProvider;
			}
			const { modelProviderChoice, ...plain } = changes;
			const columns = {
				...plain,
				...(modelProviderChoice !== undefined ? { modelProvider: modelProviderChoice } : {})
			};
			await tx
				.insert(userSetting)
				.values({ userId, ...columns })
				.onConflictDoUpdate({
					target: userSetting.userId,
					set: { ...columns, updatedAt: new Date() }
				});
			const settings = withProviders({
				currency: before.currency,
				language: before.language,
				replyLanguage: before.replyLanguage,
				weekStartsOn: before.weekStartsOn,
				modelProviderChoice: before.modelProviderChoice,
				...changes
			});
			const notice =
				settings.currency !== before.currency
					? `Your main currency is now ${settings.currency}. Your accounts keep the currencies they hold, and the total is shown in ${settings.currency}. Your income, goals, rules and minimum balances are the same numbers, now read in ${settings.currency}: nothing in the money plan was converted. Your bills keep their own currency.`
					: null;
			return { settings, notice };
		})
	);
}
