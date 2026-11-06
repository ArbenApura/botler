// THE CHAT SERVICE: ONE CHAT MESSAGE, ANSWERED EXACTLY ONCE.
// The app chooses a clientMessageId for every message. The first request with an id claims it and runs the turn; any later request with
// the same id (a retry, a reconnect after a dropped connection) gets the stored answer replayed and never runs the turn again.
// A turn that is still running answers CONFLICT, so the app waits and asks again. A turn stuck in "running" because the server stopped
// can be taken over after two minutes; its writes carry request ids made from the message id, so nothing is applied twice.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { ChatMessage } from '../proxy/deepseek';
import type { TurnEvent, TurnModel, TurnParams } from './turn';
import type { TranscriptProvider } from './transcript';
// -- DEP-MODULES -- //
import { and, asc, eq, gt, lt, ne, sql } from 'drizzle-orm';
import { z } from 'zod';
// -- MODULES -- //
import { chat, chatTurn } from '../db/schema';
import { lockPerson } from '../db/tenant';
import { recentCardLines } from '../ops/actions';
import {
	forkSource,
	readVerbCounts,
	resolveChat,
	touchChat,
	writingVerbCounts
} from '../ops/chats';
import { getSettings } from '../ops/settings';
import { loadNotebookContext } from '../ops/notebook';
import { OpsError, run } from '../ops/context';
import { verbByName } from '../ops/registry';
import { parse } from '../ops/shared';
import {
	afterTurn,
	DEFAULT_HISTORY_TOKENS,
	HISTORY_LOAD_MAX,
	queueCompactionIfDue,
	summaryState
} from './compact';
import { imagesInput, readImages } from './images';
import { MAX_PHOTO_CHARS, MAX_PHOTOS, MAX_PHOTOS_TOTAL_CHARS, notebookMessage } from './prompt';
import { buildHistory } from './transcript';
import { runTurn } from './turn';

// -- TYPES -- //

export type ChatDeps = {
	model: TurnModel;
	web?: TurnParams['web'];
	signal?: AbortSignal;
	now?: () => Date;
	persona?: string;
	memories?: string[];
	names?: string[];
	tools?: TurnParams['tools'];
	/** Which provider answers this person, so stored tool rounds are replayed only to the one that wrote them. Left out, history is text only. */
	provider?: (ctx: Ctx) => Promise<TranscriptProvider | undefined>;
	/** The token budget of the history sent with a message (HISTORY_TOKENS). Left out, 40000. */
	historyTokens?: number;
	/** Overrides of the turn limits, such as the token budget of one message from TURN_TOKEN_BUDGET. */
	limits?: TurnParams['limits'];
	/** Leave the notebook and the private names out of this call (tests of the loop alone). */
	noMemory?: boolean;
	/** How often a running message tells the database it is alive. Left out, 20 seconds. */
	heartbeatMs?: number;
	/** How long a running message may go without that before another request takes it over. Left out, 120 seconds. */
	staleMs?: number;
};

// -- CONSTANTS -- //

export const chatInput = z.strictObject({
	clientMessageId: z.string().min(8).max(80),
	text: z.string().trim().min(1).max(4000),
	/** The conversation this message belongs to. Old apps leave it out and get the newest one. */
	chatId: z.uuid().optional(),
	/** Text the phone read from one photo or screenshot (older apps). Untrusted. */
	ocrText: z.string().max(MAX_PHOTO_CHARS).optional(),
	/** Text the phone read from each of up to six photos. Untrusted. Wins over ocrText when it holds any text. */
	ocrTexts: z
		.array(z.string().max(MAX_PHOTO_CHARS))
		.max(MAX_PHOTOS)
		.refine((l) => l.reduce((n, t) => n + t.length, 0) <= MAX_PHOTOS_TOTAL_CHARS, {
			message: 'The photos hold too much text together.'
		})
		.optional(),
	/** Pictures of the photos. Used only when the person chose the picture and their host reads pictures; otherwise dropped, never kept. Untrusted. */
	images: imagesInput.optional(),
	/** The food camera sent this: a meal photo needs the model to see the picture, so it is refused at once when it cannot. */
	foodCamera: z.enum(['meal', 'label']).optional(),
	/** The app can run the tools that run on the phone (scripts, the toolbox) and answer them at the device-result route. */
	scripts: z.boolean().optional(),
	/** The clock the phone reads (12 or 24 hour), so the assistant writes times the way the person reads them. */
	clock: z.enum(['12', '24']).optional()
});

const STALE_RUNNING_MS = 120_000;
const HEARTBEAT_MS = 20_000;
const NOTE_TOOLS = 20;
/** The most characters one stored tool event keeps (its data). A longer one is stored without the data: the screen shows the tool and its status only. */
export const EVENT_CHARS = 4000;
/** Stored with the events of a message whose answer was written after untrusted text. Never replayed to the app. */
export const TAINTED_MARK = { type: 'tainted' } as const;
/** The only events kept with a finished message. Thinking, phases and start are live only: never stored, never replayed. */
const STORED = new Set<TurnEvent['type']>(['tool', 'card', 'fallback']);

// -- FUNCTIONS -- //

/** A tool event as it is stored: the data stays only up to EVENT_CHARS, and a note only up to the same. Everything else is kept as it is. */
export function forStorage(e: TurnEvent): TurnEvent {
	if (e.type !== 'tool') return e;
	const { data, message, ...rest } = e;
	return {
		...rest,
		...(message ? { message: message.slice(0, EVENT_CHARS) } : {}),
		...(data !== undefined && (JSON.stringify(data) ?? '').length <= EVENT_CHARS ? { data } : {})
	};
}

async function claim(ctx: Ctx, input: z.infer<typeof chatInput>, staleMs: number) {
	return run(ctx, async (tx, userId) => {
		// One person's first messages line up here, so two of them never make two chats
		await lockPerson(tx, userId);
		const [row] = await tx
			.select()
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.clientMessageId, input.clientMessageId)))
			// Locked, so two requests that find the same stuck turn take turns: the second sees it running again and is refused
			.for('update');
		if (!row) {
			const target = await resolveChat(tx, userId, input.chatId, {
				hidden: input.foodCamera !== undefined
			});
			const [fresh] = await tx
				.insert(chatTurn)
				.values({
					userId,
					chatId: target.id,
					clientMessageId: input.clientMessageId,
					userText: input.text
				})
				.returning({ id: chatTurn.id });
			if (!fresh) throw new OpsError('CONFLICT', 'That message could not be started.');
			await touchChat(tx, userId, target, input.text);
			return { mode: 'run' as const, id: fresh.id, chatId: target.id, runNo: 0 };
		}
		if (row.userText !== input.text)
			throw new OpsError('CONFLICT', 'That message id was already used for a different message.');
		// A resend into another chat is not a replay of this one
		if (input.chatId && input.chatId !== row.chatId)
			throw new OpsError('CONFLICT', 'That message id belongs to another chat.');
		if (row.status === 'done') return { mode: 'replay' as const, row };
		const stale = Date.now() - row.updatedAt.getTime() > staleMs;
		if (row.status === 'running' && !stale)
			throw new OpsError(
				'CONFLICT',
				'That message is still being answered. Ask again in a moment.'
			);
		// A failed or abandoned turn is taken over. The run number goes up, so the run that was stuck, if it is still alive, finds out
		// at its next heartbeat and can no longer write the turn's end
		const [taken] = await tx
			.update(chatTurn)
			.set({ status: 'running', runNo: sql`${chatTurn.runNo} + 1`, updatedAt: sql`now()` })
			.where(and(eq(chatTurn.id, row.id), ne(chatTurn.status, 'done')))
			.returning({ runNo: chatTurn.runNo });
		return {
			mode: 'run' as const,
			id: row.id,
			chatId: row.chatId,
			runNo: taken?.runNo ?? row.runNo
		};
	});
}

/**
 * What a chat sends before the new message, from the finished messages after the chat's summary: each message with its tool rounds when they
 * fit the live provider, held under the token budget (see buildHistory). The summary, when there is one, comes back on its own to be
 * placed as a system message ahead of the history.
 */
async function history(
	ctx: Ctx,
	beforeId: string,
	options: { provider: TranscriptProvider | undefined; budget: number }
): Promise<{ messages: ChatMessage[]; summary: string | null }> {
	const found = await run(ctx, async (tx, userId) => {
		const [self] = await tx
			.select({ at: chatTurn.createdAt, chatId: chatTurn.chatId })
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.id, beforeId)));
		if (!self) return null;
		const state = await summaryState(tx, userId, self.chatId);
		const filter = and(
			eq(chatTurn.userId, userId),
			eq(chatTurn.status, 'done'),
			eq(chatTurn.chatId, self.chatId),
			lt(chatTurn.createdAt, self.at),
			afterTurn(state?.after ?? null)
		);
		const [counted] = await tx
			.select({ n: sql<number>`count(*)` })
			.from(chatTurn)
			.where(filter);
		// A chat that never got a summary is read from its newest messages, in steps of five so the start holds still
		const n = Number(counted?.n ?? 0);
		const skip = n > HISTORY_LOAD_MAX ? 5 * Math.ceil((n - HISTORY_LOAD_MAX) / 5) : 0;
		const rows = await tx
			.select({
				userText: chatTurn.userText,
				reply: chatTurn.reply,
				transcript: chatTurn.transcript
			})
			.from(chatTurn)
			.where(filter)
			.orderBy(asc(chatTurn.createdAt), asc(chatTurn.id))
			.offset(skip)
			.limit(HISTORY_LOAD_MAX);
		return { rows, summary: state?.summary ?? null };
	});
	if (!found) return { messages: [], summary: null };
	// A turn that ended in the fallback text has no reply and no rounds: it is left out, an empty assistant message would be refused
	return { messages: buildHistory(found.rows, options).messages, summary: found.summary };
}

/** The summary as a system message: the model is told it was written by itself and may be stale. */
const summaryMessage = (summary: string) =>
	`Earlier in this chat (a summary you wrote; numbers in it were true on the day they name, so read the data again before a new total):
${summary}`;

/**
 * When messages were cut off from this chat (a branch, or an edit and resend), one line for the assistant: what they had already done.
 * Those changes stay in force, so it must not do them again unless asked. Only the names of the writing verbs of the registry are listed,
 * with counts: no message text and nothing the model wrote, so nothing here can carry an instruction. The counts are stored on the chat;
 * a branch made before they were stored reads the original live, but only while the message it was cut at still exists.
 */
async function rewindNote(ctx: Ctx, chatId: string): Promise<string | undefined> {
	const stored = await run(ctx, async (tx, userId) => {
		const [row] = await tx
			.select({ verbs: chat.rewoundVerbs })
			.from(chat)
			.where(and(eq(chat.userId, userId), eq(chat.id, chatId)));
		if (row?.verbs) return { counts: readVerbCounts(row.verbs) };
		const source = await forkSource(tx, userId, chatId);
		if (!source) return null;
		const [cut] = source.atTurnId
			? await tx
					.select({ at: chatTurn.createdAt })
					.from(chatTurn)
					.where(and(eq(chatTurn.userId, userId), eq(chatTurn.id, source.atTurnId)))
			: [];
		// The message it was cut at is gone (the original was edited): what was cut off cannot be told any more
		if (source.atTurnId && !cut) return null;
		const rows = await tx
			.select({ events: chatTurn.events })
			.from(chatTurn)
			.where(
				and(
					eq(chatTurn.userId, userId),
					eq(chatTurn.chatId, source.chatId),
					eq(chatTurn.status, 'done'),
					// Only what was cut off when the branch was made: later turns of the original are not part of this story
					lt(chatTurn.createdAt, source.madeAt),
					...(cut ? [gt(chatTurn.createdAt, cut.at)] : [])
				)
			)
			.orderBy(asc(chatTurn.createdAt))
			.limit(200);
		return { counts: await writingVerbCounts(rows) };
	});
	if (!stored) return undefined;
	// Names are checked against the registry again here, whatever was stored
	const made = Object.entries(stored.counts)
		.filter(([name]) => {
			const kind = verbByName(name)?.kind;
			return kind === 'free' || kind === 'gated';
		})
		.sort((x, y) => y[1] - x[1] || x[0].localeCompare(y[0]));
	const list = made.slice(0, NOTE_TOOLS).map(([name, n]) => `${name} x${n}`);
	if (made.length > NOTE_TOOLS) list.push('and more');
	return list.length
		? `Some messages of this chat were cut off (a branch, or the person edited a message and sent it again). The messages that were cut off had already done these, and they stay done, so do not do them again unless asked: ${list.join(', ')}.`
		: undefined;
}

/** Answers one chat message. Yields the events for the app as they happen; a repeat of a finished message replays them. */
export async function* handleChat(
	ctx: Ctx,
	raw: unknown,
	deps: ChatDeps
): AsyncGenerator<TurnEvent> {
	const input = parse(chatInput, raw);
	// A picture that is not one is refused before the message is claimed, so the person can send it again without that picture
	const pictures = readImages(input.images);
	// A meal photo with no way to reach the model would only bring a guess: said before anything is claimed or any model is called. A failed settings read counts as no
	if (input.foodCamera === 'meal') {
		const canSee = await getSettings(ctx)
			.then((s) => s.photoMode === 'image' && s.photoVision)
			.catch(() => false);
		if (!canSee || pictures.length === 0)
			throw new OpsError(
				'INVALID',
				'The food camera needs the AI to see your photo, and your settings send only the text in it. You can change this in Settings, or scan a barcode or label.'
			);
	}
	const claimed = await claim(ctx, input, deps.staleMs ?? STALE_RUNNING_MS);
	// The message is accepted: the screen starts showing that the assistant is working before memory, history or the model are touched
	const where =
		claimed.mode === 'replay'
			? { turnId: claimed.row.id, chatId: claimed.row.chatId }
			: { turnId: claimed.id, chatId: claimed.chatId };
	// Pictures are used only when the person chose the picture AND the host that will answer reads pictures. A settings read that fails
	// means no pictures (it never falls back to sending them). Decided once, here; the router checks again on every model call
	const provider =
		claimed.mode === 'run' ? await deps.provider?.(ctx).catch(() => undefined) : undefined;
	const usePictures =
		claimed.mode === 'run' &&
		pictures.length > 0 &&
		(await getSettings(ctx)
			.then((s) => s.photoMode === 'image' && s.photoVision)
			.catch(() => false));
	// The app learns which message and which chat this is, so it can branch from the message later
	yield {
		type: 'start',
		...where,
		...(claimed.mode === 'run' && pictures.length > 0 ? { usedImages: usePictures } : {})
	};
	if (claimed.mode === 'replay') {
		const stored = Array.isArray(claimed.row.events) ? (claimed.row.events as TurnEvent[]) : [];
		for (const e of stored) if (STORED.has(e.type)) yield e;
		yield { type: 'delta', text: claimed.row.reply };
		yield { type: 'done', reply: claimed.row.reply, toolsRun: [] };
		return;
	}
	const kept: TurnEvent[] = [];
	let reply = '';
	// This run of the message. Another request that takes the message over raises the run number; the heartbeat below then finds no row to
	// touch and stops this run, which also may no longer write the end of the turn
	const mine = and(
		eq(chatTurn.id, claimed.id),
		eq(chatTurn.status, 'running'),
		eq(chatTurn.runNo, claimed.runNo)
	);
	const owner = new AbortController();
	const beat = setInterval(() => {
		run(ctx, (tx, userId) =>
			tx
				.update(chatTurn)
				.set({ updatedAt: sql`now()` })
				.where(and(eq(chatTurn.userId, userId), mine))
				.returning({ id: chatTurn.id })
		).then(
			(rows) => {
				if (rows.length === 0) owner.abort();
			},
			// A failed heartbeat is not proof that the turn was taken: the next one tries again
			() => undefined
		);
	}, deps.heartbeatMs ?? HEARTBEAT_MS);
	beat.unref?.();
	// A cancelled request is not working any more: the heartbeat stops with it, and the turn ends on its own
	deps.signal?.addEventListener('abort', () => clearInterval(beat), { once: true });
	try {
		// The notebook and the private names. Trouble reading them never stops a chat: it is logged by class and skipped
		const known = deps.noMemory
			? null
			: await loadNotebookContext(ctx).catch((e: unknown) => {
					console.error(
						JSON.stringify({
							event: 'notebook_unavailable',
							error: e instanceof Error ? e.name : 'Error'
						})
					);
					return null;
				});
		const earlier = await history(ctx, claimed.id, {
			provider,
			budget: deps.historyTokens ?? DEFAULT_HISTORY_TOKENS
		});
		const turn = runTurn({
			ctx,
			model: deps.model,
			history: earlier.messages,
			// The notebook is the second system message and the summary the third: both are the same for every call of this message, even
			// when the assistant edits the notebook meanwhile, so the cached prefix holds
			system: [
				...(known ? [notebookMessage(known.text, known.outline)] : []),
				...(earlier.summary ? [summaryMessage(earlier.summary)] : [])
			],
			rewindNote: await rewindNote(ctx, claimed.chatId).catch(() => undefined),
			userText: input.text,
			ocrText: input.ocrText,
			ocrTexts: input.ocrTexts,
			images: usePictures ? pictures : undefined,
			picturesReceived: pictures.length,
			turnKey: input.clientMessageId,
			names: [...new Set([...(deps.names ?? []), ...(known?.names ?? [])])],
			persona: deps.persona,
			memories: deps.memories,
			// Which cards the person approved or turned down since the last message. A read that fails never stops a chat
			cards: await recentCardLines(ctx, 12, 3, claimed.chatId).catch(() => []),
			signal: deps.signal ? AbortSignal.any([deps.signal, owner.signal]) : owner.signal,
			now: deps.now?.(),
			tools: deps.tools,
			device: input.scripts === true,
			clock: input.clock,
			web: deps.web,
			limits: deps.limits
		});
		for await (const e of turn) {
			// The text arrives in pieces for the screen; the stored copy keeps the tool results, cards and fallback only
			if (e.type === 'done') {
				reply = e.reply;
				const ended = e.stopped !== 'cancelled' && e.stopped !== 'length';
				const written = await run(ctx, (tx, userId) =>
					tx
						.update(chatTurn)
						.set({
							status: ended ? 'done' : 'failed',
							reply,
							// After untrusted text the answer is marked, so a summary later treats it as untrusted data
							events: e.tainted ? [...kept, TAINTED_MARK] : kept,
							// The tool rounds stay for the next messages of the chat; a cancelled or cut-off message keeps none
							transcript: ended && e.transcript ? e.transcript : null,
							finishedAt: sql`now()`,
							updatedAt: sql`now()`
						})
						// Only the run that owns the message writes its end: a run that was taken over leaves the new run's result alone
						.where(and(eq(chatTurn.userId, userId), mine))
						.returning({ id: chatTurn.id })
				);
				// A long chat is folded into its summary in the background, never inside a message. A failure here never stops the reply
				if (ended && written.length > 0)
					await run(ctx, (tx, userId) =>
						queueCompactionIfDue(
							tx,
							userId,
							claimed.chatId,
							claimed.id,
							deps.historyTokens ?? DEFAULT_HISTORY_TOKENS
						)
					).catch(() => undefined);
			} else if (STORED.has(e.type)) kept.push(forStorage(e));
			// The tool rounds are for the database only: the app never gets them
			if (e.type === 'done' && (e.transcript || e.tainted)) {
				const { transcript: _kept, tainted: _tainted, ...rest } = e;
				yield rest;
			} else yield e;
		}
	} catch (e) {
		await run(ctx, (tx, userId) =>
			tx
				.update(chatTurn)
				.set({ status: 'failed', updatedAt: sql`now()` })
				// Not a run that was taken over: the new run keeps the message
				.where(and(eq(chatTurn.userId, userId), mine))
		).catch(() => undefined);
		throw e;
	} finally {
		clearInterval(beat);
	}
}

/** The stored state of a message, for an app that lost its connection and wants to know how it ended. */
export async function chatStatus(ctx: Ctx, clientMessageId: string) {
	const row = await run(ctx, async (tx, userId) => {
		const [r] = await tx
			.select({ status: chatTurn.status, reply: chatTurn.reply, events: chatTurn.events })
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.clientMessageId, clientMessageId)));
		return r;
	});
	if (!row) throw new OpsError('NOT_FOUND', 'There is no such message.');
	// The marks only the server reads stay out of what the app gets
	return {
		...row,
		events: Array.isArray(row.events)
			? (row.events as TurnEvent[]).filter((x) => STORED.has(x.type))
			: row.events
	};
}
