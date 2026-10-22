// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { isAllowed, normaliseEmail, parseAllowList } from './allowlist';

describe('allow-list', () => {
	it('normalises case and spaces', () => {
		expect(normaliseEmail('  Arben@Example.COM ')).toBe('arben@example.com');
	});

	it('accepts a listed address in any case', () => {
		const allow = parseAllowList('arben@example.com, Other@Example.com');
		expect(isAllowed(allow, 'ARBEN@example.com')).toBe(true);
		expect(isAllowed(allow, 'other@example.com')).toBe(true);
	});

	it('refuses an address that is not listed, and empty values', () => {
		const allow = parseAllowList('arben@example.com');
		expect(isAllowed(allow, 'stranger@example.com')).toBe(false);
		expect(isAllowed(allow, '')).toBe(false);
		expect(isAllowed(allow, null)).toBe(false);
		expect(isAllowed(allow, undefined)).toBe(false);
	});

	it('does not match a partial or look-alike address', () => {
		const allow = parseAllowList('arben@example.com');
		expect(isAllowed(allow, 'arben@example.com.evil.test')).toBe(false);
		expect(isAllowed(allow, 'xarben@example.com')).toBe(false);
	});

	it('fails loudly on an empty or malformed list instead of opening registration', () => {
		expect(() => parseAllowList(undefined)).toThrow(/ALLOWED_EMAILS is required/);
		expect(() => parseAllowList('')).toThrow(/ALLOWED_EMAILS is required/);
		expect(() => parseAllowList(' , ')).toThrow(/ALLOWED_EMAILS is required/);
		expect(() => parseAllowList('not-an-email')).toThrow(/bad address/);
	});
});
