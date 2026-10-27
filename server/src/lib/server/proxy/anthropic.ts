// THE ANTHROPIC CLIENT: THE /v1/messages WIRE FORMAT (blocks), FOR WHEN MODEL_PROVIDER IS anthropic.
// Every shared rule (rate limit, monthly budget, masking, timeout, retries, usage recording, the log) lives in
// proxy/core.ts. The masking runs on the internal messages before any translation, so the top-level system
// field, the assistant text and every tool argument carry only placeholders. Message text is never logged. The
// key is read once from the server environment and is never returned or written anywhere.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Usage } from './limits';
import type { Masker } from './mask';
import type {
	ChatMessage,
	Completion,
	CompletionRequest,
	ModelConfig,
	StreamEvent,
	ToolCall,
	WireThinkingBlock
} from './types';
export type {
	Completion,
	CompletionRequest,
	ChatMessage,
	ModelConfig,
	StreamEvent,
	ToolCall
} from './types';
// -- MODULES -- //
import {
	createCore,
	DOWN,
	estimateTokens,
	finish,
	maskerFor,
	maskMessages,
	readWrittenCalls,
	toolDetail,
	toolsOffered,
	within
} from './core';
import { defaultSleep } from './core';
import { createDsmlGuard } from './dsml';
import { OpsError } from '../ops/context';
import { DEFAULT_CHAT_MAX_TOKENS } from './chatEnv';
import { STREAM_TIMEOUT_MS } from './deepseek';

// -- TYPES -- (local wire shapes)

type CacheControl = { type: 'ephemeral'; ttl?: '1h' };

type Block = (
	| { type: 'text'; text: string }
	| { type: 'tool_use'; id: string; name: string; input: unknown }
	| { type: 'tool_result'; tool_use_id: string; content: string }
	| WireThinkingBlock
) & { cache_control?: CacheControl };

type WireMessage = { role: 'user' | 'assistant'; content: string | Block[] };

type UsageWire = {
	input_tokens?: number;
	output_tokens?: number;
	cache_read_input_tokens?: number;
	cache_creation_input_tokens?: number;
	cache_creation?: { ephemeral_1h_input_tokens?: number };
};

type FullBody = {
	content?: Block[];
	stop_reason?: string;
	usage?: UsageWire;
};

type StreamChunk = {
	type: string;
	message?: { usage?: UsageWire };
	index?: number;
	content_block?: { type: string; id?: string; name?: string; data?: string };
	delta?: {
		type?: string;
		text?: string;
		partial_json?: string;
		thinking?: string;
		signature?: string;
		stop_reason?: string;
	};
	usage?: UsageWire;
};

// -- CONSTANTS -- //

/** The Claude 5 models, which answer a temperature with a 400. */
const SAMPLING_REFUSED = /(haiku|sonnet|opus|fable)-5/;

/** The shortest prefix the host will cache, by model name. A marker on a shorter prefix is ignored by the API, so it is not sent. */
export function cacheMinimum(model: string): number {
	if (/haiku-5|sonnet-5|opus-5/.test(model)) return 512;
	if (/haiku-4-5|opus-4-5|opus-4-6/.test(model)) return 4096;
	if (/haiku-3-5|opus-4-7/.test(model)) return 2048;
	return 1024;
}

// -- FUNCTIONS -- //

const sizeOf = (v: unknown): number => estimateTokens(JSON.stringify(v).length);

/** The last block of a wire turn, which is where a cache marker for the end of that turn goes. */
function lastBlock(turn: WireMessage | undefined): Block | null {
	if (!turn) return null;
	if (typeof turn.content === 'string') {
		turn.content = [{ type: 'text', text: turn.content }];
	}
	return turn.content[turn.content.length - 1] ?? null;
}

/**
 * Tool arguments go into a tool_use input object, from the originals (the turn loop sends the real values
 * back). Masking goes into the string leaves only, so numbers stay numbers and the sent input is always valid
 * JSON. An unparsable slip, or a string that already carries placeholders, is kept as one masked string leaf.
 */
function maskedArgs(argumentsJson: string, masker: Masker): unknown {
	let parsed: unknown;
	try {
		parsed = JSON.parse(argumentsJson || '{}');
	} catch {
		return { raw: masker.mask(argumentsJson) };
	}
	const walk = (v: unknown): unknown => {
		if (typeof v === 'string') return masker.mask(v);
		if (Array.isArray(v)) return v.map(walk);
		if (v && typeof v === 'object')
			return Object.fromEntries(
				Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, walk(x)])
			);
		return v;
	};
	return walk(parsed);
}

/**
 * The internal messages, already masked, become Anthropic turns. System messages join into the top-level system
 * field; a run of user and tool results merges into one user turn (tool results carry the tool_use id they answer);
 * an assistant turn is its signed thinking blocks (only inside one message's tool rounds, never from history), then its text
 * block (when it has one), then its tool_use blocks.
 * Tool arguments are taken from the originals (the turn loop sends the real values back) and masked into the
 * string leaves only: masking the whole arguments text could turn an unquoted number into a token and break
 * the JSON the input_schema expects. Messages and originals walk in step (maskMessages maps one to one).
 */
function toWire(
	messages: ChatMessage[],
	originals: ChatMessage[],
	masker: Masker,
	stableCount = 0
): { system: string[]; turns: WireMessage[]; stableTurns: number } {
	// One text block per system message, never one joined string, so a cache breakpoint can sit on the end of the stable one
	const system: string[] = [];
	const turns: WireMessage[] = [];
	// How many wire turns the first stableCount messages made
	let stableTurns = 0;
	const lastUser = (): Block[] | null => {
		const last = turns[turns.length - 1];
		if (last && last.role === 'user' && Array.isArray(last.content)) return last.content;
		return null;
	};
	for (const [i, m] of messages.entries()) {
		if (m.role === 'system') {
			system.push(m.content);
		} else if (m.role === 'user') {
			const merge = lastUser();
			if (merge) merge.push({ type: 'text', text: m.content });
			else turns.push({ role: 'user', content: [{ type: 'text', text: m.content }] });
		} else if (m.role === 'tool') {
			const result: Block = {
				type: 'tool_result',
				tool_use_id: m.tool_call_id,
				content: m.content
			};
			const merge = lastUser();
			if (merge) merge.push(result);
			else turns.push({ role: 'user', content: [result] });
		} else {
			// The signed thinking of this message goes first and unchanged: it was never masked here, and a changed byte fails the check
			const blocks: Block[] = [...((m.role === 'assistant' ? m.wire_blocks : undefined) ?? [])];
			if (m.content) blocks.push({ type: 'text', text: m.content });
			const original = originals[i];
			const calls = (m.role === 'assistant' ? m.tool_calls : undefined) ?? [];
			const sourceCalls =
				original && original.role === 'assistant' ? (original.tool_calls ?? []) : calls;
			calls.forEach((c, j) => {
				const json = sourceCalls[j]?.function.arguments ?? c.function.arguments;
				blocks.push({
					type: 'tool_use',
					id: c.id,
					name: c.function.name,
					// The original can hold an unparsable or already-masked string; maskedArgs keeps both cases loud-safe
					input: maskedArgs(json, masker)
				});
			});
			turns.push({
				role: 'assistant',
				content: blocks.length ? blocks : [{ type: 'text', text: '' }]
			});
		}
		if (i === stableCount - 1) stableTurns = turns.length;
	}
	return { system, turns, stableTurns };
}

export function createAnthropicClient(config: ModelConfig) {
	const core = createCore({
		provider: 'anthropic',
		model: config.model,
		limits: config.limits,
		rateLimiter: config.rateLimiter,
		timeoutMs: config.timeoutMs ?? STREAM_TIMEOUT_MS,
		maxRetries: config.maxRetries ?? 2,
		fetch: config.fetch ?? fetch,
		sleep: config.sleep ?? defaultSleep
	});
	const defaultMaxTokens = config.defaultMaxTokens ?? 2048;
	const chatMaxTokens = config.chatMaxTokens ?? DEFAULT_CHAT_MAX_TOKENS;
	const thinkingMaxTokens = config.thinkingMaxTokens ?? chatMaxTokens;
	const chatEffort = config.chatEffort ?? 'high';
	const timeoutMs = config.timeoutMs ?? STREAM_TIMEOUT_MS;

	/** The body for one call. max_tokens is required on /v1/messages. Adaptive thinking is offered only to a streamed
	 * chat answer, with the tools still offered: the signed thinking blocks go back unchanged inside the message's
	 * tool rounds. The effort is the person's chat setting for a chat stream and always low for complete() (the jobs). */
	function buildBody(
		req: CompletionRequest,
		masker: Masker,
		stream: boolean
	): Record<string, unknown> {
		const thinking = stream && config.thinking === true && req.bucket === 'chat';
		const effort = stream && req.bucket === 'chat' ? chatEffort : 'low';
		const masked = maskMessages(req.messages, masker);
		const { system, turns, stableTurns } = toWire(masked, req.messages, masker, req.stableCount);
		// The repo's tool definitions are OpenAI shaped; the wire wants input_schema
		const wireTools: {
			name: string;
			description: string;
			input_schema: Record<string, unknown>;
			cache_control?: CacheControl;
		}[] = (req.tools ?? []).map((t) => ({
			name: t.function.name,
			description: t.function.description,
			input_schema: t.function.parameters
		}));
		const systemBlocks: { type: 'text'; text: string; cache_control?: CacheControl }[] = system.map(
			(text) => ({ type: 'text', text })
		);
		// Cache markers only on a chat request that names its stable prefix. The memory jobs send none, so they pay no write premium
		if (config.caching !== false && req.stableCount) {
			const long: CacheControl =
				config.cacheTtl === '1h' ? { type: 'ephemeral', ttl: '1h' } : { type: 'ephemeral' };
			const short: CacheControl = { type: 'ephemeral' };
			const minimum = cacheMinimum(config.model);
			// Tokens before each breakpoint, counted from the start: tools, then system, then the turns
			const toolsSize = sizeOf(wireTools);
			const systemSize = sizeOf(systemBlocks);
			// 1: the last tool definition
			const lastTool = wireTools[wireTools.length - 1];
			if (lastTool && toolsSize >= minimum) lastTool.cache_control = long;
			// 2: the end of the stable system block
			const lastSystem = systemBlocks[0];
			if (lastSystem && toolsSize + systemSize >= minimum) lastSystem.cache_control = long;
			// 3: the end of the history. Not on the first turn of a chat (no history) or on the same block as 4
			const turnsBefore = (n: number) => sizeOf(turns.slice(0, n));
			if (stableTurns > 0 && stableTurns < turns.length) {
				const block = lastBlock(turns[stableTurns - 1]);
				if (block && toolsSize + systemSize + turnsBefore(stableTurns) >= minimum)
					block.cache_control = short;
			}
			// 4: the last block of the last message, so the next round of the same turn reads this one
			const last = lastBlock(turns[turns.length - 1]);
			if (last && toolsSize + systemSize + turnsBefore(turns.length) >= minimum)
				last.cache_control = short;
		}
		return {
			model: config.model,
			// Every call has a ceiling, so one call can never spend more than this. Thinking shares it with the answer
			max_tokens:
				req.maxTokens ??
				(thinking ? thinkingMaxTokens : req.bucket === 'chat' ? chatMaxTokens : defaultMaxTokens),
			...(systemBlocks.length ? { system: systemBlocks } : {}),
			messages: turns,
			...(wireTools.length ? { tools: wireTools } : {}),
			// 'none' keeps the tools in the body (so their cache survives) and forbids any call. Never sent without tools
			...(wireTools.length && req.toolChoice === 'none' ? { tool_choice: { type: 'none' } } : {}),
			// Claude 5 models refuse sampling settings, and a thinking model ignores them, so none are sent to either
			...(req.temperature !== undefined && !thinking && !SAMPLING_REFUSED.test(config.model)
				? { temperature: req.temperature }
				: {}),
			// Adaptive thinking, summarized for the screen. The budget_tokens form is refused by Claude 5 models
			...(thinking ? { thinking: { type: 'adaptive', display: 'summarized' } } : {}),
			output_config: { effort },
			stream
		};
	}

	const call = (body: Record<string, unknown>, signal?: AbortSignal): Promise<Response> =>
		core.send({
			url: `${config.baseUrl}/v1/messages`,
			headers: {
				'content-type': 'application/json',
				'x-api-key': config.apiKey,
				'anthropic-version': '2023-06-01'
			},
			body,
			signal
		});

	const finishReasonOf = (stopReason: string | undefined): string => {
		if (stopReason === 'max_tokens') return 'length';
		if (stopReason === 'tool_use') return 'tool_calls';
		return 'stop';
	};

	/** The total input is uncached + cache read + cache write, so promptTokens keeps its meaning. */
	const promptTokensOf = (u: UsageWire | undefined): number =>
		(u?.input_tokens ?? 0) +
		(u?.cache_read_input_tokens ?? 0) +
		(u?.cache_creation_input_tokens ?? 0);

	const blocksToCompletion = (blocks: Block[]): { content: string; calls: ToolCall[] } => {
		let content = '';
		const calls: ToolCall[] = [];
		for (const b of blocks) {
			if (b.type === 'text') content += b.text;
			else if (b.type === 'tool_use')
				calls.push({
					id: b.id,
					type: 'function',
					function: { name: b.name, arguments: JSON.stringify(b.input ?? {}) }
				});
		}
		return { content, calls };
	};

	return {
		/** One answer, not streamed. */
		async complete(ctx: Ctx, req: CompletionRequest): Promise<Completion> {
			await core.admit(ctx, req.bucket);
			const masker = maskerFor(req);
			const body = buildBody(req, masker, false);
			const started = Date.now();
			const res = await call(body, req.signal);
			let wire: FullBody;
			try {
				wire = (await within(res.json(), timeoutMs)) as FullBody;
			} catch {
				throw new OpsError('UNAVAILABLE', DOWN);
			}
			const flat = blocksToCompletion(wire.content ?? []);
			// Tested on the usage being there, not on input_tokens being truthy: a full cache hit can report input_tokens 0
			const usage: Usage = wire.usage
				? {
						promptTokens: promptTokensOf(wire.usage),
						completionTokens: wire.usage.output_tokens ?? 0,
						cacheReadTokens: wire.usage.cache_read_input_tokens ?? 0,
						cacheWriteTokens: wire.usage.cache_creation_input_tokens ?? 0,
						cacheWrite1hTokens: wire.usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
					}
				: {
						promptTokens: estimateTokens(JSON.stringify(body.messages).length),
						completionTokens: estimateTokens(flat.content.length)
					};
			await core.record(ctx, req.bucket, usage);
			core.log(ctx, req.bucket, Date.now() - started, usage, true, toolDetail(req));
			const written = readWrittenCalls(
				flat.content,
				flat.calls,
				finishReasonOf(wire.stop_reason),
				toolsOffered(req)
			);
			return finish(masker, written.content, written.calls, written.finishReason, usage);
		},

		/** A streamed answer: text pieces as they arrive, then one final event with the whole completion. */
		async *stream(ctx: Ctx, req: CompletionRequest): AsyncGenerator<StreamEvent> {
			await core.admit(ctx, req.bucket);
			const masker = maskerFor(req);
			const unmasker = masker.streamUnmasker();
			// A tool call written as text is held back here, so no piece of it is shown
			const guard = createDsmlGuard();
			// The thinking has its own unmasker, so a placeholder split inside it is never mixed with the answer's
			const thinkUnmasker = masker.streamUnmasker();
			const body = buildBody(req, masker, true);
			const started = Date.now();
			const res = await call(body, req.signal);
			if (!res.body) throw new OpsError('UNAVAILABLE', DOWN);

			const reader = res.body.getReader();
			const decoder = new TextDecoder();
			let buffer = '';
			let content = '';
			let reasoning = '';
			let thinking = false;
			let finishReason = 'stop';
			// Usage arrives in pieces: input_tokens with message_start, output_tokens with message_delta
			let reportedPrompt: number | null = null;
			let reportedRead = 0;
			let reportedWrite = 0;
			let reportedWrite1h = 0;
			let reportedUncached = 0;
			let reportedOut: number | null = null;
			const calls = new Map<number, { id: string; name: string; arguments: string }>();
			// The thinking blocks as they arrive, by block index: the text, the signature, or the redacted data
			const thoughts = new Map<number, WireThinkingBlock>();
			let completed = false;
			// Assigned in the finally block below, which always runs
			let final: Usage;
			try {
				read: for (;;) {
					let chunk: ReadableStreamReadResult<Uint8Array>;
					try {
						// A silent stream is cut off after the same wait as the start of the answer
						chunk = await within(reader.read(), timeoutMs);
					} catch (e) {
						if (e instanceof OpsError) throw e;
						throw new OpsError('UNAVAILABLE', DOWN);
					}
					if (chunk.done) break;
					buffer += decoder.decode(chunk.value, { stream: true });
					let nl: number;
					while ((nl = buffer.indexOf('\n')) !== -1) {
						const line = buffer.slice(0, nl).trim();
						buffer = buffer.slice(nl + 1);
						if (!line.startsWith('data:')) continue;
						const data = line.slice(5).trim();
						let wire: StreamChunk;
						try {
							wire = JSON.parse(data) as StreamChunk;
						} catch {
							continue;
						}
						if (wire.type === 'message_start') {
							if (wire.message?.usage) {
								reportedPrompt = promptTokensOf(wire.message.usage);
								reportedUncached = wire.message.usage.input_tokens ?? 0;
								reportedRead = wire.message.usage.cache_read_input_tokens ?? 0;
								reportedWrite = wire.message.usage.cache_creation_input_tokens ?? 0;
								reportedWrite1h = wire.message.usage.cache_creation?.ephemeral_1h_input_tokens ?? 0;
							}
						} else if (wire.type === 'content_block_start') {
							if (wire.index !== undefined && wire.content_block?.type === 'tool_use')
								calls.set(wire.index, {
									id: wire.content_block.id ?? '',
									name: wire.content_block.name ?? '',
									arguments: ''
								});
							else if (wire.index !== undefined && wire.content_block?.type === 'thinking')
								thoughts.set(wire.index, { type: 'thinking', thinking: '', signature: '' });
							else if (wire.index !== undefined && wire.content_block?.type === 'redacted_thinking')
								thoughts.set(wire.index, {
									type: 'redacted_thinking',
									data: wire.content_block.data ?? ''
								});
						} else if (wire.type === 'content_block_delta' && wire.delta?.type) {
							if (wire.delta.type === 'signature_delta' && wire.index !== undefined) {
								const block = thoughts.get(wire.index);
								if (block?.type === 'thinking') block.signature += wire.delta.signature ?? '';
							} else if (wire.delta.type === 'thinking_delta' && wire.delta.thinking) {
								if (wire.index !== undefined) {
									const block = thoughts.get(wire.index);
									if (block?.type === 'thinking') block.thinking += wire.delta.thinking;
								}
								reasoning += wire.delta.thinking;
								thinking = true;
								const shown = thinkUnmasker.push(wire.delta.thinking);
								if (shown) yield { type: 'reasoning', text: shown };
							} else if (wire.delta.type === 'text_delta' && wire.delta.text) {
								// The thinking is over once the answer begins: release what the unmasker held back
								if (thinking) {
									thinking = false;
									const rest = thinkUnmasker.flush();
									if (rest) yield { type: 'reasoning', text: rest };
								}
								content += wire.delta.text;
								const out = unmasker.push(guard.push(wire.delta.text));
								if (out) yield { type: 'delta', text: out };
							} else if (
								wire.delta.type === 'input_json_delta' &&
								wire.delta.partial_json &&
								wire.index !== undefined
							) {
								const piece = calls.get(wire.index);
								if (piece) piece.arguments += wire.delta.partial_json;
							}
						} else if (wire.type === 'message_delta') {
							if (wire.delta?.stop_reason) finishReason = finishReasonOf(wire.delta.stop_reason);
							if (wire.usage?.output_tokens) reportedOut = wire.usage.output_tokens;
							// Some replies repeat the input figures here. Each figure that is present is the latest; one that is absent keeps its earlier value
							const u = wire.usage;
							if (u) {
								// A figure counts only when it is a number: a null keeps the value from message_start
								const num = (v: unknown): v is number => typeof v === 'number';
								if (num(u.input_tokens)) reportedUncached = u.input_tokens;
								if (num(u.cache_read_input_tokens)) reportedRead = u.cache_read_input_tokens;
								if (num(u.cache_creation_input_tokens))
									reportedWrite = u.cache_creation_input_tokens;
								if (num(u.cache_creation?.ephemeral_1h_input_tokens))
									reportedWrite1h = u.cache_creation.ephemeral_1h_input_tokens;
								if (
									num(u.input_tokens) ||
									num(u.cache_read_input_tokens) ||
									num(u.cache_creation_input_tokens)
								)
									reportedPrompt = reportedUncached + reportedRead + reportedWrite;
							}
						} else if (wire.type === 'message_stop') {
							break read;
						} else if (wire.type === 'error') {
							// The provider broke mid-answer: this is a model failure, never a short answer
							throw new OpsError('UNAVAILABLE', DOWN);
						}
					}
				}
				if (thinking) {
					const left = thinkUnmasker.flush();
					if (left) yield { type: 'reasoning', text: left };
				}
				const rest = unmasker.push(guard.flush()) + unmasker.flush();
				if (rest) yield { type: 'delta', text: rest };
				completed = true;
			} finally {
				// Record what was used even when the app disconnected half way, and stop the upstream call
				await reader.cancel().catch(() => undefined);
				// Streamed usage counts whichever side arrived; the missing side is the rough estimate
				final =
					reportedPrompt !== null || reportedOut !== null
						? {
								promptTokens:
									reportedPrompt ?? estimateTokens(JSON.stringify(body.messages).length),
								completionTokens: reportedOut ?? estimateTokens(content.length + reasoning.length),
								cacheReadTokens: reportedRead,
								cacheWriteTokens: reportedWrite,
								cacheWrite1hTokens: reportedWrite1h
							}
						: {
								promptTokens: estimateTokens(JSON.stringify(body.messages).length),
								completionTokens: estimateTokens(content.length + reasoning.length)
							};
				await core.record(ctx, req.bucket, final);
				core.log(ctx, req.bucket, Date.now() - started, final, completed, toolDetail(req));
			}
			const written = readWrittenCalls(
				content,
				[...calls.values()].map((c) => ({
					id: c.id,
					type: 'function' as const,
					function: { name: c.name, arguments: c.arguments || '{}' }
				})),
				finishReason,
				toolsOffered(req)
			);
			// In the order they came, and only whole ones: a thinking block with no signature would be refused when it goes back
			const wireBlocks = [...thoughts.entries()]
				.sort((a, b) => a[0] - b[0])
				.map(([, b]) => b)
				.filter((b) => b.type === 'redacted_thinking' || b.signature !== '');
			yield {
				type: 'done',
				completion: {
					...finish(masker, written.content, written.calls, written.finishReason, final),
					charged: core.charged(final),
					provider: 'anthropic' as const,
					...(wireBlocks.length ? { wireBlocks } : {}),
					...(reasoning ? { reasoningRaw: masker.unmask(reasoning) } : {})
				}
			};
		}
	};
}

export type ModelClient = ReturnType<typeof createAnthropicClient>;
