// THE MODEL CALL TYPES, SHARED BY EVERY PROVIDER. One shape for the callers: the turn loop, the chat
// service and the memory jobs never learn which provider answered.

// -- TYPES -- //
import type { Bucket, Limits, Usage } from './limits';
import type { Masker } from './mask';

export type ToolCall = {
	id: string;
	type: 'function';
	function: { name: string; arguments: string };
};

export type ChatMessage =
	| { role: 'system' | 'user'; content: string }
	| {
			role: 'assistant';
			content: string | null;
			tool_calls?: ToolCall[];
			/** The model's own thinking. Masked like the rest on its way out; a provider that cannot take it back drops it. */
			reasoning_content?: string;
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
	/** Milliseconds to wait for the model to start answering, and between two pieces of a streamed answer. */
	timeoutMs?: number;
	/** Retries after the first try, for network errors, 429 and 5xx. */
	maxRetries?: number;
	/** The most tokens one answer may use when the caller names no limit. It bounds what a single call can spend. */
	defaultMaxTokens?: number;
	/** Streamed chat answers think first and show their thinking. Never applies to the memory bucket or to complete(). */
	thinking?: boolean;
	/** The ceiling when thinking is on: thinking tokens share max_tokens with the answer. */
	thinkingMaxTokens?: number;
	/** For tests: a stand-in for fetch and for waiting between retries. */
	fetch?: typeof fetch;
	sleep?: (ms: number) => Promise<void>;
};

export type CompletionRequest = {
	bucket: Bucket;
	messages: ChatMessage[];
	tools?: ToolDef[];
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
};

export type StreamEvent =
	| { type: 'delta'; text: string }
	| { type: 'reasoning'; text: string }
	| { type: 'done'; completion: Completion };
