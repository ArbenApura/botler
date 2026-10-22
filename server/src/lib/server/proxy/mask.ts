// THE PAYLOAD FILTER: WHAT LEAVES FOR THE MODEL CARRIES AMOUNTS AND LABELS, NEVER ACCOUNT NUMBERS, CARD NUMBERS, PHONES, EMAILS OR FAMILY NAMES.
// Each secret becomes a placeholder such as [ACCT_1]. The same value always gets the same placeholder inside one masker, and the
// replies are restored with unmask(). The masker is built per call from the caller's own name list, so nothing is shared between people.

// -- TYPES -- //

export type Masker = {
	/** Masks one piece of text. */
	mask(text: string): string;
	/** Puts the original values back into a reply. Unknown placeholders are left as they are. */
	unmask(text: string): string;
	/** Like unmask, for the JSON arguments of a tool call: values go back into the string leaves only, so a quote or a backslash in a name can never break or extend the JSON. */
	unmaskJson(json: string): string;
	/** A stateful unmasker for a streamed reply: feed chunks, call flush() at the end. A placeholder split across two chunks is held back. */
	streamUnmasker(): { push(chunk: string): string; flush(): string };
	/** How many values were masked so far, by kind. Never the values. */
	counts(): Record<string, number>;
};

// -- CONSTANTS -- //

// Bounded on purpose: an unbounded local part makes a long run of letters quadratic and would freeze the server
const EMAIL = /[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63}){1,8}/g;
// Text in the input that already looks like one of our placeholders, such as [CARD_1]
const FORGED = /\[(ACCT|CARD|PHONE|EMAIL|NAME)_(\d+)\]/g;
// Philippine mobile numbers: 09XXXXXXXXX, +639XXXXXXXXX, 639XXXXXXXXX, with optional spaces or dashes
const PHONE = /(?<![\d])(?:\+?63|0)[\s-]?9(?:[\s-]?\d){9}(?![\d])/g;
// A run of digits that may be split by single spaces or dashes: 1234 5678 9012, 1234-5678-9012
const DIGIT_RUN = /(?<![\d.,])\d(?:[\s-]?\d){7,}(?![\d])(?!,\d{3})/g;
const ACCOUNT_WORDS = /(?:acct|account|acc|a\/c|card|number|no\.?|#)\s*[:#-]?\s*$/i;
const PLACEHOLDER = /\[(?:ACCT|CARD|PHONE|EMAIL|NAME)_\d+\]/g;
// The longest placeholder is [PHONE_999], so a chunk end that could still become one is at most this long
const PARTIAL_PLACEHOLDER = /\[[A-Z]{0,5}_?\d{0,3}$/;

// -- FUNCTIONS -- //

const digitsOf = (s: string) => s.replace(/\D/g, '');

/** The Luhn check, so only strings that can be card numbers are called cards. */
function luhn(digits: string): boolean {
	let sum = 0;
	let alt = false;
	for (let i = digits.length - 1; i >= 0; i--) {
		let n = digits.charCodeAt(i) - 48;
		if (alt) {
			n *= 2;
			if (n > 9) n -= 9;
		}
		sum += n;
		alt = !alt;
	}
	return sum % 10 === 0;
}

const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Builds a masker. `names` are the words to hide (family and contact names). Masking is case-insensitive and whole word.
 * Money amounts are left alone: a digit run only counts as an account number with nine or more digits, or eight digits
 * right after a word such as "account" or "card". Amounts with thousands separators never match.
 */
export function createMasker(names: readonly string[] = []): Masker {
	const forward = new Map<string, string>();
	const backward = new Map<string, string>();
	const counters: Record<string, number> = {};

	const tokenFor = (kind: string, value: string): string => {
		const key = `${kind}:${value.toLowerCase()}`;
		const seen = forward.get(key);
		if (seen) return seen;
		counters[kind] = (counters[kind] ?? 0) + 1;
		const token = `[${kind}_${counters[kind]}]`;
		forward.set(key, token);
		backward.set(token, value);
		return token;
	};

	const cleanNames = [...new Set(names.map((n) => n.trim()).filter((n) => n.length >= 2))].sort(
		(a, b) => b.length - a.length
	);
	const nameRe = cleanNames.length
		? new RegExp(
				`(?<![\\p{L}\\p{N}])(?:${cleanNames.map(escapeRegex).join('|')})(?![\\p{L}\\p{N}])`,
				'giu'
			)
		: null;

	const unmaskPlain = (text: string) => text.replace(PLACEHOLDER, (t) => backward.get(t) ?? t);

	return {
		mask(text) {
			// Text that already looks like a placeholder is changed first, so it can never be mistaken for one we issued
			let out = text.replace(FORGED, '[$1-$2]');
			// Order matters: emails and phones first, so their digits are not read as an account number
			out = out.replace(EMAIL, (m) => tokenFor('EMAIL', m));
			// +63 9XX and 09XX are the same number, so both forms share one placeholder and come back as 09XX
			out = out.replace(PHONE, (m) => {
				const d = digitsOf(m);
				return tokenFor('PHONE', d.startsWith('63') ? `0${d.slice(2)}` : d);
			});
			out = out.replace(DIGIT_RUN, (m, offset: number, whole: string) => {
				const digits = digitsOf(m);
				if (digits.length >= 13 && digits.length <= 19 && luhn(digits))
					return tokenFor('CARD', digits);
				const before = whole.slice(Math.max(0, offset - 16), offset);
				if (digits.length >= 9 || ACCOUNT_WORDS.test(before)) return tokenFor('ACCT', digits);
				return m;
			});
			if (nameRe) out = out.replace(nameRe, (m) => tokenFor('NAME', m));
			return out;
		},
		unmask: unmaskPlain,
		unmaskJson(json) {
			const walk = (v: unknown): unknown =>
				typeof v === 'string'
					? unmaskPlain(v)
					: Array.isArray(v)
						? v.map(walk)
						: v && typeof v === 'object'
							? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, walk(x)]))
							: v;
			try {
				return JSON.stringify(walk(JSON.parse(json)));
			} catch {
				// Not valid JSON (a model slip): hand it back untouched, with the placeholders still in place
				return json;
			}
		},
		streamUnmasker() {
			let pending = '';
			return {
				push(chunk) {
					const text = pending + chunk;
					const cut = text.search(PARTIAL_PLACEHOLDER);
					// Hold back only a tail that could still grow into a placeholder
					const safe = cut === -1 ? text : text.slice(0, cut);
					pending = cut === -1 ? '' : text.slice(cut);
					return unmaskPlain(safe);
				},
				flush() {
					const rest = pending;
					pending = '';
					return unmaskPlain(rest);
				}
			};
		},
		counts() {
			return { ...counters };
		}
	};
}
