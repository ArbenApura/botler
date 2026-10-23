// THE TURN LOOP: ONE MESSAGE FROM THE PERSON, THE MODEL CALLED UP TO A FEW TIMES, TOOLS RUN BETWEEN THE CALLS.
// What this loop guarantees, whatever the model says:
// - The caller is the session's person, set here. A tool call can never name another user (the schemas hold no user id and are strict).
// - Reads run. Records (free verbs) run. A change to the money plan (gated) only ever becomes an approval card. Person-only verbs are not offered.
// - Once untrusted text enters the turn (a web page, a photo's text, anything a tool marks untrusted), every write verb for the rest of
//   the turn becomes a card too, and web reading is closed except for addresses the person typed themselves, so the model cannot carry
//   private text out in an address. Web search stays open but short: a plain query of a few words, none with a run of digits.
// - Bounded: at most 6 model calls, 12 tool calls, 3 web searches, a time limit per tool. A cancelled request stops the model call and runs no more tools.
// - A model that is down or over its cap ends the turn with a fallback event: the app shows the manual form, and the verbs still work.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type {
	ChatMessage,
	Completion,
	CompletionRequest,
	StreamEvent,
	ToolCall
} from '../proxy/deepseek';
import type { AgentTool, WebDeps } from './tools';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
// -- MODULES -- //
import { createAction } from '../ops/actions';
import { OpsError } from '../ops/context';
import { invokeVerb } from '../ops/registry';
import { getSettings, SETTING_DEFAULTS } from '../ops/settings';
import { createMasker } from '../proxy/mask';
import { buildMessages } from './prompt';
import { buildTools, toDefs, WEB_READ, WEB_SEARCH } from './tools';

// -- TYPES -- //

export type TurnEvent =
	// Live only: start, phase, reasoning and tool_start are shown while the turn runs and are never stored or replayed
	| { type: 'start'; turnId?: string; chatId?: string }
	| { type: 'phase'; phase: 'thinking' | 'writing' }
	| { type: 'reasoning'; text: string }
	| { type: 'tool_start'; id: string; name: string }
	| { type: 'delta'; text: string }
	| {
			type: 'tool';
			/** The model's call id, so the screen can match this to its tool_start. Missing on events stored before it existed. */
			id?: string;
			name: string;
			status: 'ok' | 'error' | 'needs_approval' | 'blocked';
			data?: unknown;
			message?: string;
	  }
	| { type: 'card'; actionId: string; summary: string }
	| { type: 'fallback'; reason: 'down' | 'capped' | 'rate'; form: 'expense' }
	| {
			type: 'done';
			reply: string;
			stopped?: 'depth' | 'tools' | 'cancelled' | 'length';
			toolsRun: string[];
	  };

export type TurnModel = { stream(ctx: Ctx, req: CompletionRequest): AsyncGenerator<StreamEvent> };

export type TurnParams = {
	/** The signed in person's context. Only its user id is used, and it is the only place a user id comes from. */
	ctx: Ctx;
	model: TurnModel;
	history: ChatMessage[];
	userText: string;
	/** Text read from a photo on the phone. Untrusted. */
	ocrText?: string;
	/** The chat message id: the request ids of this turn's writes are made from it, so a re-run repeats nothing. */
	turnKey: string;
	names?: string[];
	persona?: string;
	memories?: string[];
	/** Recent approval cards and how each was answered, so the assistant knows what was approved, rejected or is still waiting. */
	cards?: string[];
	/** In a branched chat: what the cut-off messages already did. Made by the server from verb names, never from message text. */
	rewindNote?: string;
	/** The person's currency and how the assistant replies, read from their settings. */
	currency?: string;
	replyLanguage?: 'auto' | 'en' | 'fil' | 'taglish';
	signal?: AbortSignal;
	now?: Date;
	tools?: AgentTool[];
	web?: WebDeps;
	limits?: Partial<typeof LIMITS>;
};

type Outcome = {
	status: 'ok' | 'error' | 'needs_approval' | 'blocked';
	forModel: string;
	data?: unknown;
	message?: string;
	card?: { actionId: string; summary: string };
};

// -- CONSTANTS -- //

export const LIMITS = {
	maxModelCalls: 6,
	maxToolCalls: 12,
	/** Web searches in one message, so a poor result can be tried again with other words but quota and what a search can carry out stay small. */
	maxWebSearches: 3,
	/** After untrusted text was read, a search this long or longer is blocked, and so is one holding a run of digits like an account number. */
	maxTaintedQueryChars: 80,
	toolTimeoutMs: 15_000,
	webTimeoutMs: 25_000,
	maxResultChars: 6_000,
	maxEventChars: 20_000
};

// -- FUNCTIONS -- //

/** What untrusted text did to a turn so far. */
export class TurnState {
	tainted = false;
	/** Web searches started in this message, counted before each runs so a failed or slow one still counts. */
	searches = 0;
	readonly reasons = new Set<string>();
	constructor(readonly userUrls: ReadonlySet<string> = new Set()) {}
	taint(reason: string) {
		this.tainted = true;
		this.reasons.add(reason);
	}
}

/** Addresses written in the person's own message, in a form that compares equal. */
export function urlsIn(text: string): Set<string> {
	const out = new Set<string>();
	for (const m of text.matchAll(/https?:\/\/[^\s<>"')]+/gi)) {
		try {
			out.add(new URL(m[0].replace(/[.,;:!?]+$/, '')).toString());
		} catch {
			// Not an address
		}
	}
	return out;
}

const normalizeUrl = (u: unknown): string | null => {
	try {
		return new URL(String(u)).toString();
	} catch {
		return null;
	}
};

/** A search query that is short and holds no run of five digits (the shape of an account number or a balance). */
function plainQuery(query: unknown, max: number): boolean {
	return (
		typeof query === 'string' &&
		query.length <= max &&
		!/\d{5}/.test(query.replace(/[^\p{L}\p{N}]/gu, ''))
	);
}

/** A tool result that is only an error text the tool wrote itself. Checked on the object's own keys, never by searching its text. */
function isPlainError(result: unknown): boolean {
	if (!result || typeof result !== 'object' || Array.isArray(result)) return false;
	const keys = Object.keys(result);
	return (
		keys.length === 1 &&
		keys[0] === 'error' &&
		typeof (result as { error: unknown }).error === 'string'
	);
}

function capJson(value: unknown, max: number): string {
	const text = JSON.stringify(value) ?? 'null';
	return text.length <= max
		? text
		: JSON.stringify({ truncated: true, preview: text.slice(0, max - 80) });
}

function withTimeout<T>(work: Promise<T>, ms: number, what: string): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const late = new Promise<never>((_, reject) => {
		timer = setTimeout(() => reject(new OpsError('UNAVAILABLE', `${what} took too long.`)), ms);
	});
	return Promise.race([work, late]).finally(() => clearTimeout(timer));
}

async function executeTool(
	p: TurnParams,
	limits: typeof LIMITS,
	state: TurnState,
	byName: ReadonlyMap<string, AgentTool>,
	call: ToolCall,
	seq: number
): Promise<Outcome> {
	const err = (code: string, message: string, status: Outcome['status'] = 'error'): Outcome => ({
		status,
		message,
		forModel: JSON.stringify({ error: code, message })
	});
	const tool = byName.get(call.function.name);
	if (!tool) return err('unknown_tool', `There is no tool called ${call.function.name}.`);
	let args: Record<string, unknown>;
	try {
		const parsed: unknown = JSON.parse(call.function.arguments || '{}');
		if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed))
			throw new Error('not an object');
		args = parsed as Record<string, unknown>;
	} catch {
		return err(
			'invalid_arguments',
			'The arguments were not a JSON object. Call the tool again with valid JSON.'
		);
	}
	// The caller is built here from the session. Nothing in `args` can change it
	const agentCtx: Ctx = {
		handle: p.ctx.handle,
		actor: { userId: p.ctx.actor.userId, kind: 'agent', tool: tool.name },
		channel: 'chat',
		turnId: createHash('sha256').update(p.turnKey).digest('hex').slice(0, 32),
		// Hashed so a long client message id cannot cut the sequence number off and make every write of a turn share one id
		requestId: `t-${createHash('sha256').update(p.turnKey).digest('hex').slice(0, 40)}-${seq}`
	};

	// -- WEB -- //
	if (tool.kind === 'web' && tool.web) {
		if (tool.name === WEB_SEARCH) {
			// Counted before the call, tainted or not, and a blocked or failed search still counts
			state.searches += 1;
			if (state.searches > limits.maxWebSearches)
				return err(
					'blocked',
					`At most ${limits.maxWebSearches} searches are allowed in one message. Answer with what you have.`,
					'blocked'
				);
			// After untrusted text, a query may not be a way to carry text out: it must be short and hold nothing like an account number
			if (state.tainted && !plainQuery(args.query, limits.maxTaintedQueryChars))
				return err(
					'blocked',
					'Untrusted text was already read in this message, so only a short search with plain words is allowed now. Do not put numbers or personal details in it.',
					'blocked'
				);
		} else if (state.tainted) {
			const typed = tool.name === WEB_READ && state.userUrls.has(normalizeUrl(args.url) ?? '');
			if (!typed)
				return err(
					'blocked',
					'Untrusted text was already read in this message, so opening addresses is turned off. Only an address the person typed can be opened.',
					'blocked'
				);
		}
		try {
			const result = await withTimeout(
				tool.web(args, p.web ?? {}, p.signal),
				limits.webTimeoutMs,
				'The web'
			);
			// Whatever came back from the web closes the door on writes. The one exception is a plain error the tool wrote itself (an own
			// "error" text and no "untrusted" key): nothing from outside came back. Anything else fails closed and taints
			if (!isPlainError(result)) state.taint(tool.name === WEB_SEARCH ? 'web-search' : 'web-page');
			return { status: 'ok', forModel: capJson(result, limits.maxResultChars) };
		} catch (e) {
			if (e instanceof OpsError) return err('unavailable', e.message);
			if (e instanceof Error && e.name === 'ZodError')
				return err('invalid_arguments', 'The arguments do not match the tool.');
			console.error(
				JSON.stringify({
					event: 'web_tool_error',
					tool: tool.name,
					error: e instanceof Error ? e.name : 'Error'
				})
			);
			return err('internal', 'That did not work.');
		}
	}

	// -- A CHANGE THE PERSON MUST APPROVE -- //
	const asCard = async (why: string): Promise<Outcome> => {
		try {
			const card = await createAction(agentCtx, { verb: tool.name, args, turnId: p.turnKey });
			return {
				status: 'needs_approval',
				card,
				message: card.summary,
				forModel: JSON.stringify({
					status: 'needs_approval',
					summary: card.summary,
					note: `${why} A card was made. Tell the person to approve it in the app. It is not done yet.`
				})
			};
		} catch (e) {
			if (e instanceof OpsError) return err(e.code.toLowerCase(), e.message);
			throw e;
		}
	};
	if (tool.kind === 'gated')
		return asCard('This changes the plan, so it needs the person to approve it.');
	if (tool.kind === 'free' && state.tainted)
		return asCard('Untrusted text was read in this message, so even records wait for approval.');

	// -- A READ OR A RECORD -- //
	try {
		const result = await withTimeout(
			invokeVerb(agentCtx, tool.name, args),
			limits.toolTimeoutMs,
			tool.name
		);
		// A read that can hold text other people wrote (a calendar) is untrusted like a web page: it is marked, and the turn is
		// closed to writes from here on
		if (tool.taints) {
			state.taint(tool.name);
			return {
				status: 'ok',
				data: result,
				forModel: capJson(
					{ untrusted: true, source: tool.name, data: result },
					limits.maxResultChars
				)
			};
		}
		return {
			status: 'ok',
			data: result,
			forModel: capJson(result, limits.maxResultChars)
		};
	} catch (e) {
		if (e instanceof OpsError) {
			// A free verb that turns out to need approval for this input (a payment on a bill whose amount varies)
			if (e.code === 'FORBIDDEN' && tool.kind === 'free')
				return asCard('This one needs the person to approve it.');
			return err(e.code.toLowerCase(), e.message);
		}
		console.error(
			JSON.stringify({
				event: 'tool_error',
				tool: tool.name,
				error: e instanceof Error ? e.name : 'Error'
			})
		);
		return err('internal', 'That did not work.');
	}
}

/** Runs one message from the person to the end, yielding what the app should show as it happens. */
export async function* runTurn(p: TurnParams): AsyncGenerator<TurnEvent> {
	const limits = { ...LIMITS, ...p.limits };
	const tools = p.tools ?? buildTools();
	const byName = new Map(tools.map((t) => [t.name, t]));
	const defs = toDefs(tools);
	const state = new TurnState(urlsIn(p.userText));
	if (p.ocrText) state.taint('photo');
	const masker = createMasker(p.names);
	// The person's currency and reply language. A settings read that fails never stops a chat: it falls back to the defaults
	const settings =
		p.currency && p.replyLanguage
			? { currency: p.currency, replyLanguage: p.replyLanguage }
			: await getSettings(p.ctx).catch(() => SETTING_DEFAULTS);
	const messages = buildMessages({
		now: p.now ?? new Date(),
		persona: p.persona,
		memories: p.memories,
		cards: p.cards,
		rewindNote: p.rewindNote,
		history: p.history,
		userText: p.userText,
		ocrText: p.ocrText,
		currency: settings.currency,
		replyLanguage: settings.replyLanguage
	});
	const toolsRun: string[] = [];
	let reply = '';
	let seq = 0;
	let stopped: 'depth' | 'tools' | 'cancelled' | 'length' | undefined;
	let toolsOff = false;

	for (let call = 0; call < limits.maxModelCalls; call++) {
		if (p.signal?.aborted) {
			stopped = 'cancelled';
			break;
		}
		let completion: Completion | null = null;
		// The model is working; the screen shows it until the first word of the answer arrives
		yield { type: 'phase', phase: 'thinking' };
		let writing = false;
		try {
			const req: CompletionRequest = {
				bucket: 'chat',
				messages,
				masker,
				signal: p.signal,
				...(toolsOff ? {} : { tools: defs })
			};
			for await (const ev of p.model.stream(p.ctx, req)) {
				if (ev.type === 'delta') {
					if (!writing) {
						writing = true;
						yield { type: 'phase', phase: 'writing' };
					}
					reply += ev.text;
					yield { type: 'delta', text: ev.text };
				} else if (ev.type === 'reasoning') {
					// Shown as it comes. It is not part of the reply and is never kept
					yield { type: 'reasoning', text: ev.text };
				} else completion = ev.completion;
			}
		} catch (e) {
			if (p.signal?.aborted) {
				stopped = 'cancelled';
				break;
			}
			if (e instanceof OpsError && (e.code === 'UNAVAILABLE' || e.code === 'LIMIT')) {
				const reason = /minute/i.test(e.message) ? 'rate' : e.code === 'LIMIT' ? 'capped' : 'down';
				yield { type: 'fallback', reason, form: 'expense' };
				yield { type: 'done', reply, toolsRun };
				return;
			}
			throw e;
		}
		if (!completion) throw new Error('The model ended without an answer.');
		// The model ran out of room (its thinking shares the limit with the answer). Cut-off tool arguments are never run, and a
		// cut-off answer says so and is not read for memory
		if (completion.finishReason === 'length') {
			const note =
				'That took more thinking than I had room for. Please ask again, maybe a little simpler.';
			const tail = reply.trim()
				? `

${note}`
				: note;
			reply += tail;
			yield { type: 'delta', text: tail };
			yield { type: 'done', reply, stopped: 'length', toolsRun };
			return;
		}
		if (completion.toolCalls.length === 0) {
			// Thinking alone is not an answer: never end on a blank reply
			if (!reply.trim() && !completion.content.trim()) {
				reply = 'I did not come up with an answer. Please ask me again.';
				yield { type: 'delta', text: reply };
			}
			yield {
				type: 'done',
				reply: reply || completion.content,
				toolsRun,
				...(stopped ? { stopped } : {})
			};
			return;
		}
		messages.push({
			role: 'assistant',
			content: completion.content || null,
			tool_calls: completion.toolCalls,
			// DeepSeek wants the thinking back while a tool round continues. It is the masked text it sent
			...(completion.reasoningRaw ? { reasoning_content: completion.reasoningRaw } : {})
		});
		for (const tc of completion.toolCalls) {
			if (p.signal?.aborted) {
				stopped = 'cancelled';
				break;
			}
			if (seq >= limits.maxToolCalls) {
				stopped = 'tools';
				toolsOff = true;
				messages.push({
					role: 'tool',
					tool_call_id: tc.id,
					content: JSON.stringify({
						error: 'tool_limit',
						message: 'Too many tool calls in one message. Answer with what you have.'
					})
				});
				continue;
			}
			seq++;
			// Only the call id and the tool's name: the arguments may hold text from the web or from memory
			if (byName.has(tc.function.name))
				yield { type: 'tool_start', id: tc.id, name: tc.function.name };
			const out = await executeTool(p, limits, state, byName, tc, seq);
			toolsRun.push(tc.function.name);
			yield {
				type: 'tool',
				id: tc.id,
				name: tc.function.name,
				status: out.status,
				...(out.message ? { message: out.message } : {}),
				...(out.data !== undefined && JSON.stringify(out.data).length <= limits.maxEventChars
					? { data: out.data }
					: {})
			};
			if (out.card) yield { type: 'card', actionId: out.card.actionId, summary: out.card.summary };
			messages.push({ role: 'tool', tool_call_id: tc.id, content: out.forModel });
		}
		if (stopped === 'cancelled') break;
	}

	if (!stopped) stopped = 'depth';
	// Report what happened instead of ending in silence
	if (!reply.trim()) {
		const ran = toolsRun.length
			? `I ran: ${[...new Set(toolsRun)].join(', ')}.`
			: 'I did not run anything.';
		reply =
			stopped === 'cancelled'
				? `Stopped. ${ran}`
				: `I could not finish that in one go. ${ran} Ask me again to continue.`;
		yield { type: 'delta', text: reply };
	}
	yield { type: 'done', reply, stopped, toolsRun };
}
