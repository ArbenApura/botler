// THE PROVIDER ROUTER: ONE MODEL CLIENT THAT SENDS EACH CALL TO THE HOST THE PERSON OF THAT CALL CHOSE.
// It holds no environment, so a test can hand it stand-in clients. The provider is read when a call starts, inside the person's own
// transaction, and a failed read stops the call: it never falls back to the default on an error.

// -- TYPES -- //
import type { SelectableProvider } from '../../providers';
import type { Ctx } from '../ops/context';
import type { CompletionRequest } from './types';
import type { ModelClient } from './deepseek';
// -- MODULES -- //
import { visionOf } from '../../providers';
import { run } from '../ops/context';
import { readSettings } from '../ops/settings';
import { withoutImages } from './core';
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
	async function route(ctx: Ctx): Promise<{ provider: SelectableProvider; pictures: boolean }> {
		const settings = await run(ctx, (tx, userId) => readSettings(tx, userId));
		const stored = settings.modelProviderChoice;
		const effective = effectiveProvider(stored, config.available(), config.fallback);
		if (stored && stored !== effective)
			console.warn(JSON.stringify({ event: 'provider_choice_unavailable', provider: stored }));
		// A picture goes only to a host that reads pictures AND only when the person chose the picture. Decided here for every call,
		// from the settings read inside the call, so a failed read stops the call instead of sending a picture
		return { provider: effective, pictures: settings.photoMode === 'image' && visionOf(effective) };
	}

	const providerOf = async (ctx: Ctx): Promise<SelectableProvider> => (await route(ctx)).provider;

	const forCall = (req: CompletionRequest, pictures: boolean): CompletionRequest =>
		pictures ? req : { ...req, messages: withoutImages(req.messages) };

	const client: ModelClient = {
		async complete(ctx, req) {
			const r = await route(ctx);
			return config.clientFor(r.provider).complete(ctx, forCall(req, r.pictures));
		},
		async *stream(ctx, req) {
			const r = await route(ctx);
			yield* config.clientFor(r.provider).stream(ctx, forCall(req, r.pictures));
		}
	};
	return { client, providerOf };
}
