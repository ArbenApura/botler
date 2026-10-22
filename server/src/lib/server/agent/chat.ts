// THE CHAT SERVICE: ONE CHAT MESSAGE, ANSWERED EXACTLY ONCE.
// The app chooses a clientMessageId for every message. The first request with an id claims it and runs the turn; any later request with
// the same id (a retry, a reconnect after a dropped connection) gets the stored answer replayed and never runs the turn again.
// A turn that is still running answers CONFLICT, so the app waits and asks again. A turn stuck in "running" because the server stopped
// can be taken over after two minutes; its writes carry request ids made from the message id, so nothing is applied twice.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Embedder } from '../memory/embed';
import type { ChatMessage } from '../proxy/deepseek';
import type { TurnEvent, TurnModel, TurnParams } from './turn';
// -- DEP-MODULES -- //
import { and, desc, eq, isNull, lt, ne, sql } from 'drizzle-orm';
import { z } from 'zod';
// -- MODULES -- //
import { chatTurn } from '../db/schema';
import { enqueue } from '../jobs/queue';
import { activeEmbedder } from '../memory/embed';
import { loadMemoryContext } from '../memory/retrieve';
import { recentCardLines } from '../ops/actions';
import { OpsError, run } from '../ops/context';
import { parse } from '../ops/shared';
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
	/** The embedder for memory search. Left out, the one the server turned on is used; null means keywords only. */
	embedder?: Embedder | null;
	/** Turn memory off for this call (tests of the loop alone). */
	noMemory?: boolean;
};

// -- CONSTANTS -- //

export const chatInput = z.strictObject({
	clientMessageId: z.string().min(8).max(80),
	text: z.string().trim().min(1).max(4000),
	/** Text the phone read from a photo or screenshot. Untrusted. */
	ocrText: z.string().max(8000).optional()
});

const HISTORY_TURNS = 10;
const HISTORY_CHARS = 1500;
const STALE_RUNNING_MS = 120_000;
/** The only events kept with a finished message. Thinking, phases and start are live only: never stored, never replayed. */
const STORED = new Set<TurnEvent['type']>(['tool', 'card', 'fallback']);

// -- FUNCTIONS -- //

async function claim(ctx: Ctx, input: z.infer<typeof chatInput>) {
	return run(ctx, async (tx, userId) => {
		const [fresh] = await tx
			.insert(chatTurn)
			.values({ userId, clientMessageId: input.clientMessageId, userText: input.text })
			.onConflictDoNothing()
			.returning({ id: chatTurn.id });
		if (fresh) return { mode: 'run' as const, id: fresh.id };
		const [row] = await tx
			.select()
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.clientMessageId, input.clientMessageId)))
			// Locked, so two requests that find the same stuck turn take turns: the second sees it running again and is refused
			.for('update');
		if (!row) throw new OpsError('CONFLICT', 'That message could not be started.');
		if (row.userText !== input.text)
			throw new OpsError('CONFLICT', 'That message id was already used for a different message.');
		if (row.status === 'done') return { mode: 'replay' as const, row };
		const stale = Date.now() - row.updatedAt.getTime() > STALE_RUNNING_MS;
		if (row.status === 'running' && !stale)
			throw new OpsError(
				'CONFLICT',
				'That message is still being answered. Ask again in a moment.'
			);
		// A failed or abandoned turn is taken over
		await tx
			.update(chatTurn)
			.set({ status: 'running', updatedAt: sql`now()` })
			.where(and(eq(chatTurn.id, row.id), ne(chatTurn.status, 'done')));
		return { mode: 'run' as const, id: row.id };
	});
}

async function history(ctx: Ctx, beforeId: string): Promise<ChatMessage[]> {
	const rows = await run(ctx, async (tx, userId) => {
		const [self] = await tx
			.select({ at: chatTurn.createdAt })
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.id, beforeId)));
		if (!self) return [];
		return tx
			.select({ userText: chatTurn.userText, reply: chatTurn.reply })
			.from(chatTurn)
			.where(
				and(
					eq(chatTurn.userId, userId),
					eq(chatTurn.status, 'done'),
					isNull(chatTurn.clearedAt),
					lt(chatTurn.createdAt, self.at)
				)
			)
			.orderBy(desc(chatTurn.createdAt))
			.limit(HISTORY_TURNS);
	});
	return rows.reverse().flatMap((r): ChatMessage[] => [
		{ role: 'user', content: r.userText.slice(0, HISTORY_CHARS) },
		{ role: 'assistant', content: r.reply.slice(0, HISTORY_CHARS) }
	]);
}

/** Answers one chat message. Yields the events for the app as they happen; a repeat of a finished message replays them. */
export async function* handleChat(
	ctx: Ctx,
	raw: unknown,
	deps: ChatDeps
): AsyncGenerator<TurnEvent> {
	const input = parse(chatInput, raw);
	const claimed = await claim(ctx, input);
	// The message is accepted: the screen starts showing that the assistant is working before memory, history or the model are touched
	yield { type: 'start' };
	if (claimed.mode === 'replay') {
		const stored = Array.isArray(claimed.row.events) ? (claimed.row.events as TurnEvent[]) : [];
		for (const e of stored) if (STORED.has(e.type)) yield e;
		yield { type: 'delta', text: claimed.row.reply };
		yield { type: 'done', reply: claimed.row.reply, toolsRun: [] };
		return;
	}
	const kept: TurnEvent[] = [];
	let reply = '';
	try {
		// What is remembered that matters for this message. Memory trouble never stops a chat: it is logged by class and skipped
		const memory = deps.noMemory
			? null
			: await loadMemoryContext(ctx, {
					query: input.text,
					embedder: deps.embedder === undefined ? activeEmbedder() : deps.embedder,
					now: deps.now?.()
				}).catch((e: unknown) => {
					console.error(
						JSON.stringify({
							event: 'memory_unavailable',
							error: e instanceof Error ? e.name : 'Error'
						})
					);
					return null;
				});
		const turn = runTurn({
			ctx,
			model: deps.model,
			history: await history(ctx, claimed.id),
			userText: input.text,
			ocrText: input.ocrText,
			turnKey: input.clientMessageId,
			names: [...new Set([...(deps.names ?? []), ...(memory?.names ?? [])])],
			persona:
				[deps.persona, memory?.persona, memory?.tone].filter(Boolean).join('\n') || undefined,
			memories: [...(deps.memories ?? []), ...(memory?.lines ?? [])],
			// Which cards the person approved or turned down since the last message. A read that fails never stops a chat
			cards: await recentCardLines(ctx).catch(() => []),
			signal: deps.signal,
			now: deps.now?.(),
			tools: deps.tools,
			web: deps.web
		});
		for await (const e of turn) {
			// The text arrives in pieces for the screen; the stored copy keeps the tool results, cards and fallback only
			if (e.type === 'done') {
				reply = e.reply;
				await run(ctx, (tx, userId) =>
					tx
						.update(chatTurn)
						.set({
							status: e.stopped === 'cancelled' || e.stopped === 'length' ? 'failed' : 'done',
							reply,
							events: kept,
							finishedAt: sql`now()`,
							updatedAt: sql`now()`
						})
						.where(and(eq(chatTurn.userId, userId), eq(chatTurn.id, claimed.id)))
				);
				// What the person said is read for lasting facts later, by a job that carries only the turn id
				if (e.stopped !== 'cancelled' && e.stopped !== 'length' && !deps.noMemory)
					await run(ctx, (tx, userId) =>
						enqueue(tx, {
							userId,
							kind: 'memory.extract',
							key: input.clientMessageId,
							payload: { turnId: claimed.id }
						})
					).catch(() => undefined);
			} else if (STORED.has(e.type)) kept.push(e);
			yield e;
		}
	} catch (e) {
		await run(ctx, (tx, userId) =>
			tx
				.update(chatTurn)
				.set({ status: 'failed', updatedAt: sql`now()` })
				.where(and(eq(chatTurn.userId, userId), eq(chatTurn.id, claimed.id)))
		).catch(() => undefined);
		throw e;
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
	return row;
}
