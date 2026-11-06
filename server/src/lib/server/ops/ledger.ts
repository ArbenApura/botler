// LEDGER VERBS: EXPENSES (BY FORM OR BY CHAT TEXT), INCOME, REFUNDS, TRANSFERS, BALANCE COUNTS WITH DRIFT, UNDO, THE WEEKLY CHECK-IN
// None of these call the model. Logging an expense or marking a bill paid works when the model is down or its monthly cap is reached.
// Balance = the latest count of the account plus the signed transactions after it (see src/lib/finance/ledger.ts).

// -- TYPES -- //
import type { Txn } from '../../finance/ledger';
import type { Tx } from '../db/client';
import type { Plain } from './shared';
import type { Ctx } from './context';
import type {
	ExpenseFromTextInput,
	ExpenseLogInput,
	IncomeRecordInput,
	SnapshotRecordInput,
	TransferRecordInput
} from '../db/zod';
// -- DEP-MODULES -- //
import { and, desc, eq, gt, gte, isNull, lt, lte, or, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, toLocalDate, dayStart } from '../../finance/dates';
import { checkBalanceChange, needsAmountConfirmation } from '../../finance/confirm';
import { balanceOf, spendingOf, untrackedSpendingOf } from '../../finance/ledger';
import { parseExpenseText } from '../../finance/text';
import { balanceConfirmThreshold } from '../../finance/currency';
import { setAuditContext } from '../db/tenant';
import { readSettings } from './settings';
import {
	account,
	accountWallet,
	balanceSnapshot,
	billOverride,
	billPayment,
	ledgerTxn,
	requestLog,
	splitPlan,
	undoJournal
} from '../db/schema';
import {
	expenseFromTextInput,
	expenseLogInput,
	incomeRecordInput,
	rangeInput,
	snapshotRecordInput,
	transferRecordInput,
	undoInput
} from '../db/zod';
import { OpsError, recordUndo, run, runWrite } from './context';
import { mapped, parse, plain, requireActiveAccount, requirePerson } from './shared';

// -- TYPES -- //

export type TxnView = Plain<typeof ledgerTxn.$inferSelect> & {
	/** The id `undo` takes for this entry; what a write answers, never stored on the row. */
	journalId?: string;
	/** A hint for the assistant on a write that may not be what the person meant. Never stored. */
	check?: string;
};

/** What the person is asked to confirm before an amount is saved. */
export type Chip = {
	accountId: string;
	accountName: string;
	amount: number;
	/** The currency of the amount: the wallet it is for. */
	currency: string;
	date: string;
	note: string;
	/** For a balance count: what the app expected, and how unusual the change is. */
	expected?: number | null;
	severity?: 'normal' | 'large';
};

export type ExpenseResult =
	| { status: 'saved'; txn: TxnView }
	| { status: 'needs_confirmation'; chip: Chip }
	| {
			status: 'needs_account';
			amount: number;
			/** The currency the words named, or the main currency when they named none. */
			currency: string;
			note: string;
			accounts: string[];
	  }
	| { status: 'needs_amount'; note: string };

export type SnapshotResult =
	| {
			status: 'saved';
			snapshotId: string;
			/** The wallet that was counted: counted, expected, drift and untracked are in this currency. */
			currency: string;
			counted: number;
			expected: number | null;
			drift: number;
			untracked: number;
			mode: 'count' | 'reset';
	  }
	| { status: 'needs_confirmation'; chip: Chip };

// -- CONSTANTS -- //

const CHECKIN_DAYS = 7;
/** An entry dated further ahead than this is a typo, not a plan. */
const FUTURE_SLACK_MS = 5 * 60_000;

// -- FUNCTIONS -- //

const toTxn = (r: typeof ledgerTxn.$inferSelect): Txn => ({
	type: r.type,
	accountId: r.accountId,
	toAccountId: r.toAccountId,
	amount: r.amount,
	currency: r.currency,
	toCurrency: r.toCurrency,
	toAmount: r.toAmount,
	fee: r.fee,
	occurredAt: r.occurredAt,
	voided: r.voidedAt !== null
});

function instant(value: string | undefined, label: string): Date {
	if (!value) return new Date();
	const d = new Date(value);
	if (d.getTime() > Date.now() + FUTURE_SLACK_MS)
		throw new OpsError('INVALID', `${label} is in the future.`);
	return d;
}

/** Makes sure the account has a wallet in the currency. Safe to repeat and to run at the same time: the second one finds it there. */
export async function ensureWallet(tx: Tx, userId: string, accountId: string, currency: string) {
	await tx
		.insert(accountWallet)
		.values({ userId, accountId, currency })
		.onConflictDoNothing({
			target: [accountWallet.userId, accountWallet.accountId, accountWallet.currency]
		});
}

/**
 * The balance of one wallet of an account (the account in one currency) at an instant, from its latest count and what happened after.
 * Reads only, inside a transaction.
 */
export async function balanceFor(
	tx: Tx,
	userId: string,
	accountId: string,
	currency: string,
	at: Date = new Date()
) {
	const [snap] = await tx
		.select()
		.from(balanceSnapshot)
		.where(
			and(
				eq(balanceSnapshot.userId, userId),
				eq(balanceSnapshot.accountId, accountId),
				eq(balanceSnapshot.currency, currency),
				lte(balanceSnapshot.takenAt, at)
			)
		)
		.orderBy(desc(balanceSnapshot.takenAt))
		.limit(1);
	const rows = await tx
		.select()
		.from(ledgerTxn)
		.where(
			and(
				eq(ledgerTxn.userId, userId),
				isNull(ledgerTxn.voidedAt),
				lte(ledgerTxn.occurredAt, at),
				or(eq(ledgerTxn.accountId, accountId), eq(ledgerTxn.toAccountId, accountId)),
				snap ? gt(ledgerTxn.occurredAt, snap.takenAt) : undefined
			)
		);
	return {
		balance: balanceOf(
			accountId,
			currency,
			snap ? { amount: snap.amount, takenAt: snap.takenAt } : null,
			rows.map(toTxn)
		),
		countedAt: snap?.takenAt ?? null,
		hasData: Boolean(snap) || rows.some((r) => r.currency === currency || r.toCurrency === currency)
	};
}

/** Writes one ledger row and its undo entry in the verb's own transaction. */
export async function insertTxn(
	tx: Tx,
	userId: string,
	requestId: string | undefined,
	values: Omit<typeof ledgerTxn.$inferInsert, 'userId' | 'id'>,
	// A verb that writes its own, wider undo entry (a bill marked paid) turns the row's own entry off
	options: { journal?: boolean } = {}
) {
	const [row] = await tx
		.insert(ledgerTxn)
		.values({ ...values, userId })
		.returning();
	if (!row) throw new OpsError('CONFLICT', 'The entry could not be saved.');
	// An entry in a currency the account did not hold yet opens that wallet (both sides of a transfer)
	await ensureWallet(tx, userId, row.accountId, row.currency);
	if (row.toAccountId && row.toCurrency)
		await ensureWallet(tx, userId, row.toAccountId, row.toCurrency);
	if (options.journal === false) return row;
	const journalId = await recordUndo(tx, userId, requestId, {
		verb: `ledger.${row.type}`,
		entity: 'ledger_txn',
		entityId: row.id,
		before: null,
		after: row
	});
	// The id to give undo: the entry's own id is not the journal's (in the chat of 6 Nov the first undo failed on it)
	return journalId ? { ...row, journalId } : row;
}

// -- EXPENSES -- //

/** Logs an expense. An amount read from a picture comes back as a chip to confirm first and writes nothing. */
export async function logExpense(ctx: Ctx, raw: ExpenseLogInput): Promise<ExpenseResult> {
	const input = parse(expenseLogInput, raw);
	const source = input.source ?? 'manual';
	const occurredAt = instant(input.occurredAt, 'The date');
	if (needsAmountConfirmation(source) && !input.confirmed) {
		const acc = await run(ctx, (tx, userId) => requireActiveAccount(tx, userId, input.accountId));
		return {
			status: 'needs_confirmation',
			chip: {
				accountId: acc.id,
				accountName: acc.name,
				amount: input.amount,
				currency: input.currency ?? acc.currency,
				date: toLocalDate(occurredAt),
				note: input.note ?? ''
			}
		};
	}
	return mapped(() =>
		runWrite(ctx, 'expense.log', input, async (tx, userId) => {
			const acc = await requireActiveAccount(tx, userId, input.accountId);
			const row = await insertTxn(tx, userId, ctx.requestId, {
				type: 'expense',
				accountId: input.accountId,
				amount: input.amount,
				currency: input.currency ?? acc.currency,
				note: input.note ?? '',
				category: input.category ?? null,
				billId: input.billId ?? null,
				occurredAt,
				source
			});
			return { status: 'saved' as const, txn: plain(row) };
		})
	);
}

/** Logs an expense said in plain words, like "lunch 180 gcash". Asks for what is missing instead of guessing. */
export async function logExpenseFromText(
	ctx: Ctx,
	raw: ExpenseFromTextInput
): Promise<ExpenseResult> {
	const input = parse(expenseFromTextInput, raw);
	const { accounts, currency, prior } = await run(ctx, async (tx, userId) => ({
		// What this request id already saved: a retry after the account list changed must get that answer, not a conflict
		prior: ctx.requestId
			? (((
					await tx
						.select({ result: requestLog.result })
						.from(requestLog)
						.where(
							and(
								eq(requestLog.userId, userId),
								eq(requestLog.requestId, ctx.requestId),
								eq(requestLog.verb, 'expense.log')
							)
						)
				)[0]?.result ?? null) as { status?: string; txn?: TxnView } | null)
			: null,
		accounts: await tx
			.select({ id: account.id, name: account.name, currency: account.currency })
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)))
			.orderBy(account.sortOrder, account.name),
		// "lunch 5" is five of the account's own currency; the main currency only reads the first pass
		currency: (await readSettings(tx, userId)).currency
	}));
	const names = accounts.map((a) => a.name);
	// The first answer is replayed when the words still read as the amount that was saved (a different message under the same id is still refused)
	if (prior?.status === 'saved' && prior.txn) {
		const again = parseExpenseText(input.text, names, prior.txn.currency);
		if (again.amount === prior.txn.amount) return { status: 'saved', txn: prior.txn };
	}
	let parsed = parseExpenseText(input.text, names, currency);
	const named = parsed.accountName
		? accounts.find((a) => a.name.toLowerCase() === parsed.accountName?.toLowerCase())
		: undefined;
	const accountId =
		named?.id ?? input.accountId ?? (accounts.length === 1 ? accounts[0]?.id : undefined);
	const acc = accounts.find((a) => a.id === accountId);
	// A number with no symbol or code in front of it is in the currency of the account it is spent from
	if (acc && !parsed.currency && acc.currency !== currency)
		parsed = parseExpenseText(input.text, names, acc.currency);
	if (parsed.amount === null || parsed.amount < 1)
		return { status: 'needs_amount', note: parsed.note };
	if (!accountId)
		return {
			status: 'needs_account',
			amount: parsed.amount,
			currency: parsed.currency ?? currency,
			note: parsed.note,
			accounts: names
		};
	const spentIn = parsed.currency ?? acc?.currency ?? currency;
	// Two numbers in one message: the person checks which one was meant before anything is saved
	if (parsed.ambiguous && !input.confirmed) {
		return {
			status: 'needs_confirmation',
			chip: {
				accountId,
				accountName: acc?.name ?? '',
				amount: parsed.amount,
				currency: spentIn,
				date: toLocalDate(new Date()),
				note: parsed.note
			}
		};
	}
	return logExpense(ctx, {
		accountId,
		amount: parsed.amount,
		currency: spentIn,
		note: parsed.note,
		category: parsed.category,
		source: 'chat'
	});
}

// -- OTHER ENTRIES -- //

async function recordSimple(
	ctx: Ctx,
	verb: 'income.record' | 'refund.record',
	type: 'income' | 'refund',
	raw: IncomeRecordInput
): Promise<TxnView> {
	const input = parse(incomeRecordInput, raw);
	const occurredAt = instant(input.occurredAt, 'The date');
	return mapped(() =>
		runWrite(ctx, verb, input, async (tx, userId) => {
			const acc = await requireActiveAccount(tx, userId, input.accountId);
			const row = await insertTxn(tx, userId, ctx.requestId, {
				type,
				accountId: input.accountId,
				amount: input.amount,
				currency: input.currency ?? acc.currency,
				note: input.note ?? '',
				category: type === 'income' ? 'income' : null,
				occurredAt,
				source: 'manual'
			});
			return plain(row);
		})
	);
}

/** Money that arrived in an account. */
export const recordIncome = (ctx: Ctx, input: IncomeRecordInput) =>
	recordSimple(ctx, 'income.record', 'income', input);

/** Money that came back (a returned purchase). It lowers what counts as spending. */
export const recordRefund = (ctx: Ctx, input: IncomeRecordInput) =>
	recordSimple(ctx, 'refund.record', 'refund', input);

/** Words that say money is for spending, and words that say it is being kept (a cash stash). */
const SPEND_WORDS = /\b(pocket money|allowance|to spend|for spending|expenses?|baon|gastos)\b/i;
const KEEP_WORDS = /\b(stash|savings?|keep|safe|reserve)\b/i;

/**
 * A hint, never a refusal: a move into a cash account whose note says the money is for spending is usually an expense (in the chat of 6 Nov an
 * ATM withdrawal for pocket money was first booked as a move into the cash stash). The assistant asks once; a note that says the money is
 * being kept gets nothing.
 */
export function spendingTransferHint(toKind: string, note: string): string | null {
	if (toKind !== 'cash' || !SPEND_WORDS.test(note) || KEEP_WORDS.test(note)) return null;
	return 'This moved money into a cash account, and the note says it is for spending. Money for pocket money or expenses is spending, not a move: ask the person once whether it should be an expense instead (undo this entry with its journalId and log the expense), unless they meant to keep it in the cash account.';
}

/** A move between the person's own accounts. Never spending; its fee is. */
export async function recordTransfer(ctx: Ctx, raw: TransferRecordInput): Promise<TxnView> {
	const input = parse(transferRecordInput, raw);
	const occurredAt = instant(input.occurredAt, 'The date');
	return mapped(() =>
		runWrite(ctx, 'transfer.record', input, async (tx, userId) => {
			const from = await requireActiveAccount(
				tx,
				userId,
				input.fromAccountId,
				'account to move from'
			);
			const to = await requireActiveAccount(tx, userId, input.toAccountId, 'account to move to');
			const currency = input.currency ?? from.currency;
			const toCurrency = input.toCurrency ?? to.currency;
			// Moving inside one account is a conversion between two of its wallets, so the wallets must differ
			if (input.fromAccountId === input.toAccountId && currency === toCurrency)
				throw new OpsError('INVALID', 'Pick two different accounts, or two different currencies.');
			// Two currencies: the person says what really arrived (their own rate); one currency: there is nothing to say
			if (currency !== toCurrency && !input.toAmount)
				throw new OpsError(
					'INVALID',
					`Say how much ${toCurrency} arrived: the amount sent is in ${currency}.`
				);
			if (currency === toCurrency && input.toAmount && input.toAmount !== input.amount)
				throw new OpsError(
					'INVALID',
					'Both wallets are in one currency, so the same amount arrives.'
				);
			const row = await insertTxn(tx, userId, ctx.requestId, {
				type: 'transfer',
				accountId: input.fromAccountId,
				toAccountId: input.toAccountId,
				amount: input.amount,
				currency,
				toCurrency,
				toAmount: currency === toCurrency ? null : (input.toAmount ?? null),
				fee: input.fee ?? 0,
				note: input.note ?? '',
				occurredAt,
				source: 'manual'
			});
			const hint = spendingTransferHint(to.kind, input.note ?? '');
			return { ...plain(row), ...(hint ? { check: hint } : {}) };
		})
	);
}

// -- BALANCE COUNTS -- //

/**
 * Records what an account really holds. The difference from what the app expected is stored as a signed adjustment and is shown
 * as untracked spending only when it is negative. A big change, or one read from a picture, is confirmed first; a count ten times
 * more or less than expected needs a second yes (acknowledgeLarge).
 */
export async function recordSnapshot(ctx: Ctx, raw: SnapshotRecordInput): Promise<SnapshotResult> {
	// A balance count moves the base every balance is computed from, so it is the person's call
	requirePerson(ctx.actor.kind, 'record a balance count');
	const input = parse(snapshotRecordInput, raw);
	const reset = input.mode === 'reset';
	if (reset && !input.reason) throw new OpsError('INVALID', 'Say why you are resetting it.');
	// A reset is dated by the server clock, never by a time the caller chose
	const takenAt = reset ? new Date() : instant(input.takenAt, 'The date');
	const source = input.source ?? 'manual';
	const state = await run(ctx, async (tx, userId) => {
		const acc = await requireActiveAccount(tx, userId, input.accountId);
		// The count is of one wallet: the one named, else the account's own currency
		const currency = input.currency ?? acc.currency;
		const [last] = await tx
			.select({ takenAt: balanceSnapshot.takenAt })
			.from(balanceSnapshot)
			.where(
				and(
					eq(balanceSnapshot.userId, userId),
					eq(balanceSnapshot.accountId, acc.id),
					eq(balanceSnapshot.currency, currency)
				)
			)
			.orderBy(desc(balanceSnapshot.takenAt))
			.limit(1);
		return {
			acc,
			last,
			now: await balanceFor(tx, userId, acc.id, currency, takenAt),
			currency
		};
	});
	// A count dated in the future would block every later count, so it is refused (a few minutes of clock difference is allowed)
	if (takenAt.getTime() > Date.now() + 5 * 60_000)
		throw new OpsError('INVALID', 'A count cannot be dated in the future.');
	if (state.last && takenAt.getTime() <= state.last.takenAt.getTime())
		throw new OpsError('INVALID', 'That count is older than the last one for this account.');
	const expected = state.now.hasData ? state.now.balance : null;
	// The size that needs a yes follows the currency: about 2,000 pesos worth
	// A reset is the person's own explicit act, so the typo guard (ten times off) does not apply to it, but it is always confirmed
	const check = reset
		? 'ok'
		: checkBalanceChange(expected, input.amount, balanceConfirmThreshold(state.currency));
	const fromPicture = needsAmountConfirmation(source);
	if ((check !== 'ok' || fromPicture || reset) && !input.confirmed)
		return {
			status: 'needs_confirmation',
			chip: {
				accountId: state.acc.id,
				accountName: state.acc.name,
				amount: input.amount,
				currency: state.currency,
				date: toLocalDate(takenAt),
				note: '',
				expected,
				severity: check === 'confirm_large' ? 'large' : 'normal'
			}
		};
	if (check === 'confirm_large' && !input.acknowledgeLarge)
		return {
			status: 'needs_confirmation',
			chip: {
				accountId: state.acc.id,
				accountName: state.acc.name,
				amount: input.amount,
				currency: state.currency,
				date: toLocalDate(takenAt),
				note: '',
				expected,
				severity: 'large'
			}
		};
	return mapped(() =>
		runWrite(ctx, 'snapshot.record', input, async (tx, userId) => {
			// Lock the account and look again: a count or an expense that landed while this was being confirmed changes the base
			await tx
				.select({ id: account.id })
				.from(account)
				.where(and(eq(account.userId, userId), eq(account.id, input.accountId)))
				.for('update');
			const again = await balanceFor(tx, userId, input.accountId, state.currency, takenAt);
			if ((again.hasData ? again.balance : null) !== expected)
				throw new OpsError(
					'CONFLICT',
					'The balance changed while you were confirming. Look at it again.'
				);
			const [snap] = await tx
				.insert(balanceSnapshot)
				.values({
					userId,
					accountId: input.accountId,
					amount: input.amount,
					currency: state.currency,
					takenAt,
					expectedAmount: expected,
					source
				})
				.returning();
			if (!snap) throw new OpsError('CONFLICT', 'The count could not be saved.');
			await ensureWallet(tx, userId, input.accountId, state.currency);
			const drift = expected === null ? 0 : input.amount - expected;
			let adjustmentId: string | null = null;
			if (drift !== 0) {
				// Dated at the count itself, so the count is the base and the adjustment is only the record of the difference
				const adj = await tx
					.insert(ledgerTxn)
					.values({
						userId,
						type: 'adjustment',
						accountId: input.accountId,
						currency: state.currency,
						amount: drift,
						// A reset is not spending, so it never counts as untracked
						category: reset ? 'reset' : drift < 0 ? 'untracked' : null,
						note: reset
							? `Balance reset: ${input.reason}`
							: input.reason
								? `Balance count: ${input.reason}`
								: 'Balance count',
						occurredAt: takenAt,
						source: 'drift'
					})
					.returning({ id: ledgerTxn.id });
				adjustmentId = adj[0]?.id ?? null;
			}
			await recordUndo(tx, userId, ctx.requestId, {
				verb: 'snapshot.record',
				entity: 'balance_snapshot',
				entityId: snap.id,
				before: null,
				after: { snapshotId: snap.id, adjustmentTxnId: adjustmentId, amount: input.amount, drift }
			});
			return {
				status: 'saved' as const,
				snapshotId: snap.id,
				currency: state.currency,
				counted: input.amount,
				expected,
				drift,
				untracked: drift < 0 && !reset ? -drift : 0,
				mode: reset ? ('reset' as const) : ('count' as const)
			};
		})
	);
}

// -- READS -- //

/** One currency an account holds, with its balance now. */
export type WalletBalance = { currency: string; balance: number; countedAt: string | null };

/** The currencies an account holds, its own first and the rest in code order. Its own is listed even before anything was entered in it. */
export async function walletCurrencies(
	tx: Tx,
	userId: string,
	accountId: string,
	own: string
): Promise<string[]> {
	const rows = await tx
		.select({ currency: accountWallet.currency })
		.from(accountWallet)
		.where(and(eq(accountWallet.userId, userId), eq(accountWallet.accountId, accountId)));
	return [own, ...rows.map((r) => r.currency).filter((c) => c !== own)].sort((a, b) =>
		a === own ? -1 : b === own ? 1 : a < b ? -1 : 1
	);
}

/**
 * The wallets of some accounts and the balance of each, in one pass: one query for the wallets, one for the latest count of every wallet and
 * one for the entries after the oldest count, however many accounts there are. The same rule as balanceFor: the latest count at or before
 * `at` plus the signed entries after it. Keys are `accountId|currency`; `order` lists each account's currencies, its own first.
 */
export async function walletBalances(
	tx: Tx,
	userId: string,
	accounts: readonly { id: string; currency: string }[],
	at: Date = new Date()
) {
	const order = new Map<string, string[]>();
	const out = new Map<string, { balance: number; countedAt: Date | null; hasData: boolean }>();
	if (accounts.length === 0) return { order, balances: out };
	const walletRows = await tx
		.select({ accountId: accountWallet.accountId, currency: accountWallet.currency })
		.from(accountWallet)
		.where(eq(accountWallet.userId, userId));
	for (const a of accounts) {
		const rest = walletRows.filter((w) => w.accountId === a.id && w.currency !== a.currency);
		order.set(
			a.id,
			[a.currency, ...rest.map((w) => w.currency)].sort((x, y) =>
				x === a.currency ? -1 : y === a.currency ? 1 : x < y ? -1 : 1
			)
		);
	}
	// The latest count of every wallet (one row each)
	const snaps = await tx
		.selectDistinctOn([balanceSnapshot.accountId, balanceSnapshot.currency])
		.from(balanceSnapshot)
		.where(and(eq(balanceSnapshot.userId, userId), lte(balanceSnapshot.takenAt, at)))
		.orderBy(balanceSnapshot.accountId, balanceSnapshot.currency, desc(balanceSnapshot.takenAt));
	const snapOf = new Map(snaps.map((s) => [`${s.accountId}|${s.currency}`, s]));
	// Entries after the oldest count; when some wallet has no count, every entry up to `at` counts for it
	const wanted = accounts.flatMap((a) => (order.get(a.id) ?? []).map((c) => `${a.id}|${c}`));
	const allCounted = wanted.every((k) => snapOf.has(k));
	const oldest = allCounted
		? Math.min(...wanted.map((k) => (snapOf.get(k) as { takenAt: Date }).takenAt.getTime()))
		: null;
	const rows = await tx
		.select()
		.from(ledgerTxn)
		.where(
			and(
				eq(ledgerTxn.userId, userId),
				isNull(ledgerTxn.voidedAt),
				lte(ledgerTxn.occurredAt, at),
				oldest === null ? undefined : gt(ledgerTxn.occurredAt, new Date(oldest))
			)
		);
	const byAccount = new Map<string, Txn[]>();
	for (const r of rows) {
		const t = toTxn(r);
		for (const id of new Set([r.accountId, r.toAccountId])) {
			if (!id) continue;
			byAccount.set(id, [...(byAccount.get(id) ?? []), t]);
		}
	}
	for (const a of accounts)
		for (const currency of order.get(a.id) ?? []) {
			const snap = snapOf.get(`${a.id}|${currency}`);
			const mine = byAccount.get(a.id) ?? [];
			out.set(`${a.id}|${currency}`, {
				balance: balanceOf(
					a.id,
					currency,
					snap ? { amount: snap.amount, takenAt: snap.takenAt } : null,
					mine
				),
				countedAt: snap?.takenAt ?? null,
				hasData:
					Boolean(snap) || mine.some((r) => r.currency === currency || r.toCurrency === currency)
			});
		}
	return { order, balances: out };
}

/**
 * Every active account with its balance now. `balance` and `countedAt` are those of the wallet in the account's own currency (what an
 * older app reads); `wallets` lists every currency the account holds. The minimum balance is a money plan rule, so it is judged in the
 * main currency: an account with no wallet in it is not below its minimum (there is nothing to judge), never "empty".
 */
export async function accountBalances(ctx: Ctx) {
	return run(ctx, (tx, userId) => balancesIn(tx, userId));
}

/** The balances of every active account inside a transaction. ops/net.ts adds the net to the same rows in the same transaction. */
export async function balancesIn(tx: Tx, userId: string) {
	const main = (await readSettings(tx, userId)).currency;
	const accounts = await tx
		.select()
		.from(account)
		.where(and(eq(account.userId, userId), isNull(account.archivedAt)))
		.orderBy(account.sortOrder, account.name);
	const out = [];
	const { order, balances } = await walletBalances(tx, userId, accounts);
	for (const a of accounts) {
		const wallets: WalletBalance[] = [];
		for (const currency of order.get(a.id) ?? [a.currency]) {
			const b = balances.get(`${a.id}|${currency}`);
			wallets.push({
				currency,
				balance: b?.balance ?? 0,
				countedAt: b?.countedAt?.toISOString() ?? null
			});
		}
		const own = wallets[0] as WalletBalance;
		const inMain = wallets.find((w) => w.currency === main);
		out.push({
			id: a.id,
			name: a.name,
			kind: a.kind,
			minBalance: a.minBalance,
			purpose: a.purpose,
			icon: a.icon,
			imageId: a.imageId,
			currency: a.currency,
			balance: own.balance,
			countedAt: own.countedAt,
			belowMinimum: inMain ? inMain.balance < a.minBalance : false,
			wallets
		});
	}
	return out;
}

/** Recent entries, newest first. `from` and `to` are Manila dates, inclusive. */
export async function listTransactions(
	ctx: Ctx,
	opts: { from?: string; to?: string; accountId?: string; limit?: number } = {}
) {
	const limit = Math.min(Math.max(opts.limit ?? 50, 1), 200);
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					opts.from ? gte(ledgerTxn.occurredAt, dayStart(opts.from)) : undefined,
					opts.to ? lt(ledgerTxn.occurredAt, dayStart(addDays(opts.to, 1))) : undefined,
					opts.accountId
						? or(eq(ledgerTxn.accountId, opts.accountId), eq(ledgerTxn.toAccountId, opts.accountId))
						: undefined
				)
			)
			.orderBy(desc(ledgerTxn.occurredAt))
			.limit(limit)
	);
	return plain(rows);
}

/** What was spent between two Manila dates, by category, with the untracked part apart. */
export async function spendingSummary(ctx: Ctx, raw: { from: string; to: string }) {
	const { from, to } = parse(rangeInput, raw);
	const { all, currency } = await run(ctx, async (tx, userId) => ({
		all: await tx
			.select()
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					isNull(ledgerTxn.voidedAt),
					gte(ledgerTxn.occurredAt, dayStart(from)),
					lt(ledgerTxn.occurredAt, dayStart(addDays(to, 1)))
				)
			),
		currency: (await readSettings(tx, userId)).currency
	}));
	// Amounts of different currencies are never added: this is the main currency, and the others are named so nothing is hidden
	const rows = all.filter((r) => r.currency === currency);
	const otherCurrencies = [
		...new Set(
			all.filter((r) => r.currency !== currency && r.type !== 'transfer').map((r) => r.currency)
		)
	].sort();
	// The same pieces as `spending` (expenses, transfer fees, less refunds), so the categories add up to it. Categories that differ only in case
	// or spaces are one group (as in the simulation), shown under the spelling met first; a fee is "fees"; a refund comes off its category.
	const byCategory: Record<string, number> = {};
	const labelOf = new Map<string, string>();
	const addTo = (category: string | null, amount: number) => {
		const name = (category ?? '').trim() || 'other';
		const key = name.toLowerCase();
		const label = labelOf.get(key) ?? name;
		labelOf.set(key, label);
		byCategory[label] = (byCategory[label] ?? 0) + amount;
	};
	for (const r of rows) {
		if (r.type === 'expense') addTo(r.category, r.amount);
		else if (r.type === 'refund') addTo(r.category, -r.amount);
		else if (r.type === 'transfer' && r.fee > 0) addTo('fees', r.fee);
	}
	return {
		from,
		to,
		currency,
		otherCurrencies,
		spending: spendingOf(rows.map(toTxn), currency),
		untracked: untrackedSpendingOf(
			rows.filter((r) => r.type === 'adjustment' && r.category !== 'reset').map((r) => r.amount)
		),
		byCategory
	};
}

/** The weekly check-in: which accounts are due for a count, and how much went untracked in the last week. */
export async function weeklyCheckin(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const now = new Date();
		const since = new Date(now.getTime() - CHECKIN_DAYS * 86_400_000);
		const accounts = await tx
			.select()
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)))
			.orderBy(account.sortOrder, account.name);
		const main = (await readSettings(tx, userId)).currency;
		const list = [];
		// One line for every wallet: each currency is counted on its own
		const { order, balances } = await walletBalances(tx, userId, accounts, now);
		for (const a of accounts) {
			for (const currency of order.get(a.id) ?? [a.currency]) {
				const b = balances.get(`${a.id}|${currency}`) ?? {
					balance: 0,
					countedAt: null,
					hasData: false
				};
				const days = b.countedAt
					? Math.floor((now.getTime() - b.countedAt.getTime()) / 86_400_000)
					: null;
				list.push({
					accountId: a.id,
					name: a.name,
					currency,
					expected: b.balance,
					lastCountedAt: b.countedAt?.toISOString() ?? null,
					daysSinceCount: days,
					due: days === null || days >= CHECKIN_DAYS
				});
			}
		}
		const drifts = await tx
			.select({
				amount: ledgerTxn.amount,
				category: ledgerTxn.category,
				currency: ledgerTxn.currency
			})
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					eq(ledgerTxn.type, 'adjustment'),
					isNull(ledgerTxn.voidedAt),
					gte(ledgerTxn.occurredAt, since)
				)
			);
		const counted = drifts.filter((d) => d.category !== 'reset');
		// Untracked money of a wallet in another currency is named, never dropped and never added to the main currency's figure
		const other = new Map<string, number>();
		for (const d of counted)
			if (d.currency !== main && d.amount < 0)
				other.set(d.currency, (other.get(d.currency) ?? 0) - d.amount);
		return {
			accounts: list,
			untrackedLast7Days: untrackedSpendingOf(
				counted.filter((d) => d.currency === main).map((d) => d.amount)
			),
			/** The currency of untrackedLast7Days: the main currency. */
			untrackedCurrency: main,
			/** Untracked money of wallets in other currencies, each in its own currency (never added to the figure above). */
			untrackedOtherCurrencies: [...other.entries()]
				.sort(([a], [b]) => (a < b ? -1 : 1))
				.map(([currency, amount]) => ({ currency, amount }))
		};
	});
}

// -- UNDO -- //

/** What can be undone now, newest first. */
export async function listUndoable(ctx: Ctx, limit = 10) {
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select({
				id: undoJournal.id,
				verb: undoJournal.verb,
				entity: undoJournal.entity,
				after: undoJournal.after,
				createdAt: undoJournal.createdAt
			})
			.from(undoJournal)
			.where(
				and(
					eq(undoJournal.userId, userId),
					isNull(undoJournal.undoneAt),
					isNull(undoJournal.before)
				)
			)
			.orderBy(desc(undoJournal.createdAt))
			.limit(Math.min(Math.max(limit, 1), 50))
	);
	return plain(rows);
}

/** Undoes a created entry: an expense, income, transfer, a bill marked paid, or a balance count. The row stays, marked void. */
export async function undo(ctx: Ctx, raw: { journalId: string }) {
	const { journalId } = parse(undoInput, raw);
	return mapped(() =>
		runWrite(ctx, 'undo', { journalId }, async (tx, userId) => {
			// The audit rows of an undo point back at the journal entry they undo
			await setAuditContext(tx, { undoOf: journalId });
			const [entry] = await tx
				.select()
				.from(undoJournal)
				.where(and(eq(undoJournal.userId, userId), eq(undoJournal.id, journalId)));
			if (!entry) throw new OpsError('NOT_FOUND', 'There is nothing to undo with that id.');
			if (entry.undoneAt) throw new OpsError('CONFLICT', 'That was already undone.');
			if (entry.before !== null)
				throw new OpsError('INVALID', 'That change cannot be undone automatically.');
			// A balance count is the person's own: undoing one removes the count, so the assistant only asks (a card)
			if (entry.entity === 'balance_snapshot')
				requirePerson(ctx.actor.kind, 'undo a balance count');
			const after = (entry.after ?? {}) as Record<string, unknown>;
			const voidTxn = async (txnId: string) => {
				const [t] = await tx
					.update(ledgerTxn)
					.set({ voidedAt: sql`now()`, updatedAt: sql`now()` })
					.where(
						and(eq(ledgerTxn.userId, userId), eq(ledgerTxn.id, txnId), isNull(ledgerTxn.voidedAt))
					)
					.returning({ id: ledgerTxn.id, splitId: ledgerTxn.splitId });
				// A transfer marked sent on a split is unmarked, so it can be sent again
				if (t?.splitId) {
					const [plan] = await tx
						.select({ sent: splitPlan.sentTransfers })
						.from(splitPlan)
						.where(and(eq(splitPlan.userId, userId), eq(splitPlan.id, t.splitId)));
					const sent = Array.isArray(plan?.sent) ? (plan.sent as { txnId?: string }[]) : [];
					await tx
						.update(splitPlan)
						.set({ sentTransfers: sent.filter((s) => s.txnId !== txnId), updatedAt: sql`now()` })
						.where(and(eq(splitPlan.userId, userId), eq(splitPlan.id, t.splitId)));
				}
			};
			switch (entry.entity) {
				case 'ledger_txn':
					await tx
						.delete(billPayment)
						.where(and(eq(billPayment.userId, userId), eq(billPayment.txnId, entry.entityId)));
					await voidTxn(entry.entityId);
					break;
				case 'bill_payment':
					await tx
						.delete(billPayment)
						.where(and(eq(billPayment.userId, userId), eq(billPayment.id, entry.entityId)));
					if (typeof after.txnId === 'string') await voidTxn(after.txnId);
					break;
				case 'bill_override': {
					// A date that was moved and then paid keeps its change: removing it would show the date unpaid on its old day
					const [row] = await tx
						.select()
						.from(billOverride)
						.where(and(eq(billOverride.userId, userId), eq(billOverride.id, entry.entityId)));
					if (row?.newDueDate) {
						const paid = await tx
							.select({ id: billPayment.id })
							.from(billPayment)
							.where(
								and(
									eq(billPayment.userId, userId),
									eq(billPayment.billId, row.billId),
									sql`coalesce(${billPayment.windowStart}, ${billPayment.dueDate}) <= ${row.newDueDate}`,
									sql`coalesce(${billPayment.windowEnd}, ${billPayment.dueDate}) >= ${row.newDueDate}`
								)
							)
							.limit(1);
						if (paid.length > 0)
							throw new OpsError('CONFLICT', 'That date is already paid, so the change stays.');
					}
					await tx
						.delete(billOverride)
						.where(and(eq(billOverride.userId, userId), eq(billOverride.id, entry.entityId)));
					break;
				}
				case 'balance_snapshot':
					await tx
						.delete(balanceSnapshot)
						.where(and(eq(balanceSnapshot.userId, userId), eq(balanceSnapshot.id, entry.entityId)));
					if (typeof after.adjustmentTxnId === 'string') await voidTxn(after.adjustmentTxnId);
					break;
				default:
					throw new OpsError('INVALID', 'That change cannot be undone automatically.');
			}
			await tx
				.update(undoJournal)
				.set({ undoneAt: sql`now()` })
				.where(and(eq(undoJournal.userId, userId), eq(undoJournal.id, entry.id)));
			return { undone: true, entity: entry.entity };
		})
	);
}
