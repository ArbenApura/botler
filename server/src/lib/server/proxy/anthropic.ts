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
	ToolCall
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
	within
} from './core';
import { defaultSleep } from './core';
import { createDsmlGuard } from './dsml';
import { OpsError } from '../ops/context';

// -- TYPES -- (local wire shapes)

type Block =
	| { type: 'text'; text: string }
	| { type: 'tool_use'; id: string; name: string; input: unknown }
	| { type: 'tool_result'; tool_use_id: string; content: string };

type WireMessage = { role: 'user' | 'assistant'; content: string | Block[] };

type UsageWire = {
	input_tokens?: number;
	output_tokens?: number;
	cache_read_input_tokens?: number;
	cache_creation_input_tokens?: number;
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
	content_block?: { type: string; id?: string; name?: string };
	delta?: {
		type?: string;
		text?: string;
		partial_json?: string;
		thinking?: string;
		stop_reason?: string;
	};
	usage?: UsageWire;
};

// -- FUNCTIONS -- //

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
 * an assistant turn is its text block (when it has one) behind its tool_use blocks, and its thinking is never
 * sent back (Anthropic wants a signed thinking block on the way back, which this build does not keep).
 * Tool arguments are taken from the originals (the turn loop sends the real values back) and masked into the
 * string leaves only: masking the whole arguments text could turn an unquoted number into a token and break
 * the JSON the input_schema expects. Messages and originals walk in step (maskMessages maps one to one).
 */
function toWire(
	messages: ChatMessage[],
	originals: ChatMessage[],
	masker: Masker
): { system?: string; turns: WireMessage[] } {
	let system: string | undefined;
	const turns: WireMessage[] = [];
	const lastUser = (): Block[] | null => {
		const last = turns[turns.length - 1];
		if (last && last.role === 'user' && Array.isArray(last.content)) return last.content;
		return null;
	};
	for (const [i, m] of messages.entries()) {
		if (m.role === 'system') {
			system = system ? `${system}\n\n${m.content}` : m.content;
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
			const blocks: Block[] = [];
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
	}
	return { system, turns };
}

export function createAnthropicClient(config: ModelConfig) {
	const core = createCore({
		limits: config.limits,
		timeoutMs: config.timeoutMs ?? 60_000,
		maxRetries: config.maxRetries ?? 2,
		fetch: config.fetch ?? fetch,
		sleep: config.sleep ?? defaultSleep
	});
	const defaultMaxTokens = config.defaultMaxTokens ?? 2048;
	const thinkingMaxTokens = config.thinkingMaxTokens ?? 8192;
	const timeoutMs = config.timeoutMs ?? 60_000;

	/** The body for one call. max_tokens is required on /v1/messages. Thinking is offered only to a streamed
	 * chat answer, and a thinking answer carries no tools: thinking is display-only in this build, because a
	 * thinking block would have to go back signed on the next round. */
	function buildBody(
		req: CompletionRequest,
		masker: Masker,
		stream: boolean
	): Record<string, unknown> {
		const thinking = stream && config.thinking === true && req.bucket === 'chat';
		const masked = maskMessages(req.messages, masker);
		const { system, turns } = toWire(masked, req.messages, masker);
		// The repo's tool definitions are OpenAI shaped; the wire wants input_schema
		const wireTools = !thinking
			? (req.tools ?? []).map((t) => ({
					name: t.function.name,
					description: t.function.description,
					input_schema: t.function.parameters
				}))
			: [];
		return {
			model: config.model,
			// Every call has a ceiling, so one call can never spend more than this. Thinking shares it with the answer
			max_tokens: req.maxTokens ?? (thinking ? thinkingMaxTokens : defaultMaxTokens),
			...(system ? { system } : {}),
			messages: turns,
			...(wireTools.length ? { tools: wireTools } : {}),
			// A thinking model ignores sampling settings, so none are sent while thinking
			...(req.temperature !== undefined && !thinking ? { temperature: req.temperature } : {}),
			...(thinking ? { thinking: { type: 'enabled', budget_tokens: 4096 } } : {}),
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
			const usage: Usage = wire.usage?.input_tokens
				? {
						promptTokens: promptTokensOf(wire.usage),
						completionTokens: wire.usage.output_tokens ?? 0
					}
				: {
						promptTokens: estimateTokens(JSON.stringify(body.messages).length),
						completionTokens: estimateTokens(flat.content.length)
					};
			await core.record(ctx, req.bucket, usage);
			core.log(ctx, req.bucket, Date.now() - started, usage, true);
			const written = readWrittenCalls(
				flat.content,
				flat.calls,
				finishReasonOf(wire.stop_reason),
				(req.tools?.length ?? 0) > 0
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
			let reportedOut: number | null = null;
			const calls = new Map<number, { id: string; name: string; arguments: string }>();
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
							if (wire.message?.usage) reportedPrompt = promptTokensOf(wire.message.usage);
						} else if (wire.type === 'content_block_start') {
							if (wire.index !== undefined && wire.content_block?.type === 'tool_use')
								calls.set(wire.index, {
									id: wire.content_block.id ?? '',
									name: wire.content_block.name ?? '',
									arguments: ''
								});
						} else if (wire.type === 'content_block_delta' && wire.delta?.type) {
							if (wire.delta.type === 'thinking_delta' && wire.delta.thinking) {
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
								completionTokens: reportedOut ?? estimateTokens(content.length + reasoning.length)
							}
						: {
								promptTokens: estimateTokens(JSON.stringify(body.messages).length),
								completionTokens: estimateTokens(content.length + reasoning.length)
							};
				await core.record(ctx, req.bucket, final);
				core.log(ctx, req.bucket, Date.now() - started, final, completed);
			}
			const written = readWrittenCalls(
				content,
				[...calls.values()].map((c) => ({
					id: c.id,
					type: 'function' as const,
					function: { name: c.name, arguments: c.arguments || '{}' }
				})),
				finishReason,
				// A thinking answer went out without tools on the wire, so its markup is only removed
				(req.tools?.length ?? 0) > 0 && !(config.thinking === true && req.bucket === 'chat')
			);
			yield {
				type: 'done',
				completion: {
					...finish(masker, written.content, written.calls, written.finishReason, final),
					...(reasoning ? { reasoningRaw: masker.unmask(reasoning) } : {})
				}
			};
		}
	};
}

export type ModelClient = ReturnType<typeof createAnthropicClient>;
