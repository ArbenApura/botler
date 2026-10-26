// THE MODEL PROVIDERS A PERSON CAN CHOOSE. A pure list with no imports, so the schema, the validation, the ops and the proxy all read the same one.
// Adding a provider is one entry here, plus a CHECK migration for the provider columns, its cache weights, a client branch and an env key.

// -- CONSTANTS -- //

/** The hosts the assistant can run on. This is what a person picks from. */
export const SELECTABLE_PROVIDERS = ['anthropic', 'deepseek'] as const;

/** Usage rows from before the provider was recorded are 'unknown'. It is never a choice. */
export const USAGE_PROVIDERS = [...SELECTABLE_PROVIDERS, 'unknown'] as const;

// -- TYPES -- //

export type SelectableProvider = (typeof SELECTABLE_PROVIDERS)[number];

// -- FUNCTIONS -- //

export function isSelectableProvider(value: unknown): value is SelectableProvider {
	return SELECTABLE_PROVIDERS.some((p) => p === value);
}
