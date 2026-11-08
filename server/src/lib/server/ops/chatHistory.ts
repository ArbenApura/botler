// THE RECENT CONVERSATION, FOR THE SCREEN WHEN THE APP OPENS. A PLAIN DATABASE READ: NO MODEL CALL, SO NO TOKENS, AND IT NEVER REACHES THE MODEL'S PROMPT
// (that has its own bounded history in agent/chat.ts). What it returns is bounded too: at most 30 turns, 12 events a turn, and about 200 KB in all.
// The stored events are read as untrusted JSON: one odd row can only lose its own event, never the whole answer.

// -- TYPES -- //
import type { Ctx } from './context';
import type { ChatHistoryInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, desc, eq, inArray, lt, ne, or, sql } from 'drizzle-orm';
import { z } from 'zod';
// -- MODULES -- //
import { agentAction, chat, chatTurn } from '../db/schema';
import { chatHistoryInput } from '../db/zod';
import { contextWindow } from '../agent/contextWindow';
import { activeChatId } from './chats';
import { run } from './context';
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
	/** What the call was doing (its kind and, when safe, its subject), and how long it took. Missing on events stored before they existed. */
	label?: { family: string; subject?: string };
	ms?: number;
};
type CardRead = { type: 'card'; actionId: string; summary: string; verb?: string };
type FallbackOut = { type: 'fallback'; reason: string };

export type HistoryEvent = ToolOut | (CardRead & { status: CardNow }) | FallbackOut;

/** The chat the turns belong to, and where it was branched from. */
export type HistoryChat = {
	id: string;
	title: string | null;
	forkedFrom: { id: string; title: string | null } | null;
	/** The prompt size the host reported at the last good answer, or null when unknown (the meter stays hidden). Numbers only, never text. */
	contextTokens: number | null;
	/** The context window the meter measures against. */
	contextWindow: number;
	/** When the earlier part of the chat was last folded into its summary, or null. */
	summarizedAt: string | null;
};

export type HistoryTurn = {
	id: string;
	clientMessageId: string;
	text: string;
	reply: string;
	status: 'done' | 'failed';
	/** A copy made by a branch: its approval cards belong to the original chat. */
	copied: boolean;
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
	data: z.unknown().optional(),
	// A label that does not fit is dropped alone: the row keeps its old wording
	label: z
		.object({ family: z.string().min(1).max(40), subject: z.string().max(80).optional() })
		.optional()
		.catch(undefined),
	ms: z.number().int().min(0).max(86_400_000).optional().catch(undefined)
});
const cardEvent = z.object({
	type: z.literal('card'),
	actionId: z.string().regex(UUID),
	summary: z.string().transform((v) => v.slice(0, 2_000)),
	verb: z.string().max(60).optional()
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
			const { id, name, status, message, data, label, ms } = tool.data;
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
				...(keep !== undefined ? { data: keep } : {}),
				...(label ? { label } : {}),
				...(ms !== undefined ? { ms } : {})
			});
			continue;
		}
		const card = cardEvent.safeParse(e);
		if (card.success) {
			out.push({
				type: 'card',
				actionId: card.data.actionId,
				summary: card.data.summary,
				...(card.data.verb ? { verb: card.data.verb } : {})
			});
			continue;
		}
		const fb = fallbackEvent.safeParse(e);
		if (fb.success) out.push({ type: 'fallback', reason: fb.data.reason });
	}
	return out;
}

/** The person's recent finished or stopped turns, oldest first. */
export async function chatHistory(
	ctx: Ctx,
	raw: ChatHistoryInput
): Promise<{ chat: HistoryChat | null; turns: HistoryTurn[] }> {
	requirePerson(ctx.actor.kind, 'read the chat history');
	const { limit, chatId } = parse(chatHistoryInput, raw);
	return run(ctx, async (tx, userId) => {
		const wanted = chatId ?? (await activeChatId(tx, userId));
		const [head] = wanted
			? await tx
					.select({
						id: chat.id,
						title: chat.title,
						from: chat.forkedFromChatId,
						tokens: chat.lastPromptTokens,
						summaryAt: chat.summaryAt
					})
					.from(chat)
					.where(and(eq(chat.userId, userId), eq(chat.id, wanted)))
			: [];
		if (!head) return { chat: null, turns: [] };
		const [origin] = head.from
			? await tx
					.select({ id: chat.id, title: chat.title })
					.from(chat)
					.where(and(eq(chat.userId, userId), eq(chat.id, head.from)))
			: [];
		const chatHead: HistoryChat = {
			id: head.id,
			title: head.title,
			forkedFrom: origin ? { id: origin.id, title: origin.title } : null,
			contextTokens: head.tokens,
			contextWindow: contextWindow(),
			summarizedAt: head.summaryAt ? head.summaryAt.toISOString() : null
		};
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
				updatedAt: chatTurn.updatedAt,
				copiedFrom: chatTurn.copiedFromTurnId
			})
			.from(chatTurn)
			.where(
				and(
					eq(chatTurn.userId, userId),
					ne(chatTurn.userText, ''),
					eq(chatTurn.chatId, head.id),
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
				copied: row.copiedFrom !== null,
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
		return { chat: chatHead, turns };
	});
}
