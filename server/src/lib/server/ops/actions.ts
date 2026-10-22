// APPROVAL CARDS: THE ASSISTANT MAY ONLY ASK FOR A CHANGE TO THE MONEY PLAN. IT BECOMES A CARD; THE PERSON APPROVES OR REJECTS IT; ONLY THEN THE VERB RUNS, AS THE PERSON.
// The text on a card is built here from the validated arguments and names looked up in the person's own data. Free text from the model is
// never the card text, and a model can neither approve a card nor mint anything that approves one: this verb needs a person caller.

// -- TYPES -- //
import type { Plain } from './shared';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, desc, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { formatPhp } from '../../finance/money';
import { account, agentAction, bill, goal } from '../db/schema';
import { OpsError, run } from './context';
import { invokeVerb, verbByName } from './registry';
import { mapped, plain, requirePerson } from './shared';

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
const money = (v: unknown) => (num(v) === null ? 'an amount' : formatPhp(num(v) as number));

function when(schedule: unknown): string {
	const s = schedule as { kind?: string; day?: number; days?: number[]; n?: number } | null;
	if (s?.kind === 'monthly') return `on day ${s.day} of each month`;
	if (s?.kind === 'semi_monthly') return `on days ${s.days?.join(' and ')} of each month`;
	if (s?.kind === 'every_n_days') return `every ${s.n} days`;
	return 'on a schedule';
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
	names: ReadonlyMap<string, string>
): string {
	const nm = (id: unknown) => names.get(typeof id === 'string' ? id : '') ?? 'an account';
	switch (verbName) {
		case 'account_create':
			return `Add the account "${text(args.name)}".`;
		case 'account_update':
			return `Change the account ${nm(args.accountId)}${args.name ? ` to "${text(args.name)}"` : ''}${num(args.minBalance) !== null ? `, minimum balance ${money(args.minBalance)}` : ''}.`;
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
		case 'bill_mark_paid':
			return `Mark "${names.get(typeof args.billId === 'string' ? args.billId : '') ?? 'the bill'}" paid for ${text(args.dueDate, 10)}${args.amount ? `, ${money(args.amount)}` : ''}.`;
		case 'goal_create':
			return `Add the goal "${text(args.name)}" in ${nm(args.accountId)}${num(args.perPayday) ? `, setting aside ${money(args.perPayday)} each payday` : ''}.`;
		case 'goal_update':
			return `Change the goal ${nm(args.goalId)}${args.name ? ` ("${text(args.name)}")` : ''}${num(args.perPayday) !== null ? `, ${money(args.perPayday)} each payday` : ''}.`;
		case 'snapshot_record':
			return `Record that ${nm(args.accountId)} holds ${money(args.amount)}.`;
		case 'expense_log':
			return `Log an expense of ${money(args.amount)} on ${nm(args.accountId)}${args.note ? `: "${text(args.note, 80)}"` : ''}.`;
		case 'expense_from_text':
			return `Log the expense "${text(args.text, 80)}".`;
		case 'income_record':
			return `Record ${money(args.amount)} arriving in ${nm(args.accountId)}.`;
		case 'refund_record':
			return `Record a refund of ${money(args.amount)} into ${nm(args.accountId)}.`;
		case 'transfer_record':
			return `Move ${money(args.amount)} from ${nm(args.fromAccountId)} to ${nm(args.toAccountId)}${num(args.fee) ? ` (fee ${money(args.fee)})` : ''}.`;
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
		const issue = parsed.error.issues[0];
		throw new OpsError(
			'INVALID',
			`${issue?.path.join('.') ?? 'input'}: ${issue?.message ?? 'invalid'}`
		);
	}
	// The person's tap on the card is the confirmation, so a model never pre-sets it
	const {
		confirmed: _confirmed,
		acknowledgeLarge: _acknowledgeLarge,
		...clean
	} = parsed.data as Args;
	const args: Args = clean;
	const names = await namesFor(ctx, args);
	const summary = describeAction(v.name, args, names);
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
		const args = asksForYes
			? {
					...(card.args as Args),
					confirmed: true,
					...(card.verb === 'snapshot_record' && wasAsked ? { acknowledgeLarge: true } : {})
				}
			: card.args;
		const result = await invokeVerb({ ...ctx, requestId: `card-${card.id}` }, card.verb, args);
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
