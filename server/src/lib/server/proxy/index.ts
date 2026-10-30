// THE APP'S MODEL CLIENT, BUILT FROM THE ENVIRONMENT. Every provider speaks the same ModelClient interface; today only deepseek exists.
// MODEL_PROVIDER is the default; a person may choose another one in settings once there is more than one (when its key is set). getModelClient() returns one
// client that looks up the provider of the person on each call, so the chat route, the memory jobs and the turn loop all follow the
// choice with no change of their own. Reading the environment is loud: a blank key for the default provider, or an unknown provider
// name, stops the server here at start (hooks.server.ts).

// -- TYPES -- //
import type { SelectableProvider } from '../../providers';
import type { Ctx } from '../ops/context';
import type { ModelClient } from './deepseek';
import type { Limits } from './limits';
// -- ENVS -- //
import {
	BOTLER_CHAT_TOKEN_CAP,
	BOTLER_GLOBAL_TOKEN_CAP,
	BOTLER_MEMORY_TOKEN_CAP,
	BOTLER_RATE_PER_MINUTE,
	CHAT_EFFORT,
	CHAT_MAX_TOKENS,
	DEEPSEEK_API_KEY,
	DEEPSEEK_BASE_URL,
	DEEPSEEK_MODEL,
	DEEPSEEK_THINKING,
	MODEL_PROVIDER
} from '$app/env/private';
// -- MODULES -- //
import { OpsError } from '../ops/context';
import { createModelClient } from './deepseek';
import { createRateLimiter } from './limits';
import { createProviderRouter } from './router';
import { assertProviderKeys, configureProviders, providersWithKeys } from './provider';

// -- STATES -- //

const clients = new Map<SelectableProvider, ModelClient>();
let router: ModelClient | null = null;
let providerOfFn: ((ctx: Ctx) => Promise<SelectableProvider>) | null = null;

// -- CONSTANTS -- //

const LIMITS: Limits = {
	chatTokenCap: BOTLER_CHAT_TOKEN_CAP,
	memoryTokenCap: BOTLER_MEMORY_TOKEN_CAP,
	globalTokenCap: BOTLER_GLOBAL_TOKEN_CAP,
	ratePerMinute: BOTLER_RATE_PER_MINUTE
};

// One counter for every provider: switching provider must not give a person a second allowance per minute
const RATE_LIMITER = createRateLimiter(BOTLER_RATE_PER_MINUTE);

// -- FUNCTIONS -- //

function keys(): Record<SelectableProvider, string> {
	return { deepseek: DEEPSEEK_API_KEY || '' };
}

/** Fails loudly when the default provider has no key, then tells the ops layer which providers a person may choose. Called at server start. */
export function assertModelConfigured(): void {
	assertProviderKeys(MODEL_PROVIDER, keys());
	configureProviders({
		available: providersWithKeys(keys()),
		fallback: MODEL_PROVIDER as SelectableProvider
	});
}

/** The client of one provider, built on first use. A provider without a key is an error, never a silent switch to the other one. */
function clientFor(provider: SelectableProvider): ModelClient {
	const built = clients.get(provider);
	if (built) return built;
	let made: ModelClient;
	switch (provider) {
		case 'deepseek':
			if (!DEEPSEEK_API_KEY)
				throw new OpsError('UNAVAILABLE', 'The DeepSeek server is not set up.');
			made = createModelClient({
				apiKey: DEEPSEEK_API_KEY,
				baseUrl: DEEPSEEK_BASE_URL || 'https://api.deepseek.com',
				model: DEEPSEEK_MODEL || 'deepseek-flash',
				thinking: DEEPSEEK_THINKING,
				chatMaxTokens: CHAT_MAX_TOKENS,
				thinkingMaxTokens: CHAT_MAX_TOKENS,
				chatEffort: CHAT_EFFORT,
				limits: LIMITS,
				rateLimiter: RATE_LIMITER
			});
			break;
		default: {
			// A provider added to the list without a branch here stops loudly instead of falling to another host
			const never: never = provider;
			throw new Error(`No model client for provider ${String(never)}`);
		}
	}
	clients.set(provider, made);
	return made;
}

/**
 * One client for the process. Each call goes to the provider of the person named in its context, found when the call starts (after the
 * chat replay check, inside the person's own transaction). Usage, caps and the rate limit are shared by all providers.
 */
export function getModelClient(): ModelClient {
	assertModelConfigured();
	if (!router) {
		const made = createProviderRouter({
			clientFor,
			available: () => providersWithKeys(keys()),
			fallback: MODEL_PROVIDER as SelectableProvider
		});
		router = made.client;
		providerOfFn = made.providerOf;
	}
	return router;
}

/** The provider that answers a person, found the same way a model call finds it. Stored tool rounds are replayed only to that provider. */
export function getProviderOf(): (ctx: Ctx) => Promise<SelectableProvider> {
	getModelClient();
	if (!providerOfFn) throw new Error('The model router is not set up.');
	return providerOfFn;
}
