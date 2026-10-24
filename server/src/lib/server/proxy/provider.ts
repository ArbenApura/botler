// THE PROVIDER SWITCH: WHICH MODEL PROVIDER THE AGENT RUNS ON AND THE LOUD CHECK ITS KEY NEEDS.
// The provider itself is fixed per process by MODEL_PROVIDER from the environment; this module keeps only the
// check, so it can be called from the server start, from the script that builds its own environment and from
// the tests, without touching the environment module.

export type ProviderName = 'anthropic' | 'deepseek';

/**
 * The provider whose turn it is must have a key; the provider left out may carry one but nothing calls it.
 * A blank key for the chosen provider, or a provider name outside the two, stops the server.
 */
export function assertProviderKeys(
	provider: string,
	anthropicKey: string,
	deepseekKey: string
): void {
	if (provider === 'anthropic') {
		if (!anthropicKey)
			throw new Error('ANTHROPIC_API_KEY is required when MODEL_PROVIDER is anthropic');
	} else if (provider === 'deepseek') {
		if (!deepseekKey)
			throw new Error('DEEPSEEK_API_KEY is required when MODEL_PROVIDER is deepseek');
	} else {
		throw new Error(
			`MODEL_PROVIDER must be anthropic or deepseek, not ${JSON.stringify(provider)}`
		);
	}
}
