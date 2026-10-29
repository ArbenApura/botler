// THE DUE DATES OF A SET OF BILLS BETWEEN TWO DAYS, FROM ROWS ALREADY LOADED: A PURE FUNCTION (BTL-20261029-0117)
// ops/bills.ts dueBills loads the bills, their payments, their single-date changes and their usual amounts, then calls this. The
// simulation loads the same rows once and calls it for every payday and every period, so 5 years of paydays never read the database again.
// Rules that hold (the same as before the move):
// - The dates come from effectiveOccurrences, so a moved or skipped date is the same everywhere.
// - A window is paid when a payment's settled stretch overlaps it, so a later change of the schedule never hides a payment.
// - The amount of a date is its override's, else the bill's own or learned amount, else unknown.

// -- TYPES -- //
import type { ManilaDate } from './dates';
import type { OverrideLike } from './occurrence';
import type { Schedule, WeekendRule } from './schedule';
// -- MODULES -- //
import { effectiveOccurrences } from './occurrence';

// -- TYPES -- //

/** What the windows need of a bill row. */
export type BillLike = {
	id: string;
	name: string;
	category: string;
	accountId: string;
	schedule: unknown;
	weekendRule: WeekendRule;
	deferrable: boolean;
	startsOn: ManilaDate | null;
	currency: string;
};

/** The stretch a payment settled: its stored window, or only its due date on older rows. */
export type SettledStretch = { start: ManilaDate; end: ManilaDate };

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
	/** Minor units of currency, or null when a variable bill has no estimate yet (the person must be asked). */
	amount: number | null;
	/** The currency of the bill and of amount. */
	currency: string;
	unknownAmount: boolean;
	paid: boolean;
	deferrable: boolean;
};

// -- FUNCTIONS -- //

/**
 * The occurrences of the bills whose due date falls between two Manila dates, inclusive, paid or not, sorted by due date then name.
 * `overrides`, `settled` and `amounts` are keyed by bill id; a bill with no entry has no changes, no payments or an unknown amount.
 */
export function billOccurrences<O extends OverrideLike>(
	bills: readonly BillLike[],
	from: ManilaDate,
	to: ManilaDate,
	overrides: ReadonlyMap<string, readonly O[]>,
	settled: ReadonlyMap<string, readonly SettledStretch[]>,
	amounts: ReadonlyMap<string, number | null>
): DueBill[] {
	const out: DueBill[] = [];
	for (const b of bills) {
		const windows = effectiveOccurrences(
			b.schedule as Schedule,
			from,
			to,
			{ weekend: b.weekendRule },
			overrides.get(b.id) ?? [],
			b.startsOn
		);
		const usual = amounts.get(b.id) ?? null;
		for (const w of windows) {
			const amount = w.override?.amount ?? usual ?? null;
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
				amount,
				currency: b.currency,
				unknownAmount: amount === null,
				// Overlap, so a later change of the weekend rule or the schedule does not hide a payment already made
				paid: (settled.get(b.id) ?? []).some((p) => p.start <= w.end && p.end >= w.start),
				deferrable: b.deferrable
			});
		}
	}
	return out.sort((a, b) =>
		a.dueDate < b.dueDate ? -1 : a.dueDate > b.dueDate ? 1 : a.name < b.name ? -1 : 1
	);
}
