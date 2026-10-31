// WHERE THE EXCHANGE RATES COME FROM: ONE FIXED HTTPS ADDRESS SET AT START (FX_RATES_URL), NEVER AN ADDRESS FROM A PERSON OR A MODEL.
// The server start passes it in; a test passes a stand-in fetch. A refresh with nothing configured stops with a plain message, it never guesses.

// -- TYPES -- //
export type FxConfig = {
	/** The https address of the rates feed: units of each currency per US dollar, as JSON. */
	url: string;
	/** The fetch to use. The platform one when left out; tests pass their own, so no test ever reaches the network. */
	fetch?: typeof fetch;
	/** How long one request may take. Default 10 seconds. */
	timeoutMs?: number;
	/** The most bytes read from the answer. Default 1 MB. */
	maxBytes?: number;
};

// -- STATES -- //

let current: FxConfig | null = null;

// -- FUNCTIONS -- //

/** The address must be a full https address; anything else stops the server at start instead of fetching from somewhere unexpected. */
export function checkFxUrl(url: string): string {
	let parsed: URL;
	try {
		parsed = new URL(url);
	} catch {
		throw new Error(
			'FX_RATES_URL must be a full address such as https://open.er-api.com/v6/latest/USD'
		);
	}
	if (parsed.protocol !== 'https:') throw new Error('FX_RATES_URL must use https');
	if (parsed.username || parsed.password)
		throw new Error('FX_RATES_URL must not hold a user name or a password');
	return parsed.toString();
}

/**
 * The address from the environment. In production a missing one stops the server at start (no silent guess); elsewhere (development, tests)
 * a missing one means no feed: nothing is fetched and a manual refresh says so. A given address is always checked.
 */
export function fxUrlFromEnv(value: string | undefined, production: boolean): string {
	const url = value?.trim() ?? '';
	if (!url) {
		if (production)
			throw new Error(
				'FX_RATES_URL is required in production, for example https://open.er-api.com/v6/latest/USD'
			);
		return '';
	}
	return checkFxUrl(url);
}

/** Sets the source. Called once when the server starts, and by tests. */
export function configureFx(config: FxConfig | null): void {
	current = config ? { ...config, url: checkFxUrl(config.url) } : null;
}

/** The source, or null when none was set (the lazy refresh then does nothing, an asked refresh says so). */
export const fxConfig = (): FxConfig | null => current;
