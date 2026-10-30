// THE DEEPSEEK CLIENT: THE OPENAI-STYLE WIRE FORMAT (chat/completions), FOR WHEN MODEL_PROVIDER IS deepseek.
// Every shared rule (rate limit, monthly budget, masking, timeout, retries, usage recording, the log) lives in
// proxy/core.ts. Message text is never logged. The key is read once from the server environment and is never
// returned or written anywhere.
//
// PROMPT CACHING: DeepSeek caches automatically and on a best effort basis. A prefix is cached on disk after it is seen, in seconds, and
// kept for hours to days, so a hit is never assumed in the cap. There are no markers to send. What helps is ORDER: the tool definitions,
// then the system message, then the history (which only grows at its end), then the turn context and the new message last. Anything that
// changes from call to call must sit after everything that does not. The usage fields prompt_cache_hit_tokens and
// prompt_cache_miss_tokens say what was served from the cache.

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
	ToolCall,
	ToolDef
} from './types';
// -- MODULES -- //
import {
	createCore,
	DOWN,
	estimateJsonTokens,
	estimateTokens,
	finish,
	maskerFor,
	maskMessages,
	readWrittenCalls,
	toolDetail,
	toolsOffered,
	within,
	withoutImages
} from './core';
import { defaultSleep } from './core';
import { createDsmlGuard } from './dsml';
import { OpsError } from '../ops/context';
import { DEFAULT_CHAT_MAX_TOKENS, deepseekEffort } from './chatEnv';

// -- CONSTANTS -- //

/** The wait for the first byte, and the longest silence inside a streamed answer. A long thinking phase can be quiet for a while. */
export const STREAM_TIMEOUT_MS = 120_000;

type Wire = {
	choices?: {
		message?: { content?: string | null; tool_calls?: ToolCall[] };
		delta?: {
			content?: string | null;
			reasoning_content?: string | null;
			tool_calls?: {
				index: number;
				id?: string;
				function?: { name?: string; arguments?: string };
			}[];
		};
		finish_reason?: string | null;
	}[];
	usage?: {
		prompt_tokens?: number;
		completion_tokens?: number;
		prompt_cache_hit_tokens?: number;
		prompt_cache_miss_tokens?: number;
	};
};

/** Reads the usage block. A reply with no cache fields counts as zero cache read and is noted once in the log, so an API change shows. */
function readUsage(u: NonNullable<Wire['usage']>, fallbackPrompt: number): Usage {
	const hit = u.prompt_cache_hit_tokens;
	if (hit === undefined && !cacheFieldsNoted) {
		cacheFieldsNoted = true;
		console.warn(JSON.stringify({ event: 'cache_fields_missing', provider: 'deepseek' }));
	}
	return {
		// With no prompt_tokens the hit and miss figures still say how much went in
		promptTokens:
			u.prompt_tokens ??
			Math.max(
				fallbackPrompt,
				(u.prompt_cache_hit_tokens ?? 0) + (u.prompt_cache_miss_tokens ?? 0)
			),
		completionTokens: u.completion_tokens ?? 0,
		cacheReadTokens: Math.max(0, hit ?? 0),
		cacheWriteTokens: 0
	};
}

let cacheFieldsNoted = false;

// -- FUNCTIONS -- //

/**
 * The masked messages as this host takes them. A user message with pictures becomes a list of parts: each picture as an image_url data URL, then
 * the words. The pictures were never masked and are not changed here. A picture on any other role is dropped: the host takes them in user messages only.
 */
function withPictureParts(messages: ChatMessage[]): unknown[] {
	return messages.map((m) => {
		if (m.role !== 'user' || !m.images?.length) return withoutImages([m])[0];
		const { images, ...rest } = m;
		return {
			...rest,
			content: [
				...images.map((img) => ({
					type: 'image_url',
					image_url: { url: `data:${img.mediaType};base64,${img.data}` }
				})),
				{ type: 'text', text: m.content }
			]
		};
	});
}

export function createModelClient(config: ModelConfig) {
	const core = createCore({
		provider: 'deepseek',
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

	/** The body for one call, with the masked messages. Thinking only for a streamed chat answer. */
	function buildBody(req: CompletionRequest, masker: Masker, stream: boolean) {
		const thinking = stream && config.thinking === true && req.bucket === 'chat';
		return {
			model: config.model,
			messages: withPictureParts(maskMessages(req.messages, masker)),
			stream,
			...(stream ? { stream_options: { include_usage: true } } : {}),
			...(thinking
				? { thinking: { type: 'enabled' }, reasoning_effort: deepseekEffort(chatEffort) }
				: {}),
			...(req.tools?.length ? { tools: req.tools } : {}),
			...(req.tools?.length && req.toolChoice === 'none' ? { tool_choice: 'none' } : {}),
			// A thinking model ignores sampling settings, so none are sent
			...(req.temperature !== undefined && !thinking ? { temperature: req.temperature } : {}),
			// Every call has a ceiling, so one call can never spend more than this. Thinking shares it with the answer
			max_tokens:
				req.maxTokens ??
				(thinking ? thinkingMaxTokens : req.bucket === 'chat' ? chatMaxTokens : defaultMaxTokens)
		};
	}

	const call = (body: Record<string, unknown>, signal?: AbortSignal): Promise<Response> =>
		core.send({
			url: `${config.baseUrl}/chat/completions`,
			headers: { 'content-type': 'application/json', authorization: `Bearer ${config.apiKey}` },
			body,
			signal
		});

	return {
		/** One answer, not streamed. */
		async complete(ctx: Ctx, req: CompletionRequest): Promise<Completion> {
			await core.admit(ctx, req.bucket);
			const masker = maskerFor(req);
			const body = buildBody(req, masker, false);
			const started = Date.now();
			const res = await call(body, req.signal);
			let wire: Wire;
			try {
				wire = (await within(res.json(), timeoutMs)) as Wire;
			} catch {
				throw new OpsError('UNAVAILABLE', DOWN);
			}
			const choice = wire.choices?.[0];
			const content = choice?.message?.content ?? '';
			const estimated = estimateJsonTokens(body.messages);
			const usage: Usage = wire.usage
				? {
						...readUsage(wire.usage, estimated),
						completionTokens: wire.usage.completion_tokens ?? estimateTokens(content.length)
					}
				: { promptTokens: estimated, completionTokens: estimateTokens(content.length) };
			await core.record(ctx, req.bucket, usage);
			core.log(ctx, req.bucket, Date.now() - started, usage, true, toolDetail(req));
			const written = readWrittenCalls(
				content,
				choice?.message?.tool_calls ?? [],
				choice?.finish_reason ?? 'stop',
				toolsOffered(req)
			);
			return finish(masker, written.content, written.calls, written.finishReason, usage);
		},

		/** A streamed answer: text pieces as they arrive, then one final event with the whole completion. */
		async *stream(ctx: Ctx, req: CompletionRequest): AsyncGenerator<StreamEvent> {
			await core.admit(ctx, req.bucket);
			const masker = maskerFor(req);
			const unmasker = masker.streamUnmasker();
			// A tool call the model wrote as text is held back here, so no piece of it is shown
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
			let reported: Usage | null = null;
			const calls: ToolCall[] = [];
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
						if (data === '[DONE]') break read;
						let wire: Wire;
						try {
							wire = JSON.parse(data) as Wire;
						} catch {
							continue;
						}
						if (wire.usage) reported = readUsage(wire.usage, 0);
						const choice = wire.choices?.[0];
						if (choice?.finish_reason) finishReason = choice.finish_reason;
						const thought = choice?.delta?.reasoning_content;
						if (thought) {
							reasoning += thought;
							thinking = true;
							const shown = thinkUnmasker.push(thought);
							if (shown) yield { type: 'reasoning', text: shown };
						}
						const text = choice?.delta?.content;
						// The thinking is over once the answer or a tool call begins: release what the unmasker held back
						if (thinking && (text || choice?.delta?.tool_calls?.length)) {
							thinking = false;
							const rest = thinkUnmasker.flush();
							if (rest) yield { type: 'reasoning', text: rest };
						}
						if (text) {
							content += text;
							const out = unmasker.push(guard.push(text));
							if (out) yield { type: 'delta', text: out };
						}
						for (const d of choice?.delta?.tool_calls ?? []) {
							const call = (calls[d.index] ??= {
								id: '',
								type: 'function',
								function: { name: '', arguments: '' }
							});
							if (d.id) call.id = d.id;
							if (d.function?.name) call.function.name += d.function.name;
							if (d.function?.arguments) call.function.arguments += d.function.arguments;
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
				final = reported ?? {
					promptTokens: estimateJsonTokens(body.messages),
					completionTokens: estimateTokens(content.length + reasoning.length)
				};
				await core.record(ctx, req.bucket, final);
				core.log(ctx, req.bucket, Date.now() - started, final, completed, toolDetail(req));
			}
			const written = readWrittenCalls(
				content,
				calls.filter(Boolean),
				finishReason,
				toolsOffered(req)
			);
			yield {
				type: 'done',
				completion: {
					...finish(masker, written.content, written.calls, written.finishReason, final),
					charged: core.charged(final),
					provider: 'deepseek' as const,
					...(reasoning ? { reasoningRaw: masker.unmask(reasoning) } : {})
				}
			};
		}
	};
}

export type ModelClient = ReturnType<typeof createModelClient>;
