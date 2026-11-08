// THE WEB CLIENT: WHAT IT SENDS TO DEEPSEEK, WHAT IT KEEPS, AND THAT EVERY FAILURE IS A PLAIN "SEARCH UNAVAILABLE" OR "PAGE UNAVAILABLE" THAT HOLDS NEITHER THE KEY, THE QUERY NOR THE ADDRESS

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import {
	deepseekFetch,
	deepseekSearch,
	MAX_PAGE_CHARS
} from '../../src/lib/server/agent/deepseekWeb';
import { buildTools } from '../../src/lib/server/agent/tools';
import { LIMITS } from '../../src/lib/server/agent/turn';
import { createTestDb } from '../support/testDb';
import { fakeWeb, play, seedPerson, stubModel, toolEvents } from './support';

// -- CONSTANTS -- //

const KEY = 'sk-test-key-123';
const BASE = 'https://api.deepseek.test';
const QUERY = 'latest news about the harbour closing';
// Zero width space, right to left override and bell: made from numbers so no odd character sits in the source
const ZWSP = String.fromCharCode(0x200b);
const RLO = String.fromCharCode(0x202e);
const BELL = String.fromCharCode(7);
const PAGE = 'https://news.example/secret-path/story';

const reply = (body: unknown, status = 200) =>
	new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });

/** A fetch that answers once and remembers how it was called. */
function fake(answer: () => Response | Promise<Response>) {
	const calls: { url: string; init: RequestInit }[] = [];
	const impl = (async (url: string | URL | Request, init?: RequestInit) => {
		calls.push({ url: String(url), init: init ?? {} });
		return answer();
	}) as typeof fetch;
	return { impl, calls, deps: { deepseekKey: KEY, baseUrl: BASE, fetch: impl } };
}

/** What a message may never hold: the key, the query, the page address or a piece of it. */
const holdsNothing = (message: string) => {
	for (const secret of [KEY, QUERY, 'harbour', PAGE, 'secret-path'])
		expect(message).not.toContain(secret);
};

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

afterEach(() => vi.restoreAllMocks());

// -- TESTS -- //

describe('deepseek search', () => {
	it('is not set up without a key, and sends nothing', async () => {
		const f = fake(() => reply({ results: [] }));
		for (const deepseekKey of [undefined, '', '   ']) {
			const out = await deepseekSearch(QUERY, { deepseekKey, baseUrl: BASE, fetch: f.impl });
			expect(out).toEqual({ ok: false, message: expect.stringMatching(/^Search unavailable: /) });
		}
		expect(f.calls).toHaveLength(0);
	});

	it('posts to the fixed path with the key as a bearer token and refuses redirects', async () => {
		const f = fake(() => reply({ results: [] }));
		await deepseekSearch(QUERY, { ...f.deps, deepseekKey: ` ${KEY} `, baseUrl: `${BASE}/` });
		const call = f.calls[0];
		expect(call?.url).toBe(`${BASE}/v1/tools/search`);
		expect(call?.init.method).toBe('POST');
		expect(call?.init.redirect).toBe('error');
		const headers = call?.init.headers as Record<string, string>;
		expect(headers.authorization).toBe(`Bearer ${KEY}`);
		expect(JSON.parse(String(call?.init.body))).toEqual({
			query: QUERY,
			count: 5,
			need_content: false
		});
		// The key goes in the header only
		expect(String(call?.init.body)).not.toContain(KEY);
	});

	it('uses the public DeepSeek address when none is given', async () => {
		const f = fake(() => reply({ results: [] }));
		await deepseekSearch(QUERY, { deepseekKey: KEY, fetch: f.impl });
		expect(f.calls[0]?.url).toBe('https://api.deepseek.com/v1/tools/search');
	});

	it('never sends the key to an address that is not https (this machine excepted)', async () => {
		const f = fake(() => reply({ results: [] }));
		for (const baseUrl of [
			'http://api.deepseek.com',
			'ftp://x.example',
			'not a url',
			'https://u:p@x.example'
		]) {
			const out = await deepseekSearch(QUERY, { deepseekKey: KEY, baseUrl, fetch: f.impl });
			expect(out.ok, baseUrl).toBe(false);
		}
		expect(f.calls).toHaveLength(0);
		await deepseekSearch(QUERY, {
			deepseekKey: KEY,
			baseUrl: 'http://localhost:9999',
			fetch: f.impl
		});
		expect(f.calls[0]?.url).toBe('http://localhost:9999/v1/tools/search');
	});

	it('keeps the title, address, summary and date, cleaned and cut, at most five', async () => {
		const f = fake(() =>
			reply({
				results: [
					{
						title: 'Harbour <b>closed</b>\u0007',
						url: 'https://news.example/a?x=1',
						snippet: 'short text',
						summary: `Long   summary
${ZWSP}with ${RLO}hidden marks ${'x'.repeat(500)}`,
						date: '2026-10-30<script>'
					},
					{
						title: 'Snippet only',
						url: 'https://news.example/b',
						snippet: 'the snippet',
						summary: ''
					},
					{ title: null, url: 'https://news.example/c', snippet: null, summary: null, date: null },
					{ title: 'No address', url: null, snippet: 'x' },
					{ title: 'Script', url: 'javascript:alert(1)', snippet: 'x' },
					{ title: 'Spaced', url: 'https://news.example/has space', snippet: 'x' },
					{ title: 'Long', url: `https://news.example/${'a'.repeat(600)}`, snippet: 'x' },
					{ title: 'D', url: 'https://news.example/d' },
					{ title: 'E', url: 'https://news.example/e' },
					{ title: 'F', url: 'https://news.example/f' },
					{ title: 'G', url: 'https://news.example/g' }
				]
			})
		);
		const out = await deepseekSearch(QUERY, f.deps);
		expect(out.ok).toBe(true);
		if (!out.ok) return;
		expect(out.results.map((r) => r.url)).toEqual([
			'https://news.example/a?x=1',
			'https://news.example/b',
			'https://news.example/c',
			'https://news.example/d',
			'https://news.example/e'
		]);
		const first = out.results[0];
		expect(first?.title).toBe('Harbour b closed /b');
		expect(first?.snippet.startsWith('Long summary with hidden marks x')).toBe(true);
		expect(first?.snippet.length).toBeLessThanOrEqual(300);
		expect(first?.date).toBe('2026-10-30 script');
		const shown = `${first?.title}${first?.snippet}${first?.date}`;
		for (const bad of ['<', '>', ZWSP, RLO, BELL]) expect(shown).not.toContain(bad);
		expect(out.results[1]?.snippet).toBe('the snippet');
		expect(out.results[2]).toMatchObject({ title: '', snippet: '', date: '' });
	});

	it('answers an empty list when nothing was found, which is not a failure', async () => {
		const f = fake(() => reply({ results: [] }));
		expect(await deepseekSearch(QUERY, f.deps)).toEqual({ ok: true, results: [] });
	});

	it.each([
		[401, /key was refused/],
		[403, /key was refused/],
		[402, /balance is used up/],
		[429, /rate limit or quota/],
		[400, /request was refused/],
		[422, /request was refused/],
		[404, /not found at the configured address/],
		[408, /could not be reached/],
		[500, /could not be reached/],
		[503, /could not be reached/]
	] as const)('maps HTTP %s to a plain reason', async (status, reason) => {
		const f = fake(() => reply(`${KEY} ${QUERY} secret from the other side`, status));
		const out = await deepseekSearch(QUERY, f.deps);
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/^Search unavailable: /) });
		if (out.ok) return;
		expect(out.message).toMatch(reason);
		holdsNothing(out.message);
		expect(out.message).not.toContain('secret from the other side');
	});

	it('is a plain failure when the network fails, the call is aborted or the answer is wrong', async () => {
		const down = fake(() => Promise.reject(new Error(`boom ${KEY} ${QUERY}`)));
		const a = await deepseekSearch(QUERY, down.deps);
		expect(a.ok).toBe(false);
		if (!a.ok) holdsNothing(a.message);

		const stopped = new AbortController();
		stopped.abort();
		const abortable = {
			deepseekKey: KEY,
			baseUrl: BASE,
			fetch: (async (_u: string | URL | Request, init?: RequestInit) => {
				if (init?.signal?.aborted) throw new Error('aborted');
				return reply({ results: [] });
			}) as typeof fetch
		};
		expect((await deepseekSearch(QUERY, abortable, stopped.signal)).ok).toBe(false);

		for (const body of [
			'not json',
			'{}',
			'{"results":"x"}',
			'{"error":{"message":"bad"}}',
			'null'
		]) {
			const out = await deepseekSearch(QUERY, fake(() => reply(body)).deps);
			expect(out, body).toEqual({ ok: false, message: expect.stringMatching(/not understood/) });
		}
	});

	it('keeps a gateway path in the address, and stops when the call is aborted while waiting', async () => {
		const f = fake(() => reply({ results: [] }));
		await deepseekSearch(QUERY, { ...f.deps, baseUrl: 'https://gw.example/deepseek/' });
		expect(f.calls[0]?.url).toBe('https://gw.example/deepseek/v1/tools/search');
		const stop = new AbortController();
		const slow = {
			deepseekKey: KEY,
			baseUrl: BASE,
			fetch: ((_u: string | URL | Request, init?: RequestInit) =>
				new Promise<Response>((_ok, no) => {
					init?.signal?.addEventListener('abort', () => no(new Error('aborted')));
				})) as typeof fetch
		};
		const pending = deepseekSearch(QUERY, slow, stop.signal);
		stop.abort();
		expect(await pending).toEqual({
			ok: false,
			message: expect.stringMatching(/could not be reached/)
		});
	});

	it('refuses an answer longer than the cap', async () => {
		const f = fake(() => reply(JSON.stringify({ results: [], pad: 'x'.repeat(250_000) })));
		const out = await deepseekSearch(QUERY, f.deps);
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/too long/) });
	});

	it('refuses a redirect instead of following it with the key', async () => {
		const f = fake(() => Promise.reject(new TypeError('redirect mode is set to error')));
		expect((await deepseekSearch(QUERY, f.deps)).ok).toBe(false);
		expect(f.calls[0]?.init.redirect).toBe('error');
	});
});

describe('deepseek page read', () => {
	it('is not set up without a key, and sends nothing', async () => {
		const f = fake(() => reply({ title: 't', content: 'c' }));
		const out = await deepseekFetch(PAGE, { deepseekKey: '', baseUrl: BASE, fetch: f.impl });
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/^Page unavailable: /) });
		expect(f.calls).toHaveLength(0);
	});

	it('posts the checked address to the fixed path and keeps the text with its line breaks', async () => {
		const f = fake(() =>
			reply({
				title: 'Story <b>1</b>',
				content: '# Heading\r\n\r\n\r\n\r\nFirst   line​ here\n- item <x>'
			})
		);
		const out = await deepseekFetch(` ${PAGE.replace('news.example', 'News.Example')} `, f.deps);
		expect(f.calls[0]?.url).toBe(`${BASE}/v1/tools/fetch`);
		expect((f.calls[0]?.init.headers as Record<string, string>).authorization).toBe(
			`Bearer ${KEY}`
		);
		expect(f.calls[0]?.init.redirect).toBe('error');
		expect(JSON.parse(String(f.calls[0]?.init.body))).toEqual({ url: PAGE });
		expect(out).toEqual({
			ok: true,
			url: PAGE,
			title: 'Story b 1 /b',
			text: '# Heading\n\nFirst line here\n- item x',
			truncated: false
		});
	});

	it('cuts a long answer to the page limit and says so, and still reads one of 500 KB', async () => {
		const f = fake(() => reply({ title: 'Big', content: `${'word '.repeat(100_000)}end` }));
		const out = await deepseekFetch(PAGE, f.deps);
		expect(out.ok).toBe(true);
		if (!out.ok) return;
		expect(out.text.length).toBeLessThanOrEqual(MAX_PAGE_CHARS);
		expect(out.truncated).toBe(true);
	});

	it('refuses an answer beyond the read cap with a plain reason', async () => {
		const f = fake(() => reply(JSON.stringify({ title: 't', content: 'x'.repeat(5_100_000) })));
		const out = await deepseekFetch(PAGE, f.deps);
		expect(out).toEqual({
			ok: false,
			message: expect.stringMatching(/^Page unavailable: .*too long/)
		});
	});

	it.each([
		[401, /key was refused/],
		[403, /blocked by the fetch service/],
		[404, /could not be read/],
		[402, /balance is used up/],
		[429, /rate limit or quota/],
		[408, /could not be reached/],
		[500, /could not be reached/]
	] as const)('maps HTTP %s to a plain reason', async (status, reason) => {
		const f = fake(() => reply(`${KEY} ${PAGE} secret from the other side`, status));
		const out = await deepseekFetch(PAGE, f.deps);
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/^Page unavailable: /) });
		if (out.ok) return;
		expect(out.message).toMatch(reason);
		holdsNothing(out.message);
		expect(out.message).not.toContain('secret from the other side');
	});

	it('is a plain failure on a network error or a wrong answer', async () => {
		const down = fake(() => Promise.reject(new Error(`boom ${KEY} ${PAGE}`)));
		const a = await deepseekFetch(PAGE, down.deps);
		expect(a.ok).toBe(false);
		if (!a.ok) holdsNothing(a.message);
		for (const body of ['not json', '"text"', '{"title":1}', 'null'])
			expect(await deepseekFetch(PAGE, fake(() => reply(body)).deps), body).toEqual({
				ok: false,
				message: expect.stringMatching(/not understood/)
			});
	});

	it.each([
		'file:///etc/passwd',
		'ftp://news.example/a',
		'https://user:pw@news.example/a',
		'http://localhost/a',
		'http://localhost./a',
		'http://10.0.0.1/a',
		'http://[::1]/a',
		'http://2130706433/a',
		'https://news.example:8443/a',
		'not an address'
	])('refuses %s before anything is sent, with a reason that holds nothing', async (u) => {
		const f = fake(() => reply({ title: 't', content: 'c' }));
		const out = await deepseekFetch(u, f.deps);
		expect(out).toEqual({ ok: false, message: expect.stringMatching(/^Page unavailable: /) });
		expect(f.calls, u).toHaveLength(0);
		if (!out.ok) holdsNothing(out.message);
	});
});

describe('the web tools in a message', () => {
	it('offers the main turn the research tool and keeps the two page tools for the helper alone', () => {
		const names = buildTools().map((x) => x.name);
		expect(names).toContain('research');
		expect(names).not.toContain('web_search');
		expect(names).not.toContain('web_read');
	});

	it('a failed search and a failed read in research are plain errors: nothing came back from outside, so a write afterwards still saves', async () => {
		const f = await seedPerson(t);
		const web = fakeWeb({}, { searchFails: true });
		const model = stubModel(
			(_r, n) => {
				if (n === 0) return { calls: [['research', { question: 'harbour news' }]] };
				if (n === 1)
					return { calls: [['expense_log', { amount: 5000, accountId: f.gcash, note: 'coffee' }]] };
				return { say: 'Logged.' };
			},
			{
				helper: (r, n) =>
					n === 0
						? {
								calls: [
									['web_search', { query: 'harbour news' }],
									['web_read', { url: 'https://missing.example/x' }]
								]
							}
						: { say: `Nothing found. ${JSON.stringify(r.messages.at(-1))}` }
			}
		);
		const events = await play({
			f,
			model,
			text: 'search for harbour news and log 50 coffee on gcash',
			web: web.deps
		});
		expect(toolEvents(events).map((e) => `${e.name}:${e.status}`)).toEqual([
			'research:ok',
			'expense_log:ok'
		]);
	});

	it('keeps the page text the helper reads to its own size and out of the main turn', async () => {
		const f = await seedPerson(t);
		const web = fakeWeb({ 'https://big.example/p': 'PAGEWORD '.repeat(5_000) });
		const model = stubModel([
			{ calls: [['research', { question: 'read it', urls: ['https://big.example/p'] }]] },
			{ say: 'Done.' }
		]);
		await play({ f, model, text: 'read https://big.example/p', web: web.deps });
		// The helper saw a page cut to its limit; the main model got the digest, which is at most 4000 characters
		const helperPage = JSON.stringify(model.helperRequests.at(-1)?.messages ?? []);
		expect(helperPage.length).toBeLessThan(LIMITS.researchPageChars * 3);
		const mainTool = model.requests
			.at(1)
			?.messages.filter((m) => m.role === 'tool')
			.map((m) => m.content)
			.join('');
		expect(mainTool?.length ?? 0).toBeLessThanOrEqual(LIMITS.maxResultChars);
	});
});
