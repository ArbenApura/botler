// THE WEB CLIENT: ONE POST TO DEEPSEEK'S SEARCH API AND ONE TO ITS FETCH API. THE PATHS ARE FIXED AND THE HOST IS THE CONFIGURED DEEPSEEK ADDRESS, SO NOTHING THE MODEL WRITES CAN CHANGE WHERE THE KEY GOES.
// Every failure comes back as a short plain message that starts with "Search unavailable" or "Page unavailable". The message never holds the key,
// the query, the address or anything the other side sent, and a search that worked but found nothing is not a failure. The key and the base
// address come in as arguments: this file reads no environment, so tests need no setup. DeepSeek reads the page from its own network, so the
// server never connects to an address the model picked; the address pre-check lives in fetchGuard.ts.

// -- DEP-MODULES -- //
import { z } from 'zod';
// -- MODULES -- //
import { checkPublicUrl, FetchRefused } from './fetchGuard';

// -- TYPES -- //

export type WebClientDeps = {
	/** The DeepSeek key. Left out or blank, search and read answer that they are not set up. */
	deepseekKey?: string;
	/** The DeepSeek address, https and without a path (https://api.deepseek.com). Blank means the public one. */
	baseUrl?: string;
	/** Replaces the global fetch (tests). */
	fetch?: typeof fetch;
};

export type SearchResult = { title: string; url: string; snippet: string; date: string };

export type SearchOutcome = { ok: true; results: SearchResult[] } | { ok: false; message: string };

export type PageOutcome =
	| { ok: true; url: string; title: string; text: string; truncated: boolean }
	| { ok: false; message: string };

// -- CONSTANTS -- //

const DEFAULT_BASE = 'https://api.deepseek.com';
const SEARCH_TIMEOUT_MS = 15_000;
const FETCH_TIMEOUT_MS = 20_000;
const MAX_SEARCH_BODY_BYTES = 200_000;
const MAX_FETCH_BODY_BYTES = 5_000_000;
const MAX_RESULTS = 5;
const MAX_URL_CHARS = 500;
const MAX_TITLE_CHARS = 160;
const MAX_SNIPPET_CHARS = 300;
const MAX_DATE_CHARS = 40;
/** Page text kept for the model: the whole tool result has to stay under the turn's result cap (16000 characters). */
export const MAX_PAGE_CHARS = 12_000;

const nullishText = z.string().nullish();

const searchAnswer = z.object({
	results: z.array(
		z.object({
			// A hit may carry null instead of text: that is still a working search
			title: nullishText,
			url: nullishText,
			snippet: nullishText,
			summary: nullishText,
			date: nullishText
		})
	)
});

const fetchAnswer = z.object({ title: nullishText, content: nullishText });

// -- FUNCTIONS -- //

const unavailable = (why: string): SearchOutcome => ({
	ok: false,
	message: `Search unavailable: ${why}`
});

const pageUnavailable = (why: string): PageOutcome => ({
	ok: false,
	message: `Page unavailable: ${why}`
});

/**
 * Text from the web as one line: control and format characters (zero width, right to left marks), line and paragraph separators and
 * angle brackets taken out, white space collapsed, cut to a length.
 */
function clean(text: string | null | undefined, max: number): string {
	return (text ?? '')
		.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}<>]/gu, ' ')
		.replace(/\s+/g, ' ')
		.trim()
		.slice(0, max);
}

/** A page's Markdown with its line breaks kept: the same characters taken out, runs of blank lines and spaces collapsed. */
function cleanPage(text: string | null | undefined): string {
	return (text ?? '')
		.replace(/\r\n?/g, '\n')
		.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}<>]/gu, (c) => (c === '\n' || c === '\t' ? c : ' '))
		.replace(/[ \t]+/g, ' ')
		.replace(/ ?\n ?/g, '\n')
		.replace(/\n{3,}/g, '\n\n')
		.trim();
}

/** Reads the body up to a cap. Null when it is longer than that. */
async function readCapped(res: Response, max: number): Promise<string | null> {
	if (!res.body) return '';
	const reader = res.body.getReader();
	const chunks: Uint8Array[] = [];
	let size = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.length;
		if (size > max) {
			await reader.cancel();
			return null;
		}
		chunks.push(value);
	}
	return Buffer.concat(chunks).toString('utf8');
}

/** The address to post to, or null when the key must not be sent there: only https, and plain http only on this machine. */
function endpoint(deps: WebClientDeps, path: string): string | null {
	const raw = (deps.baseUrl?.trim() || DEFAULT_BASE).replace(/\/+$/, '');
	let base: URL;
	try {
		base = new URL(raw);
	} catch {
		return null;
	}
	const local = base.hostname === 'localhost' || base.hostname === '127.0.0.1';
	if (base.protocol !== 'https:' && !(base.protocol === 'http:' && local)) return null;
	if (base.username || base.password) return null;
	// A gateway prefix in the address is kept, as the chat client keeps it
	return `${base.origin}${base.pathname.replace(/\/+$/, '')}${path}`;
}

type Posted = { ok: true; text: string } | { ok: false; why: string };

/** One POST with the key as a bearer token. A failure is a short reason that holds nothing from either side. */
async function post(
	url: string,
	key: string,
	body: Record<string, unknown>,
	opts: { timeoutMs: number; maxBytes: number; gone: string; blocked?: string },
	deps: WebClientDeps,
	signal?: AbortSignal
): Promise<Posted> {
	const timeout = AbortSignal.timeout(opts.timeoutMs);
	let res: Response;
	try {
		res = await (deps.fetch ?? fetch)(url, {
			method: 'POST',
			headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
			body: JSON.stringify(body),
			// A redirect would carry the key somewhere else
			redirect: 'error',
			signal: signal ? AbortSignal.any([signal, timeout]) : timeout
		});
	} catch {
		return { ok: false, why: 'it could not be reached.' };
	}
	if (res.status === 401 || res.status === 403) {
		void res.body?.cancel();
		// A 403 from the fetch service means the page is blocked by its policy, not that the key is wrong
		return {
			ok: false,
			why: res.status === 403 && opts.blocked ? opts.blocked : 'the key was refused.'
		};
	}
	if (res.status === 402) {
		void res.body?.cancel();
		return { ok: false, why: 'the DeepSeek balance is used up.' };
	}
	if (res.status === 429) {
		void res.body?.cancel();
		return { ok: false, why: 'the rate limit or quota is used up.' };
	}
	if (res.status === 404) {
		void res.body?.cancel();
		return { ok: false, why: opts.gone };
	}
	if (res.status === 400 || res.status === 413 || res.status === 422) {
		void res.body?.cancel();
		return { ok: false, why: 'the request was refused.' };
	}
	if (!res.ok) {
		void res.body?.cancel();
		console.error(JSON.stringify({ event: 'web_call_failed', status: res.status }));
		return { ok: false, why: 'it could not be reached.' };
	}
	try {
		const text = await readCapped(res, opts.maxBytes);
		if (text === null) return { ok: false, why: 'the answer was too long.' };
		return { ok: true, text };
	} catch {
		return { ok: false, why: 'the answer was not understood.' };
	}
}

/** Runs one search. Never throws and never returns the key, the query or the other side's error text. */
export async function deepseekSearch(
	query: string,
	deps: WebClientDeps,
	signal?: AbortSignal
): Promise<SearchOutcome> {
	const key = deps.deepseekKey?.trim();
	if (!key) return unavailable('it is not set up on this server.');
	const url = endpoint(deps, '/v1/tools/search');
	if (!url) return unavailable('the DeepSeek address must use https.');
	const sent = await post(
		url,
		key,
		{ query, count: MAX_RESULTS, need_content: false },
		{
			timeoutMs: SEARCH_TIMEOUT_MS,
			maxBytes: MAX_SEARCH_BODY_BYTES,
			gone: 'the search service was not found at the configured address.'
		},
		deps,
		signal
	);
	if (!sent.ok) return unavailable(sent.why);
	let parsed: z.infer<typeof searchAnswer>;
	try {
		const checked = searchAnswer.safeParse(JSON.parse(sent.text));
		if (!checked.success) return unavailable('the answer was not understood.');
		parsed = checked.data;
	} catch {
		return unavailable('the answer was not understood.');
	}
	const results: SearchResult[] = [];
	for (const r of parsed.results) {
		// Only plain web addresses: anything else is dropped, and the kept one is the parsed form
		const raw = r.url ?? '';
		if (!raw || raw.length > MAX_URL_CHARS || /[\s\p{Cc}\p{Cf}<>]/u.test(raw)) continue;
		let href: string;
		try {
			const u = new URL(raw);
			if (u.protocol !== 'http:' && u.protocol !== 'https:') continue;
			href = u.href;
		} catch {
			continue;
		}
		results.push({
			title: clean(r.title, MAX_TITLE_CHARS),
			url: href,
			// The summary is the longer text written for models; the snippet is the fallback
			snippet: clean(r.summary?.trim() ? r.summary : r.snippet, MAX_SNIPPET_CHARS),
			date: clean(r.date, MAX_DATE_CHARS)
		});
		if (results.length >= MAX_RESULTS) break;
	}
	return { ok: true, results };
}

/** Reads one public page as text through DeepSeek. Never throws and never returns the key, the address or the other side's error text. */
export async function deepseekFetch(
	rawUrl: string,
	deps: WebClientDeps,
	signal?: AbortSignal
): Promise<PageOutcome> {
	const key = deps.deepseekKey?.trim();
	if (!key) return pageUnavailable('it is not set up on this server.');
	// The address is checked here and the checked form is what is sent
	let checked: string;
	try {
		checked = checkPublicUrl(rawUrl);
	} catch (e) {
		if (e instanceof FetchRefused) return pageUnavailable(e.message);
		throw e;
	}
	const url = endpoint(deps, '/v1/tools/fetch');
	if (!url) return pageUnavailable('the DeepSeek address must use https.');
	const sent = await post(
		url,
		key,
		{ url: checked },
		{
			timeoutMs: FETCH_TIMEOUT_MS,
			maxBytes: MAX_FETCH_BODY_BYTES,
			gone: 'that page could not be read.',
			blocked: 'that page is blocked by the fetch service, so it could not be read.'
		},
		deps,
		signal
	);
	if (!sent.ok) return pageUnavailable(sent.why);
	let parsed: z.infer<typeof fetchAnswer>;
	try {
		const answer = fetchAnswer.safeParse(JSON.parse(sent.text));
		if (!answer.success) return pageUnavailable('the answer was not understood.');
		parsed = answer.data;
	} catch {
		return pageUnavailable('the answer was not understood.');
	}
	const text = cleanPage(parsed.content);
	return {
		ok: true,
		url: checked,
		title: clean(parsed.title, MAX_TITLE_CHARS),
		text: text.slice(0, MAX_PAGE_CHARS),
		truncated: text.length > MAX_PAGE_CHARS
	};
}
