// THE PROVIDER SWITCH: WHICH MODEL PROVIDERS THE SERVER CAN RUN, WHICH ONE IS THE DEFAULT, AND THE LOUD CHECK THE KEYS NEED.
// The default is MODEL_PROVIDER from the environment; a person may choose another one that has a key (settings). This module holds
// only plain logic and the setup the server start passes in, so the start, the ops layer and the tests can use it without touching
// the environment module.

// -- TYPES -- //
import type { SelectableProvider } from '../../providers';
// -- MODULES -- //
import { isSelectableProvider, SELECTABLE_PROVIDERS } from '../../providers';

export type ProviderName = SelectableProvider;

export type ProviderSetup = {
	/** The providers that have a key on this server, in the order of SELECTABLE_PROVIDERS. */
	available: readonly SelectableProvider[];
	/** MODEL_PROVIDER: who runs for a person who chose nothing. */
	fallback: SelectableProvider;
};

// -- STATES -- //

let setup: ProviderSetup | null = null;

// -- FUNCTIONS -- //

/** Set once when the server starts, and by tests. Null clears it. */
export function configureProviders(next: ProviderSetup | null): void {
	setup = next;
}

/** What the server was started with. Nothing set means nothing is offered: a choice is refused, never guessed. */
export function providerSetup(): ProviderSetup | null {
	return setup;
}

/** The providers whose key is present, from the keys the environment holds. */
export function providersWithKeys(keys: Record<SelectableProvider, string>): SelectableProvider[] {
	return SELECTABLE_PROVIDERS.filter((p) => keys[p].length > 0);
}

/**
 * The provider that will run for a person: what they chose when its key is still there, otherwise the server default. A stored
 * choice whose key was taken away falls back instead of locking the person out of chat; settings shows it as unavailable.
 */
export function effectiveProvider(
	stored: string | null | undefined,
	available: readonly SelectableProvider[],
	fallback: SelectableProvider
): SelectableProvider {
	if (isSelectableProvider(stored) && available.includes(stored)) return stored;
	return fallback;
}

/**
 * The provider whose turn it is must have a key; the provider left out may carry one but nothing calls it.
 * A blank key for the chosen provider, or a provider name outside the list, stops the server.
 */
export function assertProviderKeys(
	provider: string,
	keys: Record<SelectableProvider, string>
): void {
	if (!isSelectableProvider(provider))
		throw new Error(
			`MODEL_PROVIDER must be one of ${SELECTABLE_PROVIDERS.join(', ')}, not ${JSON.stringify(provider)}`
		);
	if (!keys[provider])
		throw new Error(
			`${provider.toUpperCase()}_API_KEY is required when MODEL_PROVIDER is ${provider}`
		);
}
