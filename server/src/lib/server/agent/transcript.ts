// THE STORED TOOL ROUNDS OF A CHAT MESSAGE, AND HOW THEY COME BACK AS HISTORY. Plain functions, no database.
// A message keeps what its tool rounds said and answered, so a later message still has the data and the work, not only the two texts.
// What is kept is made safe on the way in:
// - a tool result is shortened to 3000 characters, with a marker that says it is old (the data may have changed: read it again);
// - a web or calendar result (untrusted text) is replaced by a stub that names the tool, and the assistant text of that round is dropped,
//   so nothing a stranger wrote is replayed as if it were true or as an instruction;
// - thinking is never kept: the model's reasoning stays in memory for the tool rounds of the live message only (the host wants it back
//   while a round continues) and is not written to the database. Old rows that carry a `reasoning_content` field are read without it.
// Coming back, a message whose rounds do not fit the live provider, or do not pair up, is replayed as its two texts only.

// -- TYPES -- //
import type { ChatMessage, ToolCall } from '../proxy/types';

// Rows stored while Anthropic was a host still carry 'anthropic'; they are read as such and never replayed to another host.
export type TranscriptProvider = 'anthropic' | 'deepseek';

export type TranscriptMessage =
	| {
			role: 'assistant';
			content: string | null;
			tool_calls: ToolCall[];
			/** Which provider wrote it: the rounds are replayed only to the same one. */
			provider?: TranscriptProvider;
	  }
	| { role: 'tool'; tool_call_id: string; content: string };

/** A finished message as history needs it. */
export type HistoryTurn = {
	userText: string;
	reply: string;
	/** The stored column: unknown until checked. */
	transcript: unknown;
};

// -- CONSTANTS -- //

export const RESULT_CHARS = 3000;
const SHORTENED = ' ...[shortened: read again for current data]';
const STEP = 5;
/** What a message with tool rounds but no written answer says in history, so the work it did stays in view. */
const NO_ANSWER = 'I stopped before I could answer this one.';

// -- FUNCTIONS -- //

/** A tool result for storage: whole when short, otherwise cut with a marker that says it is old. */
export function shortenResult(content: string): string {
	return content.length <= RESULT_CHARS ? content : content.slice(0, RESULT_CHARS) + SHORTENED;
}

/** What replaces the result of a web or calendar tool: the name only, never a word of the text. */
export function untrustedStub(tool: string): string {
	return JSON.stringify({
		untrusted: true,
		source: tool,
		// Not "verified" and not "stands": a page can be wrong, and nothing of it is kept. The figures the assistant quoted came from the live read
		note: 'Old read, text not stored. Numbers the assistant quoted in its replies came from it; run the tool again only to re-check them.'
	});
}

/** About four characters to the token, as everywhere else in the proxy. */
export const tokensOf = (messages: ChatMessage[]): number =>
	messages.reduce((sum, m) => sum + Math.ceil(JSON.stringify(m).length / 4), 0);

const isObject = (v: unknown): v is Record<string, unknown> =>
	typeof v === 'object' && v !== null && !Array.isArray(v);

/** The stored column read back, or null when it is empty or does not have the shape this code wrote. */
export function readTranscript(value: unknown): TranscriptMessage[] | null {
	if (!Array.isArray(value) || value.length === 0) return null;
	const out: TranscriptMessage[] = [];
	for (const m of value) {
		if (!isObject(m)) return null;
		if (m.role === 'tool') {
			if (typeof m.tool_call_id !== 'string' || typeof m.content !== 'string') return null;
			out.push({ role: 'tool', tool_call_id: m.tool_call_id, content: m.content });
		} else if (m.role === 'assistant') {
			if (!Array.isArray(m.tool_calls) || m.tool_calls.length === 0) return null;
			if (m.content !== null && typeof m.content !== 'string') return null;
			const calls: ToolCall[] = [];
			for (const c of m.tool_calls) {
				if (!isObject(c) || typeof c.id !== 'string' || !isObject(c.function)) return null;
				const fn = c.function;
				if (typeof fn.name !== 'string' || typeof fn.arguments !== 'string') return null;
				calls.push({
					id: c.id,
					type: 'function',
					function: { name: fn.name, arguments: fn.arguments }
				});
			}
			out.push({
				role: 'assistant',
				content: m.content,
				tool_calls: calls,
				...(m.provider === 'anthropic' || m.provider === 'deepseek' ? { provider: m.provider } : {})
			});
		} else return null;
	}
	return out;
}

/**
 * The rounds as chat messages for the live provider, or null when they cannot be replayed: another provider wrote them, or a tool call has no
 * answer (or an answer has no call). No host gets thinking from history: it is not stored, and the models do not need it for a new message.
 */
export function replayRounds(
	transcript: TranscriptMessage[],
	provider: TranscriptProvider | undefined
): ChatMessage[] | null {
	if (!provider) return null;
	const out: ChatMessage[] = [];
	let open: Set<string> | null = null;
	for (const m of transcript) {
		if (m.role === 'assistant') {
			if (open && open.size > 0) return null;
			if (m.provider !== provider) return null;
			open = new Set(m.tool_calls.map((c) => c.id));
			out.push({
				role: 'assistant',
				content: m.content,
				tool_calls: m.tool_calls
			});
		} else {
			if (!open || !open.delete(m.tool_call_id)) return null;
			out.push({ role: 'tool', tool_call_id: m.tool_call_id, content: m.content });
		}
	}
	return open && open.size > 0 ? null : out;
}

/**
 * One finished message as history: what the person said, the tool rounds when they can be replayed, then the answer. A message with no
 * answer and no rounds is left out (an empty assistant message is refused by the host).
 */
export function turnMessages(
	turn: HistoryTurn,
	provider: TranscriptProvider | undefined,
	textOnly = false
): ChatMessage[] {
	const stored = textOnly ? null : readTranscript(turn.transcript);
	const rounds = stored ? replayRounds(stored, provider) : null;
	const reply = turn.reply.trim() ? turn.reply : rounds ? NO_ANSWER : '';
	if (!reply) return [];
	return [
		{ role: 'user', content: turn.userText },
		...(rounds ?? []),
		{ role: 'assistant', content: reply }
	];
}

/**
 * The messages of the turns after the last summary, in order, held under a token budget. Over it, the oldest turns drop in steps of five (so
 * the start of the history stays the same for five messages in a row, which keeps the host's prefix cache valid). When even the two newest
 * turns are over it, they are replayed as text only. Returns the first turn kept, for the tests and the log.
 */
export function buildHistory(
	turns: HistoryTurn[],
	options: { provider: TranscriptProvider | undefined; budget: number }
): { messages: ChatMessage[]; start: number } {
	const units = turns.map((t) => turnMessages(t, options.provider));
	const sizes = units.map((u) => tokensOf(u));
	const n = units.length;
	const from = (s: number) => sizes.slice(s).reduce((a, b) => a + b, 0);
	let start = 0;
	while (start < n && from(start) > options.budget) start += STEP;
	if (start > Math.max(0, n - 2)) start = Math.max(0, n - 2);
	let kept = units.slice(start);
	if (tokensOf(kept.flat()) > options.budget && n - start <= 2)
		kept = turns.slice(start).map((t) => turnMessages(t, options.provider, true));
	return { messages: kept.flat(), start };
}
