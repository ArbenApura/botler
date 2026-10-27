// THE MODEL CALL TYPES, SHARED BY EVERY PROVIDER. One shape for the callers: the turn loop, the chat
// service and the memory jobs never learn which provider answered.

// -- TYPES -- //
import type { Bucket, Limits, RateLimiter, Usage } from './limits';
import type { Masker } from './mask';

export type ToolCall = {
	id: string;
	type: 'function';
	function: { name: string; arguments: string };
};

/** A thinking block exactly as Anthropic sent it, signature included. */
export type WireThinkingBlock =
	| { type: 'thinking'; thinking: string; signature: string }
	| { type: 'redacted_thinking'; data: string };

export type ChatMessage =
	| { role: 'system' | 'user'; content: string }
	| {
			role: 'assistant';
			content: string | null;
			tool_calls?: ToolCall[];
			/** The model's own thinking. Masked like the rest on its way out; a provider that cannot take it back drops it. */
			reasoning_content?: string;
			/**
			 * Anthropic only: the thinking and redacted_thinking blocks this message came with, signed and in order. They go back unchanged
			 * (never masked again) inside the same message's tool rounds, and are never stored or put in history.
			 */
			wire_blocks?: WireThinkingBlock[];
	  }
	| { role: 'tool'; tool_call_id: string; content: string };

export type ToolDef = {
	type: 'function';
	function: { name: string; description: string; parameters: Record<string, unknown> };
};

export type ModelConfig = {
	apiKey: string;
	baseUrl: string;
	model: string;
	limits: Limits;
	/** One per-minute counter shared by every provider's client. Left out, the client keeps its own. */
	rateLimiter?: RateLimiter;
	/** Milliseconds to wait for the model to start answering, and between two pieces of a streamed answer. */
	timeoutMs?: number;
	/** Retries after the first try, for network errors, 429 and 5xx. */
	maxRetries?: number;
	/** The most tokens one answer may use when the caller names no limit. It bounds what a single call can spend. */
	defaultMaxTokens?: number;
	/** The ceiling for a chat call that is not thinking. A tool round re-reads every result and the answer can be long, so it is higher than defaultMaxTokens, which the memory jobs keep. */
	chatMaxTokens?: number;
	/** Streamed chat answers think first and show their thinking. Never applies to the memory bucket or to complete(). */
	thinking?: boolean;
	/** The ceiling when thinking is on: thinking tokens share max_tokens with the answer. Follows chatMaxTokens when left out. */
	thinkingMaxTokens?: number;
	/** How hard a chat call thinks. Default 'high'. DeepSeek maps low and medium to high. A call to complete() (the jobs) always uses low. */
	chatEffort?: 'low' | 'medium' | 'high' | 'max';
	/** Anthropic only: how long a cached prefix lives. '5m' is renewed free on every read; '1h' costs more to write. Default '5m'. */
	cacheTtl?: '5m' | '1h';
	/** Anthropic only: send cache markers. On by default. */
	caching?: boolean;
	/** For tests: a stand-in for fetch and for waiting between retries. */
	fetch?: typeof fetch;
	sleep?: (ms: number) => Promise<void>;
};

export type CompletionRequest = {
	bucket: Bucket;
	messages: ChatMessage[];
	tools?: ToolDef[];
	/** 'none' keeps the tools in the request (so the host's cache of them survives) but forbids calling any. Default 'auto'. */
	toolChoice?: 'auto' | 'none';
	/** How many leading messages are the stable prefix (the system message and the history). Left out by the memory jobs, which get no cache markers. */
	stableCount?: number;
	/** Hide these names (family, contacts) from the model. Ignored when a masker is passed. */
	names?: string[];
	/** One masker for a whole turn, so a placeholder means the same thing in every call of the turn. */
	masker?: Masker;
	temperature?: number;
	maxTokens?: number;
	/** Aborts the call, including the model request, when the app disconnects. */
	signal?: AbortSignal;
};

export type Completion = {
	content: string;
	toolCalls: ToolCall[];
	finishReason: string;
	usage: Usage;
	/** The thinking with real values restored, like content: it is only kept to go back to the model in a tool round, where maskMessages masks it again. Never stored or logged. */
	reasoningRaw?: string;
	/** Anthropic only: the signed thinking blocks of this answer, to be passed back unchanged in the same message's tool rounds. */
	wireBlocks?: WireThinkingBlock[];
	/** What this call counted against the monthly cap (cache reads and writes weighted). Left out by a stand-in model. */
	charged?: number;
	/** Which host answered, so a stored transcript is only replayed to the same one. Left out by a stand-in model. */
	provider?: 'anthropic' | 'deepseek';
};

export type StreamEvent =
	| { type: 'delta'; text: string }
	| { type: 'reasoning'; text: string }
	| { type: 'done'; completion: Completion };
