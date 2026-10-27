// THE CHAT MODEL SETTINGS READ FROM THE ENVIRONMENT, AS PLAIN FUNCTIONS. A bad value fails loudly here, so the server stops at start
// instead of choosing for the person. env.ts calls these; the tests call them directly.

// -- TYPES -- //

export type ChatEffort = 'low' | 'medium' | 'high' | 'max';

// -- CONSTANTS -- //

export const CHAT_EFFORTS: readonly ChatEffort[] = ['low', 'medium', 'high', 'max'];

export const DEFAULT_CHAT_MAX_TOKENS = 64_000;

export const DEFAULT_TURN_TOKEN_BUDGET = 300_000;

// -- FUNCTIONS -- //

/** A whole number above zero, or the default when the variable is empty. A bad value stops the server. */
export function positiveInt(value: string | undefined, fallback: number, name: string): number {
	if (!value || !value.trim()) return fallback;
	const n = Number(value);
	if (!Number.isInteger(n) || n <= 0) throw new Error(`${name} must be a whole number above zero`);
	return n;
}

/** How hard the model thinks: low, medium, high or max. Empty gives high. A typo stops the server instead of silently choosing. */
export function parseChatEffort(value: string | undefined): ChatEffort {
	if (!value || !value.trim()) return 'high';
	const v = value.trim().toLowerCase();
	const found = CHAT_EFFORTS.find((e) => e === v);
	if (found) return found;
	throw new Error('CHAT_EFFORT must be low, medium, high or max');
}

/** The effort DeepSeek takes: it knows high and max, and maps low and medium to high, so the request says so plainly. */
export function deepseekEffort(effort: ChatEffort): 'high' | 'max' {
	return effort === 'max' ? 'max' : 'high';
}
