// THE MODEL PROVIDERS A PERSON CAN CHOOSE. A pure list with no imports, so the schema, the validation, the ops and the proxy all read the same one.
// Adding a provider is one entry here, plus a CHECK migration for the provider columns, its cache weights, a client branch and an env key.

// -- CONSTANTS -- //

/** The hosts the assistant can run on. This is what a person picks from. */
export const SELECTABLE_PROVIDERS = ['anthropic', 'deepseek'] as const;

/** Whether the host reads pictures. DeepSeek's chat API takes text only; flipping one entry is all it takes if that changes. */
export const PROVIDER_VISION: Record<SelectableProvider, boolean> = {
	anthropic: true,
	deepseek: false
};

/** Usage rows from before the provider was recorded are 'unknown'. It is never a choice. */
export const USAGE_PROVIDERS = [...SELECTABLE_PROVIDERS, 'unknown'] as const;

// -- TYPES -- //

export type SelectableProvider = (typeof SELECTABLE_PROVIDERS)[number];

// -- FUNCTIONS -- //

/** True when the host can be sent a picture. */
export function visionOf(provider: SelectableProvider | null | undefined): boolean {
	return provider ? PROVIDER_VISION[provider] : false;
}

/**
 * The host that reads the pictures of a message for this person: their own when it can, else the first available one that can, else null.
 * A person on a host that cannot read pictures still gets Picture mode: only the messages that carry pictures go to the other host.
 */
export function pictureProviderFor(
	effective: SelectableProvider | null | undefined,
	available: readonly SelectableProvider[]
): SelectableProvider | null {
	if (effective && visionOf(effective)) return effective;
	return available.find((p) => visionOf(p)) ?? null;
}

export function isSelectableProvider(value: unknown): value is SelectableProvider {
	return SELECTABLE_PROVIDERS.some((p) => p === value);
}
