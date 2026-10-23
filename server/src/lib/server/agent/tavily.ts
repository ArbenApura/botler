// THE WEB SEARCH CLIENT: ONE POST TO THE TAVILY SEARCH API. THE ADDRESS IS FIXED, SO NOTHING THE MODEL WRITES CAN CHANGE WHERE IT GOES.
// Every failure comes back as a short plain message that starts with "Search unavailable". The message never holds the key, the query or
// anything the other side sent, and a search that worked but found nothing is not a failure. The key comes in as an argument: this file reads
// no environment, so tests need no setup.

// -- DEP-MODULES -- //
import { z } from 'zod';

// -- TYPES -- //

export type TavilyDeps = {
	/** The Tavily key. Left out or blank, search answers that it is not set up. */
	tavilyKey?: string;
	/** Replaces the global fetch (tests). */
	fetch?: typeof fetch;
};

export type SearchResult = { title: string; url: string; snippet: string };

export type SearchOutcome = { ok: true; results: SearchResult[] } | { ok: false; message: string };

// -- CONSTANTS -- //

const ENDPOINT = 'https://api.tavily.com/search';
const TIMEOUT_MS = 15_000;
const MAX_BODY_BYTES = 200_000;
const MAX_RESULTS = 5;
const MAX_URL_CHARS = 500;

const answer = z.object({
	results: z.array(
		z.object({
			// A hit may carry null instead of text: that is still a working search
			title: z.string().nullish(),
			url: z.string(),
			content: z.string().nullish()
		})
	)
});

const unavailable = (why: string): SearchOutcome => ({
	ok: false,
	message: `Search unavailable: ${why}`
});

// -- FUNCTIONS -- //

/** Text from the web with control characters and angle brackets taken out, cut to a length. */
function clean(text: string | null | undefined, max: number): string {
	return (text ?? '')
		.replace(/[\p{Cc}<>]/gu, ' ')
		.replace(/\s+/g, ' ')
		.trim()
		.slice(0, max);
}

/** Reads the body up to a cap. Null when it is longer than that. */
async function readCapped(res: Response): Promise<string | null> {
	if (!res.body) return '';
	const reader = res.body.getReader();
	const chunks: Uint8Array[] = [];
	let size = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.length;
		if (size > MAX_BODY_BYTES) {
			await reader.cancel();
			return null;
		}
		chunks.push(value);
	}
	return Buffer.concat(chunks).toString('utf8');
}

/** Runs one search. Never throws and never returns the key, the query or the other side's error text. */
export async function tavilySearch(
	query: string,
	deps: TavilyDeps,
	signal?: AbortSignal
): Promise<SearchOutcome> {
	const key = deps.tavilyKey?.trim();
	if (!key) return unavailable('it is not set up on this server.');
	const timeout = AbortSignal.timeout(TIMEOUT_MS);
	let res: Response;
	try {
		res = await (deps.fetch ?? fetch)(ENDPOINT, {
			method: 'POST',
			headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
			body: JSON.stringify({
				query,
				max_results: MAX_RESULTS,
				search_depth: 'basic',
				include_answer: false,
				include_raw_content: false
			}),
			// A redirect would carry the key somewhere else
			redirect: 'error',
			signal: signal ? AbortSignal.any([signal, timeout]) : timeout
		});
	} catch {
		return unavailable('it could not be reached.');
	}
	if (res.status === 401 || res.status === 403) {
		void res.body?.cancel();
		return unavailable('the key was refused.');
	}
	if (res.status === 429 || res.status === 432 || res.status === 433) {
		void res.body?.cancel();
		return unavailable('the search quota is used up.');
	}
	if (!res.ok) {
		void res.body?.cancel();
		console.error(JSON.stringify({ event: 'web_search_failed', status: res.status }));
		return unavailable('it could not be reached.');
	}
	let parsed: z.infer<typeof answer>;
	try {
		const text = await readCapped(res);
		if (text === null) return unavailable('the answer was too long.');
		const checked = answer.safeParse(JSON.parse(text));
		if (!checked.success) return unavailable('the answer was not understood.');
		parsed = checked.data;
	} catch {
		return unavailable('the answer was not understood.');
	}
	const results: SearchResult[] = [];
	for (const r of parsed.results) {
		// Only plain web addresses: anything else is dropped, and the kept one is the parsed form
		if (r.url.length > MAX_URL_CHARS || /[\s\p{Cc}<>]/u.test(r.url)) continue;
		let href: string;
		try {
			const u = new URL(r.url);
			if (u.protocol !== 'http:' && u.protocol !== 'https:') continue;
			href = u.href;
		} catch {
			continue;
		}
		results.push({ title: clean(r.title, 160), url: href, snippet: clean(r.content, 300) });
		if (results.length >= MAX_RESULTS) break;
	}
	return { ok: true, results };
}
