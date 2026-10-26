// THE PROVIDER ROUTER: ONE MODEL CLIENT THAT SENDS EACH CALL TO THE HOST THE PERSON OF THAT CALL CHOSE.
// It holds no environment, so a test can hand it stand-in clients. The provider is read when a call starts, inside the person's own
// transaction, and a failed read stops the call: it never falls back to the default on an error.

// -- TYPES -- //
import type { SelectableProvider } from '../../providers';
import type { Ctx } from '../ops/context';
import type { ModelClient } from './deepseek';
// -- MODULES -- //
import { run } from '../ops/context';
import { readSettings } from '../ops/settings';
import { effectiveProvider } from './provider';

// -- TYPES -- //

export type RouterConfig = {
	/** The client of one provider; throws when that provider is not set up. */
	clientFor: (provider: SelectableProvider) => ModelClient;
	/** The providers with a key right now. */
	available: () => readonly SelectableProvider[];
	/** MODEL_PROVIDER. */
	fallback: SelectableProvider;
};

// -- FUNCTIONS -- //

export function createProviderRouter(config: RouterConfig) {
	/** The person's choice when its key is still set, otherwise the default. A stored choice that lost its key is noted in the log. */
	async function providerOf(ctx: Ctx): Promise<SelectableProvider> {
		const stored = (await run(ctx, (tx, userId) => readSettings(tx, userId))).modelProviderChoice;
		const effective = effectiveProvider(stored, config.available(), config.fallback);
		if (stored && stored !== effective)
			console.warn(JSON.stringify({ event: 'provider_choice_unavailable', provider: stored }));
		return effective;
	}

	const client: ModelClient = {
		async complete(ctx, req) {
			return config.clientFor(await providerOf(ctx)).complete(ctx, req);
		},
		async *stream(ctx, req) {
			yield* config.clientFor(await providerOf(ctx)).stream(ctx, req);
		}
	};
	return { client, providerOf };
}
