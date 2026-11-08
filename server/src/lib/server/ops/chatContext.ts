// THE CHAT'S CONTEXT METER, THE PERSON'S SIDE: THIS MONTH'S SHARE OF THE CHAT CAP, AND "SUMMARIZE NOW". BOTH ARE FOR THE PERSON ONLY (never an agent tool,
// never behind an approval card). The figures are counts only, no text and no other person's spend: the cap is the one assertBudget holds the chat to.
// Summarize now changes no data of the person, only the chat's running summary; the full messages stay stored. It queues the same chat.compact job the
// automatic path uses, so its model call, its prompt and its budget are the same.

// -- TYPES -- //
import type { Ctx } from './context';
import type { ChatIdInput } from '../db/zod';
// -- MODULES -- //
import { queueManualCompaction } from '../agent/compact';
import { chatIdInput } from '../db/zod';
import { configuredLimits, monthlyUsed } from '../proxy/limits';
import { OpsError, run, runWrite } from './context';
import { parse, requirePerson } from './shared';

// -- FUNCTIONS -- //

/** What the person has used of this month's chat allowance, in charged tokens, and the allowance. Over every provider, the chat bucket only. */
export async function chatUsage(ctx: Ctx): Promise<{ used: number; cap: number }> {
	requirePerson(ctx.actor.kind, 'read the chat usage');
	const used = await run(ctx, (tx, userId) => monthlyUsed(tx, userId, 'chat'));
	return { used, cap: configuredLimits().chatTokenCap };
}

/**
 * Folds the earlier part of the chat into its summary now. Answers `queued`, or `busy` (one is already running) or `short` (too little
 * to fold), and the answer of the first call is replayed for the same request id.
 */
export async function chatCompact(
	ctx: Ctx,
	raw: ChatIdInput
): Promise<{ queued: true } | { queued: false; reason: 'busy' | 'short' }> {
	requirePerson(ctx.actor.kind, 'summarize a chat');
	const { chatId } = parse(chatIdInput, raw);
	return runWrite(ctx, 'chat.compact', { chatId }, async (tx, userId) => {
		const result = await queueManualCompaction(tx, userId, chatId, ctx.requestId ?? chatId);
		if (result === 'missing') throw new OpsError('NOT_FOUND', 'There is no such chat.');
		return result === 'queued'
			? { queued: true as const }
			: { queued: false as const, reason: result };
	});
}
