// THE DEEPSEEK CLIENT: THE ONLY PLACE THAT HOLDS THE API KEY AND TALKS TO THE MODEL.
// Every call: rate limit, monthly budget, mask the payload, call with a timeout and retries, unmask the reply, record the tokens.
// Message text is never logged. The key is read once from the server environment and is never returned or written anywhere.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Bucket, Limits, Usage } from './limits';
import type { Masker } from './mask';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
// -- MODULES -- //
import { OpsError, run } from '../ops/context';
import { createDsmlGuard, splitDsml } from './dsml';
import { assertBudget, createRateLimiter, recordUsage } from './limits';
import { createMasker } from './mask';

// -- TYPES -- //

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
			/** The model's own thinking, which DeepSeek wants back while a tool round continues. Masked like the rest on its way out. */
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
	usage?: { prompt_tokens?: number; completion_tokens?: number };
};

// -- CONSTANTS -- //

const RETRY_STATUS = new Set([429, 500, 502, 503, 504]);
const DOWN = 'The assistant is not available right now.';

// -- FUNCTIONS -- //

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** A rough token count for when the model reports none: about four characters per token. */
const estimateTokens = (chars: number) => Math.ceil(chars / 4);

/** Rejects with UNAVAILABLE when `work` takes longer than `ms`. Used between the pieces of a stream and for reading a body. */
function within<T>(work: Promise<T>, ms: number): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const late = new Promise<never>((_, reject) => {
		timer = setTimeout(() => reject(new OpsError('UNAVAILABLE', DOWN)), ms);
	});
	return Promise.race([work, late]).finally(() => clearTimeout(timer));
}

function maskMessages(messages: ChatMessage[], masker: Masker): ChatMessage[] {
	return messages.map((m): ChatMessage => {
		if (m.role === 'assistant') {
			return {
				...m,
				content: m.content === null ? null : masker.mask(m.content),
				// Real values restored for the screen go back masked, with the same placeholders as before (one masker per turn)
				...(m.reasoning_content ? { reasoning_content: masker.mask(m.reasoning_content) } : {}),
				...(m.tool_calls
					? {
							tool_calls: m.tool_calls.map((c) => ({
								...c,
								function: { ...c.function, arguments: masker.mask(c.function.arguments) }
							}))
						}
					: {})
			};
		}
		return { ...m, content: masker.mask(m.content) };
	});
}

const userTag = (userId: string) => createHash('sha256').update(userId).digest('hex').slice(0, 8);

export function createModelClient(config: ModelConfig) {
	const doFetch = config.fetch ?? fetch;
	const sleep = config.sleep ?? defaultSleep;
	const timeoutMs = config.timeoutMs ?? 60_000;
	const maxRetries = config.maxRetries ?? 2;
	const defaultMaxTokens = config.defaultMaxTokens ?? 2048;
	const thinkingMaxTokens = config.thinkingMaxTokens ?? 8192;
	const rate = createRateLimiter(config.limits.ratePerMinute);

	/** Rate limit, then the monthly budget. Nothing leaves the server before both pass. */
	async function admit(ctx: Ctx, bucket: Bucket): Promise<void> {
		if (!rate.take(ctx.actor.userId))
			throw new OpsError('LIMIT', 'Too many requests. Try again in a minute.');
		await run(ctx, (tx, userId) => assertBudget(tx, userId, bucket, config.limits));
	}

	/**
	 * The request to the model, with a start timeout and retries. The key goes only in the Authorization header.
	 * The start timeout covers the wait for the first byte only: once the answer begins, a streamed reply may run as long as it needs.
	 */
	async function send(body: Record<string, unknown>, signal?: AbortSignal): Promise<Response> {
		let last = 'no response';
		for (let attempt = 0; attempt <= maxRetries; attempt++) {
			if (signal?.aborted) throw new OpsError('UNAVAILABLE', 'The request was cancelled.');
			const start = new AbortController();
			const timer = setTimeout(() => start.abort(), timeoutMs);
			try {
				const res = await doFetch(`${config.baseUrl}/chat/completions`, {
					method: 'POST',
					headers: { 'content-type': 'application/json', authorization: `Bearer ${config.apiKey}` },
					body: JSON.stringify(body),
					signal: signal ? AbortSignal.any([signal, start.signal]) : start.signal
				});
				clearTimeout(timer);
				if (res.ok) return res;
				last = `status ${res.status}`;
				if (res.status === 401 || res.status === 403)
					// A rejected key is a configuration problem. Nothing about it is shown to the person.
					console.error(
						JSON.stringify({ event: 'model_credentials_rejected', status: res.status })
					);
				if (!RETRY_STATUS.has(res.status)) break;
				const after = Number(res.headers.get('retry-after'));
				await sleep(
					Math.min(5000, Number.isFinite(after) && after > 0 ? after * 1000 : 400 * 2 ** attempt)
				);
			} catch (e) {
				clearTimeout(timer);
				if (signal?.aborted) throw new OpsError('UNAVAILABLE', 'The request was cancelled.');
				last = e instanceof Error ? e.name : 'error';
				if (attempt < maxRetries) await sleep(400 * 2 ** attempt);
			}
		}
		console.error(JSON.stringify({ event: 'model_unavailable', reason: last }));
		throw new OpsError('UNAVAILABLE', DOWN);
	}

	function buildBody(req: CompletionRequest, masker: Masker, stream: boolean) {
		// Thinking only for a streamed chat answer; the memory jobs never pay for it
		const thinking = stream && config.thinking === true && req.bucket === 'chat';
		return {
			model: config.model,
			messages: maskMessages(req.messages, masker),
			stream,
			...(stream ? { stream_options: { include_usage: true } } : {}),
			...(thinking ? { thinking: { type: 'enabled' } } : {}),
			...(req.tools?.length ? { tools: req.tools } : {}),
			// A thinking model ignores sampling settings, so none are sent
			...(req.temperature !== undefined && !thinking ? { temperature: req.temperature } : {}),
			// Every call has a ceiling, so one call can never spend more than this. Thinking shares it with the answer
			max_tokens: req.maxTokens ?? (thinking ? thinkingMaxTokens : defaultMaxTokens)
		};
	}

	function log(ctx: Ctx, req: CompletionRequest, ms: number, usage: Usage, ok: boolean) {
		// Counts and timings only. Never message text, names or amounts.
		console.info(
			JSON.stringify({
				event: 'model_call',
				u: userTag(ctx.actor.userId),
				bucket: req.bucket,
				ok,
				ms,
				promptTokens: usage.promptTokens,
				completionTokens: usage.completionTokens
			})
		);
	}

	/** Records the tokens. A failure here is logged loudly: the call was billed but the cap would not see it. */
	async function record(ctx: Ctx, bucket: Bucket, usage: Usage): Promise<void> {
		try {
			await run(ctx, (tx, userId) => recordUsage(tx, userId, bucket, usage));
		} catch (e) {
			console.error(
				JSON.stringify({
					event: 'usage_not_recorded',
					error: e instanceof Error ? e.name : 'Error'
				})
			);
		}
	}

	/**
	 * A call the model wrote as text (DSML) is read into a real call, and the markup never stays in the content. Real calls win: the text is
	 * only read when the model sent none. A cut-off answer is left to the "length" path, which never runs a call.
	 */
	function readWrittenCalls(
		content: string,
		calls: ToolCall[],
		finishReason: string,
		toolsOffered: boolean
	) {
		const split = splitDsml(content);
		// With no tools offered (the limit was reached) the markup is only removed: reading it would loop on refused calls
		if (
			!toolsOffered ||
			calls.length > 0 ||
			finishReason === 'length' ||
			split.calls.length === 0
		) {
			return { content: split.text, calls, finishReason };
		}
		return { content: split.text, calls: split.calls, finishReason: 'tool_calls' };
	}

	function finish(
		masker: Masker,
		content: string,
		toolCalls: ToolCall[],
		finishReason: string,
		usage: Usage
	): Completion {
		return {
			content: masker.unmask(content),
			toolCalls: toolCalls.map((c) => ({
				...c,
				// Values go back into the JSON string leaves only, so a name with a quote cannot break or extend the arguments
				function: { ...c.function, arguments: masker.unmaskJson(c.function.arguments) }
			})),
			finishReason,
			usage
		};
	}

	return {
		/** One answer, not streamed. */
		async complete(ctx: Ctx, req: CompletionRequest): Promise<Completion> {
			await admit(ctx, req.bucket);
			const masker = req.masker ?? createMasker(req.names);
			const body = buildBody(req, masker, false);
			const started = Date.now();
			const res = await send(body, req.signal);
			let wire: Wire;
			try {
				wire = (await within(res.json(), timeoutMs)) as Wire;
			} catch {
				throw new OpsError('UNAVAILABLE', DOWN);
			}
			const choice = wire.choices?.[0];
			const content = choice?.message?.content ?? '';
			const usage: Usage = {
				promptTokens:
					wire.usage?.prompt_tokens ?? estimateTokens(JSON.stringify(body.messages).length),
				completionTokens: wire.usage?.completion_tokens ?? estimateTokens(content.length)
			};
			await record(ctx, req.bucket, usage);
			log(ctx, req, Date.now() - started, usage, true);
			const written = readWrittenCalls(
				content,
				choice?.message?.tool_calls ?? [],
				choice?.finish_reason ?? 'stop',
				(req.tools?.length ?? 0) > 0
			);
			return finish(masker, written.content, written.calls, written.finishReason, usage);
		},

		/** A streamed answer: text pieces as they arrive, then one final event with the whole completion. */
		async *stream(ctx: Ctx, req: CompletionRequest): AsyncGenerator<StreamEvent> {
			await admit(ctx, req.bucket);
			const masker = req.masker ?? createMasker(req.names);
			const unmasker = masker.streamUnmasker();
			// A tool call the model wrote as text is held back here, so no piece of it is shown
			const guard = createDsmlGuard();
			// The thinking has its own unmasker, so a placeholder split inside it is never mixed with the answer's
			const thinkUnmasker = masker.streamUnmasker();
			const body = buildBody(req, masker, true);
			const started = Date.now();
			const res = await send(body, req.signal);
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
						if (wire.usage)
							reported = {
								promptTokens: wire.usage.prompt_tokens ?? 0,
								completionTokens: wire.usage.completion_tokens ?? 0
							};
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
					promptTokens: estimateTokens(JSON.stringify(body.messages).length),
					completionTokens: estimateTokens(content.length + reasoning.length)
				};
				await record(ctx, req.bucket, final);
				log(ctx, req, Date.now() - started, final, completed);
			}
			const written = readWrittenCalls(
				content,
				calls.filter(Boolean),
				finishReason,
				(req.tools?.length ?? 0) > 0
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

export type ModelClient = ReturnType<typeof createModelClient>;
