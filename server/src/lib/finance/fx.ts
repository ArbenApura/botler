// EXCHANGE RATES AS EXACT ARITHMETIC (BTL-20261023-1407, M3). A RATE IS A DECIMAL STRING: HOW MANY UNITS OF A CURRENCY BUY ONE US DOLLAR.
// An amount is converted with integers only (BigInt): no float ever holds money. The result is rounded to the smallest unit of the target,
// half away from zero, or up when a reserve must never be short. A currency with no rate throws instead of being counted as zero.

// -- MODULES -- //
import { currencyOf } from './currency';
import { isMinorAmount } from './money';

// -- TYPES -- //

/** Units of a currency per one US dollar, as plain decimal text ("56.1234", "157.2"). USD itself is always 1 and is not listed. */
export type Rates = Readonly<Record<string, string>>;

// -- CONSTANTS -- //

/** The currency every rate is quoted against. */
export const BASE_CURRENCY = 'USD';

/** The most decimals of a rate that are kept: rates are approximate by nature, and this is far finer than any minor unit needs. */
const MAX_RATE_DECIMALS = 18;

// -- TYPES -- //

/** Thrown when a conversion needs a rate that is not known. Callers show it as "missing rate" and never use zero in its place. */
export class MissingRateError extends Error {
	constructor(readonly code: string) {
		super(`No exchange rate for ${code}`);
		this.name = 'MissingRateError';
	}
}

// -- FUNCTIONS -- //

/** A decimal string as a fraction of two BigInts, or null when it is not a positive plain decimal. */
function fraction(text: string): { n: bigint; d: bigint } | null {
	const m = /^(\d+)(?:\.(\d{1,18}))?$/.exec(text.trim());
	if (!m) return null;
	const frac = m[2] ?? '';
	const n = BigInt(`${m[1]}${frac}`);
	if (n === 0n) return null;
	return { n, d: 10n ** BigInt(frac.length) };
}

/** Whether a rate is usable: a positive plain decimal, no exponent, no sign, not zero. */
export const isRate = (text: unknown): text is string =>
	typeof text === 'string' && fraction(text) !== null;

/**
 * A number from a data feed as plain decimal text, so it can be stored and read back exactly: 0.0000643 stays 0.0000643 and never becomes
 * 6.43e-5. Null for anything that is not a positive finite number.
 */
export function rateText(value: unknown): string | null {
	if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return null;
	const text = value.toString();
	const plain = /e/i.test(text) ? value.toFixed(MAX_RATE_DECIMALS) : text;
	const trimmed = plain.includes('.') ? plain.replace(/0+$/, '').replace(/\.$/, '') : plain;
	return isRate(trimmed) ? trimmed : null;
}

function rateOf(code: string, rates: Rates): { n: bigint; d: bigint } {
	if (code === BASE_CURRENCY) return { n: 1n, d: 1n };
	const text = rates[code];
	const f = text === undefined ? null : fraction(text);
	if (!f) throw new MissingRateError(code);
	return f;
}

/** Whether both currencies can be converted with these rates. */
export function canConvert(from: string, to: string, rates: Rates): boolean {
	try {
		rateOf(from, rates);
		rateOf(to, rates);
		return true;
	} catch {
		return false;
	}
}

function convertWith(
	minor: number,
	from: string,
	to: string,
	rates: Rates,
	mode: 'nearest' | 'up'
): number {
	if (!Number.isSafeInteger(minor)) throw new RangeError('Not an amount in minor units');
	if (from === to) return minor;
	const f = rateOf(from, rates);
	const t = rateOf(to, rates);
	const per = (code: string) => 10n ** BigInt(currencyOf(code).digits);
	// minor_to = minor * (rate_to / rate_from) * 10^digits_to / 10^digits_from, as one fraction
	const num = BigInt(minor) * t.n * f.d * per(to);
	const den = t.d * f.n * per(from);
	const negative = num < 0n;
	const abs = negative ? -num : num;
	let q = abs / den;
	const r = abs % den;
	if (mode === 'up' ? r > 0n : r * 2n >= den) q += 1n;
	const out = Number(negative ? -q : q);
	if (!isMinorAmount(out)) throw new RangeError('The converted amount is out of range');
	return out;
}

/**
 * An amount in the minor units of one currency as the minor units of another, by the stored rates. Rounded to the nearest minor unit, half
 * away from zero. Throws MissingRateError when a rate is not known.
 */
export const convert = (minor: number, from: string, to: string, rates: Rates): number =>
	convertWith(minor, from, to, rates, 'nearest');

/** Like convert, but rounded up in size (away from zero), for a reserve that must never fall short. */
export const convertUp = (minor: number, from: string, to: string, rates: Rates): number =>
	convertWith(minor, from, to, rates, 'up');

/**
 * How many units of `to` one unit of `from` buys, as text with up to six significant decimals, for showing a rate ("1 USD = 56.12 PHP").
 * Only for display: nothing is computed from it.
 */
export function showRate(from: string, to: string, rates: Rates): string {
	const f = rateOf(from, rates);
	const t = rateOf(to, rates);
	// (t.n / t.d) / (f.n / f.d) as one fraction
	const num = t.n * f.d;
	const den = t.d * f.n;
	const whole = num / den;
	// Six significant digits: a rate above 1 keeps what is left of six after its whole part, a small one counts from its first digit
	let decimals = whole > 0n ? Math.max(2, 6 - whole.toString().length) : 6;
	if (whole === 0n) while (num * 10n ** BigInt(decimals - 5) < den) decimals++;
	const scaled = (num * 10n ** BigInt(decimals) * 2n + den) / (den * 2n);
	const text = scaled.toString().padStart(decimals + 1, '0');
	const int = text.slice(0, text.length - decimals);
	const frac = text.slice(text.length - decimals).replace(/0+$/, '');
	return frac ? `${int}.${frac}` : int;
}

/**
 * Whether a new rate is more than `factor` times above or below the old one (both decimal text). A jump like that is far more likely a bad
 * value from the source than a real move, so it is not stored. False when either text is not a rate.
 */
export function movedTooFar(oldRate: string, newRate: string, factor = 3): boolean {
	const o = fraction(oldRate);
	const n = fraction(newRate);
	if (!o || !n) return false;
	const k = BigInt(factor);
	// new/old > k  or  new/old < 1/k, cross multiplied: n.n * o.d versus k * o.n * n.d
	const up = n.n * o.d > k * o.n * n.d;
	const down = k * n.n * o.d < o.n * n.d;
	return up || down;
}
