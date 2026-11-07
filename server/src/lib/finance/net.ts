// NET BALANCE: WHAT A WALLET HOLDS THAT IS NOT ALREADY OWED TO A BILL OR A GOAL (BTL-20261030-0546)
// A pure function from the money plan (finance/planFlows.ts PlanData, loaded once by ops/planData.ts), each wallet's balance now and today. Rules that hold:
// - Money is held per wallet (an account in one currency). A bill holds money in the wallet of ITS OWN currency, so no wallet's net needs a
//   conversion and nothing is rounded; totals convert each net with the stored rates elsewhere (ops/assets.ts). A claim with no wallet in that
//   currency is returned as unmatched and named, never dropped.
// - The next payday is the first date from today of an income with an amount above zero; a payday today counts only when its pay is not yet
//   recorded (`incomeDays`), since a recorded pay is already in the balance. With no payday ahead the horizon is 30 days.
// - An unpaid bill date before the next payday (or up to 31 days late) holds its full amount, from the same dates the forecast and the split
//   use (finance/billWindows.ts: overrides, windows, payments). A bill with no amount yet holds nothing and is named.
// - Owner decision of 2026-11-07: money a payday rule has set aside for a LATER bill does not lower net. Only the payday window (bills due before
//   the next payday) and late bills are covered; the rule's money is the owner's to see on the rule, not a deduction. A broken link is still named.
// - An account that holds a goal keeps its whole main wallet for the goal (the payday split gives nothing from it), so that wallet's net is
//   zero and any bill due from it is a shortfall.
// - The holds come by date, a late one marked `overdue`.
// - net = max(0, balance - held). shortfall = what the bills due before the next payday still lack: max(0, due - max(balance, 0)).
//   The minimum balance is NOT subtracted: it is a floor the person chose, not a promise, and stays its own line.

// -- TYPES -- //
import type { DueBill } from './billWindows';
import type { ManilaDate } from './dates';
import type { PlanData } from './planFlows';
// -- MODULES -- //
import { billOccurrences } from './billWindows';
import { addDays } from './dates';
import { OVERDUE_DAYS, planLinks, recordedPays } from './planFlows';
import { occurrencesBetween } from './schedule';

// -- TYPES -- //

/** A wallet and its balance now, minor units of its own currency. */
export type NetWalletInput = { accountId: string; currency: string; balance: number };

/** Why money in a wallet is held. */
export type NetHold = {
	kind: 'bill' | 'goal';
	/** The bill or the goal named for the person. */
	label: string;
	/** Minor units of the wallet's currency. */
	amount: number;
	/** The bill's due date, for a bill. */
	dueDate?: ManilaDate;
	/** True (only ever set to true) for an unpaid bill whose due date is before today, so the screen can name it as late. */
	overdue?: true;
};

export type NetWallet = NetWalletInput & {
	/** Minor units. */
	held: number;
	net: number;
	shortfall: number;
	holds: NetHold[];
};

/** A bill that holds money in a currency the account has no wallet in. */
export type NetUnmatched = {
	accountId: string;
	currency: string;
	label: string;
	amount: number;
	dueDate: ManilaDate;
};

/** What could not count, in plain terms for the caller to word. */
export type NetNote =
	| { kind: 'missing_amount'; accountId: string; bill: string; dueDate: ManilaDate }
	| { kind: 'broken_link'; rule: string; bill: string | null; reason: string };

export type NetResult = {
	wallets: NetWallet[];
	unmatched: NetUnmatched[];
	notes: NetNote[];
	/** The bills before this date are held (the next payday, or 30 days out when there is none). */
	until: ManilaDate;
};

// -- CONSTANTS -- //

/** With no payday ahead, bills due in this many days are held. */
export const NO_PAYDAY_DAYS = 30;

// -- FUNCTIONS -- //

const keyOf = (accountId: string, currency: string) => `${accountId}|${currency}`;

/** The first date from today that a pay is still to arrive, or null when no income has an amount and a date ahead. */
export function nextPayday(plan: PlanData, today: ManilaDate): ManilaDate | null {
	let first: ManilaDate | null = null;
	const paidToday = recordedPays(plan, today);
	for (const i of plan.incomes) {
		if ((i.expectedAmount ?? 0) <= 0) continue;
		const recorded = paidToday.has(i.id);
		const from = recorded ? addDays(today, 1) : today;
		const date = occurrencesBetween(i.schedule, from, addDays(from, 800), {
			weekend: i.weekendRule
		})[0];
		if (date !== undefined && (first === null || date < first)) first = date;
	}
	return first;
}

/** What each wallet holds back and what is left, as of `today`. Throws only on a bad schedule (a RangeError): the caller keeps balances. */
export function computeNet(
	plan: PlanData,
	wallets: readonly NetWalletInput[],
	today: ManilaDate
): NetResult {
	const notes: NetNote[] = [];
	const payday = nextPayday(plan, today);
	const until = payday ?? addDays(today, NO_PAYDAY_DAYS);
	const walletKeys = new Set(wallets.map((w) => keyOf(w.accountId, w.currency)));
	const active = new Set(plan.accounts.filter((a) => !a.archived).map((a) => a.id));
	const amounts = new Map(plan.bills.map((b) => [b.id, b.usualAmount]));
	const bills: Record<string, NetHold[]> = {};
	const unmatched: NetUnmatched[] = [];
	const push = (into: Record<string, NetHold[]>, key: string, hold: NetHold) => {
		(into[key] ??= []).push(hold);
	};

	// Unpaid bill dates before the next payday, and the ones up to 31 days late
	const due: DueBill[] = billOccurrences(
		plan.bills,
		addDays(today, -OVERDUE_DAYS),
		addDays(until, -1),
		plan.overrides,
		plan.settled,
		amounts
	).filter((b) => !b.paid && active.has(b.accountId));
	for (const b of due) {
		if (b.amount === null || b.unknownAmount) {
			notes.push({
				kind: 'missing_amount',
				accountId: b.accountId,
				bill: b.name,
				dueDate: b.dueDate
			});
			continue;
		}
		if (b.amount <= 0) continue;
		const key = keyOf(b.accountId, b.currency);
		if (!walletKeys.has(key)) {
			unmatched.push({
				accountId: b.accountId,
				currency: b.currency,
				label: b.name,
				amount: b.amount,
				dueDate: b.dueDate
			});
			continue;
		}
		push(bills, key, {
			kind: 'bill',
			label: b.name,
			amount: b.amount,
			dueDate: b.dueDate,
			...(b.dueDate < today ? { overdue: true as const } : {})
		});
	}

	// A rule that cannot save for its bill is still named, though no rule holds money here any more (owner decision of 2026-11-07)
	for (const l of planLinks(plan).broken)
		notes.push({ kind: 'broken_link', rule: l.ruleLabel, bill: l.billName, reason: l.reason });

	const goalAccounts = new Set(plan.goals.map((g) => g.accountId));
	const goalName = (accountId: string) =>
		plan.goals
			.filter((g) => g.accountId === accountId)
			.map((g) => g.name)
			.join(', ');
	const out: NetWallet[] = wallets.map((w) => {
		const key = keyOf(w.accountId, w.currency);
		const byDate = (a: NetHold, b: NetHold) => (a.dueDate ?? '').localeCompare(b.dueDate ?? '');
		const dueHolds = [...(bills[key] ?? [])].sort(byDate);
		const dueSum = dueHolds.reduce((n, h) => n + h.amount, 0);
		const isGoal = w.currency === plan.main && goalAccounts.has(w.accountId);
		const own = Math.max(w.balance, 0);
		if (isGoal)
			return {
				...w,
				held: own,
				net: 0,
				// The goal's money never pays a bill, so a bill due from here has to come from the pay
				shortfall: dueSum,
				holds: [{ kind: 'goal', label: goalName(w.accountId), amount: own }, ...dueHolds]
			};
		return {
			...w,
			held: dueSum,
			net: Math.max(0, w.balance - dueSum),
			shortfall: Math.max(0, dueSum - own),
			// Late bills lead, then by date
			holds: dueHolds
		};
	});
	return { wallets: out, unmatched, notes, until };
}
