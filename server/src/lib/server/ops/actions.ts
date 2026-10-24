// APPROVAL CARDS: THE ASSISTANT MAY ONLY ASK FOR A CHANGE TO THE MONEY PLAN. IT BECOMES A CARD; THE PERSON APPROVES OR REJECTS IT; ONLY THEN THE VERB RUNS, AS THE PERSON.
// The text on a card is built here from the validated arguments and names looked up in the person's own data. Free text from the model is
// never the card text, and a model can neither approve a card nor mint anything that approves one: this verb needs a person caller.

// -- TYPES -- //
import type { Plain } from './shared';
import type { Ctx } from './context';
import type { Schedule } from '../../finance/schedule';
// -- DEP-MODULES -- //
import { and, desc, eq, gt, inArray, sql } from 'drizzle-orm';
// -- MODULES -- //
import { DEFAULT_CURRENCY, formatMoney } from '../../finance/currency';
import { describeSchedule, validateSchedule } from '../../finance/schedule';
import { account, agentAction, bill, chatTurn, goal } from '../db/schema';
import { OpsError, run } from './context';
import { balanceFor } from './ledger';
import { readSettings } from './settings';
import { invokeVerb, verbByName } from './registry';
import { firstProblem, mapped, plain, requirePerson } from './shared';

// -- TYPES -- //

export type ActionView = Plain<typeof agentAction.$inferSelect>;

type Args = Record<string, unknown>;

// -- CONSTANTS -- //

/** A card nobody answers in this long is dropped, so an old request cannot be approved by accident. */
const CARD_LIFETIME_MS = 24 * 3_600_000;

/** Verbs that ask the person to confirm an amount: an approved card is that confirmation. */
const CONFIRMING_VERBS = new Set(['expense_log', 'expense_from_text', 'snapshot_record']);

// -- FUNCTIONS -- //

const num = (v: unknown): number | null => (typeof v === 'number' ? v : null);
const text = (v: unknown, max = 60): string => (typeof v === 'string' ? v.slice(0, max) : '');
const moneyIn = (currency: string, v: unknown) =>
	num(v) === null ? 'an amount' : formatMoney(num(v) as number, currency);

function when(schedule: unknown): string {
	// The card says what the schedule means in words, built from the validated fields, whatever the kind
	const s = schedule as Schedule | null;
	if (!s || validateSchedule(s) !== null) return 'on a schedule';
	const text = describeSchedule(s).text;
	return text.charAt(0).toLowerCase() + text.slice(1);
}

/** Looks up the names a card shows (accounts, goals, bills), from the person's own rows. */
async function namesFor(ctx: Ctx, args: Args): Promise<Map<string, string>> {
	return run(ctx, async (tx, userId) => {
		const names = new Map<string, string>();
		for (const a of await tx
			.select({ id: account.id, name: account.name })
			.from(account)
			.where(eq(account.userId, userId)))
			names.set(a.id, a.name);
		for (const g of await tx
			.select({ id: goal.id, name: goal.name })
			.from(goal)
			.where(eq(goal.userId, userId)))
			names.set(g.id, g.name);
		if (typeof args.billId === 'string')
			for (const b of await tx
				.select({ id: bill.id, name: bill.name })
				.from(bill)
				.where(and(eq(bill.userId, userId), eq(bill.id, args.billId))))
				names.set(b.id, b.name);
		return names;
	});
}

/** The sentence on a card. Pure: the same verb and arguments always read the same. */
export function describeAction(
	verbName: string,
	args: Args,
	names: ReadonlyMap<string, string>,
	currency: string = DEFAULT_CURRENCY,
	/** What the account holds now, for a balance count: a card that changes a balance says the old and the new one. */
	currentBalance: number | null = null
): string {
	const nm = (id: unknown) => names.get(typeof id === 'string' ? id : '') ?? 'an account';
	// Amounts on a card read in the person's own currency
	const money = (v: unknown) => moneyIn(currency, v);
	switch (verbName) {
		case 'account_create':
			return `Add the account "${text(args.name)}"${args.purpose ? `, for "${text(args.purpose)}"` : ''}.`;
		case 'account_update':
			return `Change the account ${nm(args.accountId)}${args.name ? ` to "${text(args.name)}"` : ''}${num(args.minBalance) !== null ? `, minimum balance ${money(args.minBalance)}` : ''}${args.purpose ? `, purpose "${text(args.purpose)}"` : args.purpose === null ? ', purpose cleared' : ''}.`;
		case 'account_wallet_add':
			return `Add a ${text(args.currency, 3)} wallet to the account ${nm(args.accountId)}.`;
		case 'account_archive':
			return `Hide the account ${nm(args.accountId)}.`;
		case 'income_create':
			return `Set up "${text(args.label)}" paying ${args.expectedAmount ? money(args.expectedAmount) : 'a varying amount'} into ${nm(args.accountId)}, ${when(args.schedule)}.`;
		case 'income_update':
			return `Change the income "${text(args.label) || 'schedule'}".`;
		case 'bill_create':
			return `Add the bill "${text(args.name)}", ${args.amount ? money(args.amount) : 'amount varies'}, paid from ${nm(args.accountId)}, ${when(args.schedule)}.`;
		case 'bill_update':
			return `Change the bill ${names.get(typeof args.billId === 'string' ? args.billId : '') ?? ''}${args.name ? ` ("${text(args.name)}")` : ''}${args.amount ? ` to ${money(args.amount)}` : ''}.`.replace(
				' .',
				'.'
			);
		case 'bill_occurrence_update':
			return `Change one date of the bill ${names.get(typeof args.billId === 'string' ? args.billId : '') ?? ''} (${text(args.dueDate, 10)})${args.newDueDate ? `: move it to ${text(args.newDueDate, 10)}` : ''}${args.amount ? `, ${money(args.amount)} this time` : ''}${args.accountId ? `, paid from ${nm(args.accountId)}` : ''}${args.skipped === true ? ', skip it' : ''}.`;
		case 'bill_mark_paid':
			return `Mark "${names.get(typeof args.billId === 'string' ? args.billId : '') ?? 'the bill'}" paid for ${text(args.dueDate, 10)}${args.amount ? `, ${money(args.amount)}` : ''}${typeof args.paidCurrency === 'string' && num(args.paidAmount) ? `, charged ${moneyIn(args.paidCurrency, args.paidAmount)}` : ''}.`;
		case 'goal_create':
			return `Add the goal "${text(args.name)}" in ${nm(args.accountId)}${num(args.perPayday) ? `, setting aside ${money(args.perPayday)} each payday` : ''}.`;
		case 'goal_update':
			return `Change the goal ${nm(args.goalId)}${args.name ? ` ("${text(args.name)}")` : ''}${num(args.perPayday) !== null ? `, ${money(args.perPayday)} each payday` : ''}.`;
		case 'snapshot_record': {
			const target = num(args.amount);
			const diff =
				target !== null && currentBalance !== null
					? ` It shows ${money(currentBalance)} now, a difference of ${target - currentBalance > 0 ? '+' : ''}${moneyIn(currency, target - currentBalance)}.`
					: '';
			return args.mode === 'reset'
				? `Reset ${nm(args.accountId)} to ${money(args.amount)}.${diff} Reason given by Botler: "${text(args.reason, 120)}". Your history is kept.`
				: `Record that ${nm(args.accountId)} holds ${money(args.amount)}.${diff}`;
		}
		case 'expense_log':
			return `Log an expense of ${money(args.amount)} on ${nm(args.accountId)}${args.note ? `: "${text(args.note, 80)}"` : ''}.`;
		case 'expense_from_text':
			return `Log the expense "${text(args.text, 80)}".`;
		case 'income_record':
			return `Record ${money(args.amount)} arriving in ${nm(args.accountId)}.`;
		case 'refund_record':
			return `Record a refund of ${money(args.amount)} into ${nm(args.accountId)}.`;
		case 'transfer_record':
			return `Move ${money(args.amount)} from ${nm(args.fromAccountId)} to ${nm(args.toAccountId)}${typeof args.toCurrency === 'string' && num(args.toAmount) ? `, where ${moneyIn(args.toCurrency, args.toAmount)} arrives` : ''}${num(args.fee) ? ` (fee ${money(args.fee)})` : ''}.`;
		default:
			return `Run "${verbName.replaceAll('_', ' ')}".`;
	}
}

/**
 * Turns a request for a gated change into a card. Nothing is changed. The arguments are validated against the verb's own strict input
 * first, so a card can always be shown and a bad request never reaches the person. Allowed for the assistant and for the person.
 */
export async function createAction(
	ctx: Ctx,
	opts: { verb: string; args: unknown; turnId?: string }
): Promise<{ actionId: string; summary: string }> {
	const v = verbByName(opts.verb);
	if (!v || v.kind === 'person' || v.kind === 'read')
		throw new OpsError('INVALID', 'That cannot be turned into an approval card.');
	const parsed = v.input.safeParse(opts.args);
	if (!parsed.success) {
		throw new OpsError('INVALID', firstProblem(v.input, parsed.error));
	}
	// The person's tap on the card is the confirmation, so a model never pre-sets it
	const {
		confirmed: _confirmed,
		acknowledgeLarge: _acknowledgeLarge,
		...clean
	} = parsed.data as Args;
	const args: Args = clean;
	const names = await namesFor(ctx, args);
	// The amounts on a card are in the currency they are for: the one named; for a bill, the bill's own (a new bill: the main currency);
	// for money in or out of an account, the wallet's, which is the account's own unless another is named; for the money plan, the main one
	const { currency, current } = await run(ctx, async (tx, userId) => {
		const main = (await readSettings(tx, userId)).currency;
		const accountId =
			typeof args.accountId === 'string'
				? args.accountId
				: typeof args.fromAccountId === 'string'
					? args.fromAccountId
					: null;
		const billId = typeof args.billId === 'string' ? args.billId : null;
		const [acc] = accountId
			? await tx
					.select({ currency: account.currency })
					.from(account)
					.where(and(eq(account.userId, userId), eq(account.id, accountId)))
			: [];
		const [theBill] = billId
			? await tx
					.select({ currency: bill.currency })
					.from(bill)
					.where(and(eq(bill.userId, userId), eq(bill.id, billId)))
			: [];
		const planVerbs = [
			'bill_create',
			'income_create',
			'income_update',
			'goal_create',
			'goal_update'
		];
		const currency =
			typeof args.currency === 'string'
				? args.currency
				: (theBill?.currency ??
					(planVerbs.includes(v.name) || v.name === 'account_update'
						? main
						: (acc?.currency ?? main)));
		return {
			currency,
			current:
				v.name === 'snapshot_record' && accountId
					? (await balanceFor(tx, userId, accountId, currency)).balance
					: null
		};
	});
	const summary = describeAction(v.name, args, names, currency, current);
	return mapped(async () => {
		const row = await run(ctx, async (tx, userId) => {
			const [r] = await tx
				.insert(agentAction)
				.values({
					userId,
					verb: v.name,
					args,
					summary,
					turnId: opts.turnId ?? null,
					expiresAt: new Date(Date.now() + CARD_LIFETIME_MS)
				})
				.returning({ id: agentAction.id });
			return r;
		});
		if (!row) throw new OpsError('CONFLICT', 'The card could not be saved.');
		return { actionId: row.id, summary };
	});
}

/** The cards of the caller, newest first. */
export async function listActions(ctx: Ctx, status?: ActionView['status']): Promise<ActionView[]> {
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(agentAction)
			.where(
				and(eq(agentAction.userId, userId), status ? eq(agentAction.status, status) : undefined)
			)
			.orderBy(desc(agentAction.createdAt))
			.limit(50)
	);
	return plain(rows);
}

/**
 * The person answers a card. Approving runs the verb now, as the person, with a request id made from the card, so a double tap
 * or a retry cannot apply it twice. Rejecting just closes it. Only a person can call this.
 */
export async function decideAction(
	ctx: Ctx,
	opts: { actionId: string; decision: 'approve' | 'reject' }
): Promise<ActionView> {
	requirePerson(ctx.actor.kind, 'answer an approval card');
	const card = await run(ctx, async (tx, userId) => {
		const [row] = await tx
			.select()
			.from(agentAction)
			.where(and(eq(agentAction.userId, userId), eq(agentAction.id, opts.actionId)));
		return row;
	});
	if (!card) throw new OpsError('NOT_FOUND', 'That card does not exist.');
	if (card.status !== 'pending' && !(card.status === 'failed' && opts.decision === 'approve'))
		throw new OpsError('CONFLICT', `That card is already ${card.status}.`);
	const settle = (patch: Partial<typeof agentAction.$inferInsert>) =>
		run(ctx, async (tx, userId) => {
			const [row] = await tx
				.update(agentAction)
				.set({ ...patch, decidedAt: sql`now()`, updatedAt: sql`now()` })
				.where(and(eq(agentAction.userId, userId), eq(agentAction.id, card.id)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That card does not exist.');
			return plain(row);
		});
	if (card.expiresAt.getTime() < Date.now()) return settle({ status: 'expired' });
	if (opts.decision === 'reject') return settle({ status: 'rejected' });
	try {
		// Approving is the yes the verb asks for. A balance count ten times off asks again: it needs the second approval
		const asksForYes = CONFIRMING_VERBS.has(card.verb);
		const wasAsked = (card.result as { status?: unknown } | null)?.status === 'needs_confirmation';
		// A balance card states the old balance, the new one and the difference. A count of exactly zero is a deliberate reset, so one tap
		// is the whole yes; any other count ten times off (most often a typo) still asks a second time
		const zero = (card.args as Args).amount === 0;
		const args = asksForYes
			? {
					...(card.args as Args),
					confirmed: true,
					...(card.verb === 'snapshot_record' && (wasAsked || zero)
						? { acknowledgeLarge: true }
						: {})
				}
			: card.args;
		// The assistant asked, the person approved: the audit trail says both
		const result = await invokeVerb(
			{
				...ctx,
				requestId: `card-${card.id}`,
				approvalId: card.id,
				...(card.turnId ? { onBehalfOf: 'agent' as const, turnId: card.turnId } : {})
			},
			card.verb,
			args
		);
		// A verb that only asked for more (an amount, an account, a second yes) wrote nothing, so the card is not applied
		const status = (result as { status?: unknown } | null)?.status;
		if (typeof status === 'string' && status.startsWith('needs_'))
			return await settle({ status: 'failed', result: result ?? null });
		return await settle({ status: 'applied', result: result ?? null });
	} catch (e) {
		if (e instanceof OpsError) {
			// A refusal (a rule that no longer fits, an archived account) is shown on the card, which can be approved again after a fix
			const done = await settle({ status: 'failed', result: { error: e.message } });
			return done;
		}
		throw e;
	}
}

/**
 * One line per recent card, newest first, for the assistant's turn context: what the card asked for and how the person answered it.
 * The sentence is the one built on the card and the failure reason is the server's own, so nothing here is free text from the model.
 */
export async function recentCardLines(
	ctx: Ctx,
	limit = 12,
	days = 3,
	chatId?: string
): Promise<string[]> {
	const since = new Date(Date.now() - days * 24 * 3_600_000);
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select({
				status: agentAction.status,
				summary: agentAction.summary,
				result: agentAction.result
			})
			.from(agentAction)
			.where(
				and(
					eq(agentAction.userId, userId),
					gt(agentAction.createdAt, since),
					// A card belongs to the message that asked for it, so only the cards of this chat reach its assistant
					chatId
						? inArray(
								agentAction.turnId,
								tx
									.select({ id: chatTurn.clientMessageId })
									.from(chatTurn)
									.where(and(eq(chatTurn.userId, userId), eq(chatTurn.chatId, chatId)))
							)
						: undefined
				)
			)
			.orderBy(desc(agentAction.createdAt))
			.limit(limit)
	);
	return rows.map((r) => {
		const why = (r.result as { error?: unknown } | null)?.error;
		return `${r.status}: ${r.summary.slice(0, 200)}${r.status === 'failed' && typeof why === 'string' ? ` (${why.slice(0, 120)})` : ''}`;
	});
}

/** Used by the assistant's turn to know how many cards wait. */
export async function pendingCount(ctx: Ctx): Promise<number> {
	return run(ctx, async (tx, userId) => {
		const [r] = await tx
			.select({ n: sql<number>`count(*)::int` })
			.from(agentAction)
			.where(and(eq(agentAction.userId, userId), eq(agentAction.status, 'pending')));
		return r?.n ?? 0;
	});
}
