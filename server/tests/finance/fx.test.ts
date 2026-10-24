// EXCHANGE RATE ARITHMETIC (BTL-20261023-1407, M3.1): INTEGERS ONLY, THE SMALLEST UNIT OF EACH CURRENCY, HALF AWAY FROM ZERO, UP FOR A RESERVE, A MISSING RATE IS AN ERROR

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	BASE_CURRENCY,
	canConvert,
	convert,
	convertUp,
	isRate,
	MissingRateError,
	rateText,
	showRate
} from '../../src/lib/finance/fx';
import type { Rates } from '../../src/lib/finance/fx';

// -- CONSTANTS -- //

const RATES: Rates = {
	PHP: '56',
	JPY: '157.2',
	EUR: '0.92',
	KWD: '0.307',
	IDR: '16000',
	VND: '25000'
};

// -- TESTS -- //

describe('a rate as text', () => {
	it('accepts a plain positive decimal and nothing else', () => {
		for (const ok of ['1', '56', '0.0000643', '157.2', '16000.123456'])
			expect(isRate(ok), ok).toBe(true);
		for (const bad of ['', '0', '0.0', '-1', '1e3', '1,5', 'abc', ' ', '.5', '5.'])
			expect(isRate(bad), bad).toBe(false);
		expect(isRate(56)).toBe(false);
	});

	it('writes a number from a feed as plain decimal text, never an exponent', () => {
		expect(rateText(56)).toBe('56');
		expect(rateText(56.12)).toBe('56.12');
		expect(rateText(0.0000643)).toBe('0.0000643');
		expect(rateText(1e-7)).toBe('0.0000001');
		expect(rateText(0)).toBeNull();
		expect(rateText(-3)).toBeNull();
		expect(rateText(Number.NaN)).toBeNull();
		expect(rateText(Number.POSITIVE_INFINITY)).toBeNull();
		expect(rateText('56')).toBeNull();
	});
});

describe('converting', () => {
	it('takes the dollar as 1 and needs no rate for it', () => {
		expect(BASE_CURRENCY).toBe('USD');
		expect(convert(10_000, 'USD', 'PHP', RATES)).toBe(560_000);
		expect(convert(560_000, 'PHP', 'USD', RATES)).toBe(10_000);
	});

	it('handles currencies with different digits: yen have none, dinars have three', () => {
		// 157.2 yen to the dollar: 1 USD (100 cents) is 157 yen (rounded from 157.2)
		expect(convert(100, 'USD', 'JPY', RATES)).toBe(157);
		expect(convert(15_720, 'JPY', 'USD', RATES)).toBe(10_000);
		// 0.307 dinars to the dollar: 1 USD is 307 fils
		expect(convert(100, 'USD', 'KWD', RATES)).toBe(307);
		expect(convert(307, 'KWD', 'USD', RATES)).toBe(100);
		// Yen to dinar, through the dollar in one step
		expect(convert(15_720, 'JPY', 'KWD', RATES)).toBe(30_700);
		// Rupiah (2 digits, large numbers) and dong (0 digits)
		expect(convert(100, 'USD', 'IDR', RATES)).toBe(1_600_000);
		expect(convert(100, 'USD', 'VND', RATES)).toBe(25_000);
	});

	it('rounds half away from zero, and a negative amount mirrors a positive one', () => {
		// 1 PHP centavo is 1/56 of a cent: far below half
		expect(convert(1, 'PHP', 'USD', RATES)).toBe(0);
		// 28 centavos is exactly half a cent: rounds away from zero
		expect(convert(28, 'PHP', 'USD', RATES)).toBe(1);
		expect(convert(-28, 'PHP', 'USD', RATES)).toBe(-1);
		expect(convert(27, 'PHP', 'USD', RATES)).toBe(0);
		expect(convert(-27, 'PHP', 'USD', RATES)).toBe(0);
		expect(convert(0, 'PHP', 'USD', RATES)).toBe(0);
		for (const n of [1, 7, 99, 12_345, 987_654])
			expect(convert(-n, 'EUR', 'PHP', RATES)).toBe(-convert(n, 'EUR', 'PHP', RATES));
	});

	it('rounds up in size for a reserve, so it never falls short', () => {
		expect(convertUp(1, 'PHP', 'USD', RATES)).toBe(1);
		expect(convertUp(56, 'PHP', 'USD', RATES)).toBe(1);
		expect(convertUp(57, 'PHP', 'USD', RATES)).toBe(2);
		expect(convertUp(0, 'PHP', 'USD', RATES)).toBe(0);
		expect(convertUp(1_599, 'USD', 'PHP', RATES)).toBe(89_544);
		// Never below the rounded-to-nearest value
		for (const n of [1, 5, 50, 999, 12_345])
			expect(convertUp(n, 'JPY', 'PHP', RATES)).toBeGreaterThanOrEqual(
				convert(n, 'JPY', 'PHP', RATES)
			);
	});

	it('comes back to within a unit or two on a round trip of a large amount', () => {
		for (const [a, b] of [
			['JPY', 'USD'],
			['PHP', 'EUR'],
			['IDR', 'KWD'],
			['USD', 'VND']
		] as const) {
			const start = 1_000_000_00;
			const there = convert(start, a, b, RATES);
			const back = convert(there, b, a, RATES);
			// One minor unit of the middle currency is worth this many of the start currency
			const unit = Math.ceil(Math.abs(convert(1, b, a, RATES))) + 1;
			expect(Math.abs(back - start), `${a} ${b}`).toBeLessThanOrEqual(unit);
		}
	});

	it('is exact where a float would not be', () => {
		// 0.1 + 0.2 style trouble: 3 cents at 0.3 per dollar
		expect(convert(10, 'USD', 'PHP', { PHP: '0.1' })).toBe(1);
		expect(convert(30, 'USD', 'PHP', { PHP: '0.7' })).toBe(21);
		expect(convert(9_007_199_254_740, 'PHP', 'PHP', RATES)).toBe(9_007_199_254_740);
	});

	it('throws for a missing rate or a bad one and never uses zero', () => {
		expect(() => convert(100, 'USD', 'ZAR', RATES)).toThrow(MissingRateError);
		expect(() => convert(100, 'ZAR', 'USD', RATES)).toThrow(MissingRateError);
		expect(() => convert(100, 'USD', 'PHP', { PHP: '0' })).toThrow(MissingRateError);
		expect(() => convert(100, 'USD', 'PHP', { PHP: '-5' })).toThrow(MissingRateError);
		expect(() => convert(100, 'USD', 'PHP', { PHP: 'abc' })).toThrow(MissingRateError);
		try {
			convert(100, 'USD', 'ZAR', RATES);
		} catch (e) {
			expect((e as MissingRateError).code).toBe('ZAR');
		}
		expect(canConvert('USD', 'PHP', RATES)).toBe(true);
		expect(canConvert('USD', 'ZAR', RATES)).toBe(false);
	});

	it('refuses a fraction and an amount that does not fit', () => {
		expect(() => convert(1.5, 'USD', 'PHP', RATES)).toThrow(RangeError);
		expect(() => convert(Number.MAX_SAFE_INTEGER, 'USD', 'IDR', RATES)).toThrow(RangeError);
		// The same currency needs no rate and returns the amount as it is, even for a currency with no rate
		expect(convert(5, 'ZAR', 'ZAR', RATES)).toBe(5);
	});
});

describe('showing a rate', () => {
	it('reads as units of the second currency for one of the first', () => {
		expect(showRate('USD', 'PHP', RATES)).toBe('56');
		expect(showRate('PHP', 'USD', RATES)).toBe('0.0178571');
		expect(showRate('USD', 'JPY', RATES)).toBe('157.2');
		expect(showRate('EUR', 'PHP', RATES)).toBe('60.8696');
		expect(showRate('JPY', 'PHP', RATES)).toBe('0.356234');
	});
});
