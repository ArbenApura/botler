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
import { addDays, toManilaDate, manilaStart } from '../../finance/dates';
import { checkBalanceChange, needsAmountConfirmation } from '../../finance/confirm';
import { balanceOf, spendingOf, untrackedSpendingOf } from '../../finance/ledger';
import { parseExpenseText } from '../../finance/text';
import { balanceConfirmThreshold } from '../../finance/currency';
import { setAuditContext } from '../db/tenant';
import { readSettings } from './settings';
import {
	account,
	balanceSnapshot,
	billOverride,
	billPayment,
	ledgerTxn,
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

export type TxnView = Plain<typeof ledgerTxn.$inferSelect>;

/** What the person is asked to confirm before an amount is saved. */
export type Chip = {
	accountId: string;
	accountName: string;
	amount: number;
	date: string;
	note: string;
	/** For a balance count: what the app expected, and how unusual the change is. */
	expected?: number | null;
	severity?: 'normal' | 'large';
};

export type ExpenseResult =
	| { status: 'saved'; txn: TxnView }
	| { status: 'needs_confirmation'; chip: Chip }
	| { status: 'needs_account'; amount: number; note: string; accounts: string[] }
	| { status: 'needs_amount'; note: string };

export type SnapshotResult =
	| {
			status: 'saved';
			snapshotId: string;
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

/** The balance of an account at an instant, from its latest count and what happened after. Reads only, inside a transaction. */
export async function balanceFor(tx: Tx, userId: string, accountId: string, at: Date = new Date()) {
	const [snap] = await tx
		.select()
		.from(balanceSnapshot)
		.where(
			and(
				eq(balanceSnapshot.userId, userId),
				eq(balanceSnapshot.accountId, accountId),
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
			snap ? { amount: snap.amount, takenAt: snap.takenAt } : null,
			rows.map(toTxn)
		),
		countedAt: snap?.takenAt ?? null,
		hasData: Boolean(snap) || rows.length > 0
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
	if (options.journal !== false)
		await recordUndo(tx, userId, requestId, {
			verb: `ledger.${row.type}`,
			entity: 'ledger_txn',
			entityId: row.id,
			before: null,
			after: row
		});
	return row;
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
				date: toManilaDate(occurredAt),
				note: input.note ?? ''
			}
		};
	}
	return mapped(() =>
		runWrite(ctx, 'expense.log', input, async (tx, userId) => {
			await requireActiveAccount(tx, userId, input.accountId);
			const row = await insertTxn(tx, userId, ctx.requestId, {
				type: 'expense',
				accountId: input.accountId,
				amount: input.amount,
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
	const { accounts, currency } = await run(ctx, async (tx, userId) => ({
		accounts: await tx
			.select({ id: account.id, name: account.name })
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)))
			.orderBy(account.sortOrder, account.name),
		// "lunch 5" is five of the person's own currency
		currency: (await readSettings(tx, userId)).currency
	}));
	const parsed = parseExpenseText(
		input.text,
		accounts.map((a) => a.name),
		currency
	);
	if (parsed.amount === null || parsed.amount < 1)
		return { status: 'needs_amount', note: parsed.note };
	const named = parsed.accountName
		? accounts.find((a) => a.name.toLowerCase() === parsed.accountName?.toLowerCase())
		: undefined;
	const accountId =
		named?.id ?? input.accountId ?? (accounts.length === 1 ? accounts[0]?.id : undefined);
	if (!accountId)
		return {
			status: 'needs_account',
			amount: parsed.amount,
			note: parsed.note,
			accounts: accounts.map((a) => a.name)
		};
	// Two numbers in one message: the person checks which one was meant before anything is saved
	if (parsed.ambiguous && !input.confirmed) {
		const acc = accounts.find((a) => a.id === accountId);
		return {
			status: 'needs_confirmation',
			chip: {
				accountId,
				accountName: acc?.name ?? '',
				amount: parsed.amount,
				date: toManilaDate(new Date()),
				note: parsed.note
			}
		};
	}
	return logExpense(ctx, {
		accountId,
		amount: parsed.amount,
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
			await requireActiveAccount(tx, userId, input.accountId);
			const row = await insertTxn(tx, userId, ctx.requestId, {
				type,
				accountId: input.accountId,
				amount: input.amount,
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

/** A move between the person's own accounts. Never spending; its fee is. */
export async function recordTransfer(ctx: Ctx, raw: TransferRecordInput): Promise<TxnView> {
	const input = parse(transferRecordInput, raw);
	if (input.fromAccountId === input.toAccountId)
		throw new OpsError('INVALID', 'Pick two different accounts.');
	const occurredAt = instant(input.occurredAt, 'The date');
	return mapped(() =>
		runWrite(ctx, 'transfer.record', input, async (tx, userId) => {
			await requireActiveAccount(tx, userId, input.fromAccountId, 'account to move from');
			await requireActiveAccount(tx, userId, input.toAccountId, 'account to move to');
			const row = await insertTxn(tx, userId, ctx.requestId, {
				type: 'transfer',
				accountId: input.fromAccountId,
				toAccountId: input.toAccountId,
				amount: input.amount,
				fee: input.fee ?? 0,
				note: input.note ?? '',
				occurredAt,
				source: 'manual'
			});
			return plain(row);
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
		const [last] = await tx
			.select({ takenAt: balanceSnapshot.takenAt })
			.from(balanceSnapshot)
			.where(and(eq(balanceSnapshot.userId, userId), eq(balanceSnapshot.accountId, acc.id)))
			.orderBy(desc(balanceSnapshot.takenAt))
			.limit(1);
		return {
			acc,
			last,
			now: await balanceFor(tx, userId, acc.id, takenAt),
			currency: (await readSettings(tx, userId)).currency
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
				date: toManilaDate(takenAt),
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
				date: toManilaDate(takenAt),
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
			const again = await balanceFor(tx, userId, input.accountId, takenAt);
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
					takenAt,
					expectedAmount: expected,
					source
				})
				.returning();
			if (!snap) throw new OpsError('CONFLICT', 'The count could not be saved.');
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

/** Every active account with its balance now. */
export async function accountBalances(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const accounts = await tx
			.select()
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)))
			.orderBy(account.sortOrder, account.name);
		const out = [];
		for (const a of accounts) {
			const b = await balanceFor(tx, userId, a.id);
			out.push({
				id: a.id,
				name: a.name,
				kind: a.kind,
				minBalance: a.minBalance,
				purpose: a.purpose,
				balance: b.balance,
				countedAt: b.countedAt?.toISOString() ?? null,
				belowMinimum: b.balance < a.minBalance
			});
		}
		return out;
	});
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
					opts.from ? gte(ledgerTxn.occurredAt, manilaStart(opts.from)) : undefined,
					opts.to ? lt(ledgerTxn.occurredAt, manilaStart(addDays(opts.to, 1))) : undefined,
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
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					isNull(ledgerTxn.voidedAt),
					gte(ledgerTxn.occurredAt, manilaStart(from)),
					lt(ledgerTxn.occurredAt, manilaStart(addDays(to, 1)))
				)
			)
	);
	const byCategory: Record<string, number> = {};
	for (const r of rows)
		if (r.type === 'expense') {
			const k = r.category ?? 'other';
			byCategory[k] = (byCategory[k] ?? 0) + r.amount;
		}
	return {
		from,
		to,
		spending: spendingOf(rows.map(toTxn)),
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
		const list = [];
		for (const a of accounts) {
			const b = await balanceFor(tx, userId, a.id, now);
			const days = b.countedAt
				? Math.floor((now.getTime() - b.countedAt.getTime()) / 86_400_000)
				: null;
			list.push({
				accountId: a.id,
				name: a.name,
				expected: b.balance,
				lastCountedAt: b.countedAt?.toISOString() ?? null,
				daysSinceCount: days,
				due: days === null || days >= CHECKIN_DAYS
			});
		}
		const drifts = await tx
			.select({ amount: ledgerTxn.amount, category: ledgerTxn.category })
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					eq(ledgerTxn.type, 'adjustment'),
					isNull(ledgerTxn.voidedAt),
					gte(ledgerTxn.occurredAt, since)
				)
			);
		return {
			accounts: list,
			untrackedLast7Days: untrackedSpendingOf(
				drifts.filter((d) => d.category !== 'reset').map((d) => d.amount)
			)
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
