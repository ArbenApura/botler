// CONVERSATIONS: MANY CHATS PER PERSON, OPENED, RENAMED, PINNED, ARCHIVED, SEARCHED AND FORKED. ALL OF THESE ARE FOR THE PERSON ONLY (never offered to the assistant).
// Nothing is deleted here. A fork copies finished turns into a new chat and leaves the original alone; archiving only hides a chat from the main list.
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
	ChatRenameInput
} from '../db/zod';
// -- DEP-MODULES -- //
import { randomUUID } from 'node:crypto';
import { and, asc, count, desc, eq, inArray, isNotNull, isNull, ne, sql } from 'drizzle-orm';
// -- MODULES -- //
import { chat, chatTurn } from '../db/schema';
import {
	chatArchiveInput,
	chatForkInput,
	chatIdInput,
	chatListInput,
	chatPinInput,
	chatRenameInput
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

// -- FUNCTIONS -- //

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

/** The person's chats, newest first. A chat with nothing said in it is not listed. */
export async function chatList(ctx: Ctx, raw: ChatListInput): Promise<{ chats: ChatSummary[] }> {
	requirePerson(ctx.actor.kind, 'list the chats');
	const input = parse(chatListInput, raw);
	return run(ctx, async (tx, userId) => {
		const said = sql`exists (select 1 from ${chatTurn} where ${chatTurn.userId} = ${chat.userId} and ${chatTurn.chatId} = ${chat.id} and ${chatTurn.userText} <> '')`;
		const pattern = input.search ? likePattern(input.search) : null;
		const match = pattern
			? sql`(${chat.title} ilike ${pattern} escape '\\' or exists (select 1 from ${chatTurn} where ${chatTurn.userId} = ${chat.userId} and ${chatTurn.chatId} = ${chat.id} and ${chatTurn.userText} ilike ${pattern} escape '\\'))`
			: undefined;
		const rows = await tx
			.select()
			.from(chat)
			.where(
				and(
					eq(chat.userId, userId),
					input.archived ? isNotNull(chat.archivedAt) : isNull(chat.archivedAt),
					said,
					match
				)
			)
			.orderBy(desc(chat.lastActiveAt), desc(chat.id))
			.limit(pattern ? SEARCH_LIMIT : (input.limit ?? DEFAULT_LIST));
		if (rows.length === 0) return { chats: [] };
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
			}))
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
			.select({ from: chat.forkedFromChatId })
			.from(chat)
			.where(and(eq(chat.userId, userId), eq(chat.id, current)));
		// An empty branch is not reused: it would bring its parent and its rewind note into a chat the person meant to start fresh
		if (previousTurns === 0 && !open?.from) {
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
		const [fresh] = await tx
			.insert(chat)
			.values({
				userId,
				title: source.title,
				forkedFromChatId: source.id,
				forkedAtTurnId: copied.at(-1)?.id ?? null
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
