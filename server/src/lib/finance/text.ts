// PLAIN WORDS TO STRUCTURE, WITHOUT A MODEL: "lunch 180 gcash" BECOMES AN EXPENSE AND "20% to savings" BECOMES A RULE.
// These work when the model is down or its cap is reached. Anything they cannot read is refused with a reason, never guessed.

// -- TYPES -- //
import type { RuleBase, RuleMode } from './rules';
// -- MODULES -- //
import { CURRENCIES, currencyOf, DEFAULT_CURRENCY } from './currency';

// -- TYPES -- //

export type ParsedExpense = {
	/** Minor units of currency, or null when no amount was found. */
	amount: number | null;
	/** The currency the text names (a symbol or a code in front of the number), or null when it names none. */
	currency: string | null;
	note: string;
	category: string;
	/** The account name as the person has it, or null when none was named. */
	accountName: string | null;
	/** More than one number was found, so the last was taken and the person should check. */
	ambiguous: boolean;
};

export type RuleTargetName = { kind: 'account' | 'goal'; id: string; name: string };

export type ParsedRule =
	| {
			ok: true;
			mode: RuleMode;
			amount: number | null;
			basisPoints: number | null;
			base: RuleBase;
			target: { kind: 'account' | 'goal'; id: string };
			label: string;
	  }
	| { ok: false; reason: string };

// -- CONSTANTS -- //

const CATEGORY_WORDS: Record<string, string[]> = {
	food: [
		'lunch',
		'dinner',
		'breakfast',
		'merienda',
		'meryenda',
		'kain',
		'coffee',
		'kape',
		'jollibee',
		'mcdo',
		'food',
		'snack',
		'groceries',
		'grocery',
		'milk tea'
	],
	transport: [
		'grab',
		'angkas',
		'jeep',
		'jeepney',
		'mrt',
		'lrt',
		'fare',
		'gas',
		'gasolina',
		'parking',
		'toll',
		'taxi',
		'bus',
		'tricycle'
	],
	bills: ['meralco', 'water', 'internet', 'wifi', 'load', 'electric', 'rent', 'subscription'],
	shopping: ['shopee', 'lazada', 'mall', 'clothes', 'shoes', 'bili'],
	health: ['gamot', 'medicine', 'doctor', 'clinic', 'pharmacy', 'mercury'],
	fun: ['movie', 'sinehan', 'game', 'netflix', 'spotify', 'inom', 'bar']
};

/**
 * Codes a person may write in any case ("usd 5", "Eur 3"): none of them is an ordinary word. Every other code is read only when it is
 * written in capitals ("MOP 150"), because "mop 150", "pen 25", "top 200", "cup 40" or "all 5" are an expense and not a currency.
 */
const ANY_CASE_CODES = new Set([
	'PHP',
	'USD',
	'EUR',
	'GBP',
	'JPY',
	'KRW',
	'CNY',
	'HKD',
	'SGD',
	'AUD',
	'NZD',
	'CAD',
	'CHF',
	'INR',
	'IDR',
	'MYR',
	'THB',
	'VND',
	'TWD',
	'AED',
	'SAR',
	'SEK',
	'NOK',
	'DKK',
	'PLN',
	'BRL',
	'MXN',
	'ZAR',
	'RUB',
	'ILS',
	'NGN',
	'EGP',
	'PKR',
	'BDT',
	'LKR',
	'NPR',
	'KWD',
	'QAR',
	'BHD',
	'OMR',
	'JOD',
	'CZK',
	'HUF',
	'UAH',
	'KES',
	'GHS',
	'COP',
	'CLP'
]);

/** A letter in either case, written out, so the pattern needs no case flag (the digits and the "k" are handled the same way). */
const anyCase = (t: string) =>
	t.replace(/[a-z]/gi, (c) => `[${c.toLowerCase()}${c.toUpperCase()}]`);
const escapeToken = (t: string) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// A currency symbol or code of the catalogue (₱, $, usd, S$ ...) or a "p" before the digits, then digits with optional thousands commas and
// decimals, and an optional "k". A name such as "firm" never counts as the RM of ringgit: a word-like prefix may not follow a letter.
const CODES = new Set(CURRENCIES.map((c) => c.code));
const AMOUNT_PREFIXES = [
	...new Set(CURRENCIES.flatMap((c) => [c.symbol.trim(), c.code]).filter((t) => t.length > 0))
]
	.sort((x, y) => y.length - x.length)
	.map((t) => {
		const letters = /^[A-Za-z]/.test(t);
		// A code that is also a word must be in capitals; a symbol and a common code may be in any case
		const body = letters
			? CODES.has(t) && !ANY_CASE_CODES.has(t)
				? escapeToken(t)
				: anyCase(escapeToken(t))
			: escapeToken(t);
		return (letters ? '(?<![A-Za-z])' : '') + body;
	});
// Group 1 is the symbol or code that was written, 2 the whole part, 3 the decimals, 4 the "k"
const AMOUNT_RE = new RegExp(
	'(?:(' +
		AMOUNT_PREFIXES.join('|') +
		')|\\b[pP](?=\\d))?\\s?(\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.(\\d{1,3}))?\\s?([kK]\\b)?',
	'g'
);

/** What a written symbol or code means (lowercase): ₱ is PHP, usd is USD. Every symbol belongs to one currency, so none is ambiguous. */
const CURRENCY_OF_TOKEN = new Map(
	CURRENCIES.flatMap((c) => [
		[c.symbol.trim().toLowerCase(), c.code] as const,
		[c.code.toLowerCase(), c.code] as const
	])
);

// -- FUNCTIONS -- //

const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Minor units of what was read. A zero digit currency (yen) has no fraction, so a decimal part is dropped. */
function toMinor(whole: string, frac: string | undefined, k: boolean, digits: 0 | 2 | 3): number {
	const major = Number(whole.replaceAll(',', ''));
	if (digits === 0) return major * (k ? 1000 : 1);
	const minor = frac ? Number(frac.slice(0, digits).padEnd(digits, '0')) : 0;
	return (major * 10 ** digits + minor) * (k ? 1000 : 1);
}

/** The category a note most likely belongs to. */
export function guessCategory(note: string): string {
	const words = note.toLowerCase();
	for (const [category, keys] of Object.entries(CATEGORY_WORDS))
		if (keys.some((k) => new RegExp(`\\b${escapeRe(k)}\\b`).test(words))) return category;
	return 'other';
}

/** The longest name that appears as a whole word in the text. */
function findName<T extends { name: string }>(text: string, names: readonly T[]): T | null {
	const sorted = [...names].sort((a, b) => b.name.length - a.name.length);
	for (const n of sorted)
		if (new RegExp(`(^|[^\\p{L}\\p{N}])${escapeRe(n.name)}($|[^\\p{L}\\p{N}])`, 'iu').test(text))
			return n;
	return null;
}

/** Reads a message like "lunch 180 gcash" or "grab ₱1,250.50 from rcbc". */
export function parseExpenseText(
	text: string,
	accountNames: readonly string[],
	currency: string = DEFAULT_CURRENCY
): ParsedExpense {
	const matches = [...text.matchAll(AMOUNT_RE)];
	const last = matches.at(-1);
	// A symbol or code in front of the number names the currency; without one the number is in the currency the caller passes
	const written = last?.[1] ? (CURRENCY_OF_TOKEN.get(last[1].toLowerCase()) ?? null) : null;
	const digits = currencyOf(written ?? currency).digits;
	const amount = last ? toMinor(last[2] as string, last[3], Boolean(last[4]), digits) : null;
	const account = findName(
		text,
		accountNames.map((name) => ({ name }))
	);
	let note = last ? text.replace(last[0], ' ') : text;
	if (account) note = note.replace(new RegExp(escapeRe(account.name), 'i'), ' ');
	note = note
		.replace(/\b(from|via|using|thru|through|sa|gamit)\b/gi, ' ')
		.replace(/\s+/g, ' ')
		.trim();
	return {
		amount,
		currency: written,
		note,
		category: guessCategory(note),
		accountName: account?.name ?? null,
		ambiguous: matches.length > 1
	};
}

/** Reads a rule said in plain words: "500 to gcash", "20% to emergency fund", "the rest to rcbc". */
export function parseRuleText(
	text: string,
	targets: readonly RuleTargetName[],
	currency: string = DEFAULT_CURRENCY
): ParsedRule {
	const digits = currencyOf(currency).digits;
	const said = text.trim();
	const rest = /\b(the )?rest\b|\beverything else\b|\bwhatever is left\b/i.test(said);
	const pct = /(\d+(?:\.\d+)?)\s?(%|percent\b)/i.exec(said);
	const target = findName(said, targets);
	if (!target) return { ok: false, reason: 'I could not tell which account or goal you mean.' };
	const t = { kind: target.kind, id: target.id };
	if (pct && !rest) {
		const bp = Math.round(Number(pct[1]) * 100);
		if (bp <= 0 || bp > 10_000)
			return { ok: false, reason: 'A share must be above 0% and at most 100%.' };
		const base: RuleBase = /\b(left|remaining|after)\b/i.test(said) ? 'remaining' : 'pay';
		return {
			ok: true,
			mode: 'percent',
			amount: null,
			basisPoints: bp,
			base,
			target: t,
			label: target.name
		};
	}
	if (rest && !pct)
		return {
			ok: true,
			mode: 'rest',
			amount: null,
			basisPoints: null,
			base: 'remaining',
			target: t,
			label: target.name
		};
	// The amount is the number that is not part of the target's own name
	const withoutName = said.replace(new RegExp(escapeRe(target.name), 'i'), ' ');
	const amounts = [...withoutName.matchAll(AMOUNT_RE)];
	const a = amounts.at(-1);
	if (!a || rest || pct)
		return {
			ok: false,
			reason: 'Say it as an amount, a percentage or "the rest", then where it goes.'
		};
	const amount = toMinor(a[2] as string, a[3], Boolean(a[4]), digits);
	if (amount <= 0) return { ok: false, reason: 'The amount must be above zero.' };
	return {
		ok: true,
		mode: 'fixed',
		amount,
		basisPoints: null,
		base: 'pay',
		target: t,
		label: target.name
	};
}
