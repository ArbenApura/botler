// THE AGENT'S TABLES: APPROVAL CARDS (A CHANGE TO THE MONEY PLAN THE ASSISTANT PROPOSED, WAITING FOR THE PERSON) AND CHAT TURNS (ONE ROW PER MESSAGE, SO A RETRIED OR RECONNECTED MESSAGE NEVER RUNS TWICE)

// -- DEP-MODULES -- //
import { foreignKey, index, jsonb, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, stamps, userTable } from './helpers';

// -- CONSTANTS -- //

export const ACTION_STATUSES = ['pending', 'applied', 'rejected', 'failed', 'expired'] as const;
export const TURN_STATUSES = ['running', 'done', 'failed'] as const;

// -- APPROVAL CARDS -- //

/**
 * A gated change the assistant asked for. Nothing has happened yet. The person approves or rejects it through a signed in call,
 * and only then is the verb run, as the person. The summary is built by the server from the validated arguments, never from model text.
 */
export const agentAction = userTable(
	'agent_action',
	() => user.id,
	{
		id: id(),
		verb: text('verb').notNull(),
		/** The arguments, already validated against the verb's schema. */
		args: jsonb('args').notNull(),
		summary: text('summary').notNull(),
		status: text('status', { enum: ACTION_STATUSES }).notNull().default('pending'),
		/** What the verb returned when it ran, or the reason it failed. */
		result: jsonb('result'),
		/** The chat message that asked for it. */
		turnId: text('turn_id'),
		expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
		decidedAt: timestamp('decided_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [
		index('agent_action_user_status_idx').on(t.userId, t.status, t.createdAt),
		oneOf('agent_action_status_chk', t.status, ACTION_STATUSES)
	]
);

// -- CHATS -- //

/**
 * One conversation. A person has many; the newest by last_active_at is the one that opens. A fork is a new chat that starts as a copy
 * of another one up to a message, and the original is never touched. The title is the person's own, or empty (the first message
 * names it on the screen). Nothing here is deleted by the app: archiving only hides a chat from the main list. The table is not audited
 * because a title can be message text, like the turns themselves; it is erased with them.
 */
export const chat = userTable(
	'chat',
	() => user.id,
	{
		id: id(),
		title: text('title'),
		pinnedAt: timestamp('pinned_at', { withTimezone: true }),
		archivedAt: timestamp('archived_at', { withTimezone: true }),
		/** Where a fork came from. Plain ids with no reference, so the source can be erased without touching the fork. */
		forkedFromChatId: uuid('forked_from_chat_id'),
		forkedAtTurnId: uuid('forked_at_turn_id'),
		/** Bumped only by opening, creating, forking and a message. Never by rename, pin or archive. */
		lastActiveAt: timestamp('last_active_at', { withTimezone: true }).notNull().defaultNow(),
		...stamps()
	},
	(t) => [
		unique('chat_user_id_uq').on(t.userId, t.id),
		index('chat_user_active_idx').on(t.userId, t.lastActiveAt)
	]
);

// -- CHAT TURNS -- //

/**
 * One chat message and the answer to it. The client chooses the message id, and a second request with the same id gets the stored
 * answer instead of running the turn again. A turn stuck in "running" (the server stopped) can be taken over after a while.
 */
export const chatTurn = userTable(
	'chat_turn',
	() => user.id,
	{
		id: id(),
		/** The conversation this message belongs to. */
		chatId: uuid('chat_id').notNull(),
		clientMessageId: text('client_message_id').notNull(),
		userText: text('user_text').notNull(),
		status: text('status', { enum: TURN_STATUSES }).notNull().default('running'),
		reply: text('reply').notNull().default(''),
		/** The events sent to the app (tool results, cards, fallback), replayed as they were. */
		events: jsonb('events').notNull().default([]),
		finishedAt: timestamp('finished_at', { withTimezone: true }),
		/** Set when the person starts a new chat: the turn is no longer shown or handed to the assistant, but it stays for memory. */
		clearedAt: timestamp('cleared_at', { withTimezone: true }),
		/** Set on a turn that was copied into a fork. Memory, the digest and the export skip it: the person said it once. */
		copiedFromTurnId: uuid('copied_from_turn_id'),
		...stamps()
	},
	(t) => [
		foreignKey({
			name: 'chat_turn_chat_fk',
			columns: [t.userId, t.chatId],
			foreignColumns: [chat.userId, chat.id]
		}).onDelete('cascade'),
		index('chat_turn_chat_created_idx').on(t.userId, t.chatId, t.createdAt),
		unique('chat_turn_user_message_uq').on(t.userId, t.clientMessageId),
		index('chat_turn_user_created_idx').on(t.userId, t.createdAt),
		oneOf('chat_turn_status_chk', t.status, TURN_STATUSES)
	]
);
