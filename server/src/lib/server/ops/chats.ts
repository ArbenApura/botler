// CONVERSATIONS: MANY CHATS PER PERSON, OPENED, RENAMED, PINNED, ARCHIVED, SEARCHED, FORKED AND REWOUND. ALL OF THESE ARE FOR THE PERSON ONLY (never offered to the assistant).
// A fork copies finished turns into a new chat and leaves the original alone; archiving only hides a chat from the main list. The one deletion is
// a rewind (edit and resend): the edited message and the ones after it leave the same chat. Chat turns are message text outside the audit trail.
// No model call is made by any verb in this file, so it costs no tokens. Search text is never logged.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type {
	ChatArchiveInput,
	ChatForkInput,
	ChatIdInput,
	ChatListInput,
	ChatPinInput,
	ChatRenameInput,
	ChatRewindInput
} from '../db/zod';
// -- DEP-MODULES -- //
import { randomUUID } from 'node:crypto';
import { and, asc, count, desc, eq, inArray, isNotNull, isNull, ne, sql } from 'drizzle-orm';
import { z } from 'zod';
// -- MODULES -- //
import { agentAction, chat, chatTurn } from '../db/schema';
import {
	chatArchiveInput,
	chatForkInput,
	chatIdInput,
	chatListInput,
	chatPinInput,
	chatRenameInput,
	chatRewindInput
} from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { parse, requirePerson } from './shared';

// -- TYPES -- //

export type ChatSummary = {
	id: string;
	title: string | null;
	/** The last thing the person said here, cut short. */
	preview: string;
	lastActiveAt: string;
	turns: number;
	pinned: boolean;
	archived: boolean;
	forkedFromChatId: string | null;
};

// -- CONSTANTS -- //

const TITLE_CHARS = 60;
const PREVIEW_CHARS = 120;
const DEFAULT_LIST = 50;
const SEARCH_LIMIT = 30;
const COPY_BATCH = 200;
/** A turn left running for longer than this is a crashed one (the same limit the chat loop uses to take it over). */
const RUNNING_STALE_MS = 120_000;
/** The most distinct verb names one chat remembers as already done. */
const MAX_REWOUND_VERBS = 100;

// -- FUNCTIONS -- //

export type VerbCounts = Record<string, number>;

/** The counts a chat stored, read back safely: only plain names with whole positive counts survive. */
export function readVerbCounts(value: unknown): VerbCounts {
	const out: VerbCounts = {};
	if (!value || typeof value !== 'object' || Array.isArray(value)) return out;
	for (const [name, n] of Object.entries(value as Record<string, unknown>)) {
		if (
			/^[a-z][a-z0-9_]{0,59}$/.test(name) &&
			typeof n === 'number' &&
			Number.isInteger(n) &&
			n > 0
		)
			out[name] = n;
	}
	return out;
}

/**
 * How many times each writing verb (free or gated) ran fine in these turns. Only verb names of the registry are counted, so no message
 * text and nothing the model wrote can get in. The registry is loaded here, not at the top, because it imports this file.
 */
export async function writingVerbCounts(turns: { events: unknown }[]): Promise<VerbCounts> {
	const { verbByName } = await import('./registry');
	const out: VerbCounts = {};
	for (const t of turns) {
		if (!Array.isArray(t.events)) continue;
		for (const e of t.events as { type?: unknown; name?: unknown; status?: unknown }[]) {
			if (e?.type !== 'tool' || e.status !== 'ok' || typeof e.name !== 'string') continue;
			const kind = verbByName(e.name)?.kind;
			if (kind === 'free' || kind === 'gated') out[e.name] = (out[e.name] ?? 0) + 1;
		}
	}
	return out;
}

/** Adds counts together, keeping the busiest verbs when there are too many names. */
export function mergeVerbCounts(a: VerbCounts, b: VerbCounts): VerbCounts {
	const sum: VerbCounts = { ...a };
	for (const [name, n] of Object.entries(b)) sum[name] = (sum[name] ?? 0) + n;
	return Object.fromEntries(
		Object.entries(sum)
			.sort((x, y) => y[1] - x[1] || x[0].localeCompare(y[0]))
			.slice(0, MAX_REWOUND_VERBS)
	);
}

/** The name a chat gets from its first message: one line, cut short. */
export function titleFrom(text: string): string | null {
	return text.replace(/\s+/g, ' ').trim().slice(0, TITLE_CHARS) || null;
}

/** The newest chat that is not archived, the one that opens by default. Null when the person has none yet. */
export async function activeChatId(tx: Tx, userId: string): Promise<string | null> {
	const [row] = await tx
		.select({ id: chat.id })
		.from(chat)
		.where(and(eq(chat.userId, userId), isNull(chat.archivedAt)))
		.orderBy(desc(chat.lastActiveAt), desc(chat.id))
		.limit(1);
	return row?.id ?? null;
}

/**
 * The chat a new message goes into. A named chat must be this person's (an archived one is brought back); without a name it is the newest
 * one, made on the spot when there is none. Callers hold the person lock, so two first messages cannot make two chats.
 */
export async function resolveChat(
	tx: Tx,
	userId: string,
	chatId: string | undefined
): Promise<{ id: string; title: string | null }> {
	if (chatId) {
		const [row] = await tx
			.select({ id: chat.id, title: chat.title })
			.from(chat)
			.where(and(eq(chat.userId, userId), eq(chat.id, chatId)));
		if (!row) throw new OpsError('NOT_FOUND', 'There is no such chat.');
		return row;
	}
	const id = await activeChatId(tx, userId);
	if (id) {
		const [row] = await tx
			.select({ id: chat.id, title: chat.title })
			.from(chat)
			.where(and(eq(chat.userId, userId), eq(chat.id, id)));
		if (row) return row;
	}
	const [fresh] = await tx
		.insert(chat)
		.values({ userId })
		.returning({ id: chat.id, title: chat.title });
	if (!fresh) throw new OpsError('CONFLICT', 'A chat could not be started.');
	return fresh;
}

/** A message was sent here: the chat moves to the top, comes back from the archive and is named by its first message. */
export async function touchChat(
	tx: Tx,
	userId: string,
	target: { id: string; title: string | null },
	text: string
): Promise<void> {
	await tx
		.update(chat)
		.set({
			lastActiveAt: sql`now()`,
			updatedAt: sql`now()`,
			archivedAt: null,
			...(target.title ? {} : { title: titleFrom(text) })
		})
		.where(and(eq(chat.userId, userId), eq(chat.id, target.id)));
}

async function requireChat(tx: Tx, userId: string, chatId: string) {
	const [row] = await tx
		.select()
		.from(chat)
		.where(and(eq(chat.userId, userId), eq(chat.id, chatId)));
	if (!row) throw new OpsError('NOT_FOUND', 'There is no such chat.');
	return row;
}

/** The pattern of a search: the person's own characters, with the wildcards of LIKE made plain. */
function likePattern(text: string): string {
	return `%${text.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
}

/**
 * The list of chats with a cursor: `before` is the last chat of the page before (its lastActiveAt and id, as the list gave them), and the
 * page that follows starts right after it. Left out, the list starts at the newest chat.
 */
export const chatListPageInput = chatListInput.extend({
	before: z.strictObject({ at: z.iso.datetime(), id: z.uuid() }).optional()
});

/** The person's chats, newest first, a page at a time. A chat with nothing said in it is not listed. */
export async function chatList(
	ctx: Ctx,
	raw: ChatListInput | z.infer<typeof chatListPageInput>
): Promise<{ chats: ChatSummary[]; next: { at: string; id: string } | null }> {
	requirePerson(ctx.actor.kind, 'list the chats');
	const input = parse(chatListPageInput, raw);
	return run(ctx, async (tx, userId) => {
		const said = sql`exists (select 1 from ${chatTurn} where ${chatTurn.userId} = ${chat.userId} and ${chatTurn.chatId} = ${chat.id} and ${chatTurn.userText} <> '')`;
		const pattern = input.search ? likePattern(input.search) : null;
		const match = pattern
			? sql`(${chat.title} ilike ${pattern} escape '\\' or exists (select 1 from ${chatTurn} where ${chatTurn.userId} = ${chat.userId} and ${chatTurn.chatId} = ${chat.id} and ${chatTurn.userText} ilike ${pattern} escape '\\'))`
			: undefined;
		// Compared to the millisecond, which is what the list shows, so a cursor made from a listed chat lands exactly after it
		const stamp = sql`date_trunc('milliseconds', ${chat.lastActiveAt})`;
		const after = input.before
			? sql`(${stamp}, ${chat.id}) < (${input.before.at}::timestamptz, ${input.before.id}::uuid)`
			: undefined;
		// A search keeps to the limit the caller gave (up to 30 when none is given), like a plain list
		const size = input.limit ?? (pattern ? SEARCH_LIMIT : DEFAULT_LIST);
		const found = await tx
			.select()
			.from(chat)
			.where(
				and(
					eq(chat.userId, userId),
					input.archived ? isNotNull(chat.archivedAt) : isNull(chat.archivedAt),
					said,
					match,
					after
				)
			)
			.orderBy(desc(stamp), desc(chat.id))
			.limit(size + 1);
		const rows = found.slice(0, size);
		const tail = rows.at(-1);
		const next =
			found.length > size && tail ? { at: tail.lastActiveAt.toISOString(), id: tail.id } : null;
		if (rows.length === 0) return { chats: [], next: null };
		const ids = rows.map((r) => r.id);
		const counts = await tx
			.select({ chatId: chatTurn.chatId, n: count() })
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), inArray(chatTurn.chatId, ids)))
			.groupBy(chatTurn.chatId);
		const lasts = await tx
			.selectDistinctOn([chatTurn.chatId], { chatId: chatTurn.chatId, text: chatTurn.userText })
			.from(chatTurn)
			.where(
				and(eq(chatTurn.userId, userId), inArray(chatTurn.chatId, ids), ne(chatTurn.userText, ''))
			)
			.orderBy(chatTurn.chatId, desc(chatTurn.createdAt), desc(chatTurn.id));
		const n = new Map(counts.map((c) => [c.chatId, c.n]));
		const last = new Map(lasts.map((l) => [l.chatId, l.text]));
		return {
			chats: rows.map((r) => ({
				id: r.id,
				title: r.title,
				preview: (last.get(r.id) ?? '').replace(/\s+/g, ' ').slice(0, PREVIEW_CHARS),
				lastActiveAt: r.lastActiveAt.toISOString(),
				turns: n.get(r.id) ?? 0,
				pinned: r.pinnedAt !== null,
				archived: r.archivedAt !== null,
				forkedFromChatId: r.forkedFromChatId
			})),
			next
		};
	});
}

/**
 * Starts a new chat, unless the newest one is still empty (then that one is used again, so two quick taps make one chat).
 * Returns how many turns the chat that was set aside holds, for old apps that ask how many were cleared.
 */
export async function startNewChat(tx: Tx, userId: string) {
	const current = await activeChatId(tx, userId);
	let previousTurns = 0;
	if (current) {
		const [r] = await tx
			.select({ n: count() })
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.chatId, current)));
		previousTurns = r?.n ?? 0;
		const [open] = await tx
			.select({ from: chat.forkedFromChatId, rewound: chat.rewoundVerbs })
			.from(chat)
			.where(and(eq(chat.userId, userId), eq(chat.id, current)));
		// An empty branch (or a chat rewound to nothing) is not reused: it would bring its parent and its rewind note into a chat the person
		// meant to start fresh
		if (previousTurns === 0 && !open?.from && !open?.rewound) {
			await tx
				.update(chat)
				.set({ lastActiveAt: sql`now()`, updatedAt: sql`now()` })
				.where(and(eq(chat.userId, userId), eq(chat.id, current)));
			return { chatId: current, created: false, previousTurns };
		}
	}
	const [fresh] = await tx.insert(chat).values({ userId }).returning({ id: chat.id });
	if (!fresh) throw new OpsError('CONFLICT', 'A chat could not be started.');
	return { chatId: fresh.id, created: true, previousTurns };
}

export async function chatNew(ctx: Ctx) {
	requirePerson(ctx.actor.kind, 'start a new chat');
	return runWrite(ctx, 'chat.new', {}, async (tx, userId) => {
		const { chatId, created } = await startNewChat(tx, userId);
		return { chatId, created };
	});
}

/** Old apps ask for "clear": it now starts a new chat, and the earlier conversation stays listed. */
export async function chatClear(ctx: Ctx) {
	requirePerson(ctx.actor.kind, 'start a new chat');
	return runWrite(ctx, 'chat.clear', {}, async (tx, userId) => {
		const { chatId, previousTurns } = await startNewChat(tx, userId);
		return { cleared: previousTurns, chatId };
	});
}

/** Makes a chat the one that opens: it moves to the top and comes back from the archive. */
export async function chatOpen(ctx: Ctx, raw: ChatIdInput) {
	requirePerson(ctx.actor.kind, 'open a chat');
	const { chatId } = parse(chatIdInput, raw);
	return runWrite(ctx, 'chat.open', { chatId }, async (tx, userId) => {
		await requireChat(tx, userId, chatId);
		await tx
			.update(chat)
			.set({ lastActiveAt: sql`now()`, updatedAt: sql`now()`, archivedAt: null })
			.where(and(eq(chat.userId, userId), eq(chat.id, chatId)));
		return { chatId };
	});
}

export async function chatRename(ctx: Ctx, raw: ChatRenameInput) {
	requirePerson(ctx.actor.kind, 'rename a chat');
	const input = parse(chatRenameInput, raw);
	return runWrite(ctx, 'chat.rename', input, async (tx, userId) => {
		await requireChat(tx, userId, input.chatId);
		await tx
			.update(chat)
			.set({ title: input.title, updatedAt: sql`now()` })
			.where(and(eq(chat.userId, userId), eq(chat.id, input.chatId)));
		return { chatId: input.chatId, title: input.title };
	});
}

export async function chatPin(ctx: Ctx, raw: ChatPinInput) {
	requirePerson(ctx.actor.kind, 'pin a chat');
	const input = parse(chatPinInput, raw);
	return runWrite(ctx, 'chat.pin', input, async (tx, userId) => {
		await requireChat(tx, userId, input.chatId);
		await tx
			.update(chat)
			.set({ pinnedAt: input.pinned ? sql`now()` : null, updatedAt: sql`now()` })
			.where(and(eq(chat.userId, userId), eq(chat.id, input.chatId)));
		return { chatId: input.chatId, pinned: input.pinned };
	});
}

export async function chatArchive(ctx: Ctx, raw: ChatArchiveInput) {
	requirePerson(ctx.actor.kind, 'archive a chat');
	const input = parse(chatArchiveInput, raw);
	return runWrite(ctx, 'chat.archive', input, async (tx, userId) => {
		await requireChat(tx, userId, input.chatId);
		await tx
			.update(chat)
			.set({ archivedAt: input.archived ? sql`now()` : null, updatedAt: sql`now()` })
			.where(and(eq(chat.userId, userId), eq(chat.id, input.chatId)));
		return { chatId: input.chatId, archived: input.archived };
	});
}

/**
 * Branches a chat: a new chat that starts as a copy of the finished turns up to a message (that message included, unless includeTurn is
 * false, which is how "edit and resend" cuts just before the edited message). The original is not touched. A copy is marked, so memory,
 * the digest and the export never count what was said twice. A turn that is still being answered cannot be the cut.
 */
export async function chatFork(ctx: Ctx, raw: ChatForkInput) {
	requirePerson(ctx.actor.kind, 'branch a chat');
	const input = parse(chatForkInput, raw);
	return runWrite(ctx, 'chat.fork', input, async (tx, userId) => {
		const source = await requireChat(tx, userId, input.chatId);
		const all = await tx
			.select()
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.chatId, source.id)))
			.orderBy(asc(chatTurn.createdAt), asc(chatTurn.id));
		let upTo = all.length;
		if (input.upToTurnId) {
			const at = all.findIndex((t) => t.id === input.upToTurnId);
			if (at < 0) throw new OpsError('NOT_FOUND', 'That message is not in this chat.');
			if (all[at]?.status === 'running')
				throw new OpsError(
					'CONFLICT',
					'That message is still being answered. Branch from it in a moment.'
				);
			upTo = input.includeTurn === false ? at : at + 1;
		}
		// Only turns that have ended are copied, and an empty message is not a turn
		const copied = all.slice(0, upTo).filter((t) => t.status !== 'running' && t.userText !== '');
		// What the messages left behind had already done is stored now, so a later rewind of the original cannot change what this chat is told
		const leftBehind = await writingVerbCounts(
			all.slice(upTo).filter((t) => t.status === 'done' && t.userText !== '')
		);
		const [fresh] = await tx
			.insert(chat)
			.values({
				userId,
				title: source.title,
				forkedFromChatId: source.id,
				forkedAtTurnId: copied.at(-1)?.id ?? null,
				rewoundVerbs: leftBehind
			})
			.returning({ id: chat.id });
		if (!fresh) throw new OpsError('CONFLICT', 'The branch could not be made.');
		for (let i = 0; i < copied.length; i += COPY_BATCH) {
			await tx.insert(chatTurn).values(
				copied.slice(i, i + COPY_BATCH).map((t) => ({
					userId,
					chatId: fresh.id,
					// A copy gets a message id of its own, so it can never collide with or replay the original
					clientMessageId: `fork_${randomUUID()}`,
					userText: t.userText,
					status: t.status,
					reply: t.reply,
					events: t.events,
					// The tool rounds travel with the messages; the summary does not, so a fork starts with none
					transcript: t.transcript,
					finishedAt: t.finishedAt,
					copiedFromTurnId: t.id,
					createdAt: t.createdAt,
					updatedAt: t.updatedAt
				}))
			);
		}
		return { chatId: fresh.id, turns: copied.length };
	});
}

/**
 * Edit and resend, in the same chat: the message and every message after it are removed, and the app then sends the new words as a normal
 * message. Nothing is copied and no chat is made. What the removed messages had already done (expenses, tasks...) stays done, so their writing
 * verb names are remembered on the chat for the assistant. Approval cards that those messages raised and that nobody answered are rejected,
 * since the messages are withdrawn. A message still being answered cannot be removed.
 */
export async function chatRewind(ctx: Ctx, raw: ChatRewindInput) {
	requirePerson(ctx.actor.kind, 'edit a message');
	const input = parse(chatRewindInput, raw);
	return runWrite(ctx, 'chat.rewind', input, async (tx, userId) => {
		const source = await requireChat(tx, userId, input.chatId);
		const all = await tx
			.select()
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, userId), eq(chatTurn.chatId, source.id)))
			.orderBy(asc(chatTurn.createdAt), asc(chatTurn.id));
		const at = all.findIndex((t) => t.id === input.fromTurnId);
		if (at < 0) throw new OpsError('NOT_FOUND', 'That message is not in this chat.');
		const gone = all.slice(at);
		// A turn that crashed while running stays "running" for ever: it does not stop the person from editing an earlier message
		const busy = gone.some(
			(t) => t.status === 'running' && Date.now() - t.updatedAt.getTime() < RUNNING_STALE_MS
		);
		if (busy)
			throw new OpsError('CONFLICT', 'A message is still being answered. Edit it in a moment.');
		const goneIds = gone.map((t) => t.id);
		const written = await writingVerbCounts(
			gone.filter((t) => t.status === 'done' && t.userText !== '')
		);
		await tx
			.delete(chatTurn)
			.where(and(eq(chatTurn.userId, userId), inArray(chatTurn.id, goneIds)));
		// The cards of the removed messages can no longer be seen in the chat, so they must not stay answerable
		await tx
			.update(agentAction)
			.set({ status: 'rejected', decidedAt: sql`now()`, updatedAt: sql`now()` })
			.where(
				and(
					eq(agentAction.userId, userId),
					eq(agentAction.status, 'pending'),
					inArray(
						agentAction.turnId,
						gone.map((t) => t.clientMessageId)
					)
				)
			);
		// A summary that reaches into the removed messages would keep their words
		const summaryGone =
			source.summaryThroughTurnId && goneIds.includes(source.summaryThroughTurnId);
		await tx
			.update(chat)
			.set({
				rewoundVerbs: mergeVerbCounts(readVerbCounts(source.rewoundVerbs), written),
				// The name came from the first message: when that one is removed the next message names the chat again
				...(at === 0 ? { title: null } : {}),
				...(summaryGone ? { summary: null, summaryThroughTurnId: null, summaryAt: null } : {}),
				updatedAt: sql`now()`
			})
			.where(and(eq(chat.userId, userId), eq(chat.id, source.id)));
		return { chatId: source.id, removed: gone.length };
	});
}

/** Whether a chat belongs to the caller and is a fork, and from where. Used to tell the assistant what the rewound messages changed. */
export async function forkSource(
	tx: Tx,
	userId: string,
	chatId: string
): Promise<{ chatId: string; atTurnId: string | null; madeAt: Date } | null> {
	const [row] = await tx
		.select({ from: chat.forkedFromChatId, at: chat.forkedAtTurnId, madeAt: chat.createdAt })
		.from(chat)
		.where(and(eq(chat.userId, userId), eq(chat.id, chatId)));
	return row?.from ? { chatId: row.from, atTurnId: row.at, madeAt: row.madeAt } : null;
}
