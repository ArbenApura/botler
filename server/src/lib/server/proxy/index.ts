// THE APP'S MODEL CLIENT, BUILT ONCE FROM THE ENVIRONMENT. The provider is MODEL_PROVIDER: anthropic (the
// default) or deepseek, both speaking the same ModelClient interface. Reading the environment is loud: a blank
// key for the chosen provider, or an unknown provider name, stops the server here at start (hooks.server.ts).

// -- TYPES -- //
import type { ModelClient } from './deepseek';
// -- ENVS -- //
import {
	ANTHROPIC_API_KEY,
	ANTHROPIC_BASE_URL,
	ANTHROPIC_MODEL,
	ANTHROPIC_THINKING,
	BOTLER_CHAT_TOKEN_CAP,
	BOTLER_GLOBAL_TOKEN_CAP,
	BOTLER_MEMORY_TOKEN_CAP,
	BOTLER_RATE_PER_MINUTE,
	DEEPSEEK_API_KEY,
	DEEPSEEK_BASE_URL,
	DEEPSEEK_MODEL,
	DEEPSEEK_THINKING,
	MODEL_PROVIDER
} from '$app/env/private';
// -- MODULES -- //
import { createAnthropicClient } from './anthropic';
import { createModelClient } from './deepseek';
import { assertProviderKeys } from './provider';
import type { Limits } from './limits';

// -- STATES -- //

let client: ModelClient | null = null;

// -- CONSTANTS -- //

const LIMITS: Limits = {
	chatTokenCap: BOTLER_CHAT_TOKEN_CAP,
	memoryTokenCap: BOTLER_MEMORY_TOKEN_CAP,
	globalTokenCap: BOTLER_GLOBAL_TOKEN_CAP,
	ratePerMinute: BOTLER_RATE_PER_MINUTE
};

// -- FUNCTIONS -- //

/** Fails loudly when the chosen provider has no key. Called at server start and before the client is built. */
export function assertModelConfigured(): void {
	assertProviderKeys(MODEL_PROVIDER, ANTHROPIC_API_KEY || '', DEEPSEEK_API_KEY || '');
}

/** One client per process, for the provider MODEL_PROVIDER names. */
export function getModelClient(): ModelClient {
	assertModelConfigured();
	if (!client) {
		client =
			MODEL_PROVIDER === 'deepseek'
				? createModelClient({
						apiKey: DEEPSEEK_API_KEY || '',
						baseUrl: DEEPSEEK_BASE_URL || 'https://api.deepseek.com',
						model: DEEPSEEK_MODEL || 'deepseek-flash',
						thinking: DEEPSEEK_THINKING,
						limits: LIMITS
					})
				: createAnthropicClient({
						apiKey: ANTHROPIC_API_KEY || '',
						baseUrl: ANTHROPIC_BASE_URL || 'https://api.anthropic.com',
						model: ANTHROPIC_MODEL || 'claude-haiku-5-5',
						thinking: ANTHROPIC_THINKING,
						limits: LIMITS
					});
	}
	return client;
}
