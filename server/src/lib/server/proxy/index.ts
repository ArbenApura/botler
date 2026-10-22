// THE APP'S MODEL CLIENT, BUILT ONCE FROM THE ENVIRONMENT

// -- TYPES -- //
import type { ModelClient } from './deepseek';
// -- ENVS -- //
import {
	BOTLER_CHAT_TOKEN_CAP,
	BOTLER_GLOBAL_TOKEN_CAP,
	BOTLER_MEMORY_TOKEN_CAP,
	BOTLER_RATE_PER_MINUTE,
	DEEPSEEK_API_KEY,
	DEEPSEEK_BASE_URL,
	DEEPSEEK_MODEL
} from '$app/env/private';
// -- MODULES -- //
import { createModelClient } from './deepseek';

// -- STATES -- //

let client: ModelClient | null = null;

// -- FUNCTIONS -- //

/** One client per process. */
export function getModelClient(): ModelClient {
	client ??= createModelClient({
		apiKey: DEEPSEEK_API_KEY,
		baseUrl: DEEPSEEK_BASE_URL,
		model: DEEPSEEK_MODEL,
		limits: {
			chatTokenCap: BOTLER_CHAT_TOKEN_CAP,
			memoryTokenCap: BOTLER_MEMORY_TOKEN_CAP,
			globalTokenCap: BOTLER_GLOBAL_TOKEN_CAP,
			ratePerMinute: BOTLER_RATE_PER_MINUTE
		}
	});
	return client;
}
