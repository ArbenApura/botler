// THE FETCH GUARD (P3.9): PRIVATE, LOOPBACK, LINK-LOCAL AND METADATA ADDRESSES, REDIRECT HOPS, DNS REBINDING, TEXT ONLY, SIZE AND TIME LIMITS

// -- TYPES -- //
import type { GuardDeps, Resolved, TransportResponse } from '../../src/lib/server/agent/fetchGuard';
// -- DEP-MODULES -- //
import { createServer } from 'node:http';
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	fetchPublicText,
	htmlToText,
	isBlockedAddress
} from '../../src/lib/server/agent/fetchGuard';

// -- CONSTANTS -- //

const PUBLIC: Resolved = { address: '93.184.216.34', family: 4 };

const page = (
	body: string,
	headers: Record<string, string> = { 'content-type': 'text/html; charset=utf-8' },
	status = 200
): TransportResponse => ({
	status,
	headers,
	body: (async function* () {
		yield new TextEncoder().encode(body);
	})(),
	destroy: () => undefined
});

/** A fake network: names resolve as listed, pages answer as listed. Records every connection. */
function net(opts: {
	names?: Record<string, Resolved[]>;
	pages: Record<string, () => TransportResponse>;
}) {
	const connections: string[] = [];
	const deps: GuardDeps = {
		lookup: async (host) => {
			const found = opts.names?.[host];
			if (!found) throw new Error('no such host');
			return found;
		},
		transport: async ({ url, address }) => {
			connections.push(`${address.address} ${url.host}${url.pathname}`);
			const make = opts.pages[`${url.host}${url.pathname}`];
			if (!make) return page('not found', { 'content-type': 'text/plain' }, 404);
			return make();
		}
	};
	return { deps, connections };
}

// -- TESTS -- //

describe('addresses that are never fetched', () => {
	it.each([
		'127.0.0.1',
		'127.8.8.8',
		'10.0.0.5',
		'172.16.0.1',
		'172.31.255.255',
		'192.168.1.1',
		'169.254.169.254',
		'100.64.0.1',
		'0.0.0.0',
		'224.0.0.1',
		'255.255.255.255',
		'198.18.0.1',
		'::1',
		'::',
		'fe80::1',
		'fc00::1',
		'fd12:3456::1',
		'ff02::1',
		'::ffff:127.0.0.1',
		'::ffff:7f00:1',
		'::ffff:169.254.169.254',
		'2002:7f00:1::1',
		'64:ff9b::7f00:1',
		'2001:db8::1'
	])('refuses %s', (addr) => {
		expect(isBlockedAddress(addr)).toBe(true);
	});

	it.each([
		'93.184.216.34',
		'8.8.8.8',
		'172.32.0.1',
		'172.15.255.255',
		'1.1.1.1',
		'2606:4700:4700::1111',
		'2a00:1450:4001::200e',
		'::ffff:8.8.8.8'
	])('allows the public address %s', (addr) => {
		expect(isBlockedAddress(addr)).toBe(false);
	});

	it('refuses text that is not an address', () => {
		expect(isBlockedAddress('example.com')).toBe(true);
		expect(isBlockedAddress('999.1.1.1')).toBe(true);
	});
});

describe('fetching a page', () => {
	it('reads a public page as text and connects to the address it checked', async () => {
		const n = net({
			names: { 'example.com': [PUBLIC] },
			pages: {
				'example.com/': () =>
					page(
						'<html><style>x{}</style><body><h1>Hello &amp; welcome</h1><p>Two</p><script>evil()</script></body></html>'
					)
			}
		});
		const r = await fetchPublicText('https://example.com/', n.deps);
		expect(r.text).toBe('Hello & welcome\nTwo');
		expect(r.contentType).toBe('text/html');
		expect(n.connections).toEqual(['93.184.216.34 example.com/']);
	});

	it('refuses private addresses typed in, on any port, with a login, or with a strange scheme', async () => {
		const n = net({ pages: {} });
		for (const u of [
			'http://localhost/',
			'http://127.0.0.1/',
			'http://[::1]/',
			'http://169.254.169.254/latest/meta-data/',
			'http://10.0.0.1/',
			'http://2130706433/',
			'http://0x7f.0.0.1/',
			'https://example.com:8443/',
			'https://user:pw@example.com/',
			'file:///etc/passwd',
			'ftp://example.com/'
		])
			await expect(fetchPublicText(u, n.deps), u).rejects.toThrow();
		expect(n.connections).toEqual([]);
	});

	it('refuses a name when any answer is private, so a mixed answer cannot slip through', async () => {
		const n = net({
			names: {
				'mixed.example': [PUBLIC, { address: '10.1.2.3', family: 4 }],
				'internal.example': [{ address: '192.168.0.9', family: 4 }]
			},
			pages: {}
		});
		await expect(fetchPublicText('https://mixed.example/', n.deps)).rejects.toThrow(/private/);
		await expect(fetchPublicText('https://internal.example/', n.deps)).rejects.toThrow(/private/);
		expect(n.connections).toEqual([]);
	});

	it('does not re-resolve after checking: a name that changes its answer is connected to the checked address', async () => {
		let calls = 0;
		const connections: string[] = [];
		const deps: GuardDeps = {
			// The first answer is public, any later one would be the metadata address (DNS rebinding)
			lookup: async () => (++calls === 1 ? [PUBLIC] : [{ address: '169.254.169.254', family: 4 }]),
			transport: async ({ address }) => {
				connections.push(address.address);
				return page('ok', { 'content-type': 'text/plain' });
			}
		};
		await fetchPublicText('https://rebind.example/', deps);
		expect(connections).toEqual(['93.184.216.34']);
		expect(calls).toBe(1);
	});

	it('re-checks every redirect hop', async () => {
		const redirect = (to: string) => () => page('', { location: to }, 302);
		const n = net({
			names: { 'a.example': [PUBLIC], 'b.example': [PUBLIC] },
			pages: {
				'a.example/start': redirect('https://b.example/next'),
				'b.example/next': redirect('http://169.254.169.254/latest/meta-data/'),
				'a.example/local': redirect('http://localhost/admin'),
				'a.example/relative': redirect('/end'),
				'a.example/end': () => page('arrived', { 'content-type': 'text/plain' })
			}
		});
		await expect(fetchPublicText('https://a.example/start', n.deps)).rejects.toThrow(/private/);
		await expect(fetchPublicText('https://a.example/local', n.deps)).rejects.toThrow(/private/);
		expect((await fetchPublicText('https://a.example/relative', n.deps)).text).toBe('arrived');
		expect(n.connections.some((c) => c.startsWith('169.') || c.startsWith('127.'))).toBe(false);
	});

	it('stops after five redirects', async () => {
		const n = net({
			names: { 'loop.example': [PUBLIC] },
			pages: { 'loop.example/': () => page('', { location: '/' }, 301) }
		});
		await expect(fetchPublicText('https://loop.example/', n.deps)).rejects.toThrow(/too many/);
		expect(n.connections).toHaveLength(6);
	});

	it('reads text types only', async () => {
		const n = net({
			names: { 'files.example': [PUBLIC] },
			pages: {
				'files.example/a.pdf': () => page('%PDF', { 'content-type': 'application/pdf' }),
				'files.example/a.png': () => page('x', { 'content-type': 'image/png' }),
				'files.example/a.json': () => page('{"ok":true}', { 'content-type': 'application/json' })
			}
		});
		await expect(fetchPublicText('https://files.example/a.pdf', n.deps)).rejects.toThrow(
			/text pages/
		);
		await expect(fetchPublicText('https://files.example/a.png', n.deps)).rejects.toThrow(
			/text pages/
		);
		expect((await fetchPublicText('https://files.example/a.json', n.deps)).text).toBe(
			'{"ok":true}'
		);
	});

	it('cuts a huge page and says so', async () => {
		const big = 'x'.repeat(2_000_000);
		const n = net({
			names: { 'big.example': [PUBLIC] },
			pages: { 'big.example/': () => page(big, { 'content-type': 'text/plain' }) }
		});
		const r = await fetchPublicText('https://big.example/', n.deps);
		expect(r.truncated).toBe(true);
		expect(r.text.length).toBeLessThanOrEqual(30_000);
	});

	it('gives up on a page that never answers', async () => {
		const deps: GuardDeps = {
			lookup: async () => [PUBLIC],
			transport: ({ signal }) =>
				new Promise((_, reject) =>
					signal.addEventListener('abort', () => reject(new Error('aborted')))
				)
		};
		const controller = new AbortController();
		const pending = fetchPublicText('https://slow.example/', deps, controller.signal);
		setTimeout(() => controller.abort(), 20);
		await expect(pending).rejects.toThrow(/too long/);
	});

	it('refuses a name that does not exist', async () => {
		const n = net({ pages: {} });
		await expect(fetchPublicText('https://nope.example/', n.deps)).rejects.toThrow(
			/could not be found/
		);
	});
});

describe('the real network path', () => {
	it('does not connect to a server on this machine, by name or by number', async () => {
		let hits = 0;
		const server = createServer((_req, res) => {
			hits++;
			res.end('secret');
		});
		await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
		const port = (server.address() as { port: number }).port;
		try {
			// The real lookup and transport: nothing is stubbed. Port 80 is the only one allowed, so also try the allowed port path
			await expect(fetchPublicText(`http://127.0.0.1:${port}/`)).rejects.toThrow();
			await expect(fetchPublicText(`http://localhost:${port}/`)).rejects.toThrow();
			await expect(fetchPublicText('http://localhost/')).rejects.toThrow(/private/);
			expect(hits).toBe(0);
		} finally {
			await new Promise((r) => server.close(r));
		}
	});
});

describe('html to text', () => {
	it('drops scripts, styles and comments and keeps the words', () => {
		expect(
			htmlToText('<p>Pay <b>now</b></p><!-- hidden --><script>alert(1)</script><style>a{}</style>')
		).toBe('Pay now');
	});
});
