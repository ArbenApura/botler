// APPROVAL CARDS: THE ASSISTANT ASKS FOR A BALANCE COUNT, AND FOR ANY WRITE AFTER UNTRUSTED TEXT OR PAST THE DELETE CAP OF A TURN. IT BECOMES A CARD; THE PERSON APPROVES OR REJECTS IT; ONLY THEN THE VERB RUNS, AS THE PERSON.
// The text on a card is built here from the validated arguments and names looked up in the person's own data. Free text from the model is
// never the card text, and a model can neither approve a card nor mint anything that approves one: this verb needs a person caller.

// -- TYPES -- //
import type { Plain } from './shared';
import type { Ctx } from './context';
import type { Schedule } from '../../finance/schedule';
import type { DbHandle, Tx } from '../db/client';
// -- DEP-MODULES -- //
import { and, desc, eq, gt, inArray, lt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { DEFAULT_CURRENCY, formatMoney } from '../../finance/currency';
import { describeSchedule, validateSchedule } from '../../finance/schedule';
import {
	account,
	agentAction,
	allocationRule,
	bill,
	chatTurn,
	goal,
	incomeSchedule,
	user
} from '../db/schema';
import { lockPerson, setAuditContext, withUser } from '../db/tenant';
import { auditOf, OpsError, run } from './context';
import { balanceFor } from './ledger';
import { redactText } from './notebook';
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
/** A short piece of model-written text on a card: control and format characters (line breaks, hidden marks) become spaces, then it is cut. */
const text = (v: unknown, max = 60): string =>
	typeof v === 'string' ? v.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, ' ').slice(0, max) : '';

/** The words of a note or page on a card: all of it up to 2000 characters, and the rest counted, so nothing the person approves is hidden. */
const words = (v: unknown, max = 2000): string =>
	typeof v === 'string'
		? v.length > max
			? `${v.slice(0, max)}... (and ${v.length - max} more characters)`
			: v
		: '';

/** The words the verb will save for the assistant: account, card and phone numbers taken out, as the page verbs do, so the card shows what is kept. */
const kept = (v: unknown, max = 2000): string =>
	words(typeof v === 'string' ? redactText(v) : v, max);

/** Where a parent named on a card is: under a page, or (an empty name) the top level. */
const underParent = (v: unknown): string =>
	typeof v === 'string' ? (v.trim() ? ` under "${text(v, 80)}"` : ' at the top level') : '';

/** A page named on a card by its titles. */
const pageName = (a: Args): string =>
	`the page "${text(a.page, 80)}"${underParent(a.parent)} in the notebook "${text(a.notebook, 80)}"`;
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
		for (const id of [args.billId, args.fundsBillId])
			if (typeof id === 'string')
				for (const b of await tx
					.select({ id: bill.id, name: bill.name })
					.from(bill)
					.where(and(eq(bill.userId, userId), eq(bill.id, id))))
					names.set(b.id, b.name);
		if (typeof args.incomeId === 'string')
			for (const i of await tx
				.select({ id: incomeSchedule.id, name: incomeSchedule.label })
				.from(incomeSchedule)
				.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, args.incomeId))))
				names.set(i.id, i.name);
		// A rule has no name of its own: the card says what it does and where it goes
		if (typeof args.ruleId === 'string')
			for (const r of await tx
				.select()
				.from(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.id, args.ruleId)))) {
				const target = names.get(r.targetAccountId ?? r.targetGoalId ?? '') ?? 'its target';
				const what =
					r.mode === 'percent'
						? `${(r.basisPoints ?? 0) / 100}%`
						: r.mode === 'rest'
							? 'the rest'
							: 'a fixed amount';
				names.set(r.id, `${what} to ${target} (${r.status})`);
			}
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
			return `Add the account "${text(args.name)}"${args.purpose ? `, for "${text(args.purpose)}"` : ''}${args.icon ? `, with the ${text(args.icon, 24)} icon` : ''}.`;
		case 'account_update':
			return `Change the account ${nm(args.accountId)}${args.name ? ` to "${text(args.name)}"` : ''}${num(args.minBalance) !== null ? `, minimum balance ${money(args.minBalance)}` : ''}${args.purpose ? `, purpose "${text(args.purpose)}"` : args.purpose === null ? ', purpose cleared' : ''}${args.icon ? `, ${text(args.icon, 24)} icon` : args.icon === null ? ', icon cleared' : ''}${args.clearImage === true ? ', picture removed' : ''}.`;
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
			return `Change the bill ${names.get(typeof args.billId === 'string' ? args.billId : '') ?? ''}${args.name ? ` ("${text(args.name)}")` : ''}${args.amount ? ` to ${money(args.amount)}` : ''}${args.icon ? `, ${text(args.icon, 24)} icon` : args.icon === null ? ', icon cleared' : ''}${args.clearImage === true ? ', picture removed' : ''}.`.replace(
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
		case 'bill_delete':
			return `Remove the bill "${names.get(typeof args.billId === 'string' ? args.billId : '') ?? 'a bill'}". If it was ever paid it is switched off instead, so its history stays.`;
		case 'income_delete':
			return `Remove the payday schedule "${names.get(typeof args.incomeId === 'string' ? args.incomeId : '') ?? 'a payday'}". If a split was made for it, it is switched off instead.`;
		case 'rule_update': {
			// A link to a bill changes what the split takes from the pay, so the card names the bill (BTL-20261029-0119)
			const rule = names.get(typeof args.ruleId === 'string' ? args.ruleId : '') ?? 'a rule';
			const parts = [
				typeof args.label === 'string' ? `call it "${text(args.label, 60)}"` : '',
				args.label === null ? 'clear its name' : '',
				typeof args.fundsBillId === 'string'
					? `make it save for the bill "${names.get(args.fundsBillId) ?? 'a bill'}", so that bill is paid from what it saved instead of from the pay`
					: '',
				args.fundsBillId === null ? 'stop it saving for a bill' : ''
			].filter(Boolean);
			return `Change the payday rule ${rule}: ${parts.join(', ')}.`;
		}
		case 'rule_propose':
			return `Propose a payday rule: ${args.mode === 'fixed' ? money(args.amount) : args.mode === 'percent' ? `${(num(args.basisPoints) ?? 0) / 100}%` : 'the rest'} to ${nm(args.targetAccountId ?? args.targetGoalId)}${typeof args.label === 'string' ? `, named "${text(args.label, 60)}"` : ''}${typeof args.fundsBillId === 'string' ? `, saving for the bill "${names.get(args.fundsBillId) ?? 'a bill'}"` : ''}. It still waits for your approval.`;
		case 'rule_delete':
			return `Remove the payday rule ${names.get(typeof args.ruleId === 'string' ? args.ruleId : '') ?? 'a rule'} for good.`;
		case 'split_delete':
			return args.all === true
				? `Remove every recorded payday split for good, as they are when you approve${args.removeEntries === true ? ', and take the pay and transfers they wrote out of your balances, which changes your account balances' : '. The pay and transfers already in your ledger stay'}. This cannot be undone.`
				: `Remove one recorded payday split for good${args.removeEntries === true ? ', and take its pay and transfers out of your balances, which changes your account balances' : '. The pay and transfers it wrote to your ledger stay'}. This cannot be undone.`;
		case 'mark_from_photo':
			return `Use photo ${num(args.photo) ?? '?'} of your message as the picture of the ${args.target === 'bill' ? 'bill' : 'account'} "${text(args.name, 80)}"${args.fit === 'contain' ? ', keeping the whole part chosen' : ''}. Your phone cuts it and shows the result here; you can zoom or move it before you approve.`;
		case 'account_delete':
			return `Remove the account ${nm(args.accountId)}. If it has entries or balance counts it is hidden instead and its history stays; if a bill, payday, goal or rule still uses it, nothing happens.`;
		case 'account_wallet_remove':
			return `Remove the ${text(args.currency, 3)} wallet from the account ${nm(args.accountId)}. Only an empty one goes.`;
		case 'goal_delete':
			// What is saved stays in its account: only the goal and the payday rules that point at it go
			return `Delete the goal ${names.get(typeof args.goalId === 'string' ? args.goalId : '') ?? 'a goal'} for good, with any payday rules that point at it. The money saved for it stays where it is.`;
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
		case 'notebook_edit': {
			// All of the text is on the card, up to the most the verb accepts (heading 80, line 400, find and replacement 2000): a note written
			// into the prompt of every later message is judged by its words, so nothing the person approves is hidden from them
			const book =
				typeof args.notebook === 'string' && args.notebook.trim()
					? `the notebook "${text(args.notebook, 80)}"`
					: 'your notebook';
			return args.op === 'add'
				? `Add this line to ${book} under "${text(args.heading, 80)}": "${text(args.line, 400)}".`
				: args.op === 'replace'
					? `In ${book}, change "${text(args.find, 2000)}" to "${text(args.replacement, 2000)}".`
					: `Remove this from ${book}: "${text(args.find, 2000)}".`;
		}
		case 'notebook_create':
			// The first text goes into the card too, so the person sees the words that will be kept
			return `Make a new notebook "${text(args.title, 80)}"${typeof args.summary === 'string' && args.summary ? ` (${text(args.summary, 200)})` : ''}${typeof args.text === 'string' && args.text ? ` with this text: "${text(args.text, 2000)}"` : ''}.`;
		case 'notebook_update':
			return `Change the notebook "${text(args.notebook, 80)}": ${[
				typeof args.newTitle === 'string' ? `call it "${text(args.newTitle, 80)}"` : '',
				typeof args.summary === 'string' ? `describe it as "${text(args.summary, 200)}"` : ''
			]
				.filter(Boolean)
				.join(', ')}.`;
		case 'notebook_delete':
			return `Delete the notebook "${text(args.notebook, 80)}". It can be restored for 30 days.`;
		case 'notebook_undelete':
			return `Put the deleted notebook "${text(args.notebook, 80)}" back.`;
		// The pages: every card shows the words that will be kept, up to the most a card holds (the rest is counted), and names the page by its titles
		case 'page_create':
			return `In the notebook "${text(args.notebook, 80)}" make a new page "${text(args.title, 80)}"${typeof args.parent === 'string' && args.parent.trim() ? ` under "${text(args.parent, 80)}"` : ''}${typeof args.text === 'string' && args.text ? ` with this text: "${kept(args.text)}"` : ''}.`;
		case 'page_edit': {
			const page = pageName(args);
			return args.op === 'add'
				? `Add this to ${page} under "${text(typeof args.heading === 'string' ? redactText(args.heading) : '', 80)}": "${kept(args.line)}".`
				: args.op === 'replace'
					? `In ${page}, change "${words(args.find)}" to "${kept(args.replacement)}".`
					: `Remove this from ${page}: "${words(args.find)}".`;
		}
		case 'page_rename':
			return `Rename ${pageName(args)} to "${text(args.newTitle, 80)}".`;
		case 'page_move':
			return `Move ${pageName(args)} ${typeof args.toParent === 'string' && args.toParent.trim() ? `under "${text(args.toParent, 80)}" in ` : 'to the top level of '}${typeof args.toNotebook === 'string' ? `the notebook "${text(args.toNotebook, 80)}"` : 'its notebook'}${num(args.position) !== null ? `, at place ${(num(args.position) ?? 0) + 1}` : ''}.`;
		case 'page_merge': {
			const sources = Array.isArray(args.sources)
				? args.sources
						.map((s: unknown) =>
							s && typeof s === 'object' ? `"${text((s as Args).page, 80)}"` : ''
						)
						.filter(Boolean)
						.join(', ')
				: 'the named pages';
			return `Merge ${sources} into ${pageName(args)}: their text is added at its end, as it is, under their titles, and the merged pages are deleted. They can be restored for 30 days.`;
		}
		case 'page_delete':
			return `Delete ${pageName(args)} with its sub-pages. They can be restored for 30 days.`;
		case 'page_undelete':
			return `Put the deleted page ${pageName(args)} back.`;
		default:
			return `Run "${verbName.replaceAll('_', ' ')}".`;
	}
}

/**
 * Turns a request for a change that needs the person (a balance count, or any write after untrusted text) into a card. Nothing is changed. The arguments are validated against the verb's own strict input
 * first, so a card can always be shown and a bad request never reaches the person. Allowed for the assistant and for the person.
 */
export async function createAction(
	ctx: Ctx,
	opts: {
		verb: string;
		args: unknown;
		turnId?: string;
		/**
		 * The call that asked for this card inside its turn (the call number and a hash of the verb and arguments). A second request with the
		 * same turn and key, such as a re-run of a turn that was taken over, finds the card that exists instead of making another. The key is
		 * kept in the card's result field while the card waits, so the table needs no new column.
		 */
		key?: string;
	}
): Promise<{ actionId: string; summary: string }> {
	const v = verbByName(opts.verb);
	if (!v || v.kind === 'person' || v.kind === 'read')
		throw new OpsError('INVALID', 'That cannot be turned into an approval card.');
	const schema = ctx.actor.kind === 'agent' && v.agentStrict ? (v.agentInput ?? v.input) : v.input;
	const parsed = schema.safeParse(opts.args);
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
			if (opts.key && opts.turnId) {
				// The person's lock serialises two runs of one turn, so the second finds the first one's card
				await lockPerson(tx, userId);
				const [same] = await tx
					.select({ id: agentAction.id, summary: agentAction.summary })
					.from(agentAction)
					.where(
						and(
							eq(agentAction.userId, userId),
							eq(agentAction.turnId, opts.turnId),
							sql`${agentAction.result}->>'key' = ${opts.key}`
						)
					);
				if (same) return same;
			}
			const [r] = await tx
				.insert(agentAction)
				.values({
					userId,
					verb: v.name,
					args,
					summary,
					turnId: opts.turnId ?? null,
					...(opts.key && opts.turnId ? { result: { key: opts.key } } : {}),
					expiresAt: new Date(Date.now() + CARD_LIFETIME_MS)
				})
				.returning({ id: agentAction.id });
			return r ? { id: r.id, summary } : undefined;
		});
		if (!row) throw new OpsError('CONFLICT', 'The card could not be saved.');
		return { actionId: row.id, summary: row.summary };
	});
}

/** The cards of the caller, newest first. */
export async function listActions(ctx: Ctx, status?: ActionView['status']): Promise<ActionView[]> {
	const rows = await run(ctx, async (tx, userId) => {
		// A card past its time is marked expired here too, so the list never shows a pending card that can no longer be approved
		await expireCards(tx, userId);
		return tx
			.select()
			.from(agentAction)
			.where(
				and(eq(agentAction.userId, userId), status ? eq(agentAction.status, status) : undefined)
			)
			.orderBy(desc(agentAction.createdAt))
			.limit(50);
	});
	return plain(rows);
}

/** Marks the pending cards of one person that are past their time as expired. Returns how many. */
async function expireCards(tx: Tx, userId: string): Promise<number> {
	const done = await tx
		.update(agentAction)
		.set({ status: 'expired', decidedAt: sql`now()`, updatedAt: sql`now()` })
		.where(
			and(
				eq(agentAction.userId, userId),
				eq(agentAction.status, 'pending'),
				lt(agentAction.expiresAt, sql`now()`)
			)
		)
		.returning({ id: agentAction.id });
	return done.length;
}

/**
 * Housekeeping, for the hourly job: marks every pending card past its time as expired, for every person. Pass the database handle (it sets
 * each person's context itself). Returns how many cards it closed. Safe to run at any time and as often as wanted.
 */
export async function expireStaleActions(handle: DbHandle): Promise<number> {
	const people = await handle.db.select({ id: user.id }).from(user);
	let closed = 0;
	for (const p of people) {
		const ctx: Ctx = {
			handle,
			actor: { userId: p.id, kind: 'agent', tool: 'job:actions.expire' },
			via: 'job',
			channel: 'job'
		};
		closed += await withUser(handle, p.id, async (tx) => {
			await setAuditContext(tx, { ...auditOf(ctx) });
			return expireCards(tx, p.id);
		});
	}
	return closed;
}

/**
 * The person answers a card. Approving runs the verb now, as the person, with a request id made from the card, so a double tap
 * or a retry cannot apply it twice. Rejecting just closes it. Only a person can call this.
 */
export async function decideAction(
	ctx: Ctx,
	opts: {
		actionId: string;
		decision: 'approve' | 'reject';
		/** The picture the phone made for a mark_from_photo card, as base64. It is used once, in memory, and never stored on the card. */
		imageData?: string;
	}
): Promise<ActionView> {
	requirePerson(ctx.actor.kind, 'answer an approval card');
	// The card's row stays locked from the read to the answer, so an approve and a reject that arrive together take turns: the second finds
	// the card already answered and gets a clear error, and the row keeps the first decision. The verb runs on its own connection
	return run(ctx, async (tx, userId) => {
		const [card] = await tx
			.select()
			.from(agentAction)
			.where(and(eq(agentAction.userId, userId), eq(agentAction.id, opts.actionId)))
			.for('update');
		if (!card) throw new OpsError('NOT_FOUND', 'That card does not exist.');
		if (card.status !== 'pending' && !(card.status === 'failed' && opts.decision === 'approve'))
			throw new OpsError('CONFLICT', `That card is already ${card.status}.`);
		// Only the card as it was read can be settled
		const settle = async (patch: Partial<typeof agentAction.$inferInsert>) => {
			const [row] = await tx
				.update(agentAction)
				.set({ ...patch, decidedAt: sql`now()`, updatedAt: sql`now()` })
				.where(
					and(
						eq(agentAction.userId, userId),
						eq(agentAction.id, card.id),
						eq(agentAction.status, card.status)
					)
				)
				.returning();
			if (!row)
				throw new OpsError('CONFLICT', 'That card was already answered. Open the list again.');
			return plain(row);
		};
		if (card.expiresAt.getTime() < Date.now()) return settle({ status: 'expired' });
		if (opts.decision === 'reject') return settle({ status: 'rejected' });
		// A picture comes only with a card that asks for one: it is never carried by another card
		if (opts.imageData !== undefined && card.verb !== 'mark_from_photo')
			throw new OpsError('INVALID', 'This card does not take a picture.');
		let patch: Partial<typeof agentAction.$inferInsert>;
		try {
			// Approving is the yes the verb asks for. A balance count ten times off asks again: it needs the second approval
			const asksForYes = CONFIRMING_VERBS.has(card.verb);
			const wasAsked =
				(card.result as { status?: unknown } | null)?.status === 'needs_confirmation';
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
				: card.verb === 'mark_from_photo' && opts.imageData !== undefined
					? { ...(card.args as Args), imageData: opts.imageData }
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
			patch =
				typeof status === 'string' && status.startsWith('needs_')
					? { status: 'failed', result: result ?? null }
					: { status: 'applied', result: result ?? null };
		} catch (e) {
			if (!(e instanceof OpsError)) throw e;
			// A refusal (a rule that no longer fits, an archived account) is shown on the card, which can be approved again after a fix
			patch = { status: 'failed', result: { error: e.message } };
		}
		return settle(patch);
	});
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
