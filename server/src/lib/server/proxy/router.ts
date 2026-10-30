// THE PROVIDER ROUTER: ONE MODEL CLIENT THAT SENDS EACH CALL TO THE HOST THE PERSON OF THAT CALL CHOSE.
// It holds no environment, so a test can hand it stand-in clients. The provider is read when a call starts, inside the person's own
// transaction, and a failed read stops the call: it never falls back to the default on an error.

// -- TYPES -- //
import type { SelectableProvider } from '../../providers';
import type { Ctx } from '../ops/context';
import type { CompletionRequest } from './types';
import type { ModelClient } from './deepseek';
// -- MODULES -- //
import { pictureProviderFor, visionOf } from '../../providers';
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
	/** Which hosts read pictures. Left out, PROVIDER_VISION. Tests give their own. */
	vision?: Record<SelectableProvider, boolean>;
};

// -- FUNCTIONS -- //

export function createProviderRouter(config: RouterConfig) {
	/** The person's choice when its key is still set, otherwise the default. A stored choice that lost its key is noted in the log. */
	async function route(
		ctx: Ctx
	): Promise<{ provider: SelectableProvider; picturesTo: SelectableProvider | null }> {
		const settings = await run(ctx, (tx, userId) => readSettings(tx, userId));
		const stored = settings.modelProviderChoice;
		const effective = effectiveProvider(stored, config.available(), config.fallback);
		if (stored && stored !== effective)
			console.warn(JSON.stringify({ event: 'provider_choice_unavailable', provider: stored }));
		// Pictures are looked at only when the person chose the picture, and only by a host that reads pictures: their own, or else another one
		// that has a key. Decided here for every call, from the settings read inside the call, so a failed read stops the call instead of
		// sending a picture. A host that cannot read them is never handed one
		const picturesTo =
			settings.photoMode === 'image'
				? pictureProviderFor(effective, config.available(), config.vision)
				: null;
		return { provider: effective, picturesTo };
	}

	const providerOf = async (ctx: Ctx): Promise<SelectableProvider> => (await route(ctx)).provider;

	const hasPictures = (req: CompletionRequest): boolean =>
		req.messages.some(
			(m) => (m.role === 'user' || m.role === 'system') && (m.images?.length ?? 0) > 0
		);

	/** Which host answers this call, and the request it is given: with pictures only when that host reads them and the person chose them. */
	async function target(
		ctx: Ctx,
		req: CompletionRequest
	): Promise<{ provider: SelectableProvider; req: CompletionRequest }> {
		const r = await route(ctx);
		const host = hasPictures(req) && r.picturesTo ? r.picturesTo : r.provider;
		const send = r.picturesTo !== null && visionOf(host, config.vision);
		return { provider: host, req: send ? req : { ...req, messages: withoutImages(req.messages) } };
	}

	const client: ModelClient = {
		async complete(ctx, req) {
			const t = await target(ctx, req);
			return config.clientFor(t.provider).complete(ctx, t.req);
		},
		async *stream(ctx, req) {
			const t = await target(ctx, req);
			yield* config.clientFor(t.provider).stream(ctx, t.req);
		}
	};
	return { client, providerOf };
}
