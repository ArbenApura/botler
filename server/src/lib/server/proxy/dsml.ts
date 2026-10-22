// THE MODEL SOMETIMES WRITES ITS TOOL CALL AS PLAIN TEXT (DEEPSEEK'S "DSML" MARKUP) INSTEAD OF IN THE TOOL CALL FIELD.
// This file finds that markup, turns it into real tool calls and keeps it out of what the person reads. Pure: no network, no database.
// The markup is model output and gets no extra power: its calls go through the same tool checks as any other.
// Every run of spaces inside a tag is bounded, so a strange answer (a "<" followed by a huge run of spaces) cannot make the matching slow.

// -- TYPES -- //
import type { ToolCall } from './deepseek';
// -- DEP-MODULES -- //
import { randomUUID } from 'node:crypto';

// -- CONSTANTS -- //

// The tags are written with the full-width bar or a plain one, sometimes doubled and with spaces: < | | DSML | | invoke name="x">
const SP = String.raw`\s{0,4}`;
const BARS = String.raw`(?:[|｜]${SP})+`;
const OPEN = String.raw`<${SP}${BARS}DSML${SP}${BARS}`;
const CLOSE = String.raw`<${SP}\/${SP}${BARS}DSML${SP}${BARS}`;

const BLOCK = new RegExp(
	String.raw`${OPEN}function_calls${SP}>([\s\S]*?)(?:${CLOSE}function_calls${SP}>|$)`,
	'g'
);
// An invoke or a parameter counts only when it is closed: a cut-off one never becomes a call
const INVOKE = new RegExp(
	String.raw`${OPEN}invoke\s{1,4}name${SP}=${SP}"([^"]{1,200})"${SP}>([\s\S]*?)${CLOSE}invoke${SP}>`,
	'g'
);
const PARAM = new RegExp(
	String.raw`${OPEN}parameter\s{1,4}name${SP}=${SP}"([^"]{1,200})"([^>]{0,200})>([\s\S]*?)${CLOSE}parameter${SP}>`,
	'g'
);
const ANY_TAG = new RegExp(String.raw`(?:${OPEN}|${CLOSE})[^>]{0,300}>`, 'g');
// The start of a tag, with the front of "DSML" possibly still to come in the next piece
const TAG_START = new RegExp(
	String.raw`<${SP}\/?${SP}(?:[|｜]${SP}){0,40}(?:D(?:S(?:M(?:L)?)?)?)?$`
);
const TAG_FOUND = new RegExp(String.raw`<${SP}\/?${SP}${BARS}DSML`);
const STRING_FALSE = new RegExp(String.raw`string${SP}=${SP}"false"`);

// -- FUNCTIONS -- //

/** One value of a parameter: text as it is, or JSON (numbers, booleans, lists) when the tag says string="false". */
function valueOf(attrs: string, raw: string): unknown {
	if (STRING_FALSE.test(attrs)) {
		try {
			return JSON.parse(raw.trim());
		} catch {
			return raw.trim();
		}
	}
	return raw;
}

/** Reads the tool calls written as markup and returns the text without any of it. Without markup the text comes back untouched. */
export function splitDsml(content: string): { text: string; calls: ToolCall[] } {
	if (!TAG_FOUND.test(content)) return { text: content, calls: [] };
	const calls: ToolCall[] = [];
	for (const block of content.matchAll(BLOCK)) {
		for (const invoke of (block[1] ?? '').matchAll(INVOKE)) {
			const args: Record<string, unknown> = {};
			for (const p of (invoke[2] ?? '').matchAll(PARAM)) {
				args[p[1] ?? ''] = valueOf(p[2] ?? '', p[3] ?? '');
			}
			calls.push({
				id: `dsml_${randomUUID().slice(0, 12)}`,
				type: 'function',
				function: { name: invoke[1] ?? '', arguments: JSON.stringify(args) }
			});
		}
	}
	const text = content.replace(BLOCK, '').replace(ANY_TAG, '');
	return { text, calls };
}

/**
 * Sits in front of the words shown to the person. Plain text passes through at once; from the first sign of the markup everything is held,
 * so no piece of it is ever shown. A "<" that turns out to be something else (a "<b>") is let go as soon as that is clear.
 */
export function createDsmlGuard() {
	let held = '';
	let inMarkup = false;
	return {
		/** The part of this piece that is safe to show now. */
		push(text: string): string {
			held += text;
			if (!inMarkup && TAG_FOUND.test(held)) {
				inMarkup = true;
				const at = held.search(TAG_FOUND);
				const safe = held.slice(0, at);
				held = held.slice(at);
				return safe;
			}
			if (inMarkup) return '';
			const start = held.search(TAG_START);
			if (start === -1) {
				const out = held;
				held = '';
				return out;
			}
			const out = held.slice(0, start);
			held = held.slice(start);
			return out;
		},
		/** The end of the answer: what was held back, minus every piece of markup. */
		flush(): string {
			const rest = inMarkup ? splitDsml(held).text : held;
			held = '';
			return rest;
		}
	};
}
