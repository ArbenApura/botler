// THE SHARED MODEL-CALL MACHINERY, PROVIDER-NEUTRAL. Every provider runs the same rate limit, monthly
// budget, payload masking, timeout and retries, usage recording and call log, so the privacy and money
// rules cannot drift between providers. Message text is never logged; the key lives only in these headers.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Bucket, Limits, Provider, RateLimiter, Usage } from './limits';
import type { ChatMessage, CompletionRequest, ToolCall } from './types';
import type { Masker } from './mask';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
// -- MODULES -- //
import { OpsError, run } from '../ops/context';
import { splitDsml } from './dsml';
import { assertBudget, BudgetError, chargedTokens, createRateLimiter, recordUsage } from './limits';
import { createMasker } from './mask';

// -- TYPES -- //

export type CoreSend = (args: {
	url: string;
	headers: Record<string, string>;
	body: Record<string, unknown>;
	signal?: AbortSignal;
}) => Promise<Response>;

/** Everything each provider hands over to the shared layer. */
export type CoreConfig = {
	/** Which host this client talks to: recorded with every call and named in the log. */
	provider: Exclude<Provider, 'unknown'>;
	model: string;
	limits: Limits;
	/** The per-minute counter. Left out, the client makes its own; the app passes one shared by every provider. */
	rateLimiter?: RateLimiter;
	timeoutMs: number;
	maxRetries: number;
	fetch: typeof fetch;
	sleep: (ms: number) => Promise<void>;
};

// -- CONSTANTS -- //

export const RETRY_STATUS = new Set([429, 500, 502, 503, 504]);
export const DOWN = 'The assistant is not available right now.';

// -- FUNCTIONS -- //

export const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** A rough token count for when the model reports none: about four characters per token. */
export const estimateTokens = (chars: number) => Math.ceil(chars / 4);

/** What one picture counts as in an estimate of tokens, whatever its size in bytes. */
export const IMAGE_TOKENS = 1600;

/**
 * A JSON.stringify replacer for any estimate of size taken from messages: a picture's base64 becomes a stand-in of the size a picture counts
 * as, so six pictures never read as a million tokens. Anything else called data and that long is a signed thinking block, also nearer the stand-in.
 */
export function imageStandIn(key: string, value: unknown): unknown {
	return key === 'data' && typeof value === 'string' && value.length > 1000
		? 'x'.repeat(IMAGE_TOKENS * 4)
		: value;
}

/** The messages without any picture: for a host that reads text only, so no picture bytes ever reach it. */
export function withoutImages(messages: ChatMessage[]): ChatMessage[] {
	return messages.some((m) => (m.role === 'user' || m.role === 'system') && m.images)
		? messages.map((m) => {
				if ((m.role !== 'user' && m.role !== 'system') || !m.images) return m;
				const { images: _dropped, ...rest } = m;
				return rest;
			})
		: messages;
}

/** The estimate of tokens in messages or a wire body, with pictures counted at IMAGE_TOKENS each. */
export const estimateJsonTokens = (value: unknown): number =>
	estimateTokens(JSON.stringify(value, imageStandIn).length);

/** An estimate of the tokens in the stable prefix (the first `count` messages), for the log. 0 when the caller named no prefix. */
export function stableTokens(messages: ChatMessage[], count?: number): number {
	return count ? estimateTokens(JSON.stringify(messages.slice(0, count)).length) : 0;
}

/** True when the request offers tools the model may call. With toolChoice 'none' the tools stay in the body (for the cache) but no call is read. */
export function toolsOffered(req: CompletionRequest): boolean {
	return (req.tools?.length ?? 0) > 0 && req.toolChoice !== 'none';
}

/** The log detail every client adds to its model_call line. */
export function toolDetail(req: CompletionRequest) {
	return {
		stableTokens: stableTokens(req.messages, req.stableCount),
		toolsOff: (req.tools?.length ?? 0) > 0 && req.toolChoice === 'none'
	};
}

/** Rejects with UNAVAILABLE when `work` takes longer than `ms`. Used between the pieces of a stream and for reading a body. */
export function within<T>(work: Promise<T>, ms: number): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const late = new Promise<never>((_, reject) => {
		timer = setTimeout(() => reject(new OpsError('UNAVAILABLE', DOWN)), ms);
	});
	return Promise.race([work, late]).finally(() => clearTimeout(timer));
}

export function maskMessages(messages: ChatMessage[], masker: Masker): ChatMessage[] {
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

/**
 * The provider-neutral half of a model client: admission (rate limit, then budget), the request with a
 * start timeout and retries, usage recording and the log. The key goes only in the headers the provider
 * builds for it.
 */
export function createCore(config: CoreConfig) {
	// One limiter can be shared by several clients, so a person cannot double the rate by switching provider
	const rate = config.rateLimiter ?? createRateLimiter(config.limits.ratePerMinute);

	/** One line when a call is refused, so a capped chat is visible in the log. Counts only. */
	function refused(
		ctx: Ctx,
		bucket: Bucket,
		why: { reason: 'rate' | 'person_cap' | 'global_cap'; used?: number; cap?: number }
	) {
		console.warn(
			JSON.stringify({
				event: 'model_call_refused',
				u: userTag(ctx.actor.userId),
				bucket,
				reason: why.reason,
				...(why.used !== undefined ? { used: why.used, cap: why.cap } : {})
			})
		);
	}

	/** Rate limit, then the monthly budget. Nothing leaves the server before both pass. */
	async function admit(ctx: Ctx, bucket: Bucket): Promise<void> {
		if (!rate.take(ctx.actor.userId)) {
			refused(ctx, bucket, { reason: 'rate' });
			throw new OpsError('LIMIT', 'Too many requests. Try again in a minute.');
		}
		try {
			await run(ctx, (tx, userId) => assertBudget(tx, userId, bucket, config.limits));
		} catch (e) {
			if (e instanceof BudgetError) refused(ctx, bucket, e.detail);
			throw e;
		}
	}

	/**
	 * The request to the model, with a start timeout and retries. The start timeout covers the wait for the
	 * first byte only: once the answer begins, a streamed reply may run as long as it needs.
	 */
	const send: CoreSend = async ({ url, headers, body, signal }) => {
		let last = 'no response';
		for (let attempt = 0; attempt <= config.maxRetries; attempt++) {
			if (signal?.aborted) throw new OpsError('UNAVAILABLE', 'The request was cancelled.');
			const start = new AbortController();
			const timer = setTimeout(() => start.abort(), config.timeoutMs);
			try {
				const res = await config.fetch(url, {
					method: 'POST',
					headers,
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
				await config.sleep(
					Math.min(5000, Number.isFinite(after) && after > 0 ? after * 1000 : 400 * 2 ** attempt)
				);
			} catch (e) {
				clearTimeout(timer);
				if (signal?.aborted) throw new OpsError('UNAVAILABLE', 'The request was cancelled.');
				last = e instanceof Error ? e.name : 'error';
				if (attempt < config.maxRetries) await config.sleep(400 * 2 ** attempt);
			}
		}
		console.error(JSON.stringify({ event: 'model_unavailable', reason: last }));
		throw new OpsError('UNAVAILABLE', DOWN);
	};

	function log(
		ctx: Ctx,
		bucket: Bucket,
		startedMs: number,
		usage: Usage,
		ok: boolean,
		detail: { stableTokens?: number; toolsOff?: boolean } = {}
	) {
		const read = usage.cacheReadTokens ?? 0;
		const write = usage.cacheWriteTokens ?? 0;
		// Counts and timings only. Never message text, names or amounts.
		console.info(
			JSON.stringify({
				event: 'model_call',
				u: userTag(ctx.actor.userId),
				bucket,
				ok,
				ms: startedMs,
				provider: config.provider,
				model: config.model,
				promptTokens: usage.promptTokens,
				completionTokens: usage.completionTokens,
				cacheRead: read,
				cacheWrite: write,
				// Input that was neither read from nor written to the cache
				miss: Math.max(0, usage.promptTokens - read - write),
				charged: chargedTokens(usage, config.provider),
				stableTokens: detail.stableTokens ?? 0,
				toolsOff: detail.toolsOff === true
			})
		);
	}

	/** Records the tokens. A failure here is logged loudly: the call was billed but the cap would not see it. */
	async function record(ctx: Ctx, bucket: Bucket, usage: Usage): Promise<void> {
		try {
			await run(ctx, (tx, userId) => recordUsage(tx, userId, bucket, usage, config.provider));
		} catch (e) {
			console.error(
				JSON.stringify({
					event: 'usage_not_recorded',
					error: e instanceof Error ? e.name : 'Error'
				})
			);
		}
	}

	/** What a call counts against the monthly cap, for the turn's own per-message budget. */
	const charged = (usage: Usage): number => chargedTokens(usage, config.provider);

	return { admit, send, log, record, charged };
}

/** Builds the masker for a request: one masker per turn when the caller brought one. */
export function maskerFor(req: CompletionRequest) {
	return req.masker ?? createMasker(req.names);
}

/**
 * A call the model wrote as text (DSML) is read into a real call, and the markup never stays in the content. Real calls win: the text is
 * only read when the model sent none. A cut-off answer is left to the "length" path, which never runs a call.
 */
export function readWrittenCalls(
	content: string,
	calls: ToolCall[],
	finishReason: string,
	toolsOffered: boolean
) {
	const split = splitDsml(content);
	// With no tools offered (the limit was reached) the markup is only removed: reading it would loop on refused calls
	if (!toolsOffered || calls.length > 0 || finishReason === 'length' || split.calls.length === 0) {
		return { content: split.text, calls, finishReason };
	}
	return { content: split.text, calls: split.calls, finishReason: 'tool_calls' };
}

/** Puts the real values back into the answer, and into the string leaves of each tool call's arguments only. */
export function finish(
	masker: Masker,
	content: string,
	toolCalls: ToolCall[],
	finishReason: string,
	usage: Usage
) {
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
