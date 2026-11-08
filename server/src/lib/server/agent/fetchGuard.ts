// THE ADDRESS CHECK BEFORE A PAGE IS OPENED: WHAT THE ASSISTANT MAY ASK DEEPSEEK'S FETCH API TO READ
// - The page is read by DeepSeek from its own network, so this server never connects to an address the model picked.
// - Still, an address that only means this machine or a private network is never sent: http and https only, standard ports only (research
//   passes { anyPort: true }, owner decision of 2026-11-08, BTL-20261108-0230; every other caller keeps the port refusal), no login in
//   the address, no local names (localhost, .local, .internal and the like, with or without a trailing dot) and no private, loopback,
//   link-local, carrier-grade NAT, multicast, documentation or cloud metadata IP written as a number (IPv4 and IPv6, including IPv4 hidden
//   in IPv6 forms; numbers written as decimal, hex or octal are normalised by the URL parser first).
// - It is a courtesy filter, not a guard: a name that resolves to a private address is DeepSeek's policy to refuse, not ours.

// -- DEP-MODULES -- //
import net from 'node:net';

// -- TYPES -- //

export class FetchRefused extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'FetchRefused';
	}
}

// -- CONSTANTS -- //

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

/**
 * The address check made before a page address is sent to DeepSeek's Fetch API: http and https only, standard ports only, no login, no name
 * that only means this machine or a private network, no private IP written as a number. Returns the parsed address, which is also the one
 * sent. Throws FetchRefused with a reason that is safe to show.
 */
export function checkPublicUrl(rawUrl: string, opts: { anyPort?: boolean } = {}): string {
	let url: URL;
	try {
		url = new URL(rawUrl.trim());
	} catch {
		throw new FetchRefused('That is not a web address.');
	}
	if (url.protocol !== 'http:' && url.protocol !== 'https:')
		throw new FetchRefused('Only http and https addresses can be read.');
	if (url.username || url.password)
		throw new FetchRefused('Addresses with a login are not allowed.');
	// The default port reads as empty, so any port left is a non standard one
	if (!opts.anyPort && url.port && url.port !== '80' && url.port !== '443')
		throw new FetchRefused('Only the standard web ports can be read.');
	// A trailing dot names the same host, so it must not slip past the name test
	const host = url.hostname.replace(/^\[|\]$/g, '').replace(/\.+$/, '');
	if (!host) throw new FetchRefused('The address has no host.');
	if (/^(localhost|.+\.(localhost|local|internal|lan|home|corp))$/i.test(host))
		throw new FetchRefused('That address is private or not allowed, so it was not opened.');
	if (net.isIP(host) && isBlockedAddress(host))
		throw new FetchRefused('That address is private or not allowed, so it was not opened.');
	return url.href;
}
