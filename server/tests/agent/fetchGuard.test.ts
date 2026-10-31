// THE ADDRESS CHECK BEFORE A PAGE IS SENT TO DEEPSEEK: PRIVATE, LOOPBACK, LINK-LOCAL AND METADATA ADDRESSES, LOCAL NAMES, PORTS, LOGINS AND SCHEMES
// The old in-process reader (DNS pinning, redirect hops, content types, size and time limits, a real local server) is gone: DeepSeek reads
// the page now, so those cases have nothing left to test here.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	checkPublicUrl,
	FetchRefused,
	isBlockedAddress
} from '../../src/lib/server/agent/fetchGuard';

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

describe('checking a page address before it is sent', () => {
	it('returns the parsed address that is also the one sent', () => {
		expect(checkPublicUrl(' https://Example.com/a?b=1#c ')).toBe('https://example.com/a?b=1#c');
		expect(checkPublicUrl('http://example.com:80/x')).toBe('http://example.com/x');
		expect(checkPublicUrl('https://example.com:443/')).toBe('https://example.com/');
		expect(checkPublicUrl('https://93.184.216.34/')).toBe('https://93.184.216.34/');
	});

	it.each([
		'http://localhost/',
		'http://localhost./',
		'http://LOCALHOST/',
		'http://printer.local/',
		'http://db.internal/',
		'http://nas.lan/',
		'http://127.0.0.1/',
		'http://127.0.0.1./',
		'http://[::1]/',
		'http://[::ffff:127.0.0.1]/',
		'http://169.254.169.254/latest/meta-data/',
		'http://10.0.0.1/',
		'http://192.168.1.1/',
		'http://2130706433/',
		'http://0x7f.0.0.1/',
		'http://017700000001/',
		'https://example.com:8443/',
		'http://example.com:8080/',
		'https://user:pw@example.com/',
		'file:///etc/passwd',
		'ftp://example.com/',
		'javascript:alert(1)',
		'not an address',
		''
	])('refuses %s', (u) => {
		expect(() => checkPublicUrl(u), u).toThrow(FetchRefused);
	});

	it('gives a reason that never repeats the address', () => {
		try {
			checkPublicUrl('http://10.9.8.7:1234/secret-path');
		} catch (e) {
			expect((e as Error).message).not.toMatch(/10\.9\.8\.7|secret-path/);
		}
	});
});
