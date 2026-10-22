// CURRENCIES: ONE PER PERSON (BTL-20261022-0218, ADR 2). AMOUNTS ARE ALWAYS INTEGERS IN THE CURRENCY'S MINOR UNIT (CENTAVOS, CENTS, YEN).
// A float never holds an amount. Changing the currency relabels amounts, it never converts them. The 32 bit cap of money.ts holds for every currency.

// -- MODULES -- //
import { isCentavos } from './money';

// -- TYPES -- //

export type Currency = {
	/** ISO 4217 code. */
	code: string;
	/** What is written in front of an amount. */
	symbol: string;
	/** Digits after the decimal point: 2 for centavos and cents, 0 for yen and won. */
	digits: 0 | 2;
	name: string;
	/** About what 2,000 pesos is worth, in whole units of this currency, for the size of a balance change that must be confirmed. */
	confirmMajor: number;
};

// -- CONSTANTS -- //

export const DEFAULT_CURRENCY = 'PHP';

/** The catalogue. Every code here is valid in the database check and the settings. */
export const CURRENCIES: readonly Currency[] = [
	{ code: 'PHP', symbol: '₱', digits: 2, name: 'Philippine peso', confirmMajor: 2000 },
	{ code: 'USD', symbol: '$', digits: 2, name: 'US dollar', confirmMajor: 35 },
	{ code: 'EUR', symbol: '€', digits: 2, name: 'Euro', confirmMajor: 32 },
	{ code: 'GBP', symbol: '£', digits: 2, name: 'Pound sterling', confirmMajor: 27 },
	{ code: 'JPY', symbol: '¥', digits: 0, name: 'Japanese yen', confirmMajor: 5500 },
	{ code: 'KRW', symbol: '₩', digits: 0, name: 'South Korean won', confirmMajor: 48000 },
	{ code: 'CNY', symbol: 'CN¥', digits: 2, name: 'Chinese yuan', confirmMajor: 250 },
	{ code: 'HKD', symbol: 'HK$', digits: 2, name: 'Hong Kong dollar', confirmMajor: 270 },
	{ code: 'SGD', symbol: 'S$', digits: 2, name: 'Singapore dollar', confirmMajor: 47 },
	{ code: 'AUD', symbol: 'A$', digits: 2, name: 'Australian dollar', confirmMajor: 53 },
	{ code: 'NZD', symbol: 'NZ$', digits: 2, name: 'New Zealand dollar', confirmMajor: 58 },
	{ code: 'CAD', symbol: 'C$', digits: 2, name: 'Canadian dollar', confirmMajor: 48 },
	{ code: 'CHF', symbol: 'CHF ', digits: 2, name: 'Swiss franc', confirmMajor: 31 },
	{ code: 'INR', symbol: '₹', digits: 2, name: 'Indian rupee', confirmMajor: 2900 },
	{ code: 'IDR', symbol: 'Rp', digits: 2, name: 'Indonesian rupiah', confirmMajor: 560000 },
	{ code: 'MYR', symbol: 'RM', digits: 2, name: 'Malaysian ringgit', confirmMajor: 155 },
	{ code: 'THB', symbol: '฿', digits: 2, name: 'Thai baht', confirmMajor: 1200 },
	{ code: 'VND', symbol: '₫', digits: 0, name: 'Vietnamese dong', confirmMajor: 880000 },
	{ code: 'TWD', symbol: 'NT$', digits: 2, name: 'New Taiwan dollar', confirmMajor: 1100 },
	{ code: 'AED', symbol: 'AED ', digits: 2, name: 'UAE dirham', confirmMajor: 130 },
	{ code: 'SAR', symbol: 'SAR ', digits: 2, name: 'Saudi riyal', confirmMajor: 130 }
];

export const CURRENCY_CODES = CURRENCIES.map((c) => c.code);

// -- FUNCTIONS -- //

export const isCurrencyCode = (code: string): boolean => CURRENCIES.some((c) => c.code === code);

/** The currency of a code. An unknown code is a bug, so it throws instead of falling back to pesos. */
export function currencyOf(code: string): Currency {
	const found = CURRENCIES.find((c) => c.code === code);
	if (!found) throw new RangeError(`Unknown currency: ${code}`);
	return found;
}

const group = (whole: string) => whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');

/** ₱1,234.50, $1,234.50 or ¥1,234, with a minus sign for a negative amount. Built from integers, so it is exact. */
export function formatMoney(minor: number, code: string = DEFAULT_CURRENCY): string {
	if (!Number.isSafeInteger(minor)) throw new RangeError('Not an amount in minor units');
	const c = currencyOf(code);
	const abs = Math.abs(minor);
	const sign = minor < 0 ? '-' : '';
	if (c.digits === 0) return `${sign}${c.symbol}${group(String(abs))}`;
	return `${sign}${c.symbol}${group(String(Math.trunc(abs / 100)))}.${String(abs % 100).padStart(2, '0')}`;
}

/** The amount for a text field, without the symbol: 18000 PHP is 180.00 and 180 JPY is 180. */
export function plainAmount(minor: number, code: string = DEFAULT_CURRENCY): string {
	const c = currencyOf(code);
	const abs = Math.abs(minor);
	const sign = minor < 0 ? '-' : '';
	return c.digits === 0
		? `${sign}${abs}`
		: `${sign}${Math.trunc(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

// A currency symbol or code before the digits, which a person may or may not type
const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * What a person typed ("180", "1,250.50", "$ 90", "usd 5") as minor units, or null when it is not an amount of this currency.
 * A currency with no decimals refuses a decimal point. Never goes through a float.
 */
export function parseMoney(text: string, code: string = DEFAULT_CURRENCY): number | null {
	const c = currencyOf(code);
	const prefix = new RegExp(`^(?:${escapeRe(c.symbol.trim())}|${c.code})`, 'i');
	const cleaned = text.trim().replace(prefix, '').replace(/[\s,]/g, '');
	const m = (c.digits === 0 ? /^(\d+)$/ : /^(\d+)(?:\.(\d{1,2}))?$/).exec(cleaned);
	if (!m) return null;
	const whole = Number(m[1]);
	const minor = c.digits === 0 ? whole : whole * 100 + Number((m[2] ?? '').padEnd(2, '0') || '0');
	return isCentavos(minor) ? minor : null;
}

/** The size of a balance change that must be confirmed, in this currency's minor units (2,000 pesos worth). */
export function balanceConfirmThreshold(code: string = DEFAULT_CURRENCY): number {
	const c = currencyOf(code);
	return c.confirmMajor * (c.digits === 0 ? 1 : 100);
}
