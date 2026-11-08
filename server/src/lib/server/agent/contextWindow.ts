// THE CONTEXT WINDOW THE CHAT METER MEASURES AGAINST: the host's window from providers.ts, or CONTEXT_WINDOW_TOKENS when the owner sets it.
// A pure read of the environment (like the food data keys), so the ops layer and the chat service use the same figure without plumbing.

// -- MODULES -- //
import { PROVIDER_CONTEXT_WINDOW, isSelectableProvider } from '../../providers';

// -- FUNCTIONS -- //

/** A whole number above zero from CONTEXT_WINDOW_TOKENS, or null when it is empty. A bad value stops the server (env.ts calls this at start). */
export function windowOverride(value: string | undefined): number | null {
	if (!value || !value.trim()) return null;
	const n = Number(value);
	if (!Number.isInteger(n) || n <= 0)
		throw new Error('CONTEXT_WINDOW_TOKENS must be a whole number above zero');
	return n;
}

/** The context window, in tokens, of the host that answers. An unknown host falls back to DeepSeek's, the only one there is. */
export function contextWindow(provider?: string | null, env = process.env.CONTEXT_WINDOW_TOKENS) {
	return (
		windowOverride(env) ??
		PROVIDER_CONTEXT_WINDOW[isSelectableProvider(provider) ? provider : 'deepseek']
	);
}
