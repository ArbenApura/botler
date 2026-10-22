// THE RECENT CONVERSATION, FOR THE SCREEN WHEN THE APP OPENS. A PLAIN DATABASE READ: NO MODEL CALL, SO NO TOKENS, AND IT NEVER REACHES THE MODEL'S PROMPT
// (that has its own bounded history in agent/chat.ts). What it returns is bounded too: at most 30 turns, 12 events a turn, and about 200 KB in all.
// The stored events are read as untrusted JSON: one odd row can only lose its own event, never the whole answer.

// -- TYPES -- //
import type { Ctx } from './context';
import type { ChatHistoryInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, desc, eq, inArray, isNull, lt, ne, or, sql } from 'drizzle-orm';
import { z } from 'zod';
// -- MODULES -- //
import { agentAction, chatTurn } from '../db/schema';
import { chatHistoryInput } from '../db/zod';
import { run, runWrite } from './context';
import { parse, requirePerson } from './shared';

// -- TYPES -- //

/** What a card is now. A pending card whose time has run out is `expired` even though nobody wrote that yet; one whose action is gone is `gone`. */
export type CardNow = 'pending' | 'applied' | 'rejected' | 'failed' | 'expired' | 'gone';

type ToolOut = {
	type: 'tool';
	id?: string;
	name: string;
	status: 'ok' | 'error' | 'needs_approval' | 'blocked';
	message?: string;
	data?: unknown;
};
type CardRead = { type: 'card'; actionId: string; summary: string };
type FallbackOut = { type: 'fallback'; reason: string };

export type HistoryEvent = ToolOut | (CardRead & { status: CardNow }) | FallbackOut;

export type HistoryTurn = {
	id: string;
	clientMessageId: string;
	text: string;
	reply: string;
	status: 'done' | 'failed';
	at: string;
	events: HistoryEvent[];
};

// -- CONSTANTS -- //

const DEFAULT_LIMIT = 20;
const MAX_EVENTS = 12;
const MAX_DATA_CHARS = 4_000;
const MAX_MESSAGE_CHARS = 300;
const BUDGET_CHARS = 200_000;
const MAX_REPLY_CHARS = 20_000;
// Same rule as agent/chat.ts: a turn still marked running after this long was left behind by a stopped server
const STALE_RUNNING_MS = 120_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// What the loop stored. Anything that does not fit is skipped, an old row without an id included
const toolEvent = z.object({
	type: z.literal('tool'),
	id: z.string().max(200).optional(),
	name: z.string().min(1).max(100),
	status: z.enum(['ok', 'error', 'needs_approval', 'blocked']),
	message: z.string().optional(),
	data: z.unknown().optional()
});
const cardEvent = z.object({
	type: z.literal('card'),
	actionId: z.string().regex(UUID),
	summary: z.string().transform((v) => v.slice(0, 2_000))
});
const fallbackEvent = z.object({ type: z.literal('fallback'), reason: z.string().max(40) });

// -- FUNCTIONS -- //

const sizeOf = (v: unknown) => JSON.stringify(v).length;

/** The stored events of one turn, validated and bounded. Cards still need their status. */
function readEvents(raw: unknown): (ToolOut | CardRead | FallbackOut)[] {
	if (!Array.isArray(raw)) return [];
	const out: (ToolOut | CardRead | FallbackOut)[] = [];
	for (const e of raw) {
		if (out.length >= MAX_EVENTS) break;
		const tool = toolEvent.safeParse(e);
		if (tool.success) {
			const { id, name, status, message, data } = tool.data;
			let keep: unknown;
			try {
				keep = data !== undefined && sizeOf(data) <= MAX_DATA_CHARS ? data : undefined;
			} catch {
				keep = undefined;
			}
			out.push({
				type: 'tool',
				name,
				status,
				...(id ? { id } : {}),
				...(message ? { message: message.slice(0, MAX_MESSAGE_CHARS) } : {}),
				...(keep !== undefined ? { data: keep } : {})
			});
			continue;
		}
		const card = cardEvent.safeParse(e);
		if (card.success) {
			out.push({ type: 'card', actionId: card.data.actionId, summary: card.data.summary });
			continue;
		}
		const fb = fallbackEvent.safeParse(e);
		if (fb.success) out.push({ type: 'fallback', reason: fb.data.reason });
	}
	return out;
}

/**
 * Starts a new chat: every finished turn so far is set aside. The app opens empty and the assistant starts without the earlier
 * conversation. Nothing is deleted, so memory and the daily digest keep what was said. A turn still running is left alone.
 */
export async function chatClear(ctx: Ctx) {
	requirePerson(ctx.actor.kind, 'start a new chat');
	return runWrite(ctx, 'chat.clear', {}, async (tx, userId) => {
		const rows = await tx
			.update(chatTurn)
			.set({ clearedAt: sql`now()` })
			.where(
				and(eq(chatTurn.userId, userId), isNull(chatTurn.clearedAt), ne(chatTurn.status, 'running'))
			)
			.returning({ id: chatTurn.id });
		return { cleared: rows.length };
	});
}

/** The person's recent finished or stopped turns, oldest first. */
export async function chatHistory(
	ctx: Ctx,
	raw: ChatHistoryInput
): Promise<{ turns: HistoryTurn[] }> {
	requirePerson(ctx.actor.kind, 'read the chat history');
	const { limit } = parse(chatHistoryInput, raw);
	return run(ctx, async (tx, userId) => {
		// A turn still running is not shown, unless it was left behind long ago (then it counts as failed). An empty message is not a turn.
		// A failed one with no answer still is: the person's words stay
		const rows = await tx
			.select({
				id: chatTurn.id,
				clientMessageId: chatTurn.clientMessageId,
				userText: chatTurn.userText,
				reply: chatTurn.reply,
				status: chatTurn.status,
				events: chatTurn.events,
				createdAt: chatTurn.createdAt,
				updatedAt: chatTurn.updatedAt
			})
			.from(chatTurn)
			.where(
				and(
					eq(chatTurn.userId, userId),
					ne(chatTurn.userText, ''),
					isNull(chatTurn.clearedAt),
					or(
						ne(chatTurn.status, 'running'),
						lt(chatTurn.updatedAt, sql`now() - make_interval(secs => ${STALE_RUNNING_MS / 1000})`)
					)
				)
			)
			.orderBy(desc(chatTurn.createdAt), desc(chatTurn.id))
			.limit(limit ?? DEFAULT_LIMIT);

		const parsed = rows.map((r) => ({ row: r, events: readEvents(r.events) }));

		// One query for every card: its status now, not the one it had when it was made
		const actionIds = [
			...new Set(
				parsed.flatMap((p) => p.events.flatMap((e) => (e.type === 'card' ? [e.actionId] : [])))
			)
		];
		const now = new Map<string, CardNow>();
		if (actionIds.length > 0) {
			const actions = await tx
				.select({
					id: agentAction.id,
					status: agentAction.status,
					expiresAt: agentAction.expiresAt
				})
				.from(agentAction)
				.where(and(eq(agentAction.userId, userId), inArray(agentAction.id, actionIds)));
			for (const a of actions)
				now.set(
					a.id,
					a.status === 'pending' && a.expiresAt.getTime() < Date.now() ? 'expired' : a.status
				);
		}

		const turns: HistoryTurn[] = parsed
			.map(({ row, events }) => ({
				id: row.id,
				clientMessageId: row.clientMessageId,
				text: row.userText,
				reply: row.reply.slice(0, MAX_REPLY_CHARS),
				status: row.status === 'done' ? ('done' as const) : ('failed' as const),
				at: row.createdAt.toISOString(),
				events: events.map((e): HistoryEvent =>
					e.type === 'card' ? { ...e, status: now.get(e.actionId) ?? 'gone' } : e
				)
			}))
			.reverse();

		// About 200 KB at most: the oldest turns lose their tool data first, then the oldest turns go
		let total = sizeOf(turns);
		for (const t of turns) {
			if (total <= BUDGET_CHARS) break;
			for (const e of t.events) {
				if (e.type === 'tool' && e.data !== undefined) {
					total -= sizeOf(e.data);
					delete e.data;
				}
			}
		}
		while (turns.length > 0 && total > BUDGET_CHARS) {
			const dropped = turns.shift();
			total -= dropped ? sizeOf(dropped) : 0;
		}
		return { turns };
	});
}
