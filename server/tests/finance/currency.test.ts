// CURRENCIES (BTL-20261022-0218, C.1): INTEGER MINOR UNITS ONLY, FORMATTED AND READ BACK FOR PESOS, DOLLARS, EUROS AND ZERO DIGIT CURRENCIES

// -- DEP-MODULES -- //
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	balanceConfirmThreshold,
	CURRENCIES,
	CURRENCY_CODES,
	currencyOf,
	formatMoney,
	isCurrencyCode,
	parseMoney,
	plainAmount
} from '../../src/lib/finance/currency';
import { formatPhp, MAX_CENTAVOS } from '../../src/lib/finance/money';

// -- TESTS -- //

describe('formatting', () => {
	it('shows pesos, dollars and euros with grouping and two decimals', () => {
		expect(formatMoney(18_000, 'PHP')).toBe('₱180.00');
		expect(formatMoney(125_050, 'PHP')).toBe('₱1,250.50');
		expect(formatMoney(123_456_789, 'USD')).toBe('$1,234,567.89');
		expect(formatMoney(5, 'EUR')).toBe('€0.05');
		expect(formatMoney(0, 'GBP')).toBe('£0.00');
	});

	it('shows a zero digit currency without decimals and never divides by 100', () => {
		expect(formatMoney(1_234, 'JPY')).toBe('¥1,234');
		expect(formatMoney(180, 'JPY')).toBe('¥180');
		expect(formatMoney(-1_500_000, 'KRW')).toBe('-₩1,500,000');
		expect(plainAmount(180, 'JPY')).toBe('180');
	});

	it('puts the minus sign first, for every currency', () => {
		expect(formatMoney(-18_000, 'PHP')).toBe('-₱180.00');
		expect(formatMoney(-1, 'USD')).toBe('-$0.01');
	});

	it('agrees with the old peso formatter on every peso amount tried', () => {
		for (const n of [0, 1, 99, 100, 18_000, -18_000, 125_050, 2_147_483_647, -2_147_483_647])
			expect(formatMoney(n, 'PHP')).toBe(formatPhp(n));
	});

	it('refuses a fraction and an unknown code instead of guessing', () => {
		expect(() => formatMoney(1.5, 'PHP')).toThrow(RangeError);
		expect(() => formatMoney(100, 'XXX')).toThrow(RangeError);
	});

	it('gives a text-field amount without the symbol', () => {
		expect(plainAmount(18_000, 'PHP')).toBe('180.00');
		expect(plainAmount(-5, 'USD')).toBe('-0.05');
	});
});

describe('reading what a person typed', () => {
	it('reads plain, grouped and symbol-led amounts', () => {
		expect(parseMoney('180')).toBe(18_000);
		expect(parseMoney('1,250.50')).toBe(125_050);
		expect(parseMoney('₱ 90', 'PHP')).toBe(9_000);
		expect(parseMoney('php 5.5', 'PHP')).toBe(550);
		expect(parseMoney('$5', 'USD')).toBe(500);
		expect(parseMoney('usd 12.05', 'USD')).toBe(1_205);
		expect(parseMoney('S$ 3', 'SGD')).toBe(300);
	});

	it('takes no decimals for a zero digit currency', () => {
		expect(parseMoney('1,500', 'JPY')).toBe(1_500);
		expect(parseMoney('¥200', 'JPY')).toBe(200);
		expect(parseMoney('1500.50', 'JPY')).toBeNull();
	});

	it('refuses what is not an amount, too many decimals and an amount too large', () => {
		for (const bad of ['', 'abc', '1.234', '-5', '5..5', '1e3', '12 34a'])
			expect(parseMoney(bad, 'PHP'), bad).toBeNull();
		expect(parseMoney('21474837', 'PHP')).toBeNull();
		expect(parseMoney('21474836', 'PHP')).toBe(2_147_483_600);
		expect(parseMoney('2147483647', 'JPY')).toBe(MAX_CENTAVOS);
		expect(parseMoney('2147483648', 'JPY')).toBeNull();
	});

	it('round-trips every catalogue currency through plain text', () => {
		for (const c of CURRENCIES)
			for (const n of [0, 1, 99, 100, 123_456]) {
				const text = plainAmount(n, c.code);
				expect(parseMoney(text, c.code), `${c.code} ${text}`).toBe(n);
			}
	});
});

describe('the catalogue', () => {
	it('has unique codes, known digits and the database list in step', () => {
		const codes = CURRENCIES.map((c) => c.code);
		expect(new Set(codes).size).toBe(codes.length);
		for (const c of CURRENCIES) {
			expect([0, 2]).toContain(c.digits);
			expect(isCurrencyCode(c.code)).toBe(true);
			expect(c.code).toMatch(/^[A-Z]{3}$/);
		}
		expect(isCurrencyCode('php')).toBe(false);
		expect(currencyOf('JPY').digits).toBe(0);
	});

	it('scales the confirmation size by the currency, not by the peso', () => {
		// 2,000 pesos
		expect(balanceConfirmThreshold('PHP')).toBe(200_000);
		// About 35 dollars in cents and about 5,500 yen in yen
		expect(balanceConfirmThreshold('USD')).toBe(3_500);
		expect(balanceConfirmThreshold('JPY')).toBe(5_500);
	});
});

describe('the database check', () => {
	it('lists exactly the currencies of the catalogue (a new currency needs a new migration)', () => {
		const dir = join(__dirname, '../../src/lib/server/db/migrations');
		const files = readdirSync(dir)
			.filter((f) => f.endsWith('.sql'))
			.sort();
		// The latest migration that defines the currency check is the one in force
		const last = files
			.filter((f) => readFileSync(join(dir, f), 'utf8').includes('user_setting_currency_chk'))
			.at(-1);
		expect(last).toBeTruthy();
		const sql = readFileSync(join(dir, last ?? ''), 'utf8');
		const line = sql
			.split(/\r?\n/)
			.find((l) => l.includes('user_setting_currency_chk') && l.includes(' in ('));
		const codes = [...(line ?? '').matchAll(/'([A-Z]{3})'/g)].map((m) => m[1]);
		expect(codes).toEqual(CURRENCY_CODES);
	});
});
