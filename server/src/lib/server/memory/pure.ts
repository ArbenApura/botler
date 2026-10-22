// THE PURE PARTS OF MEMORY: TEXT NORMALISING AND HASHING, REDACTING NUMBERS BEFORE A FACT IS STORED, THE MOOD LIMITS, FADING, AND THE TOKEN BUDGET

// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
// -- MODULES -- //
import { createMasker } from '../proxy/mask';

// -- CONSTANTS -- //

/** Mood is tone only. It moves a little at a time, stays inside -100..100, and drifts back to zero. */
export const MOOD_MAX = 100;
export const MOOD_MAX_STEP = 10;
export const MOOD_DAILY_KEEP = 0.9;
/** A fact not used for this long, and not important, starts to fade. */
export const FADE_AFTER_DAYS = 90;
export const FADE_FLOOR = 0.1;
export const FADE_MAX_IMPORTANCE = 2;
/** What a fact looks like to the token budget: about four characters a token. */
export const CHARS_PER_TOKEN = 4;

// -- FUNCTIONS -- //

/** Lowercase, no punctuation, single spaces: two ways of writing the same sentence give the same hash. */
export function normalizeFact(text: string): string {
	return text
		.toLowerCase()
		.normalize('NFKC')
		.replace(/[^\p{L}\p{N}\s]/gu, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

export const hashFact = (text: string): string =>
	createHash('sha256').update(normalizeFact(text)).digest('hex').slice(0, 32);

/**
 * Takes account, card and phone numbers out of a fact before it is stored. The masker that hides them from the model finds them;
 * here they are replaced by plain words, because a placeholder number means nothing later. Returns null when nothing is left.
 */
export function redactSecrets(text: string): string | null {
	const masker = createMasker();
	const masked = masker.mask(text);
	if (masked === text) return text.trim() || null;
	const cleaned = masked
		.replace(/\[(ACCT|CARD|PHONE|EMAIL)_\d+\]/g, '(details removed)')
		.replace(/\s+/g, ' ')
		.trim();
	// Names are not secrets in a fact (they are masked per person when sent), so any [NAME_n] goes back
	return cleaned.replace(/\[NAME_\d+\]/g, (m) => masker.unmask(m)) || null;
}

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

/** The next mood: a change of at most 10 a turn, kept inside -100..100. */
export function nextMood(current: number, delta: number): number {
	if (!Number.isFinite(delta)) return current;
	return clamp(
		Math.round(current + clamp(delta, -MOOD_MAX_STEP, MOOD_MAX_STEP)),
		-MOOD_MAX,
		MOOD_MAX
	);
}

/** Mood after some quiet days: it loses a tenth a day, towards zero, never past it. */
export function decayMood(current: number, days: number): number {
	if (days <= 0) return current;
	// "|| 0" turns a negative zero into a plain zero
	return Math.trunc(current * MOOD_DAILY_KEEP ** days) || 0;
}

/** A sentence for the prompt. Tone only. It says nothing about money. */
export function toneHint(mood: number): string {
	if (mood <= -40) return 'The person has seemed low lately. Be gentle and brief.';
	if (mood <= -15) return 'The person has seemed a little tired. Be warm and easy.';
	if (mood >= 40) return 'The person has been in a great mood. Match it lightly.';
	if (mood >= 15) return 'The person has been upbeat. A friendly tone is welcome.';
	return '';
}

/** The weight a fact gets after a night of fading: halved, never below the floor. */
export const fadeStep = (weight: number): number => Math.max(FADE_FLOOR, weight / 2);

/** Using a fact brings it back: doubled, never above one. */
export const restoreStep = (weight: number): number => Math.min(1, weight * 2);

export const estimateTokens = (text: string): number => Math.ceil(text.length / CHARS_PER_TOKEN);

/** Takes lines in order while they fit the budget. A line that does not fit is skipped, a shorter later one may still fit. */
export function fitBudget(lines: readonly string[], budgetTokens: number): string[] {
	const out: string[] = [];
	let used = 0;
	for (const line of lines) {
		const cost = estimateTokens(line) + 1;
		if (used + cost > budgetTokens) continue;
		out.push(line);
		used += cost;
	}
	return out;
}

/** Cosine similarity of two unit vectors, or of any two vectors. */
export function cosine(a: readonly number[], b: readonly number[]): number {
	let dot = 0;
	let na = 0;
	let nb = 0;
	for (let i = 0; i < a.length; i++) {
		const x = a[i] ?? 0;
		const y = b[i] ?? 0;
		dot += x * y;
		na += x * x;
		nb += y * y;
	}
	return na === 0 || nb === 0 ? 0 : dot / Math.sqrt(na * nb);
}

/** The score of one fact for one question. Similarity and keywords come in 0..1; recency decays over about three months. */
export function scoreFact(f: {
	similarity: number | null;
	keyword: number;
	ageDays: number;
	importance: number;
	fadeWeight: number;
}): number {
	const recency = Math.exp(-Math.max(0, f.ageDays) / 90);
	const importance = (f.importance - 1) / 4;
	const base =
		f.similarity === null
			? 0.6 * f.keyword + 0.2 * recency + 0.2 * importance
			: 0.55 * Math.max(0, f.similarity) + 0.25 * f.keyword + 0.1 * recency + 0.1 * importance;
	return base * f.fadeWeight;
}
