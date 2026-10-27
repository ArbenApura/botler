// THE CHAT JOBS. EACH RUNS INSIDE THE PERSON'S USER CONTEXT AND CARRIES ONLY IDS.
// - chat.compact: folds the earlier part of a long chat into the chat's running summary. Input: the previous summary and the finished
//   messages after it, except the last two. Output: the new summary (about 800 words), written only if the chat and the message that
//   asked for it still exist and no newer summary landed. Every call goes through the proxy's "memory" bucket, masked with the person's
//   private names. A model that is down means no summary: the job is retried, and meanwhile history slides by its own token bound.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
import type { Completion, CompletionRequest } from '../proxy/deepseek';
import type { JobHandler } from './queue';
// -- DEP-MODULES -- //
import { and, asc, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	afterTurn,
	COMPACT_BATCH,
	COMPACT_PROMPT,
	DEFAULT_HISTORY_TOKENS,
	HISTORY_LOAD_MAX,
	summaryState,
	turnTokens
} from '../agent/compact';
import { readTranscript } from '../agent/transcript';
import { chat, chatTurn, memoryProfile } from '../db/schema';
import { lockPerson } from '../db/tenant';

// -- TYPES -- //

export type ChatJobDeps = {
	model: () => { complete(ctx: Ctx, req: CompletionRequest): Promise<Completion> };
	/** The history budget the job compacts down from. Left out, the default. */
	historyTokens?: number;
};

// -- CONSTANTS -- //

const USER_CHARS = 1500;
const REPLY_CHARS = 3000;
const CALL_ARGS_CHARS = 200;
const CALL_RESULT_CHARS = 400;
const CALLS_PER_MESSAGE = 8;
const SUMMARY_MAX_CHARS = 6000;

// -- FUNCTIONS -- //

const clip = (text: string, max: number) =>
	text.length <= max ? text : `${text.slice(0, max)}...`;

/** One finished message for the summary: the person's words, what the tools did (names, short arguments and results), the answer. */
function render(t: { userText: string; reply: string; transcript: unknown }): string {
	const rounds = readTranscript(t.transcript) ?? [];
	const results = new Map<string, string>();
	for (const m of rounds) if (m.role === 'tool') results.set(m.tool_call_id, m.content);
	const calls = rounds
		.flatMap((m) => (m.role === 'assistant' ? m.tool_calls : []))
		.slice(0, CALLS_PER_MESSAGE)
		.map(
			(c) =>
				`- ${c.function.name}(${clip(c.function.arguments, CALL_ARGS_CHARS)}) gave ${clip(results.get(c.id) ?? '', CALL_RESULT_CHARS)}`
		);
	return [
		`Person: ${clip(t.userText, USER_CHARS)}`,
		...(calls.length ? [`Tools:\n${calls.join('\n')}`] : []),
		`Butler: ${clip(t.reply, REPLY_CHARS)}`
	].join('\n');
}

export function createChatHandlers(deps: ChatJobDeps): Record<string, JobHandler> {
	const budget = deps.historyTokens ?? DEFAULT_HISTORY_TOKENS;

	const compact: JobHandler = async (job, tx, ctx) => {
		const chatId = typeof job.payload.chatId === 'string' ? job.payload.chatId : '';
		const turnId = typeof job.payload.turnId === 'string' ? job.payload.turnId : '';
		const state = chatId ? await summaryState(tx, job.userId, chatId) : null;
		// A chat that was wiped or erased has nothing to summarise
		if (!state) return;
		const [asked] = await tx
			.select({ id: chatTurn.id })
			.from(chatTurn)
			.where(and(eq(chatTurn.userId, job.userId), eq(chatTurn.id, turnId)));
		if (!asked) return;
		const rows = await tx
			.select({
				id: chatTurn.id,
				userText: chatTurn.userText,
				reply: chatTurn.reply,
				transcript: chatTurn.transcript
			})
			.from(chatTurn)
			.where(
				and(
					eq(chatTurn.userId, job.userId),
					eq(chatTurn.chatId, chatId),
					eq(chatTurn.status, 'done'),
					afterTurn(state.after)
				)
			)
			.orderBy(asc(chatTurn.createdAt), asc(chatTurn.id))
			.limit(HISTORY_LOAD_MAX);
		// Still over the budget? A newer compaction may already have brought it down. The last two messages always stay as they are
		if (rows.reduce((sum, r) => sum + turnTokens(r), 0) <= budget || rows.length <= 2) return;
		const cut = rows.slice(0, Math.min(rows.length - 2, COMPACT_BATCH));
		const last = cut.at(-1);
		if (!last) return;

		const [p] = await tx
			.select({ people: memoryProfile.people })
			.from(memoryProfile)
			.where(eq(memoryProfile.userId, job.userId));
		const names = Array.isArray(p?.people)
			? (p.people as unknown[]).filter((x): x is string => typeof x === 'string')
			: [];
		const out = await deps.model().complete(ctx, {
			bucket: 'memory',
			names,
			temperature: 0.2,
			maxTokens: 1800,
			messages: [
				{ role: 'system', content: COMPACT_PROMPT },
				{
					role: 'user',
					content: `<previous_summary>\n${state.summary ?? '(none)'}\n</previous_summary>\n\n<conversation>\n${cut.map(render).join('\n\n')}\n</conversation>`
				}
			]
		});
		const text = out.content.trim().slice(0, SUMMARY_MAX_CHARS);
		if (!text) return;
		// The person's lock is taken only now, for the write: a message of theirs never waited for the model. A newer summary that landed
		// meanwhile is seen here, and the write below is skipped then
		await lockPerson(tx, job.userId);
		await tx
			.update(chat)
			.set({ summary: text, summaryThroughTurnId: last.id, summaryAt: sql`now()` })
			.where(
				and(
					eq(chat.userId, job.userId),
					eq(chat.id, chatId),
					sql`${chat.summaryThroughTurnId} is not distinct from ${state.through}`
				)
			);
	};

	return { 'chat.compact': compact };
}
