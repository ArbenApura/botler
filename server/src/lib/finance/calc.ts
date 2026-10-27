// THE CALCULATOR: EXACT DECIMAL ARITHMETIC FOR WHAT THE ASSISTANT WORKS OUT, WITH A PARSER OF ITS OWN. NO eval, NO FLOATS, NO DATABASE.
// A model is bad at long sums and good at saying what to add, so it writes the lines and this adds them up. Each line is one expression;
// a line may name its result and later lines may use the name (the line before is also `line1`, `line2` ...). Numbers are decimal.js with
// 40 significant digits and half-up rounding, so 0.1 + 0.2 is exactly 0.3. Dates are quoted calendar dates ('2026-12-31') in Manila time.
// Grammar, loosest to tightest:  + -   then   * /   then   unary - +   then   ^ (to the right)   then   postfix %   then   a number, a
// name, a function call or a bracket. So -2^2 is -4, and 5% is 0.05 (write 200 * 5% for five percent of 200).
// Functions: round floor ceil (value, places), abs min max sum avg sqrt pow ln exp, the finance functions pmt fv pv nper (the sign rules of
// a spreadsheet: money you pay out is negative), and the dates days add_days add_months.
// Limits keep a hostile or careless line cheap: the length of a line, the number of lines, the size of a number and of an exponent.
// A line that fails says where (its number and the character position); a later line that uses it fails too, and the others still run.

// -- DEP-MODULES -- //
import Decimal from 'decimal.js';
// -- MODULES -- //
import { addDays, daysInMonth, diffDays, formatDate, isDate, parseDate } from './dates';

// -- TYPES -- //

export type CalcLine = { name?: string; expr: string };

export type CalcValue = { type: 'number' | 'date'; text: string };

export type CalcResult =
	| {
			ok: true;
			line: number;
			name: string | null;
			/** The value, in full: up to 40 digits for a number, YYYY-MM-DD for a date. */
			value: CalcValue;
			/** A number rounded to 10 decimal places, so 1/3*3 reads 1. Equal to the value for a date. */
			shown: string;
	  }
	| { ok: false; line: number; name: string | null; error: string; position: number | null };

type Num = InstanceType<typeof Decimal>;

type V = { t: 'n'; v: Num } | { t: 'd'; v: string };

type Token =
	| { k: 'num'; text: string; at: number }
	| { k: 'id'; text: string; at: number }
	| { k: 'str'; text: string; at: number }
	| { k: 'op'; text: string; at: number }
	| { k: 'end'; text: ''; at: number };

// -- CONSTANTS -- //

export const CALC_LIMITS = {
	maxLines: 60,
	maxExprChars: 500,
	maxNumberDigits: 40,
	/** The most a power or a result may grow or shrink: a power of ten past this is refused. */
	maxExponent: 1000,
	maxPowerOperand: 1000,
	maxMonths: 12_000,
	maxDays: 3_660_000,
	maxNameChars: 40
};

const D = Decimal.clone({
	precision: 40,
	rounding: Decimal.ROUND_HALF_UP,
	toExpNeg: -1000,
	toExpPos: 1000,
	minE: -1000,
	maxE: 1000
});

const NAME = /^[a-z_][a-z0-9_]*$/;

const FUNCTIONS = new Set([
	'round',
	'floor',
	'ceil',
	'abs',
	'min',
	'max',
	'sum',
	'avg',
	'sqrt',
	'pow',
	'ln',
	'exp',
	'pmt',
	'fv',
	'pv',
	'nper',
	'days',
	'add_days',
	'add_months'
]);

// -- FUNCTIONS -- //

/** A line that cannot be worked out, and where. */
export class CalcError extends Error {
	constructor(
		message: string,
		readonly position: number | null = null
	) {
		super(message);
		this.name = 'CalcError';
	}
}

function tokenize(src: string): Token[] {
	const out: Token[] = [];
	let i = 0;
	while (i < src.length) {
		const c = src[i] ?? '';
		if (/\s/.test(c)) {
			i++;
		} else if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] ?? ''))) {
			const m = /^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/.exec(src.slice(i));
			const text = m?.[0] ?? c;
			// Only the digits of the number itself count, not those of its exponent
			const digits = (text.split(/[eE]/)[0] ?? '').replace(/[^0-9]/g, '').replace(/^0+/, '');
			if (digits.length > CALC_LIMITS.maxNumberDigits)
				throw new CalcError(`A number has more than ${CALC_LIMITS.maxNumberDigits} digits.`, i);
			out.push({ k: 'num', text, at: i });
			i += text.length;
		} else if (/[a-zA-Z_]/.test(c)) {
			const m = /^[a-zA-Z_][a-zA-Z0-9_]*/.exec(src.slice(i));
			const text = (m?.[0] ?? c).toLowerCase();
			out.push({ k: 'id', text, at: i });
			i += (m?.[0] ?? c).length;
		} else if (c === "'" || c === '"') {
			const end = src.indexOf(c, i + 1);
			if (end < 0) throw new CalcError('A quote is never closed.', i);
			out.push({ k: 'str', text: src.slice(i + 1, end), at: i });
			i = end + 1;
		} else if ('+-*/^%(),'.includes(c)) {
			out.push({ k: 'op', text: c, at: i });
			i++;
		} else throw new CalcError(`The character "${c}" is not allowed here.`, i);
	}
	out.push({ k: 'end', text: '', at: src.length });
	return out;
}

/** A result that has grown or shrunk past what is allowed is refused instead of being carried on. */
function checked(v: Num, at: number): Num {
	if (!v.isFinite()) throw new CalcError('The result is not a finite number.', at);
	if (!v.isZero() && Math.abs(v.e) >= CALC_LIMITS.maxExponent)
		throw new CalcError('The number is too large or too small.', at);
	return v;
}

const num = (v: V, at: number, what: string): Num => {
	if (v.t !== 'n') throw new CalcError(`${what} needs a number, not a date.`, at);
	return v.v;
};

const whole = (v: Num, at: number, what: string): number => {
	if (!v.isInteger() || v.abs().gt(CALC_LIMITS.maxDays))
		throw new CalcError(`${what} must be a whole number.`, at);
	return v.toNumber();
};

/** Adds months to a date, keeping the day or the last day of a shorter month. */
function addMonths(date: string, n: number): string {
	const p = parseDate(date);
	if (!p) throw new CalcError(`"${date}" is not a date written YYYY-MM-DD.`);
	const index = p.year * 12 + (p.month - 1) + n;
	const year = Math.floor(index / 12);
	const month = (index % 12) + 1;
	return formatDate(year, month, Math.min(p.day, daysInMonth(year, month)));
}

/** The finance functions follow a spreadsheet: pv, pmt and fv have opposite signs when money goes out and comes back. */
function finance(name: string, a: Num[], at: number): Num {
	const arg = (i: number, fallback: number) => a[i] ?? new D(fallback);
	const rate = arg(0, 0);
	const growth = (n: Num) => rate.plus(1).pow(n);
	const zero = rate.isZero();
	switch (name) {
		case 'pv': {
			const [n, pmt, fv, type] = [arg(1, 0), arg(2, 0), arg(3, 0), arg(4, 0)];
			if (zero) return fv.plus(pmt.times(n)).neg();
			const g = growth(n);
			return fv
				.plus(pmt.times(rate.times(type).plus(1)).times(g.minus(1)).div(rate))
				.div(g)
				.neg();
		}
		case 'fv': {
			const [n, pmt, pv, type] = [arg(1, 0), arg(2, 0), arg(3, 0), arg(4, 0)];
			if (zero) return pv.plus(pmt.times(n)).neg();
			const g = growth(n);
			return pv
				.times(g)
				.plus(pmt.times(rate.times(type).plus(1)).times(g.minus(1)).div(rate))
				.neg();
		}
		case 'pmt': {
			const [n, pv, fv, type] = [arg(1, 0), arg(2, 0), arg(3, 0), arg(4, 0)];
			if (n.isZero()) throw new CalcError('pmt needs a number of periods above zero.', at);
			if (zero) return pv.plus(fv).div(n).neg();
			const g = growth(n);
			return fv
				.plus(pv.times(g))
				.times(rate)
				.div(rate.times(type).plus(1).times(g.minus(1)))
				.neg();
		}
		default: {
			// nper
			const [pmt, pv, fv, type] = [arg(1, 0), arg(2, 0), arg(3, 0), arg(4, 0)];
			if (zero) {
				if (pmt.isZero())
					throw new CalcError('nper needs a payment above zero when the rate is zero.', at);
				return pv.plus(fv).div(pmt).neg();
			}
			const pay = pmt.times(rate.times(type).plus(1));
			const top = pay.minus(fv.times(rate));
			const bottom = pay.plus(pv.times(rate));
			const ratio = top.div(bottom);
			if (!ratio.isFinite() || ratio.lte(0))
				throw new CalcError('These numbers never pay it off: nper has no answer.', at);
			return ratio.ln().div(rate.plus(1).ln());
		}
	}
}

/** One expression, worked out, with the values of the earlier lines available by name. */
function evaluate(src: string, scope: ReadonlyMap<string, V | CalcError>): V {
	if (src.length > CALC_LIMITS.maxExprChars)
		throw new CalcError(`A line may be at most ${CALC_LIMITS.maxExprChars} characters.`);
	const tokens = tokenize(src);
	let p = 0;
	const peek = () => tokens[p] ?? { k: 'end' as const, text: '', at: src.length };
	const take = () => tokens[p++] ?? peek();
	const isOp = (text: string) => peek().k === 'op' && peek().text === text;
	const expect = (text: string) => {
		if (!isOp(text)) throw new CalcError(`Expected "${text}".`, peek().at);
		take();
	};

	const call = (name: string, at: number): V => {
		expect('(');
		const args: V[] = [];
		if (!isOp(')'))
			for (;;) {
				args.push(sum());
				if (isOp(',')) take();
				else break;
			}
		expect(')');
		const n = args.length;
		const need = (min: number, max = min) => {
			if (n < min || n > max)
				throw new CalcError(
					`${name} takes ${min === max ? min : `${min} to ${max}`} value${max === 1 ? '' : 's'}, not ${n}.`,
					at
				);
		};
		const nums = () => args.map((a) => num(a, at, name));
		switch (name) {
			case 'round':
			case 'floor':
			case 'ceil': {
				need(1, 2);
				const places = n === 2 ? whole(num(args[1] as V, at, name), at, `${name} places`) : 0;
				if (places < 0 || places > 30) throw new CalcError('Places must be from 0 to 30.', at);
				const mode =
					name === 'round' ? D.ROUND_HALF_UP : name === 'floor' ? D.ROUND_FLOOR : D.ROUND_CEIL;
				return { t: 'n', v: num(args[0] as V, at, name).toDecimalPlaces(places, mode) };
			}
			case 'abs':
				need(1);
				return { t: 'n', v: num(args[0] as V, at, name).abs() };
			case 'min':
			case 'max':
			case 'sum':
			case 'avg': {
				need(1, 200);
				const all = nums();
				if (name === 'min') return { t: 'n', v: D.min(...all) };
				if (name === 'max') return { t: 'n', v: D.max(...all) };
				const total = all.reduce((x, y) => x.plus(y), new D(0));
				return { t: 'n', v: checked(name === 'sum' ? total : total.div(n), at) };
			}
			case 'sqrt': {
				need(1);
				const x = num(args[0] as V, at, name);
				if (x.isNegative()) throw new CalcError('sqrt of a negative number has no answer.', at);
				return { t: 'n', v: x.sqrt() };
			}
			case 'ln': {
				need(1);
				const x = num(args[0] as V, at, name);
				if (x.lte(0)) throw new CalcError('ln needs a number above zero.', at);
				return { t: 'n', v: x.ln() };
			}
			case 'exp': {
				need(1);
				const x = num(args[0] as V, at, name);
				if (x.abs().gt(2300)) throw new CalcError('exp of a number this size is too large.', at);
				return { t: 'n', v: checked(x.exp(), at) };
			}
			case 'pow': {
				need(2);
				return { t: 'n', v: power(num(args[0] as V, at, name), num(args[1] as V, at, name), at) };
			}
			case 'pmt':
			case 'fv':
			case 'pv':
				need(3, 5);
				return { t: 'n', v: checked(finance(name, nums(), at), at) };
			case 'nper':
				need(3, 5);
				return { t: 'n', v: checked(finance(name, nums(), at), at) };
			case 'days': {
				need(2);
				const [a, b] = args;
				if (a?.t !== 'd' || b?.t !== 'd')
					throw new CalcError('days needs two dates written between quotes, YYYY-MM-DD.', at);
				return { t: 'n', v: new D(diffDays(b.v, a.v)) };
			}
			case 'add_days': {
				need(2);
				const [a, b] = args;
				if (a?.t !== 'd') throw new CalcError('add_days needs a date between quotes first.', at);
				return { t: 'd', v: addDays(a.v, whole(num(b as V, at, name), at, 'The days')) };
			}
			default: {
				// add_months
				need(2);
				const [a, b] = args;
				if (a?.t !== 'd') throw new CalcError('add_months needs a date between quotes first.', at);
				const months = whole(num(b as V, at, name), at, 'The months');
				if (Math.abs(months) > CALC_LIMITS.maxMonths)
					throw new CalcError('That is too many months.', at);
				return { t: 'd', v: addMonths(a.v, months) };
			}
		}
	};

	/** x to the power y, refused when the answer would be absurdly large or small, or has no real value. */
	const power = (x: Num, y: Num, at: number): Num => {
		if (y.abs().gt(CALC_LIMITS.maxPowerOperand))
			throw new CalcError(`An exponent may be at most ${CALC_LIMITS.maxPowerOperand}.`, at);
		if (x.isZero()) {
			if (y.isNegative()) throw new CalcError('Zero cannot be raised to a negative power.', at);
			return y.isZero() ? new D(1) : new D(0);
		}
		if (x.isNegative() && !y.isInteger())
			throw new CalcError('A negative number cannot be raised to a fraction.', at);
		// Digits of the answer: |y| * log10|x|. Past the limit it is refused before it is worked out
		const size = y.abs().times(x.abs().log(10));
		if (size.abs().gte(CALC_LIMITS.maxExponent))
			throw new CalcError('The power is too large or too small.', at);
		return checked(x.pow(y), at);
	};

	const primary = (): V => {
		const t = take();
		if (t.k === 'num') return { t: 'n', v: checked(new D(t.text), t.at) };
		if (t.k === 'str') {
			if (!isDate(t.text))
				throw new CalcError(`"${t.text}" is not a date written YYYY-MM-DD.`, t.at);
			return { t: 'd', v: t.text };
		}
		if (t.k === 'id') {
			if (isOp('(')) {
				if (!FUNCTIONS.has(t.text))
					throw new CalcError(`There is no function called ${t.text}.`, t.at);
				return call(t.text, t.at);
			}
			if (FUNCTIONS.has(t.text)) throw new CalcError(`${t.text} needs brackets and values.`, t.at);
			const known = scope.get(t.text);
			if (known === undefined)
				throw new CalcError(`There is nothing called ${t.text} before this line.`, t.at);
			if (known instanceof CalcError)
				throw new CalcError(
					`${t.text} could not be worked out, so this line cannot be either.`,
					t.at
				);
			return known;
		}
		if (t.k === 'op' && t.text === '(') {
			const inner = sum();
			expect(')');
			return inner;
		}
		throw new CalcError(
			t.k === 'end' ? 'The line ends too soon.' : `Unexpected "${t.text}".`,
			t.at
		);
	};

	const postfix = (): V => {
		let v = primary();
		while (isOp('%')) {
			const at = take().at;
			v = { t: 'n', v: checked(num(v, at, 'A percent').div(100), at) };
		}
		return v;
	};

	const pow = (): V => {
		const base = postfix();
		if (isOp('^')) {
			const at = take().at;
			// The exponent may carry its own sign, and the power runs to the right: 2^3^2 is 2^9
			const exponent = unary();
			return { t: 'n', v: power(num(base, at, '^'), num(exponent, at, '^'), at) };
		}
		return base;
	};

	const unary = (): V => {
		if (isOp('-') || isOp('+')) {
			const t = take();
			const v = unary();
			return t.text === '-' ? { t: 'n', v: num(v, t.at, 'A minus sign').neg() } : v;
		}
		return pow();
	};

	const product = (): V => {
		let left = unary();
		while (isOp('*') || isOp('/')) {
			const t = take();
			const right = unary();
			const a = num(left, t.at, t.text);
			const b = num(right, t.at, t.text);
			if (t.text === '/' && b.isZero())
				throw new CalcError('Dividing by zero has no answer.', t.at);
			left = { t: 'n', v: checked(t.text === '*' ? a.times(b) : a.div(b), t.at) };
		}
		return left;
	};

	function sum(): V {
		let left = product();
		while (isOp('+') || isOp('-')) {
			const t = take();
			const right = product();
			const a = num(left, t.at, t.text);
			const b = num(right, t.at, t.text);
			left = { t: 'n', v: checked(t.text === '+' ? a.plus(b) : a.minus(b), t.at) };
		}
		return left;
	}

	const value = sum();
	if (peek().k !== 'end') throw new CalcError(`Unexpected "${peek().text}".`, peek().at);
	return value;
}

const shownOf = (v: V): string =>
	v.t === 'd' ? v.v : v.v.toDecimalPlaces(10, D.ROUND_HALF_UP).toFixed();

/**
 * Works out the lines in order. A line that fails is reported with its place and does not stop the others; a later line that uses its name
 * fails too. A name must be lowercase letters, digits and underscores, not a function, and not used twice.
 */
export function calculate(lines: CalcLine[]): CalcResult[] {
	if (lines.length > CALC_LIMITS.maxLines)
		throw new CalcError(`At most ${CALC_LIMITS.maxLines} lines at a time.`);
	const scope = new Map<string, V | CalcError>();
	const taken = new Set<string>();
	return lines.map((line, i): CalcResult => {
		const n = i + 1;
		const name = line.name ? line.name.trim().toLowerCase() : null;
		const fail = (e: CalcError): CalcResult => {
			scope.set(`line${n}`, e);
			if (name) scope.set(name, e);
			return { ok: false, line: n, name, error: e.message, position: e.position };
		};
		if (name !== null) {
			if (!NAME.test(name) || name.length > CALC_LIMITS.maxNameChars)
				return fail(
					new CalcError(`"${line.name}" cannot be a name: use letters, digits and underscores.`)
				);
			if (FUNCTIONS.has(name) || /^line[0-9]+$/.test(name))
				return fail(new CalcError(`"${name}" is already taken: choose another name.`));
			if (taken.has(name)) return fail(new CalcError(`The name ${name} is used twice.`));
			taken.add(name);
		}
		try {
			const v = evaluate(line.expr, scope);
			scope.set(`line${n}`, v);
			if (name) scope.set(name, v);
			return {
				ok: true,
				line: n,
				name,
				value: { type: v.t === 'n' ? 'number' : 'date', text: v.t === 'n' ? v.v.toFixed() : v.v },
				shown: shownOf(v)
			};
		} catch (e) {
			if (e instanceof CalcError) return fail(e);
			// Decimal's own refusals (an invalid number) are plain errors: nothing of the text is repeated
			return fail(new CalcError('That line could not be worked out.'));
		}
	});
}

/**
 * A worked-out number as a whole amount in the smallest unit of a currency: `unit` says whether the number is in the currency's own unit
 * (pesos, dollars, yen) or already in the smallest one (centavos, cents). Rounded half up. Null when it is not a safe integer.
 */
export function toMinorUnits(text: string, digits: number, unit: 'major' | 'minor'): number | null {
	const minor = new D(text)
		.times(unit === 'major' ? new D(10).pow(digits) : 1)
		.toDecimalPlaces(0, D.ROUND_HALF_UP);
	return minor.abs().lte(Number.MAX_SAFE_INTEGER) ? minor.toNumber() : null;
}
