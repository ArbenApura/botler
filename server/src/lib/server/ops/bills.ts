// BILL VERBS: DUE DATES, MARKING A BILL PAID, AND LEARNING THE USUAL AMOUNT OF A VARIABLE BILL
// Reminders about a due bill are delivered by the reminder engine (P5). These verbs only know when a bill is due and whether it is paid.
// Marking a bill paid writes an expense in the ledger; it does not call the model, so it works when the model is down.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Estimate } from '../../finance/estimator';
import type { Schedule } from '../../finance/schedule';
import type { Ctx } from './context';
import type { Occurrence } from '../../finance/occurrence';
import type {
	BillCreateInput,
	BillMarkPaidInput,
	BillOccurrenceResetInput,
	BillOccurrenceUpdateInput,
	BillUpdateInput
} from '../db/zod';
import type { Plain } from './shared';
// -- DEP-MODULES -- //
import { and, desc, eq, gte, inArray, isNotNull, lte, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, diffDays, toManilaDate } from '../../finance/dates';
import { estimateBill } from '../../finance/estimator';
import {
	effectiveOccurrences,
	MOVE_LIMIT_DAYS,
	occurrenceOn,
	OVERRIDE_REACH_DAYS
} from '../../finance/occurrence';
import { bill, billOverride, billPayment } from '../db/schema';
import {
	billCreateInput,
	billMarkPaidInput,
	billOccurrenceResetInput,
	billOccurrenceUpdateInput,
	billUpdateInput
} from '../db/zod';
import { OpsError, recordUndo, run, runWrite } from './context';
import { insertTxn } from './ledger';
import {
	checkVersion,
	mapped,
	parse,
	plain,
	requireAccount,
	requireActiveAccount,
	requireBill,
	requirePerson
} from './shared';

// -- TYPES -- //

export type BillView = Plain<typeof bill.$inferSelect>;

export type BillOverrideView = Plain<typeof billOverride.$inferSelect>;

type OverrideRow = typeof billOverride.$inferSelect;

/** One occurrence of a bill inside a window. */
export type DueBill = {
	billId: string;
	name: string;
	category: string;
	accountId: string;
	/** The due date: the last day of the window. After a move this is the new date. */
	dueDate: string;
	/** The date the bill's schedule gives this occurrence. It is the same as dueDate unless the date was moved. */
	originalDueDate: string;
	/** True when this date has its own change (moved, another amount or account). */
	overridden: boolean;
	/** The first day the bill may be paid. Equal to dueDate for a single day. */
	windowStart: string;
	/** The last day, same as dueDate. */
	windowEnd: string;
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
			// A new bill counts from today, so the dates its schedule gives before today are not overdue
			const [row] = await tx
				.insert(bill)
				.values({ ...input, startsOn: input.startsOn ?? toManilaDate(new Date()), userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The bill could not be saved.');
			return plain(row);
		})
	);
}

/**
 * After the whole series of a bill is edited, the changes to single dates from today on that the edit overrides are dropped: a new
 * schedule or weekend rule makes every date key stale, a new amount or account replaces the per-date ones. Skipped dates stay unless the
 * dates themselves changed. Returns how many overrides were removed or trimmed, so the answer can say so.
 */
async function clearFutureOverrides(
	tx: Tx,
	userId: string,
	billId: string,
	changes: Omit<BillUpdateInput, 'billId' | 'expectVersion'>
): Promise<number> {
	const today = toManilaDate(new Date());
	const mine = and(
		eq(billOverride.userId, userId),
		eq(billOverride.billId, billId),
		gte(billOverride.originalDueDate, today)
	);
	// A date that was moved and then paid keeps its change: dropping it would show the date unpaid on its old day
	const notPaidMove = sql`not (${billOverride.newDueDate} is not null and exists (
		select 1 from bill_payment p
		where p.user_id = ${billOverride.userId} and p.bill_id = ${billOverride.billId}
			and coalesce(p.window_start, p.due_date) <= ${billOverride.newDueDate}
			and coalesce(p.window_end, p.due_date) >= ${billOverride.newDueDate}))`;
	if (changes.schedule !== undefined || changes.weekendRule !== undefined) {
		const gone = await tx
			.delete(billOverride)
			.where(and(mine, notPaidMove))
			.returning({ id: billOverride.id });
		return gone.length;
	}
	let touched = 0;
	// A field that is the only thing a row changes takes the whole row with it, which a row must never be left empty of
	for (const [field, column] of [
		['amount', billOverride.amount],
		['accountId', billOverride.accountId]
	] as const) {
		// A bill that turns fixed or variable also gives its dates a new base amount
		if (changes[field] === undefined && !(field === 'amount' && changes.kind !== undefined))
			continue;
		const others = ({ amount: billOverride.accountId, accountId: billOverride.amount } as const)[
			field
		];
		const gone = await tx
			.delete(billOverride)
			.where(
				and(
					mine,
					isNotNull(column),
					sql`not ${billOverride.skipped} and ${billOverride.newDueDate} is null and ${others} is null`
				)
			)
			.returning({ id: billOverride.id });
		const kept = await tx
			.update(billOverride)
			.set({ [field]: null, updatedAt: sql`now()` })
			.where(and(mine, isNotNull(column)))
			.returning({ id: billOverride.id });
		touched += gone.length + kept.length;
	}
	return touched;
}

export async function updateBill(
	ctx: Ctx,
	raw: BillUpdateInput
): Promise<BillView & { clearedOverrides: number }> {
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
			// An edit of the whole series wins over the changes made to single dates from today on
			const clearedOverrides = await clearFutureOverrides(tx, userId, billId, changes);
			return { ...plain(row), clearedOverrides };
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

/** How far a payment can sit from the range it settles: a window is at most a month long. */
const WINDOW_PAD_DAYS = 40;

/** The single-date changes of some bills whose schedule date lies between two dates, by bill. */
async function overridesOf(
	tx: Tx,
	userId: string,
	billIds: string[],
	from: string,
	to: string
): Promise<Map<string, OverrideRow[]>> {
	const out = new Map<string, OverrideRow[]>();
	if (billIds.length === 0) return out;
	const rows = await tx
		.select()
		.from(billOverride)
		.where(
			and(
				eq(billOverride.userId, userId),
				inArray(billOverride.billId, billIds),
				gte(billOverride.originalDueDate, from),
				lte(billOverride.originalDueDate, to)
			)
		);
	for (const r of rows) out.set(r.billId, [...(out.get(r.billId) ?? []), r]);
	return out;
}

/** The change a day points at: the date moved onto it, else the date whose schedule day it is. A day two dates could claim goes to the one due on it now. */
function overrideOn(rows: readonly OverrideRow[], day: string): OverrideRow | undefined {
	return (
		rows.find((o) => !o.skipped && o.newDueDate === day) ??
		rows.find((o) => o.originalDueDate === day)
	);
}

/** The dates of one bill around a day, with its changes applied (a skipped date is left out unless asked for). */
async function occurrencesAround(
	tx: Tx,
	userId: string,
	b: typeof bill.$inferSelect,
	date: string,
	opts: { keepSkipped?: boolean } = {}
): Promise<{ list: Occurrence<OverrideRow>[]; overrides: OverrideRow[] }> {
	const overrides =
		(
			await overridesOf(
				tx,
				userId,
				[b.id],
				addDays(date, -WINDOW_PAD_DAYS - OVERRIDE_REACH_DAYS),
				addDays(date, WINDOW_PAD_DAYS + OVERRIDE_REACH_DAYS)
			)
		).get(b.id) ?? [];
	const list = effectiveOccurrences(
		b.schedule as Schedule,
		addDays(date, -WINDOW_PAD_DAYS),
		addDays(date, WINDOW_PAD_DAYS),
		{ weekend: b.weekendRule },
		opts.keepSkipped ? overrides.map((o) => ({ ...o, skipped: false })) : overrides,
		b.startsOn
	);
	return { list, overrides };
}

/** Whether a payment settled any day of a stretch of one bill. */
async function paidWithin(
	tx: Tx,
	userId: string,
	billId: string,
	start: string,
	end: string
): Promise<boolean> {
	const hit = await tx
		.select({ id: billPayment.id })
		.from(billPayment)
		.where(
			and(
				eq(billPayment.userId, userId),
				eq(billPayment.billId, billId),
				// Overlap of what the payment settled (its window, or its due date) with the stretch
				lte(sql`coalesce(${billPayment.windowStart}, ${billPayment.dueDate})`, end),
				gte(sql`coalesce(${billPayment.windowEnd}, ${billPayment.dueDate})`, start)
			)
		)
		.limit(1);
	return hit.length > 0;
}

/** What several bills are expected to cost. One read for all the variable bills, not one per bill. */
async function estimatesOf(
	tx: Tx,
	userId: string,
	bills: (typeof bill.$inferSelect)[]
): Promise<Map<string, Estimate>> {
	const out = new Map<string, Estimate>();
	const variable = bills.filter((b) => b.kind !== 'fixed');
	const history = new Map<string, number[]>();
	if (variable.length > 0) {
		const rows = await tx
			.select({ billId: billPayment.billId, amount: billPayment.amount })
			.from(billPayment)
			.where(
				and(
					eq(billPayment.userId, userId),
					inArray(
						billPayment.billId,
						variable.map((b) => b.id)
					)
				)
			)
			.orderBy(desc(billPayment.paidAt));
		for (const r of rows) {
			const list = history.get(r.billId) ?? [];
			// The six most recent payments, newest first, as estimateOf uses
			if (list.length < 6) list.push(r.amount);
			history.set(r.billId, list);
		}
	}
	for (const b of bills)
		out.set(
			b.id,
			b.kind === 'fixed'
				? { amount: b.amount, unknown: b.amount === null, basis: 'user', used: 0, dropped: 0 }
				: estimateBill(history.get(b.id) ?? [], b.amount)
		);
	return out;
}

/**
 * The occurrences (windows) of the active bills whose due date falls between two Manila dates, inclusive, paid or not, in date order.
 * A window is paid when a payment's date lies inside it, so editing a bill's schedule or weekend rule never makes a paid window look
 * unpaid. Used by the split too.
 */
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
		.select({
			billId: billPayment.billId,
			dueDate: billPayment.dueDate,
			windowStart: billPayment.windowStart,
			windowEnd: billPayment.windowEnd
		})
		.from(billPayment)
		.where(
			and(
				eq(billPayment.userId, userId),
				gte(billPayment.dueDate, addDays(from, -WINDOW_PAD_DAYS)),
				lte(billPayment.dueDate, addDays(to, WINDOW_PAD_DAYS))
			)
		);
	// What each payment settled: its stored window, or just its due date on older rows
	const settled = new Map<string, { start: string; end: string }[]>();
	for (const p of payments)
		settled.set(p.billId, [
			...(settled.get(p.billId) ?? []),
			{ start: p.windowStart ?? p.dueDate, end: p.windowEnd ?? p.dueDate }
		]);
	// Single dates a person or the assistant changed: moved, another amount or account, skipped
	const overrides = await overridesOf(
		tx,
		userId,
		bills.map((b) => b.id),
		addDays(from, -OVERRIDE_REACH_DAYS),
		addDays(to, OVERRIDE_REACH_DAYS)
	);
	const withWindows = bills.map((b) => ({
		b,
		windows: effectiveOccurrences(
			b.schedule as Schedule,
			from,
			to,
			{ weekend: b.weekendRule },
			overrides.get(b.id) ?? [],
			b.startsOn
		)
	}));
	const estimates = await estimatesOf(
		tx,
		userId,
		withWindows.filter((x) => x.windows.length > 0).map((x) => x.b)
	);
	const out: DueBill[] = [];
	for (const { b, windows } of withWindows) {
		const est = estimates.get(b.id);
		for (const w of windows)
			out.push({
				billId: b.id,
				name: b.name,
				category: b.category,
				accountId: w.override?.accountId ?? b.accountId,
				dueDate: w.end,
				originalDueDate: w.original,
				overridden: w.override !== null,
				windowStart: w.start,
				windowEnd: w.end,
				amount: w.override?.amount ?? est?.amount ?? null,
				unknownAmount: (w.override?.amount ?? est?.amount ?? null) === null,
				// Overlap, so a later change of the weekend rule or the schedule does not hide a payment already made
				paid: (settled.get(b.id) ?? []).some((p) => p.start <= w.end && p.end >= w.start),
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
			// The date may be the one the schedule gives or the one it was moved to. Any day inside a window settles that occurrence,
			// and the payment is recorded on the window's due (last) day
			const { list } = await occurrencesAround(tx, userId, b, input.dueDate);
			const occurrence = occurrenceOn(list, input.dueDate);
			if (!occurrence) throw new OpsError('INVALID', `"${b.name}" is not due on ${input.dueDate}.`);
			const window = { start: occurrence.start, end: occurrence.end };
			if (await paidWithin(tx, userId, b.id, window.start, window.end))
				throw new OpsError('CONFLICT', `"${b.name}" is already paid for that period.`);
			const est = await estimateOf(tx, userId, b);
			// What this one date was changed to counts unless the payment says otherwise
			const amount = input.amount ?? occurrence.override?.amount ?? est.amount;
			if (!amount) throw new OpsError('INVALID', `Say how much "${b.name}" was this time.`);
			let accountId = input.accountId ?? b.accountId;
			if (!input.accountId && occurrence.override?.accountId) {
				// An account that was archived since the change falls back to the bill's own
				const own = await requireAccount(tx, userId, occurrence.override.accountId);
				if (!own.archivedAt) accountId = own.id;
			}
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
				.values({
					userId,
					billId: b.id,
					dueDate: window.end,
					windowStart: window.start,
					windowEnd: window.end,
					amount,
					txnId: txn.id
				})
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

/**
 * Changes ONE due date of a bill and leaves the rest of its series alone: moves it to another day (up to a month either way), gives it
 * another amount or paying account, or skips it. `dueDate` is the date the occurrence has now. A field left out keeps what it has and a
 * null clears it; a change that leaves nothing changed removes the override. A date already paid is corrected in the ledger, not here.
 */
export async function updateBillOccurrence(ctx: Ctx, raw: BillOccurrenceUpdateInput) {
	const { billId, dueDate, expectVersion, ...changes } = parse(billOccurrenceUpdateInput, raw);
	return mapped(() =>
		runWrite(
			ctx,
			'bill.occurrenceUpdate',
			{ billId, dueDate, expectVersion, ...changes },
			async (tx, userId) => {
				const b = await requireBill(tx, userId, billId);
				if (!b.active) throw new OpsError('INVALID', `"${b.name}" is switched off.`);
				// An amount on a bill whose amount varies feeds the split and the usual amount: that is the person's call
				if (changes.amount != null && b.kind === 'variable')
					requirePerson(ctx.actor.kind, 'set the amount of one date of a bill whose amount varies');
				// A skipped date is hidden from the list, so look for it with the skips switched off
				const { list, overrides } = await occurrencesAround(tx, userId, b, dueDate, {
					keepSkipped: true
				});
				const existing = overrideOn(overrides, dueDate);
				const occurrence = occurrenceOn(list, existing?.originalDueDate ?? dueDate);
				if (!occurrence) throw new OpsError('INVALID', `"${b.name}" is not due on ${dueDate}.`);
				const original = occurrence.original;
				if (existing) checkVersion(existing.version, expectVersion, 'change to that date');
				if (await paidWithin(tx, userId, b.id, occurrence.start, occurrence.end))
					throw new OpsError(
						'CONFLICT',
						`"${b.name}" is already paid for that date. A payment is corrected in the ledger.`
					);
				// Merge: a field left out keeps what it has, a null clears it
				const keep = <T>(given: T | undefined, had: T | undefined, none: T): T =>
					given !== undefined ? given : (had ?? none);
				let newDueDate = keep(changes.newDueDate, existing?.newDueDate, null);
				let amount = keep(changes.amount, existing?.amount, null);
				let accountId = keep(changes.accountId, existing?.accountId, null);
				let skipped = keep(changes.skipped, existing?.skipped, false);
				const effectGiven =
					changes.newDueDate != null || changes.amount != null || changes.accountId != null;
				if (changes.skipped === true) {
					if (effectGiven)
						throw new OpsError('INVALID', 'A date that is skipped cannot also be changed.');
					newDueDate = amount = accountId = null;
				} else if (effectGiven) skipped = false;
				if (newDueDate === original) newDueDate = null;
				// The day this date will be due on: no other date of the bill may already hold it (a skipped one still holds its own day)
				if (!skipped) {
					const finalDay = newDueDate ?? original;
					const { list: near } = await occurrencesAround(tx, userId, b, original, {
						keepSkipped: true
					});
					if (near.some((o) => o.original !== original && o.end === finalDay))
						throw new OpsError(
							'CONFLICT',
							`"${b.name}" is already due on ${finalDay}. Move the other one first.`
						);
				}
				if (newDueDate !== null) {
					if (Math.abs(diffDays(newDueDate, original)) > MOVE_LIMIT_DAYS)
						throw new OpsError(
							'INVALID',
							`A date can move at most ${MOVE_LIMIT_DAYS} days from ${original}.`
						);
					if (await paidWithin(tx, userId, b.id, newDueDate, newDueDate))
						throw new OpsError(
							'CONFLICT',
							`${newDueDate} falls in a period of "${b.name}" that is already paid.`
						);
				}
				if (accountId !== null) await requireActiveAccount(tx, userId, accountId);
				const nothing = !skipped && newDueDate === null && amount === null && accountId === null;
				if (nothing) {
					if (existing)
						await tx
							.delete(billOverride)
							.where(and(eq(billOverride.userId, userId), eq(billOverride.id, existing.id)));
					return { billId, originalDueDate: original, override: null };
				}
				if (existing) {
					const [row] = await tx
						.update(billOverride)
						.set({
							newDueDate,
							amount,
							accountId,
							skipped,
							version: sql`${billOverride.version} + 1`,
							updatedAt: sql`now()`
						})
						.where(and(eq(billOverride.userId, userId), eq(billOverride.id, existing.id)))
						.returning();
					if (!row) throw new OpsError('NOT_FOUND', 'That change does not exist.');
					return { billId, originalDueDate: original, override: plain(row) };
				}
				const [row] = await tx
					.insert(billOverride)
					.values({
						userId,
						billId,
						originalDueDate: original,
						newDueDate,
						amount,
						accountId,
						skipped
					})
					.returning();
				if (!row) throw new OpsError('CONFLICT', 'The change could not be saved.');
				// A change that created the override can be undone (it is removed); an edit of an existing one is simply made again
				await recordUndo(tx, userId, ctx.requestId, {
					verb: 'bill.occurrenceUpdate',
					entity: 'bill_override',
					entityId: row.id,
					before: null,
					after: { billId, originalDueDate: original }
				});
				return { billId, originalDueDate: original, override: plain(row) };
			}
		)
	);
}

/** Puts one due date of a bill back to what its schedule says. Nothing to reset is not an error. */
export async function resetBillOccurrence(ctx: Ctx, raw: BillOccurrenceResetInput) {
	const { billId, dueDate } = parse(billOccurrenceResetInput, raw);
	return mapped(() =>
		runWrite(ctx, 'bill.occurrenceReset', { billId, dueDate }, async (tx, userId) => {
			const b = await requireBill(tx, userId, billId);
			const found = overrideOn(
				(
					await overridesOf(
						tx,
						userId,
						[billId],
						addDays(dueDate, -OVERRIDE_REACH_DAYS),
						addDays(dueDate, OVERRIDE_REACH_DAYS)
					)
				).get(billId) ?? [],
				dueDate
			);
			if (!found) return { billId, originalDueDate: dueDate, reset: false };
			// Back on its own day, no other date of the bill may be due there
			if (found.skipped || found.newDueDate) {
				const { list: near } = await occurrencesAround(tx, userId, b, found.originalDueDate, {
					keepSkipped: true
				});
				if (
					near.some((o) => o.original !== found.originalDueDate && o.end === found.originalDueDate)
				)
					throw new OpsError(
						'CONFLICT',
						`"${b.name}" is already due on ${found.originalDueDate}. Move the other one first.`
					);
			}
			// A moved date that was paid would show as unpaid at its old day, so a paid one stays as it is
			if (
				found.newDueDate &&
				(await paidWithin(tx, userId, billId, found.newDueDate, found.newDueDate))
			)
				throw new OpsError('CONFLICT', 'That date is already paid, so it cannot be reset.');
			await tx
				.delete(billOverride)
				.where(and(eq(billOverride.userId, userId), eq(billOverride.id, found.id)));
			return { billId, originalDueDate: found.originalDueDate, reset: true };
		})
	);
}
