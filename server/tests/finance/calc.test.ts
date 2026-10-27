// THE CALCULATOR: EXACT DECIMALS, ROUNDING, THE FINANCE FUNCTIONS AGAINST KNOWN VALUES, DATES, NAMES, AND EVERY WAY A LINE CAN FAIL

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	CALC_LIMITS,
	CalcError,
	calculate,
	toMinorUnits,
	type CalcResult
} from '../../src/lib/finance/calc';

// -- FUNCTIONS -- //

/** One expression's value text. */
function one(expr: string): string {
	const [r] = calculate([{ expr }]);
	if (!r || !r.ok) throw new Error(`"${expr}" failed: ${r && !r.ok ? r.error : 'no result'}`);
	return r.value.text;
}

function failure(expr: string): Extract<CalcResult, { ok: false }> {
	const [r] = calculate([{ expr }]);
	if (!r || r.ok) throw new Error(`"${expr}" should have failed`);
	return r;
}

// -- TESTS -- //

describe('exact arithmetic', () => {
	it('adds decimals without float noise', () => {
		expect(one('0.1 + 0.2')).toBe('0.3');
		expect(one('0.1 * 3')).toBe('0.3');
		expect(one('1.15 + 2.30 + 3.45')).toBe('6.9');
		expect(one('100 - 99.99')).toBe('0.01');
	});

	it('keeps 40 digits of a division and shows it rounded', () => {
		const [r] = calculate([{ expr: '1/3*3' }]);
		expect(r).toMatchObject({
			ok: true,
			value: { text: '0.9999999999999999999999999999999999999999' }
		});
		expect(r && r.ok ? r.shown : '').toBe('1');
		expect(one('1/3')).toBe('0.3333333333333333333333333333333333333333');
		expect(one('10/4')).toBe('2.5');
	});

	it('follows the order of operations, with the power running to the right and a minus below it', () => {
		expect(one('2 + 3 * 4')).toBe('14');
		expect(one('(2 + 3) * 4')).toBe('20');
		expect(one('2^10')).toBe('1024');
		expect(one('2^3^2')).toBe('512');
		expect(one('-2^2')).toBe('-4');
		expect(one('2^-1')).toBe('0.5');
		expect(one('--5')).toBe('5');
		expect(one('10 - 3 - 2')).toBe('5');
		expect(one('100 / 10 / 5')).toBe('2');
	});

	it('reads a percent as a hundredth', () => {
		expect(one('5%')).toBe('0.05');
		expect(one('200 * 5%')).toBe('10');
		expect(one('1000 * (1 + 12%)')).toBe('1120');
		expect(one('50%%')).toBe('0.005');
	});

	it('reads decimals and exponents in numbers', () => {
		expect(one('.5 + 1.')).toBe('1.5');
		expect(one('1e3 + 2.5e-1')).toBe('1000.25');
	});

	it('ignores case and spaces', () => {
		expect(one('  ROUND( 2.5 )  ')).toBe('3');
	});
});

describe('rounding', () => {
	it('rounds half up, away from zero, on exact decimals', () => {
		expect(one('round(2.5)')).toBe('3');
		expect(one('round(-2.5)')).toBe('-3');
		expect(one('round(1.005, 2)')).toBe('1.01');
		expect(one('round(1234.5678, 2)')).toBe('1234.57');
		expect(one('round(0.5)')).toBe('1');
	});

	it('floors and ceils, with places', () => {
		expect(one('floor(-1.5)')).toBe('-2');
		expect(one('ceil(1.2)')).toBe('2');
		expect(one('floor(3.999, 2)')).toBe('3.99');
		expect(one('ceil(3.001, 2)')).toBe('3.01');
		expect(one('abs(-7.25)')).toBe('7.25');
	});

	it('refuses odd places', () => {
		expect(failure('round(1.5, 31)').error).toMatch(/Places/);
		expect(failure('round(1.5, 1.5)').error).toMatch(/whole number/);
		expect(failure('round(1.5, -1)').error).toMatch(/Places/);
	});
});

describe('the list functions', () => {
	it('sums, averages and finds the smallest and largest', () => {
		expect(one('sum(1.1, 2.2, 3.3)')).toBe('6.6');
		expect(one('avg(1, 2, 3, 4)')).toBe('2.5');
		expect(one('min(3, -1, 2)')).toBe('-1');
		expect(one('max(3, -1, 2)')).toBe('3');
		expect(one('sum(5)')).toBe('5');
	});

	it('wants at least one value', () => {
		expect(failure('sum()').error).toMatch(/takes 1 to 200/);
		expect(failure('min()').error).toMatch(/takes/);
	});
});

describe('roots, powers, logs', () => {
	it('works them out to 40 digits', () => {
		expect(one('sqrt(2)').startsWith('1.4142135623730950488016887242096980785')).toBe(true);
		expect(one('sqrt(144)')).toBe('12');
		expect(one('pow(2, 0.5)')).toBe(one('sqrt(2)'));
		expect(one('pow(10, -2)')).toBe('0.01');
		expect(one('ln(1)')).toBe('0');
		expect(one('exp(0)')).toBe('1');
		expect(one('round(ln(10), 6)')).toBe('2.302585');
		expect(one('round(exp(1), 6)')).toBe('2.718282');
	});

	it('refuses what has no answer', () => {
		expect(failure('sqrt(-1)').error).toMatch(/negative/);
		expect(failure('ln(0)').error).toMatch(/above zero/);
		expect(failure('ln(-3)').error).toMatch(/above zero/);
		expect(failure('0^-1').error).toMatch(/negative power/);
		expect(failure('(-8)^0.5').error).toMatch(/fraction/);
		expect(one('0^0')).toBe('1');
		expect(one('(-2)^3')).toBe('-8');
	});
});

describe('the finance functions, against the values a spreadsheet gives', () => {
	it('pmt: the payment of a loan', () => {
		expect(one('round(pmt(0.08/12, 10, 10000), 2)')).toBe('-1037.03');
		expect(one('pmt(0, 10, 1000)')).toBe('-100');
		expect(one('round(pmt(0.05/12, 60, 10000), 2)')).toBe('-188.71');
	});

	it('fv: what a saving grows to', () => {
		expect(one('round(fv(0.06/12, 10, -200, -500, 1), 2)')).toBe('2581.4');
		expect(one('fv(0, 10, -100)')).toBe('1000');
	});

	it('pv: what a stream of payments is worth now', () => {
		expect(one('round(pv(0.08/12, 12*20, 500), 2)')).toBe('-59777.15');
		expect(one('pv(0, 10, 100)')).toBe('-1000');
	});

	it('nper: how long to pay off', () => {
		expect(one('round(nper(0.12/12, -100, -1000, 10000, 1), 2)')).toBe('59.67');
		expect(one('nper(0, -100, 1000)')).toBe('10');
	});

	it('pmt and fv and pv fit together', () => {
		const lines = calculate([
			{ name: 'pay', expr: 'pmt(0.01, 36, 5000)' },
			{ name: 'back', expr: 'round(pv(0.01, 36, -pay), 6)' }
		]);
		expect(lines[1]).toMatchObject({ ok: true, value: { text: '-5000' } });
	});

	it('refuses a loan that never pays off, and too few values', () => {
		expect(failure('nper(0.1, -1, 1000)').error).toMatch(/never pay/);
		expect(failure('nper(0, 0, 1000)').error).toMatch(/payment/);
		expect(failure('pmt(0.1, 0, 1000)').error).toMatch(/periods/);
		expect(failure('pmt(0.1, 12)').error).toMatch(/takes 3 to 5/);
		expect(failure('pv(1, 2, 3, 4, 5, 6)').error).toMatch(/takes 3 to 5/);
	});
});

describe('dates', () => {
	it('counts days between two dates and adds days and months', () => {
		expect(one("days('2026-10-27', '2026-12-31')")).toBe('65');
		expect(one("days('2026-12-31', '2026-10-27')")).toBe('-65');
		expect(one("add_days('2026-12-31', 1)")).toBe('2027-01-01');
		expect(one("add_days('2026-03-01', -1)")).toBe('2026-02-28');
		expect(one("add_months('2026-01-31', 1)")).toBe('2026-02-28');
		expect(one("add_months('2026-03-31', -1)")).toBe('2026-02-28');
		expect(one("add_months('2026-11-15', 3)")).toBe('2027-02-15');
		expect(one("add_months('2024-01-31', 1)")).toBe('2024-02-29');
		expect(one("days(add_days('2026-10-27', 7), '2026-11-10')")).toBe('7');
	});

	it('returns a date as a date and a count as a number', () => {
		const [d, n] = calculate([
			{ expr: "add_days('2026-10-27', 3)" },
			{ expr: "days('2026-10-27', '2026-10-30')" }
		]);
		expect(d).toMatchObject({
			ok: true,
			value: { type: 'date', text: '2026-10-30' },
			shown: '2026-10-30'
		});
		expect(n).toMatchObject({ ok: true, value: { type: 'number', text: '3' } });
	});

	it('does not do arithmetic on a date, and refuses a date that is not one', () => {
		expect(failure("'2026-10-27' + 1").error).toMatch(/needs a number, not a date/);
		expect(failure("'2026-02-30'").error).toMatch(/not a date/);
		expect(failure("'tomorrow'").error).toMatch(/not a date/);
		expect(failure("days('2026-10-27', 5)").error).toMatch(/two dates/);
		expect(failure('add_days(5, 5)').error).toMatch(/date between quotes/);
		expect(failure("add_days('2026-10-27', 1.5)").error).toMatch(/whole number/);
		expect(failure("add_months('2026-10-27', 99999)").error).toMatch(/too many months/);
		expect(failure("add_months('2026-10-27', 1.5)").error).toMatch(/whole number/);
	});
});

describe('named lines', () => {
	it('lets a line use the names and the numbers of the earlier ones', () => {
		const out = calculate([
			{ name: 'pay', expr: '25000' },
			{ name: 'bills', expr: '8000 + 3500.50' },
			{ name: 'left', expr: 'pay - bills' },
			{ expr: 'round(left * 20%, 2)' },
			{ expr: 'line3 + 1' }
		]);
		expect(out.map((r) => (r.ok ? r.value.text : 'x'))).toEqual([
			'25000',
			'11500.5',
			'13499.5',
			'2699.9',
			'13500.5'
		]);
		expect(out[2]).toMatchObject({ line: 3, name: 'left' });
	});

	it('fails a line that uses a failed line, and keeps working on the others', () => {
		const out = calculate([
			{ name: 'a', expr: '1/0' },
			{ name: 'b', expr: 'a + 1' },
			{ expr: 'line2 * 2' },
			{ expr: '2 + 2' }
		]);
		expect(out[0]).toMatchObject({ ok: false, line: 1, error: expect.stringMatching(/zero/) });
		expect(out[1]).toMatchObject({
			ok: false,
			line: 2,
			error: expect.stringMatching(/a could not be worked out/)
		});
		expect(out[2]).toMatchObject({ ok: false, line: 3 });
		expect(out[3]).toMatchObject({ ok: true, value: { text: '4' } });
	});

	it('refuses a name that is used twice, is a function, or is not a name, and a name nobody made', () => {
		const out = calculate([
			{ name: 'x', expr: '1' },
			{ name: 'x', expr: '2' },
			{ name: 'sum', expr: '3' },
			{ name: 'line9', expr: '4' },
			{ name: '9lives', expr: '5' },
			{ name: 'has space', expr: '6' },
			{ expr: 'y + 1' }
		]);
		expect(out.map((r) => r.ok)).toEqual([true, false, false, false, false, false, false]);
		expect(out[1]).toMatchObject({ error: expect.stringMatching(/used twice/) });
		expect(out[2]).toMatchObject({ error: expect.stringMatching(/already taken/) });
		expect(out[3]).toMatchObject({ error: expect.stringMatching(/already taken/) });
		expect(out[4]).toMatchObject({ error: expect.stringMatching(/cannot be a name/) });
		expect(out[6]).toMatchObject({ error: expect.stringMatching(/nothing called y/) });
	});

	it('does not let a line use a name that comes later', () => {
		const out = calculate([{ expr: 'later + 1' }, { name: 'later', expr: '1' }]);
		expect(out[0]).toMatchObject({
			ok: false,
			error: expect.stringMatching(/nothing called later/)
		});
		expect(out[1]).toMatchObject({ ok: true });
	});

	it('is not case sensitive about names', () => {
		const out = calculate([{ name: 'Pay', expr: '10' }, { expr: 'PAY * 2' }]);
		expect(out[1]).toMatchObject({ ok: true, value: { text: '20' } });
	});
});

describe('every way a line can fail says where', () => {
	it('divides by zero at the slash', () => {
		const r = failure('10 + 5 / (3 - 3)');
		expect(r.error).toMatch(/zero/);
		expect(r.position).toBe(7);
	});

	it('names the character, the missing bracket and the missing quote', () => {
		expect(failure('2 $ 3')).toMatchObject({ position: 2, error: expect.stringMatching(/"\$"/) });
		expect(failure('(1 + 2')).toMatchObject({ error: expect.stringMatching(/Expected "\)"/) });
		expect(failure("add_days('2026-10-27, 1)").error).toMatch(/quote/);
		expect(failure('1 +')).toMatchObject({ error: expect.stringMatching(/ends too soon/) });
		expect(failure('1 2')).toMatchObject({
			position: 2,
			error: expect.stringMatching(/Unexpected "2"/)
		});
		expect(failure('')).toMatchObject({ error: expect.stringMatching(/ends too soon/) });
		expect(failure('3x').error).toMatch(/Unexpected "x"/);
		expect(failure('* 3')).toMatchObject({ position: 0 });
	});

	it('knows its functions', () => {
		expect(failure('foo(1)').error).toMatch(/no function called foo/);
		expect(failure('round').error).toMatch(/needs brackets/);
		expect(failure('round(1, 2, 3)').error).toMatch(/takes 1 to 2/);
		expect(failure('abs(1, 2)').error).toMatch(/takes 1 value/);
		expect(failure('pow(2)').error).toMatch(/takes 2 values/);
	});

	it('has no eval: code is just characters it does not know', () => {
		for (const bad of [
			'process.exit()',
			'constructor',
			'__proto__',
			'this',
			'1; 2',
			'a => a',
			'`x`',
			'[1]',
			'{}'
		])
			expect(failure(bad).ok).toBe(false);
		expect(failure('Math.max(1,2)').error).toMatch(/not allowed|no function|Unexpected/);
	});
});

describe('the limits', () => {
	it('refuses a line over 500 characters, a number over 40 digits and more than 60 lines', () => {
		expect(failure('1+'.repeat(300) + '1').error).toMatch(/500 characters/);
		expect(failure('1'.repeat(41)).error).toMatch(/more than 40 digits/);
		expect(one('1'.repeat(40))).toBe('1'.repeat(40));
		expect(() => calculate(Array.from({ length: 61 }, () => ({ expr: '1' })))).toThrow(CalcError);
		expect(calculate(Array.from({ length: 60 }, () => ({ expr: '1' })))).toHaveLength(60);
	});

	it('refuses a power that would be absurdly large, and stays fast', () => {
		const started = Date.now();
		for (const bad of [
			'2^1001',
			'9^9^9',
			'10^1000',
			'10^-1000',
			'99999^999',
			'pow(7, 5000)',
			'(0.5)^1001',
			'exp(5000)'
		])
			expect(failure(bad).ok).toBe(false);
		expect(Date.now() - started).toBeLessThan(1500);
		expect(one('10^999').length).toBe(1000);
		expect(CALC_LIMITS.maxExponent).toBe(1000);
	});

	it('refuses a product that grows past the limit', () => {
		const big = `${'9'.repeat(40)}e900`;
		expect(failure(`${big} * ${big}`).error).toMatch(/too large|not a finite/);
	});

	it('does not repeat the text of a line it cannot read in a plain failure', () => {
		const r = failure('1e999999999999');
		expect(r.error.length).toBeLessThan(120);
	});
});

describe('as an amount of money', () => {
	it('turns a worked out number into whole minor units, rounding half up', () => {
		expect(toMinorUnits('1234.565', 2, 'major')).toBe(123457);
		expect(toMinorUnits('1234.564', 2, 'major')).toBe(123456);
		expect(toMinorUnits('180', 0, 'major')).toBe(180);
		expect(toMinorUnits('1.5', 3, 'major')).toBe(1500);
		expect(toMinorUnits('12.5', 2, 'minor')).toBe(13);
		expect(toMinorUnits('-0.005', 2, 'major')).toBe(-1);
		expect(toMinorUnits('1e30', 2, 'major')).toBeNull();
	});
});
