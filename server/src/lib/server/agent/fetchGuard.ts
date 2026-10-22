// THE FETCH GUARD: HOW THE ASSISTANT READS THE WEB WITHOUT BEING TURNED INTO A WAY INTO THE SERVER'S OWN NETWORK
// - http and https only, ports 80 and 443 only, no credentials in the address.
// - The host is resolved here and EVERY address it resolves to must be public: private, loopback, link-local, carrier-grade NAT, multicast,
//   documentation and the cloud metadata address are refused (IPv4 and IPv6, including IPv4 hidden in IPv6 forms).
// - The connection is made to the address that was checked, with the host name only for the Host header and the TLS name, so a name that
//   answers differently a moment later (DNS rebinding) cannot reach a private address.
// - Every redirect is followed by hand, at most 5, and each hop goes through all of the above again.
// - Text only (text/*, json, xml), at most 1 MB read, 15 seconds in all. Nothing is sent but a plain GET.

// -- TYPES -- //
import type { IncomingHttpHeaders } from 'node:http';
// -- DEP-MODULES -- //
import dns from 'node:dns/promises';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';

// -- TYPES -- //

export type Resolved = { address: string; family: 4 | 6 };

export type TransportRequest = {
	url: URL;
	/** The address that passed the check. The connection goes here. */
	address: Resolved;
	signal: AbortSignal;
};

export type TransportResponse = {
	status: number;
	headers: Record<string, string | undefined>;
	body: AsyncIterable<Uint8Array>;
	/** Stops reading. */
	destroy(): void;
};

export type GuardDeps = {
	lookup?: (host: string) => Promise<Resolved[]>;
	transport?: (req: TransportRequest) => Promise<TransportResponse>;
};

export type FetchedPage = {
	url: string;
	status: number;
	contentType: string;
	text: string;
	truncated: boolean;
};

export class FetchRefused extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'FetchRefused';
	}
}

// -- CONSTANTS -- //

const MAX_BYTES = 1_000_000;
const MAX_TEXT_CHARS = 30_000;
const MAX_REDIRECTS = 5;
const TOTAL_TIMEOUT_MS = 15_000;
const TEXT_TYPES = /^(text\/|application\/(json|xml|xhtml\+xml|rss\+xml|atom\+xml|ld\+json))/i;

type Range4 = [string, number];
const BLOCKED_V4: Range4[] = [
	['0.0.0.0', 8],
	['10.0.0.0', 8],
	['100.64.0.0', 10],
	['127.0.0.0', 8],
	['169.254.0.0', 16],
	['172.16.0.0', 12],
	['192.0.0.0', 24],
	['192.0.2.0', 24],
	['192.168.0.0', 16],
	['198.18.0.0', 15],
	['198.51.100.0', 24],
	['203.0.113.0', 24],
	['224.0.0.0', 3]
];

// -- FUNCTIONS -- //

function v4ToInt(addr: string): number | null {
	const parts = addr.split('.').map(Number);
	if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p) || p < 0 || p > 255))
		return null;
	return (
		(((parts[0] as number) << 24) >>> 0) +
		((parts[1] as number) << 16) +
		((parts[2] as number) << 8) +
		(parts[3] as number)
	);
}

function inV4Range(n: number, [base, bits]: Range4): boolean {
	const b = v4ToInt(base) as number;
	const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
	return (n & mask) >>> 0 === (b & mask) >>> 0;
}

/** An IPv6 address as a 128 bit number, or null when it is not one. Handles :: and a trailing dotted IPv4. */
function v6ToBig(addr: string): bigint | null {
	let a = addr.toLowerCase();
	const zone = a.indexOf('%');
	if (zone !== -1) a = a.slice(0, zone);
	const tail = /(\d+\.\d+\.\d+\.\d+)$/.exec(a);
	if (tail) {
		const n = v4ToInt(tail[1] as string);
		if (n === null) return null;
		a = `${a.slice(0, a.length - (tail[1] as string).length)}${(n >>> 16).toString(16)}:${(n & 0xffff).toString(16)}`;
	}
	const halves = a.split('::');
	if (halves.length > 2) return null;
	const head = halves[0] ? (halves[0] as string).split(':') : [];
	const rest = halves.length === 2 && halves[1] ? (halves[1] as string).split(':') : [];
	const missing = 8 - head.length - rest.length;
	if (halves.length === 1 ? head.length !== 8 : missing < 0) return null;
	const groups = [...head, ...Array<string>(halves.length === 2 ? missing : 0).fill('0'), ...rest];
	if (groups.length !== 8) return null;
	let out = 0n;
	for (const g of groups) {
		if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
		out = (out << 16n) | BigInt(parseInt(g, 16));
	}
	return out;
}

// Each prefix is the leading bits of the address, shifted to the top of the 128 bit number
const BLOCKED_V6: [bigint, number][] = [
	[0n, 128], // ::
	[1n, 128], // ::1
	[0xfc00n << 112n, 7], // unique local
	[0xfe80n << 112n, 10], // link local
	[0xff00n << 112n, 8], // multicast
	[0x20010db8n << 96n, 32], // documentation
	[0x20010000n << 96n, 32], // Teredo
	[0x2002n << 112n, 16], // 6to4, carries an IPv4 address
	[0x0064ff9bn << 96n, 96] // NAT64, carries an IPv4 address
];

/** True when the address must never be fetched. A text that is not an address at all is also refused. */
export function isBlockedAddress(addr: string): boolean {
	if (net.isIPv4(addr)) {
		const n = v4ToInt(addr);
		return n === null || BLOCKED_V4.some((r) => inV4Range(n, r));
	}
	if (net.isIPv6(addr)) {
		const big = v6ToBig(addr);
		if (big === null) return true;
		// IPv4 mapped (::ffff:a.b.c.d) and the old compatible form (::a.b.c.d): judge the IPv4 inside
		if (big >> 32n === 0xffffn || (big >> 32n === 0n && big > 1n))
			return isBlockedAddress(
				`${Number((big >> 24n) & 255n)}.${Number((big >> 16n) & 255n)}.${Number((big >> 8n) & 255n)}.${Number(big & 255n)}`
			);
		return BLOCKED_V6.some(([prefix, bits]) => {
			const shift = BigInt(128 - bits);
			return big >> shift === prefix >> shift;
		});
	}
	return true;
}

const defaultLookup = async (host: string): Promise<Resolved[]> =>
	(await dns.lookup(host, { all: true, verbatim: true })).map((a) => ({
		address: a.address,
		family: a.family === 6 ? 6 : 4
	}));

function defaultTransport(req: TransportRequest): Promise<TransportResponse> {
	return new Promise((resolve, reject) => {
		const secure = req.url.protocol === 'https:';
		const mod = secure ? https : http;
		const r = mod.request(
			{
				// Connect to the address that was checked. The name is only for the Host header and the certificate
				host: req.address.address,
				family: req.address.family,
				port: req.url.port || (secure ? 443 : 80),
				method: 'GET',
				path: `${req.url.pathname}${req.url.search}`,
				headers: {
					host: req.url.host,
					'user-agent': 'BotlerBot/1.0',
					accept: 'text/html,text/plain,application/json;q=0.9,*/*;q=0.1',
					'accept-encoding': 'identity'
				},
				...(secure ? { servername: req.url.hostname } : {}),
				signal: req.signal
			},
			(res) => {
				const headers: Record<string, string | undefined> = {};
				for (const [k, v] of Object.entries(res.headers as IncomingHttpHeaders))
					headers[k] = Array.isArray(v) ? v.join(', ') : v;
				resolve({
					status: res.statusCode ?? 0,
					headers,
					body: res,
					destroy: () => res.destroy()
				});
			}
		);
		r.on('error', reject);
		r.end();
	});
}

/** Plain text out of HTML: scripts and styles dropped, tags removed, the common entities decoded, white space collapsed. */
export function htmlToText(html: string): string {
	return html
		.replace(/<(script|style|noscript|svg|template)[\s\S]*?<\/\1>/gi, ' ')
		.replace(/<!--[\s\S]*?-->/g, ' ')
		.replace(/<\/(p|div|li|h[1-6]|tr|br)>|<br\s*\/?>/gi, '\n')
		.replace(/<[^>]+>/g, ' ')
		.replace(/&nbsp;/g, ' ')
		.replace(/&amp;/g, '&')
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"')
		.replace(/&#39;/g, "'")
		.replace(/[ \t]+/g, ' ')
		.replace(/\s*\n\s*/g, '\n')
		.trim();
}

/** Checks an address and returns the one to connect to. Throws FetchRefused with a reason that is safe to show. */
async function vet(url: URL, deps: GuardDeps): Promise<Resolved> {
	if (url.protocol !== 'http:' && url.protocol !== 'https:')
		throw new FetchRefused('Only http and https addresses can be read.');
	if (url.username || url.password)
		throw new FetchRefused('Addresses with a login are not allowed.');
	const port = url.port || (url.protocol === 'https:' ? '443' : '80');
	if (port !== '80' && port !== '443')
		throw new FetchRefused('Only the standard web ports can be read.');
	const host = url.hostname.replace(/^\[|\]$/g, '');
	if (!host) throw new FetchRefused('The address has no host.');
	// Names that only ever mean this machine or a private network are refused without asking DNS
	if (/^(localhost|.+\.(localhost|local|internal|lan|home|corp))$/i.test(host))
		throw new FetchRefused('That address is private or not allowed, so it was not opened.');
	// An address typed as an IP is judged directly, with no name lookup to trick
	const addresses: Resolved[] = net.isIP(host)
		? [{ address: host, family: net.isIPv6(host) ? 6 : 4 }]
		: await (deps.lookup ?? defaultLookup)(host).catch(() => {
				throw new FetchRefused('That address could not be found.');
			});
	if (addresses.length === 0) throw new FetchRefused('That address could not be found.');
	// Every answer must be public: one private answer among many is how rebinding tricks are mixed in
	if (addresses.some((a) => isBlockedAddress(a.address)))
		throw new FetchRefused('That address is private or not allowed, so it was not opened.');
	return addresses[0] as Resolved;
}

async function readBody(res: TransportResponse): Promise<{ bytes: Buffer; truncated: boolean }> {
	const chunks: Buffer[] = [];
	let size = 0;
	let truncated = false;
	for await (const chunk of res.body) {
		const buf = Buffer.from(chunk);
		if (size + buf.length > MAX_BYTES) {
			chunks.push(buf.subarray(0, MAX_BYTES - size));
			truncated = true;
			res.destroy();
			break;
		}
		chunks.push(buf);
		size += buf.length;
	}
	return { bytes: Buffer.concat(chunks), truncated };
}

/** Reads one public web page as text, under all of the rules above. */
export async function fetchPublicText(
	rawUrl: string,
	deps: GuardDeps = {},
	outerSignal?: AbortSignal,
	// `raw` keeps the markup, for the search results page whose links are the point
	opts: { raw?: boolean } = {}
): Promise<FetchedPage> {
	const timeout = AbortSignal.timeout(TOTAL_TIMEOUT_MS);
	const signal = outerSignal ? AbortSignal.any([outerSignal, timeout]) : timeout;
	let url: URL;
	try {
		url = new URL(rawUrl);
	} catch {
		throw new FetchRefused('That is not a web address.');
	}
	const transport = deps.transport ?? defaultTransport;
	for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
		const address = await vet(url, deps);
		let res: TransportResponse;
		try {
			res = await transport({ url, address, signal });
		} catch (e) {
			if (e instanceof FetchRefused) throw e;
			throw new FetchRefused(
				signal.aborted ? 'The page took too long.' : 'The page could not be reached.'
			);
		}
		if (res.status >= 300 && res.status < 400) {
			const location = res.headers.location;
			res.destroy();
			if (!location) throw new FetchRefused('The page redirected nowhere.');
			try {
				url = new URL(location, url);
			} catch {
				throw new FetchRefused('The page redirected to a bad address.');
			}
			continue;
		}
		const contentType = (res.headers['content-type'] ?? '').split(';')[0]?.trim() ?? '';
		if (!TEXT_TYPES.test(contentType)) {
			res.destroy();
			throw new FetchRefused('Only text pages can be read, not files or images.');
		}
		let body: { bytes: Buffer; truncated: boolean };
		try {
			body = await readBody(res);
		} catch {
			throw new FetchRefused(
				signal.aborted ? 'The page took too long.' : 'The page could not be read.'
			);
		}
		const raw = body.bytes.toString('utf8');
		const text = !opts.raw && /html|xml/i.test(contentType) ? htmlToText(raw) : raw.trim();
		const cap = opts.raw ? MAX_BYTES : MAX_TEXT_CHARS;
		return {
			url: url.toString(),
			status: res.status,
			contentType,
			text: text.slice(0, cap),
			truncated: body.truncated || text.length > cap
		};
	}
	throw new FetchRefused('The page redirected too many times.');
}
