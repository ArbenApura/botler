// BILL VERBS: DUE DATES, MARKING A BILL PAID, AND LEARNING THE USUAL AMOUNT OF A VARIABLE BILL
// Reminders about a due bill are delivered by the reminder engine (P5). These verbs only know when a bill is due and whether it is paid.
// Marking a bill paid writes an expense in the ledger; it does not call the model, so it works when the model is down.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Estimate } from '../../finance/estimator';
import type { Schedule } from '../../finance/schedule';
import type { Ctx } from './context';
import type { BillCreateInput, BillMarkPaidInput, BillUpdateInput } from '../db/zod';
import type { Plain } from './shared';
// -- DEP-MODULES -- //
import { and, desc, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { estimateBill } from '../../finance/estimator';
import { occurrencesBetween } from '../../finance/schedule';
import { bill, billPayment } from '../db/schema';
import { billCreateInput, billMarkPaidInput, billUpdateInput } from '../db/zod';
import { OpsError, recordUndo, run, runWrite } from './context';
import { insertTxn } from './ledger';
import {
	checkVersion,
	mapped,
	parse,
	plain,
	requireActiveAccount,
	requireBill,
	requirePerson
} from './shared';

// -- TYPES -- //

export type BillView = Plain<typeof bill.$inferSelect>;

/** One occurrence of a bill inside a window. */
export type DueBill = {
	billId: string;
	name: string;
	category: string;
	accountId: string;
	dueDate: string;
	/** Centavos, or null when a variable bill has no estimate yet (the person must be asked). */
	amount: number | null;
	unknownAmount: boolean;
	paid: boolean;
	deferrable: boolean;
};

// -- FUNCTIONS -- //

/** What a bill is expected to cost: its amount when fixed, the learned usual amount when variable. */
export async function estimateOf(
	tx: Tx,
	userId: string,
	b: typeof bill.$inferSelect
): Promise<Estimate> {
	if (b.kind === 'fixed')
		return { amount: b.amount, unknown: b.amount === null, basis: 'user', used: 0, dropped: 0 };
	const history = await tx
		.select({ amount: billPayment.amount })
		.from(billPayment)
		.where(and(eq(billPayment.userId, userId), eq(billPayment.billId, b.id)))
		.orderBy(desc(billPayment.paidAt))
		.limit(6);
	return estimateBill(
		history.map((h) => h.amount),
		b.amount
	);
}

export async function createBill(ctx: Ctx, raw: BillCreateInput): Promise<BillView> {
	requirePerson(ctx.actor.kind, 'add a bill');
	const input = parse(billCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'bill.create', input, async (tx, userId) => {
			await requireActiveAccount(tx, userId, input.accountId, 'account the bill is paid from');
			const [row] = await tx
				.insert(bill)
				.values({ ...input, userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The bill could not be saved.');
			return plain(row);
		})
	);
}

export async function updateBill(ctx: Ctx, raw: BillUpdateInput): Promise<BillView> {
	requirePerson(ctx.actor.kind, 'change a bill');
	const { billId, expectVersion, ...changes } = parse(billUpdateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'bill.update', { billId, expectVersion, ...changes }, async (tx, userId) => {
			const current = await requireBill(tx, userId, billId);
			checkVersion(current.version, expectVersion, 'bill');
			if (changes.accountId) await requireActiveAccount(tx, userId, changes.accountId);
			const [row] = await tx
				.update(bill)
				.set({ ...changes, version: sql`${bill.version} + 1`, updatedAt: sql`now()` })
				.where(and(eq(bill.userId, userId), eq(bill.id, billId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That bill does not exist.');
			return plain(row);
		})
	);
}

/** Every bill with what it is expected to cost. */
export async function listBills(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const rows = await tx.select().from(bill).where(eq(bill.userId, userId)).orderBy(bill.name);
		const out = [];
		for (const b of rows) out.push({ ...plain(b), estimate: await estimateOf(tx, userId, b) });
		return out;
	});
}

/** The occurrences of the active bills between two Manila dates, inclusive, paid or not, in date order. Used by the split too. */
export async function dueBills(
	tx: Tx,
	userId: string,
	from: string,
	to: string
): Promise<DueBill[]> {
	const bills = await tx
		.select()
		.from(bill)
		.where(and(eq(bill.userId, userId), eq(bill.active, true)));
	const payments = await tx
		.select({ billId: billPayment.billId, dueDate: billPayment.dueDate })
		.from(billPayment)
		.where(eq(billPayment.userId, userId));
	const paid = new Set(payments.map((p) => `${p.billId}|${p.dueDate}`));
	const out: DueBill[] = [];
	for (const b of bills) {
		const dates = occurrencesBetween(b.schedule as Schedule, from, to, { weekend: b.weekendRule });
		if (dates.length === 0) continue;
		const est = await estimateOf(tx, userId, b);
		for (const dueDate of dates)
			out.push({
				billId: b.id,
				name: b.name,
				category: b.category,
				accountId: b.accountId,
				dueDate,
				amount: est.amount,
				unknownAmount: est.amount === null,
				paid: paid.has(`${b.id}|${dueDate}`),
				deferrable: b.deferrable
			});
	}
	return out.sort((a, b) =>
		a.dueDate < b.dueDate ? -1 : a.dueDate > b.dueDate ? 1 : a.name < b.name ? -1 : 1
	);
}

export async function listDueBills(ctx: Ctx, from: string, to: string): Promise<DueBill[]> {
	return run(ctx, (tx, userId) => dueBills(tx, userId, from, to));
}

/**
 * Marks one due date of a bill paid and writes the expense. The amount is what was really paid; without one, the bill's own
 * amount or learned estimate. When a variable bill came in under its estimate, `savingsHint` is the difference: a suggestion
 * to set it aside, never moved on its own and never counted as spending.
 */
export async function markBillPaid(ctx: Ctx, raw: BillMarkPaidInput) {
	const input = parse(billMarkPaidInput, raw);
	return mapped(() =>
		runWrite(ctx, 'bill.markPaid', input, async (tx, userId) => {
			const b = await requireBill(tx, userId, input.billId);
			if (!b.active) throw new OpsError('INVALID', `"${b.name}" is switched off.`);
			// A payment on a variable bill moves the learned usual amount, which the split reads: that is the person's call
			if (b.kind === 'variable')
				requirePerson(ctx.actor.kind, 'record a payment on a bill whose amount varies');
			const due = occurrencesBetween(b.schedule as Schedule, input.dueDate, input.dueDate, {
				weekend: b.weekendRule
			});
			if (due.length === 0)
				throw new OpsError('INVALID', `"${b.name}" is not due on ${input.dueDate}.`);
			const est = await estimateOf(tx, userId, b);
			const amount = input.amount ?? est.amount;
			if (!amount) throw new OpsError('INVALID', `Say how much "${b.name}" was this time.`);
			const accountId = input.accountId ?? b.accountId;
			await requireActiveAccount(tx, userId, accountId);
			const txn = await insertTxn(
				tx,
				userId,
				ctx.requestId,
				{
					type: 'expense',
					accountId,
					amount,
					note: b.name,
					category: b.category,
					source: 'bill',
					billId: b.id
				},
				{ journal: false }
			);
			const [payment] = await tx
				.insert(billPayment)
				.values({ userId, billId: b.id, dueDate: input.dueDate, amount, txnId: txn.id })
				.returning();
			if (!payment) throw new OpsError('CONFLICT', 'The payment could not be saved.');
			await recordUndo(tx, userId, ctx.requestId, {
				verb: 'bill.markPaid',
				entity: 'bill_payment',
				entityId: payment.id,
				before: null,
				after: {
					paymentId: payment.id,
					txnId: txn.id,
					billId: b.id,
					dueDate: input.dueDate,
					amount
				}
			});
			const hint =
				b.kind === 'variable' && est.amount !== null && amount < est.amount
					? est.amount - amount
					: null;
			return { paymentId: payment.id, txnId: txn.id, amount, savingsHint: hint };
		})
	);
}
