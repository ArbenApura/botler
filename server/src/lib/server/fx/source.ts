// FETCHING THE RATES: ONE REQUEST TO THE FIXED ADDRESS, READ WITH A TIME AND A SIZE LIMIT, CHECKED, AND TURNED INTO PLAIN DECIMAL TEXT.
// Nothing about a person is ever sent. A redirect is refused, so the address cannot send the server somewhere else. Anything that does not
// look right is an error with a short reason code, and the caller keeps the rates it already has.

// -- DEP-MODULES -- //
import { z } from 'zod';
// -- MODULES -- //
import { CURRENCY_CODES } from '../../finance/currency';
import { BASE_CURRENCY, rateText } from '../../finance/fx';
import { checkFxUrl } from './config';
import type { FxConfig } from './config';

// -- TYPES -- //

export type FetchedRates = {
	/** Plain decimal text per currency code of the catalogue, the dollar left out. */
	rates: Record<string, string>;
	/** The host the rates came from, for showing the source. */
	source: string;
	/** Codes of the catalogue the feed had no usable rate for. */
	missing: string[];
};

/** Why a fetch failed: a short code, never text from the feed. */
export class FxFetchError extends Error {
	constructor(readonly reason: string) {
		super(`Rates could not be fetched: ${reason}`);
		this.name = 'FxFetchError';
	}
}

// -- CONSTANTS -- //

const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_MAX_BYTES = 1_000_000;
/** A feed with fewer usable rates than this is broken or the wrong one. */
const MIN_RATES = 100;

const feedSchema = z.object({
	result: z.literal('success'),
	base_code: z.literal(BASE_CURRENCY),
	rates: z.record(z.string(), z.unknown())
});

// -- FUNCTIONS -- //

/** Reads the answer up to a size limit, stopping as soon as it is passed. */
async function readLimited(res: Response, maxBytes: number): Promise<string> {
	const body = res.body;
	if (!body) throw new FxFetchError('empty');
	const reader = body.getReader();
	const chunks: Uint8Array[] = [];
	let size = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.byteLength;
		if (size > maxBytes) {
			await reader.cancel();
			throw new FxFetchError('too_large');
		}
		chunks.push(value);
	}
	return Buffer.concat(chunks).toString('utf8');
}

/** The rates of the feed, checked. Throws FxFetchError with a reason code when anything is wrong. */
export async function fetchRates(config: FxConfig): Promise<FetchedRates> {
	const url = checkFxUrl(config.url);
	const doFetch = config.fetch ?? fetch;
	let res: Response;
	try {
		res = await doFetch(url, {
			method: 'GET',
			headers: { accept: 'application/json' },
			// A redirect is an error: the address is fixed and never followed elsewhere
			redirect: 'error',
			signal: AbortSignal.timeout(config.timeoutMs ?? DEFAULT_TIMEOUT_MS)
		});
	} catch (e) {
		const name = e instanceof Error ? e.name : '';
		throw new FxFetchError(
			name === 'TimeoutError' || name === 'AbortError' ? 'timeout' : 'network'
		);
	}
	if (!res.ok) throw new FxFetchError(`http_${res.status}`);
	if (!(res.headers.get('content-type') ?? '').toLowerCase().includes('json'))
		throw new FxFetchError('not_json');
	let text: string;
	try {
		text = await readLimited(res, config.maxBytes ?? DEFAULT_MAX_BYTES);
	} catch (e) {
		if (e instanceof FxFetchError) throw e;
		throw new FxFetchError('network');
	}
	let json: unknown;
	try {
		json = JSON.parse(text);
	} catch {
		throw new FxFetchError('not_json');
	}
	const parsed = feedSchema.safeParse(json);
	if (!parsed.success) throw new FxFetchError('bad_shape');
	const feed = parsed.data.rates;
	// The dollar is the base, so the feed must say it is 1 if it lists it
	if (BASE_CURRENCY in feed && feed[BASE_CURRENCY] !== 1) throw new FxFetchError('bad_base');
	const rates: Record<string, string> = {};
	const missing: string[] = [];
	for (const code of CURRENCY_CODES) {
		if (code === BASE_CURRENCY) continue;
		const text = rateText(feed[code]);
		if (text) rates[code] = text;
		else missing.push(code);
	}
	if (Object.keys(rates).length < MIN_RATES) throw new FxFetchError('too_few_rates');
	return { rates, source: new URL(url).hostname, missing };
}
