// THE WEB SEARCH CLIENT: WHAT IT SENDS, WHAT IT KEEPS, AND THAT EVERY FAILURE IS A PLAIN "SEARCH UNAVAILABLE" THAT HOLDS NEITHER THE KEY NOR THE QUERY

// -- DEP-MODULES -- //
import { afterEach, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { tavilySearch } from '../../src/lib/server/agent/tavily';

// -- CONSTANTS -- //

const KEY = 'tvly-test-key-123';
const QUERY = 'latest news about the harbour closing';

const reply = (body: unknown, status = 200) =>
	new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });

/** A fetch that answers once and remembers how it was called. */
function fake(answer: () => Response | Promise<Response>) {
	const calls: { url: string; init: RequestInit }[] = [];
	const impl = (async (url: string | URL | Request, init?: RequestInit) => {
		calls.push({ url: String(url), init: init ?? {} });
		return answer();
	}) as typeof fetch;
	return { impl, calls };
}

afterEach(() => vi.restoreAllMocks());

// -- TESTS -- //

describe('tavily search', () => {
	it('is not set up without a key, and sends nothing', async () => {
		const f = fake(() => reply({ results: [] }));
		for (const tavilyKey of [undefined, '', '   ']) {
			const out = await tavilySearch(QUERY, { tavilyKey, fetch: f.impl });
			expect(out).toEqual({ ok: false, message: expect.stringMatching(/^Search unavailable: /) });
		}
		expect(f.calls).toHaveLength(0);
	});

	it('posts to the fixed address with the key as a bearer token and refuses redirects', async () => {
		const f = fake(() => reply({ results: [] }));
		await tavilySearch(QUERY, { tavilyKey: ` ${KEY} `, fetch: f.impl });
		const call = f.calls[0];
		expect(call?.url).toBe('https://api.tavily.com/search');
		expect(call?.init.method).toBe('POST');
		expect(call?.init.redirect).toBe('error');
		const headers = call?.init.headers as Record<string, string>;
		expect(headers.authorization).toBe(`Bearer ${KEY}`);
		const body = JSON.parse(String(call?.init.body)) as Record<string, unknown>;
		expect(body).toMatchObject({ query: QUERY, max_results: 5, include_answer: false });
		// The key goes in the header only
		expect(String(call?.init.body)).not.toContain(KEY);
	});

	it('keeps the title, address and snippet, cleaned and cut, at most five', async () => {
		const f = fake(() =>
			reply({
				results: [
					{
						title: 'Harbour <b>closed</b>\u0007',
						url: 'https://news.example/a',
						content: 'x'.repeat(900)
					},
					{ title: 'Not a web address', url: 'javascript:alert(1)', content: 'no' },
					{ title: 'Too long address', url: `https://e.example/${'a'.repeat(600)}`, content: 'no' },
					...Array.from({ length: 8 }, (_, i) => ({
						title: `Hit ${i}`,
						url: `https://site.example/${i}`,
						content: 'ok'
					}))
				]
			})
		);
		const out = await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl });
		expect(out.ok).toBe(true);
		if (!out.ok) return;
		expect(out.results).toHaveLength(5);
		expect(out.results[0]?.title).toBe('Harbour b closed /b');
		expect(out.results[0]?.snippet).toHaveLength(300);
		expect(out.results.every((r) => /^https?:\/\//.test(r.url))).toBe(true);
		expect(out.results.map((r) => r.url)).not.toContain('javascript:alert(1)');
	});

	it('a hit with a null title or text still counts, and an address with spaces or odd parts is dropped', async () => {
		const f = fake(() =>
			reply({
				results: [
					{ title: null, url: 'https://a.example/x', content: null },
					{ title: 'Spaces', url: 'https://a.example/a b', content: 'no' },
					{ title: 'Ftp', url: 'ftp://a.example/x', content: 'no' }
				]
			})
		);
		const out = await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl });
		expect(out).toEqual({
			ok: true,
			results: [{ title: '', url: 'https://a.example/x', snippet: '' }]
		});
	});

	it('a search that found nothing is a success with no results, not a failure', async () => {
		const f = fake(() => reply({ results: [] }));
		expect(await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl })).toEqual({
			ok: true,
			results: []
		});
	});

	it.each([
		[401, /key was refused/],
		[403, /key was refused/],
		[429, /quota is used up/],
		[432, /quota is used up/],
		[433, /quota is used up/],
		[500, /could not be reached/],
		[502, /could not be reached/]
	])('answers %i with a plain message', async (status, message) => {
		vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const logged = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const f = fake(() => reply({ detail: `secret ${KEY} ${QUERY}` }, status));
		const out = await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl });
		// Whatever was logged holds the status at most, never the key, the query or the other side's text
		const everything = JSON.stringify([out, logged.mock.calls]);
		expect(everything).not.toContain(KEY);
		expect(everything).not.toContain('harbour');
		expect(everything).not.toContain('secret');
		expect(out).toEqual({ ok: false, message: expect.stringMatching(message) });
		expect(out.ok === false && out.message.startsWith('Search unavailable')).toBe(true);
	});

	it('a broken or odd answer is unavailable, never an exception', async () => {
		for (const body of ['not json', '{"results": "no"}', '{}', 'null']) {
			const f = fake(() => reply(body));
			const out = await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl });
			expect(out).toEqual({ ok: false, message: expect.stringMatching(/not understood/) });
		}
	});

	it('an answer over the size cap is unavailable', async () => {
		const f = fake(() => reply(`{"results": [], "pad": "${'x'.repeat(250_000)}"}`));
		const out = await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl });
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/too long/) });
	});

	it('a network failure never lets the key or the query out, in the result or in the logs', async () => {
		const logged = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const f = fake(() => {
			throw new Error(`connect failed for ${QUERY} with ${KEY}`);
		});
		const out = await tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl });
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/could not be reached/) });
		const everything = JSON.stringify([out, logged.mock.calls]);
		expect(everything).not.toContain(KEY);
		expect(everything).not.toContain('harbour');
	});

	it('a cancelled turn ends the search quickly', async () => {
		const controller = new AbortController();
		const f = fake(
			() =>
				new Promise<Response>((_, reject) => {
					controller.signal.addEventListener('abort', () => reject(new Error('aborted')));
				})
		);
		const pending = tavilySearch(QUERY, { tavilyKey: KEY, fetch: f.impl }, controller.signal);
		controller.abort();
		expect(await pending).toEqual({
			ok: false,
			message: expect.stringMatching(/Search unavailable/)
		});
	});
});
