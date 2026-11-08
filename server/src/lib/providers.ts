// THE MODEL PROVIDERS A PERSON CAN CHOOSE. A pure list with no imports, so the schema, the validation, the ops and the proxy all read the same one.
// Adding a provider is one entry here, plus a CHECK migration for the provider columns (they still allow 'anthropic' for old rows), its cache weights in limits.ts, a client file in proxy/ with a branch in proxy/index.ts, and an env key.

// -- CONSTANTS -- //

/** The hosts the assistant can run on. This is what a person picks from. */
export const SELECTABLE_PROVIDERS = ['deepseek'] as const;

/**
 * Whether the host reads pictures. DeepSeek does: its chat reference takes image_url parts (a data URL of a JPEG, PNG, GIF or WebP) in a user
 * message, and a live call with deepseek-flash described a test picture (checked 2026-10-30). A model set in DEEPSEEK_MODEL that is text only
 * answers 400, and the first call with pictures is then repeated once on the text. One entry flips a host.
 */
export const PROVIDER_VISION: Record<SelectableProvider, boolean> = {
	deepseek: true
};

/**
 * How many tokens one request may carry to the host (its context window), for the chat's context meter. DeepSeek: 1,000,000 tokens, from
 * its documentation (the owner's figure, 2026-11-08; a live check is the owner's optional manual step, never a test). CONTEXT_WINDOW_TOKENS
 * overrides it (agent/contextWindow.ts) when the host or the model changes. It does not change HISTORY_TOKENS or the tool-off guard.
 */
export const PROVIDER_CONTEXT_WINDOW: Record<SelectableProvider, number> = {
	deepseek: 1_000_000
};

/** Usage rows from before the provider was recorded are 'unknown'. It is never a choice. */
export const USAGE_PROVIDERS = [...SELECTABLE_PROVIDERS, 'unknown'] as const;

// -- TYPES -- //

export type SelectableProvider = (typeof SELECTABLE_PROVIDERS)[number];

// -- FUNCTIONS -- //

/** True when the host can be sent a picture. */
export function visionOf(
	provider: SelectableProvider | null | undefined,
	vision: Record<SelectableProvider, boolean> = PROVIDER_VISION
): boolean {
	return provider ? vision[provider] : false;
}

/**
 * The host that reads the pictures of a message for this person: their own when it can, else the first available one that can, else null.
 * A person on a host that cannot read pictures still gets Picture mode: only the messages that carry pictures go to the other host.
 */
export function pictureProviderFor(
	effective: SelectableProvider | null | undefined,
	available: readonly SelectableProvider[],
	vision: Record<SelectableProvider, boolean> = PROVIDER_VISION
): SelectableProvider | null {
	if (effective && visionOf(effective, vision)) return effective;
	return available.find((p) => visionOf(p, vision)) ?? null;
}

export function isSelectableProvider(value: unknown): value is SelectableProvider {
	return SELECTABLE_PROVIDERS.some((p) => p === value);
}
