// THE TURN LOOP: ONE MESSAGE FROM THE PERSON, THE MODEL CALLED UP TO A FEW TIMES, TOOLS RUN BETWEEN THE CALLS.
// What this loop guarantees, whatever the model says:
// - The caller is the session's person, set here. A tool call can never name another user (the schemas hold no user id and are strict).
// - Reads run. Records and changes to the money plan (free verbs) run, including deletes (owner decision 2026-10-28), but only three deletes
//   per message: the fourth and later become cards. A balance count (gated) only ever becomes an approval card. Person-only verbs are not offered.
// - Once untrusted text enters the turn (a web page, a photo's text, anything a tool marks untrusted), every write verb for the rest of
//   the turn becomes a card too, and web reading is closed except for addresses the person typed themselves, so the model cannot carry
//   private text out in an address. Web search stays open but short: a plain query of a few words, none with a run of digits.
// - Bounded: at most 20 model calls, 40 tool calls, 3 web searches, a time limit per tool, a token budget for the whole message and a guard on
//   how big the prompt may grow. When tools, the budget or the guard run out, the last call is told to answer from what it has and say what it
//   could not check. A cancelled request stops the model call and runs no more tools.
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
import type { ChatImage } from '../proxy/types';
import type { AgentTool, WebDeps } from './tools';
import type { TranscriptMessage } from './transcript';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
// -- MODULES -- //
import { createAction } from '../ops/actions';
import { OpsError } from '../ops/context';
import { checkMarkFromPhoto } from '../ops/markPhoto';
import { invokeVerb } from '../ops/registry';
import { defaultSettingsView, getSettings } from '../ops/settings';
import { createMasker } from '../proxy/mask';
import { buildMessages, photoTexts } from './prompt';
import { buildTools, toDefs, WEB_READ, WEB_SEARCH } from './tools';
import { shortenResult, untrustedStub } from './transcript';

// -- TYPES -- //

export type TurnEvent =
	// Live only: start, phase, reasoning and tool_start are shown while the turn runs and are never stored or replayed
	| { type: 'start'; turnId?: string; chatId?: string; usedImages?: boolean }
	// The pictures could not be used by the host, so this answer goes by the text read from them
	| { type: 'pictures'; used: false }
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
	| {
			type: 'card';
			actionId: string;
			summary: string;
			/** Left out except for a card the phone must finish itself (a picture cut from a photo), so the app knows to fetch its plan. */
			verb?: string;
	  }
	| { type: 'fallback'; reason: 'down' | 'capped' | 'rate'; form: 'expense' }
	| {
			type: 'done';
			reply: string;
			stopped?: 'depth' | 'tools' | 'cancelled' | 'length';
			toolsRun: string[];
			/** The tool rounds of the message, for the chat to store. Left out when no tool ran. Never sent to the app. */
			transcript?: TranscriptMessage[];
			/** Untrusted text (a web page, a photo, someone else's calendar) entered the turn, so what the assistant wrote is stored marked. Never sent to the app. */
			tainted?: boolean;
	  };

export type TurnModel = { stream(ctx: Ctx, req: CompletionRequest): AsyncGenerator<StreamEvent> };

export type TurnParams = {
	/** The signed in person's context. Only its user id is used, and it is the only place a user id comes from. */
	ctx: Ctx;
	model: TurnModel;
	history: ChatMessage[];
	userText: string;
	/** Text read from one photo on the phone (older apps). Untrusted. */
	ocrText?: string;
	/** Text read from each photo of the message, up to six. Untrusted. Wins over ocrText. */
	ocrTexts?: string[];
	/** Pictures that go with the message, checked and allowed (the person chose them and the host reads them). Untrusted. */
	images?: ChatImage[];
	/** How many pictures the request carried, used or not. Any of them taints the turn: a picture can hold an instruction as text can. */
	picturesReceived?: number;
	/** The chat message id: the request ids of this turn's writes are made from it, so a re-run repeats nothing. */
	turnKey: string;
	names?: string[];
	persona?: string;
	/** System messages that follow the fixed prefix and come before the history: the notebook, the chat summary. Stable for the whole message. */
	system?: string[];
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
	card?: { actionId: string; summary: string; verb?: string };
};

// -- CONSTANTS -- //

export const LIMITS = {
	maxModelCalls: 20,
	maxToolCalls: 40,
	/** Charged tokens (as the monthly cap counts them) one message may use over all its model calls. The server sets it from TURN_TOKEN_BUDGET. */
	turnTokenBudget: 300_000,
	/** When the last call's prompt was this big, tools are closed: the next call answers from what it has, before a provider refuses the size. */
	contextGuardTokens: 100_000,
	/** From this share of the tool calls used on, every tool result says how many are left. */
	toolsLeftNoteShare: 0.75,
	/** Web searches in one message, so a poor result can be tried again with other words but quota and what a search can carry out stay small. */
	maxWebSearches: 3,
	/** Pages opened in one message. Each one is a paid call to DeepSeek, so a loop of reads cannot run up the balance. */
	maxWebReads: 5,
	/** Deletes the assistant may make in one message before the rest become cards, so one misread message cannot empty the money plan. */
	maxDeletes: 3,
	/** After untrusted text was read, a search this long or longer is blocked, and so is one holding a run of digits like an account number. */
	maxTaintedQueryChars: 80,
	toolTimeoutMs: 15_000,
	webTimeoutMs: 25_000,
	maxResultChars: 16_000,
	maxEventChars: 20_000
};

// -- FUNCTIONS -- //

/** What untrusted text did to a turn so far. */
/** The verbs that remove or hide something in the money plan or the notebooks. A page delete with its sub-pages and a merge count once. */
export const DELETE_VERBS: ReadonlySet<string> = new Set([
	'bill_delete',
	'income_delete',
	'rule_delete',
	'split_delete',
	'account_delete',
	'account_wallet_remove',
	'goal_delete',
	'account_archive',
	'notebook_delete',
	'page_delete',
	'page_merge'
]);

export class TurnState {
	tainted = false;
	/** Web searches started in this message, counted before each runs so a failed or slow one still counts. */
	searches = 0;
	/** Pages opened in this message, counted before each runs for the same reason. */
	reads = 0;
	/** Deletes started in this message: past the limit they wait for the person. */
	deletes = 0;
	readonly reasons = new Set<string>();
	/** How many calls with the same verb and arguments already succeeded in this message, so the second real purchase gets its own request id. */
	readonly succeeded = new Map<string, number>();
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

/** Keys that are null when there is nothing to say, and mean nothing to the model then. A null that carries meaning is never on this list. */
const NOISE_NULLS = new Set(['archivedAt', 'deletedAt', 'note', 'purpose']);

/**
 * A verb's result as the model reads it, without what only costs tokens: every `userId` (always the caller) and the null values of the
 * keys in NOISE_NULLS. A null that means something (a variable bill's amount, a wallet with no rate) stays, and so does every array
 * element. Only for verb results: web and calendar text and the app's own event data are never passed through here.
 */
export function trimForModel(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(trimForModel);
	if (!value || typeof value !== 'object') return value;
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
		if (k === 'userId') continue;
		if (v === null && NOISE_NULLS.has(k)) continue;
		out[k] = trimForModel(v);
	}
	return out;
}

/**
 * Whether a final reply says anything: after the dates, times, markup tags and numbers are taken out it still holds a word of two letters
 * or more. A reply of two stray dates, or of markup alone, is not an answer.
 */
export function hasRealWords(text: string): boolean {
	const bare = text
		.replace(/<[^>]*>/g, ' ')
		.replace(/\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?Z?)?/g, ' ')
		.replace(/[\d.,:/\-+%]+/g, ' ');
	return /\p{L}{2,}/u.test(bare);
}

/** What the model is told once it may not call tools any more. Plain words, no names, no amounts. */
const WRAP_UP =
	'No more tools can be used in this message. Answer now from what you already have, and say plainly what you could not check.';

/** The note that replaces a final reply with no words in it, and the one shown when the monthly chat allowance is used up. */
function couldNotFinish(toolsRun: string[]): string {
	const ran = toolsRun.length
		? `I ran: ${[...new Set(toolsRun)].join(', ')}.`
		: 'I did not run anything.';
	return `I could not finish that in one go. ${ran} Ask me again to continue.`;
}

const CAPPED_NOTE =
	'The chat allowance for this month is used up, so I cannot answer now. Your expenses, bills and schedule still work, and chat opens again on the first of the month.';

function capJson(value: unknown, max: number): string {
	const text = JSON.stringify(value) ?? 'null';
	return text.length <= max
		? text
		: JSON.stringify({ truncated: true, preview: text.slice(0, max - 80) });
}

/** A tool that did not answer in time. Its work may still finish later, so a write must not be repeated blindly. */
class ToolTimeout extends OpsError {
	constructor(what: string) {
		super('UNAVAILABLE', `${what} took too long.`);
	}
}

/** Runs the work against a time limit. The abort signal is for tools that can stop (the web); a write cannot be stopped half way. */
function withTimeout<T>(
	work: (signal: AbortSignal | undefined) => Promise<T>,
	ms: number,
	what: string,
	outer?: AbortSignal,
	abortable = false
): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const stop = abortable ? new AbortController() : undefined;
	const signal = stop ? (outer ? AbortSignal.any([outer, stop.signal]) : stop.signal) : undefined;
	const late = new Promise<never>((_, reject) => {
		timer = setTimeout(() => {
			stop?.abort();
			reject(new ToolTimeout(what));
		}, ms);
	});
	return Promise.race([work(signal), late]).finally(() => clearTimeout(timer));
}

/** The same value with its object keys in order, so the same call always hashes the same. */
function stableJson(value: unknown): string {
	const order = (v: unknown): unknown =>
		Array.isArray(v)
			? v.map(order)
			: v && typeof v === 'object'
				? Object.fromEntries(
						Object.entries(v as Record<string, unknown>)
							.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
							.map(([k, x]) => [k, order(x)])
					)
				: v;
	return JSON.stringify(order(value)) ?? 'null';
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
	// The write id is the turn, the call (verb and arguments) and how many identical calls already succeeded: a retry of a call that timed out
	// or failed reuses its id and replays, two real identical purchases get 0 and 1 and both write, and a re-run of the turn repeats the ids
	const callHash = createHash('sha256')
		.update(`${tool.name}|${stableJson(args)}`)
		.digest('hex')
		.slice(0, 12);
	const sameBefore = state.succeeded.get(callHash) ?? 0;
	const agentCtx: Ctx = {
		handle: p.ctx.handle,
		actor: { userId: p.ctx.actor.userId, kind: 'agent', tool: tool.name },
		channel: 'chat',
		turnId: createHash('sha256').update(p.turnKey).digest('hex').slice(0, 32),
		// Hashed so a long client message id cannot cut the rest off: 2 + 40 + 1 + 12 + 1 + digits stays far under 80 characters
		requestId: `t-${createHash('sha256').update(p.turnKey).digest('hex').slice(0, 40)}-${callHash}-${sameBefore}`
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
		} else {
			// Each page read is a paid call, so it is counted before it runs, blocked or failed ones included
			state.reads += 1;
			if (state.reads > limits.maxWebReads)
				return err(
					'blocked',
					`At most ${limits.maxWebReads} pages can be opened in one message. Answer with what you have.`,
					'blocked'
				);
			if (state.tainted) {
				const typed = tool.name === WEB_READ && state.userUrls.has(normalizeUrl(args.url) ?? '');
				if (!typed)
					return err(
						'blocked',
						'Untrusted text was already read in this message, so opening addresses is turned off. Only an address the person typed can be opened.',
						'blocked'
					);
			}
		}
		try {
			const web = tool.web;
			const result = await withTimeout(
				(signal) => web(args, p.web ?? {}, signal),
				limits.webTimeoutMs,
				'The web',
				p.signal,
				true
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
			const card = await createAction(agentCtx, {
				verb: tool.name,
				args,
				turnId: p.turnKey,
				// A re-run of this turn reaches the same call and finds its card instead of making a second one
				key: `${seq}:${callHash}`
			});
			return {
				status: 'needs_approval',
				card: tool.name === 'mark_from_photo' ? { ...card, verb: tool.name } : card,
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
	if (tool.name === 'mark_from_photo') {
		// The photo number must be one the person really attached to this message, and the item must exist, before a card is made
		try {
			await checkMarkFromPhoto(
				agentCtx,
				args,
				// The photos as the model counts them: the pictures it was given, else the texts read from them (the phone numbers its copies the same way)
				p.images?.length ? p.images.length : photoTexts(p.ocrText, p.ocrTexts).length
			);
		} catch (e) {
			if (e instanceof OpsError) return err('invalid_arguments', e.message);
			throw e;
		}
		return asCard(
			'The picture is made on the phone from the photo and shown on the card, so the person approves it there.'
		);
	}
	if (tool.kind === 'gated')
		return asCard('This changes the plan, so it needs the person to approve it.');
	if (tool.kind === 'free' && state.tainted)
		return asCard('Untrusted text was read in this message, so even records wait for approval.');
	if (tool.kind === 'free' && DELETE_VERBS.has(tool.name)) {
		// Clearing every split at once uses the whole allowance of the message, so it cannot be followed by more deletes
		state.deletes += tool.name === 'split_delete' && args.all === true ? limits.maxDeletes : 1;
		if (state.deletes > limits.maxDeletes)
			return asCard(
				`At most ${limits.maxDeletes} deletes are done at once in one message, so this one waits for approval.`
			);
	}

	// -- A READ OR A RECORD -- //
	try {
		const result = await withTimeout(
			() => invokeVerb(agentCtx, tool.name, args),
			limits.toolTimeoutMs,
			tool.name
		);
		state.succeeded.set(callHash, sameBefore + 1);
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
			forModel: capJson(trimForModel(result), limits.maxResultChars)
		};
	} catch (e) {
		if (e instanceof OpsError) {
			// A write that ran out of time may still finish: the model must check before it tries again
			if (e instanceof ToolTimeout && tool.kind === 'free')
				return err(
					'timeout',
					`${tool.name} took too long. The change may already have been made: read the data again to check before you try it again, and do not repeat it blindly.`
				);
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
	if (
		photoTexts(p.ocrText, p.ocrTexts).length > 0 ||
		(p.picturesReceived ?? 0) > 0 ||
		(p.images?.length ?? 0) > 0
	)
		state.taint('photo');
	const masker = createMasker(p.names);
	// The person's currency and reply language. A settings read that fails never stops a chat: it falls back to the defaults
	const settings =
		p.currency && p.replyLanguage
			? { currency: p.currency, replyLanguage: p.replyLanguage }
			: await getSettings(p.ctx).catch(() => defaultSettingsView());
	const messages = buildMessages({
		now: p.now ?? new Date(),
		persona: p.persona,
		system: p.system,
		memories: p.memories,
		cards: p.cards,
		rewindNote: p.rewindNote,
		history: p.history,
		userText: p.userText,
		ocrText: p.ocrText,
		ocrTexts: p.ocrTexts,
		images: p.images,
		currency: settings.currency,
		replyLanguage: settings.replyLanguage
	});
	// The system message and the history: the part of the request that is the same from one call to the next
	// The extra system messages sit inside it, so the host's history breakpoint lands on the real end of the history
	const stableCount = 1 + (p.system?.length ?? 0) + p.history.length;
	/** Takes the pictures off the message, once. True when there were any to take. */
	const dropPictures = (): boolean => {
		let dropped = false;
		for (const m of messages) {
			if ((m.role === 'user' || m.role === 'system') && m.images) {
				delete m.images;
				dropped = true;
			}
		}
		return dropped;
	};
	// What the message keeps for later messages of the chat
	const transcript: TranscriptMessage[] = [];
	const toolsRun: string[] = [];
	let reply = '';
	let seq = 0;
	let stopped: 'depth' | 'tools' | 'cancelled' | 'length' | undefined;
	let toolsOff = false;
	// Whether a call cut off by the model's limit was already given its one second try
	let continued = false;
	// What the message has used so far, from the model's own usage reports
	let charged = 0;
	let lastPrompt = 0;

	for (let call = 0; call < limits.maxModelCalls; call++) {
		if (p.signal?.aborted) {
			stopped = 'cancelled';
			break;
		}
		// Out of room (the token budget, the size of the prompt, or the last model call): tools close and the model is told once to answer
		if (
			!toolsOff &&
			(charged >= limits.turnTokenBudget ||
				lastPrompt >= limits.contextGuardTokens ||
				call === limits.maxModelCalls - 1)
		) {
			toolsOff = true;
			stopped ??= call === limits.maxModelCalls - 1 ? 'depth' : 'tools';
			messages.push({ role: 'user', content: WRAP_UP });
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
				stableCount,
				tools: defs,
				...(toolsOff ? { toolChoice: 'none' as const } : {})
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
			// The host refused the FIRST call with pictures in it (one it cannot read, or too large): once, with nothing yet written, the same call
			// goes again without them, on the text read from them, and the person is told
			if (
				e instanceof OpsError &&
				e.code === 'UNAVAILABLE' &&
				call === 0 &&
				!writing &&
				dropPictures()
			) {
				yield { type: 'pictures', used: false };
				call--;
				continue;
			}
			if (e instanceof OpsError && (e.code === 'UNAVAILABLE' || e.code === 'LIMIT')) {
				const reason = /minute/i.test(e.message) ? 'rate' : e.code === 'LIMIT' ? 'capped' : 'down';
				yield { type: 'fallback', reason, form: 'expense' };
				// Writes may already have run in this message: the person is told what, so they are not done again by hand
				const already = toolsRun.length
					? `Before that stopped I had already run: ${[...new Set(toolsRun)].join(', ')}. Check those before you do them again.`
					: '';
				// A used-up monthly allowance says so in words, and is never retried by the app
				if (reason === 'capped') {
					const note = already ? `${CAPPED_NOTE} ${already}` : CAPPED_NOTE;
					reply += reply.trim() ? `\n\n${note}` : note;
					yield { type: 'delta', text: reply };
				} else if (already) {
					const tail = reply.trim() ? `\n\n${already}` : already;
					reply += tail;
					yield { type: 'delta', text: tail };
				}
				yield {
					type: 'done',
					reply,
					toolsRun,
					...(transcript.length ? { transcript } : {}),
					...(state.tainted ? { tainted: true } : {})
				};
				return;
			}
			throw e;
		}
		if (!completion) throw new Error('The model ended without an answer.');
		charged +=
			completion.charged ?? completion.usage.promptTokens + completion.usage.completionTokens;
		lastPrompt = completion.usage.promptTokens;
		// The model ran out of room (its thinking shares the limit with the answer). Cut-off tool arguments are never run. The first
		// cut-off is given one carry-on; the second, or one with no model call left, says so and is not read for memory
		if (
			completion.finishReason === 'length' &&
			!continued &&
			call + 1 < limits.maxModelCalls &&
			!p.signal?.aborted
		) {
			// The model is asked once to carry on from where it stopped, with what it wrote kept. A cut-off tool call is dropped (never
			// run), so with nothing kept the nudge asks for a short answer instead of a continuation
			continued = true;
			const kept = completion.content.trim() !== '';
			if (kept)
				messages.push({
					role: 'assistant',
					content: completion.content,
					...(completion.wireBlocks ? { wire_blocks: completion.wireBlocks } : {})
				});
			// Once tools are turned off the nudge must not point at them
			const data = toolsOff ? '' : ' Use the tools if you still need data.';
			messages.push({
				role: 'user',
				content: kept
					? `Your last message was cut off. Carry on exactly where it stopped without repeating anything, then finish briefly: the answer first, and no long tables.${data}`
					: `Your last attempt ran out of room. Try again and answer briefly: the answer first, and no long tables.${data}`
			});
			continue;
		}
		if (completion.finishReason === 'length') {
			const note =
				'That took more thinking than I had room for. Please ask again, maybe a little simpler.';
			const tail = reply.trim()
				? `

${note}`
				: note;
			reply += tail;
			yield { type: 'delta', text: tail };
			yield {
				type: 'done',
				reply,
				stopped: 'length',
				toolsRun,
				...(state.tainted ? { tainted: true } : {})
			};
			return;
		}
		if (completion.toolCalls.length === 0) {
			// Thinking alone is not an answer: never end on a blank reply
			if (!reply.trim() && !completion.content.trim()) {
				reply = 'I did not come up with an answer. Please ask me again.';
				yield { type: 'delta', text: reply };
			}
			let final = reply || completion.content;
			// A reply of stray dates or markup is not an answer either: it is replaced by a plain note of what ran
			if (toolsRun.length > 0 && !hasRealWords(final)) {
				final = couldNotFinish(toolsRun);
				yield { type: 'delta', text: `\n\n${final}` };
			}
			yield {
				type: 'done',
				reply: final,
				toolsRun,
				...(stopped ? { stopped } : {}),
				...(transcript.length ? { transcript } : {}),
				...(state.tainted ? { tainted: true } : {})
			};
			return;
		}
		messages.push({
			role: 'assistant',
			content: completion.content || null,
			tool_calls: completion.toolCalls,
			// DeepSeek wants the thinking back while a tool round continues. It is the masked text it sent
			...(completion.reasoningRaw ? { reasoning_content: completion.reasoningRaw } : {}),
			// A host with signed thinking wants it back unchanged while a tool round continues
			...(completion.wireBlocks ? { wire_blocks: completion.wireBlocks } : {})
		});
		// What this round keeps for later messages of the chat (see transcript.ts)
		const roundResults: TranscriptMessage[] = [];
		let roundUntrusted = false;
		const finished: Completion = completion;
		const keepRound = () =>
			transcript.push(
				{
					role: 'assistant',
					// The words around a stranger's text are dropped with it
					content: roundUntrusted ? null : finished.content || null,
					tool_calls: finished.toolCalls,
					...(finished.provider ? { provider: finished.provider } : {})
				},
				...roundResults
			);
		for (const tc of completion.toolCalls) {
			if (p.signal?.aborted) {
				stopped = 'cancelled';
				break;
			}
			if (seq >= limits.maxToolCalls) {
				stopped = 'tools';
				toolsOff = true;
				const limit = JSON.stringify({
					error: 'tool_limit',
					message: 'Too many tool calls in one message. Answer with what you have.'
				});
				messages.push({ role: 'tool', tool_call_id: tc.id, content: limit });
				roundResults.push({ role: 'tool', tool_call_id: tc.id, content: limit });
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
			if (out.card)
				yield {
					type: 'card',
					actionId: out.card.actionId,
					summary: out.card.summary,
					...(out.card.verb ? { verb: out.card.verb } : {})
				};
			// Late in the message every result says how many tool calls are left, so the model plans its last ones
			const left = limits.maxToolCalls - seq;
			const note =
				seq >= Math.ceil(limits.maxToolCalls * limits.toolsLeftNoteShare)
					? `\n(${left} tool call${left === 1 ? '' : 's'} left in this message)`
					: '';
			messages.push({ role: 'tool', tool_call_id: tc.id, content: out.forModel + note });
			// Web and calendar text is untrusted: only a stub naming the tool is kept
			const named = byName.get(tc.function.name);
			const outside = named?.kind === 'web' || named?.taints === true;
			if (outside) roundUntrusted = true;
			roundResults.push({
				role: 'tool',
				tool_call_id: tc.id,
				content: outside ? untrustedStub(tc.function.name) : shortenResult(out.forModel)
			});
		}
		keepRound();
		if (stopped === 'cancelled') break;
	}

	if (!stopped) stopped = 'depth';
	// Report what happened instead of ending in silence
	if (!reply.trim()) {
		const ran = toolsRun.length
			? `I ran: ${[...new Set(toolsRun)].join(', ')}.`
			: 'I did not run anything.';
		reply = stopped === 'cancelled' ? `Stopped. ${ran}` : couldNotFinish(toolsRun);
		yield { type: 'delta', text: reply };
	}
	yield {
		type: 'done',
		reply,
		stopped,
		toolsRun,
		...(transcript.length ? { transcript } : {}),
		...(state.tainted ? { tainted: true } : {})
	};
}
