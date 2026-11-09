// NET BALANCE: WHAT A WALLET HOLDS THAT IS NOT ALREADY OWED TO A BILL OR A GOAL (BTL-20261030-0546)
// A pure function from the money plan (finance/planFlows.ts PlanData, loaded once by ops/planData.ts), each wallet's balance now and today. Rules that hold:
// - Money is held per wallet (an account in one currency). A bill holds money in the wallet of ITS OWN currency, so no wallet's net needs a
//   conversion and nothing is rounded; totals convert each net with the stored rates elsewhere (ops/assets.ts). A claim with no wallet in that
//   currency is returned as unmatched and named, never dropped.
// - The next payday is the first date from today of an income with an amount above zero; a payday today counts only when its pay is not yet
//   recorded (`incomeDays`), since a recorded pay is already in the balance. With no payday ahead the horizon is 30 days.
// - An unpaid bill date before the next payday (or up to 31 days late) holds its full amount, from the same dates the forecast and the split
//   use (finance/billWindows.ts: overrides, windows, payments). A bill with no amount yet holds nothing and is named.
// - For a later bill, money a linked rule has set aside holds it (finance/funding.ts reservedFor as of today, valid links only; a broken link
//   holds nothing and is named). It lowers net but is never a shortfall: the bill is not due yet.
// - An account that holds a goal keeps its whole main wallet for the goal (the payday split gives nothing from it), so that wallet's net is
//   zero and any bill due from it is a shortfall.
// - The holds come bills first (by date, a late one marked `overdue`), then what the rules set aside, so the screen can group them "owed now" and
//   "set aside for later". `spentSetAside` is the part of the rule holds the balance no longer covers (money set aside and then spent).
// - net = max(0, balance - held). shortfall = what the bills due before the next payday still lack: max(0, due - max(balance, 0)).
//   The minimum balance is NOT subtracted: it is a floor the person chose, not a promise, and stays its own line.

// -- TYPES -- //
import type { DueBill } from './billWindows';
import type { ManilaDate } from './dates';
import type { PlanData } from './planFlows';
// -- MODULES -- //
import { billOccurrences } from './billWindows';
import { addDays } from './dates';
import { reservedFor } from './funding';
import { OVERDUE_DAYS, datedBills, deferPaydays, planLinks, recordedPays } from './planFlows';
import { occurrencesBetween } from './schedule';

// -- TYPES -- //

/** A wallet and its balance now, minor units of its own currency. */
export type NetWalletInput = { accountId: string; currency: string; balance: number };

/** Why money in a wallet is held. */
export type NetHold = {
	kind: 'bill' | 'rule' | 'goal';
	/** The bill, the rule or the goal named for the person. */
	label: string;
	/** Minor units of the wallet's currency. */
	amount: number;
	/** The bill's due date, for a bill. */
	dueDate?: ManilaDate;
	/** The bill a bill hold is for, or the bill a rule saves for, so the screen can show its icon. Only the net at a simulated day sets it. */
	billId?: string;
	/** True (only ever set to true) for an unpaid bill whose due date is before today, so the screen can name it as late. */
	overdue?: true;
};

export type NetWallet = NetWalletInput & {
	/** Minor units. */
	held: number;
	net: number;
	shortfall: number;
	holds: NetHold[];
	/** Money the linked rules set aside here that the balance no longer holds (it was spent): what the rule holds exceed the free balance by. Zero for a goal wallet. */
	spentSetAside: number;
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
	const rules: Record<string, NetHold[]> = {};
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

	// What a linked rule has set aside for a bill that is not due before the next payday
	const { links, broken } = planLinks(plan);
	for (const l of broken)
		notes.push({ kind: 'broken_link', rule: l.ruleLabel, bill: l.billName, reason: l.reason });
	const paydaysBetween = (from: ManilaDate, to: ManilaDate) =>
		from > to
			? []
			: plan.incomes
					.filter((i) => (i.expectedAmount ?? 0) > 0)
					.flatMap((i) => occurrencesBetween(i.schedule, from, to, { weekend: i.weekendRule }));
	const dueIds = new Set(due.map((b) => b.billId));
	for (const l of links) {
		const b = plan.bills.find((x) => x.id === l.billId);
		if (!b || !active.has(l.accountId)) continue;
		const dates = billOccurrences(
			[b],
			addDays(today, -400),
			addDays(today, 400),
			plan.overrides,
			plan.settled,
			new Map([[b.id, b.usualAmount]])
		);
		const next = dates.find((d) => d.dueDate >= today);
		if (!next) continue;
		// An occurrence before the next payday already holds its full amount above
		if (next.dueDate < until && dueIds.has(b.id)) continue;
		const previous = [...dates].reverse().find((d) => d.dueDate < next.dueDate);
		const since = previous ? addDays(previous.dueDate, 1) : l.effectiveFrom;
		const set = reservedFor(
			l,
			next.amount ?? 0,
			previous?.dueDate ?? null,
			paydaysBetween(since, addDays(today, -1)),
			today,
			next.paid
		);
		const key = keyOf(l.accountId, plan.main);
		if (set > 0 && walletKeys.has(key))
			push(rules, key, { kind: 'rule', label: l.ruleLabel, amount: set, dueDate: next.dueDate });
	}

	return { wallets: settle(plan, wallets, bills, rules), unmatched, notes, until };
}

/** What each wallet holds back and what is left, once the holds are found. The one place the net, the shortfall and the goal rule are worked out. */
function settle(
	plan: PlanData,
	wallets: readonly NetWalletInput[],
	bills: Record<string, NetHold[]>,
	rules: Record<string, NetHold[]>
): NetWallet[] {
	const goalAccounts = new Set(plan.goals.map((g) => g.accountId));
	const goalName = (accountId: string) =>
		plan.goals
			.filter((g) => g.accountId === accountId)
			.map((g) => g.name)
			.join(', ');
	return wallets.map((w) => {
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
				holds: [{ kind: 'goal', label: goalName(w.accountId), amount: own }, ...dueHolds],
				spentSetAside: 0
			};
		const ruleHolds = rules[key] ?? [];
		const ruleSum = ruleHolds.reduce((n, h) => n + h.amount, 0);
		const held = dueSum + ruleSum;
		return {
			...w,
			held,
			net: Math.max(0, w.balance - held),
			shortfall: Math.max(0, dueSum - own),
			// Bills first (late ones lead, then by date), then what the rules saved, by the date of the bill each saves for
			holds: [...dueHolds, ...[...ruleHolds].sort(byDate)],
			spentSetAside: Math.min(ruleSum, Math.max(0, ruleSum - Math.max(0, own - dueSum)))
		};
	});
}

// -- NET AT A SIMULATED DAY -- //
// The simulation (finance/simulate.ts) has already paid every bill dated up to a day and received every pay up to it, so its balance at the end
// of that day is read on a clock that starts after the day (BTL-20261109-0230): the next payday is the first after it, the held bills are those
// dated after it and before that payday, and a rule has set aside the pays up to and including it. Bills are dated by the same function the
// simulation's flows use (planFlows.ts datedBills), so a what-if delay, a deferral, a forced amount and a skipped payday all agree with the
// balance. Everything that does not depend on the day is worked out once (buildNetContext) and shared by every period end.

/** What the net at any simulated day needs from the plan, worked out once for a range. */
export type NetContext = {
	plan: PlanData;
	/** Unpaid bill dates from today to the horizon, after the what-if. */
	bills: DueBill[];
	/** Paydays that bring money (an amount above zero, what-if skips left out), sorted. */
	paydays: ManilaDate[];
	/** The rules that save for a bill, with every date of that bill around the range. */
	links: { link: ReturnType<typeof planLinks>['links'][number]; dates: DueBill[] }[];
	/** Rules that point at a bill but cannot save for it, and why: say it once for the range. */
	broken: ReturnType<typeof planLinks>['broken'];
	active: ReadonlySet<string>;
};

/** Builds the shared part for days from `today` to `last`. Throws only on a bad schedule (a RangeError). */
export function buildNetContext(plan: PlanData, today: ManilaDate, last: ManilaDate): NetContext {
	const hi = addDays(last, 400);
	const skip = plan.whatIf?.skip ?? new Set<string>();
	const paydays = [
		...new Set(
			plan.incomes
				.filter((i) => (i.expectedAmount ?? 0) > 0)
				.flatMap((i) =>
					occurrencesBetween(i.schedule, addDays(today, -800), hi, {
						weekend: i.weekendRule
					}).filter((d) => !skip.has(`${i.id}|${d}`))
				)
		)
	].sort();
	const deferral = deferPaydays(plan, today, hi);
	const bills = datedBills(plan, today, hi, deferral).filter((b) => !b.paid);
	const { links, broken } = planLinks(plan);
	const linked = links.flatMap((link) => {
		const b = plan.bills.find((x) => x.id === link.billId);
		if (!b) return [];
		return [
			{
				link,
				dates: datedBills({ ...plan, bills: [b] }, addDays(today, -400), hi, deferral)
			}
		];
	});
	return {
		plan,
		bills,
		paydays,
		links: linked,
		broken,
		active: new Set(plan.accounts.filter((a) => !a.archived).map((a) => a.id))
	};
}

/**
 * What each wallet holds back at the end of `asOf` (a day from today on), given its balance then. The bills with no amount yet are the
 * simulation's `unknown` list, so they are not repeated here, and the broken links are in the context.
 */
export function computeNetAt(
	ctx: NetContext,
	wallets: readonly NetWalletInput[],
	asOf: ManilaDate
): NetResult {
	const { plan } = ctx;
	const until = ctx.paydays.find((p) => p > asOf) ?? addDays(asOf, NO_PAYDAY_DAYS);
	const walletKeys = new Set(wallets.map((w) => keyOf(w.accountId, w.currency)));
	const bills: Record<string, NetHold[]> = {};
	const rules: Record<string, NetHold[]> = {};
	const unmatched: NetUnmatched[] = [];
	const push = (into: Record<string, NetHold[]>, key: string, hold: NetHold) => {
		(into[key] ??= []).push(hold);
	};
	const dueIds = new Set<string>();
	for (const b of ctx.bills) {
		if (b.dueDate <= asOf || b.dueDate >= until || !ctx.active.has(b.accountId)) continue;
		// As in the net of today, a bill due before the payday is "due" for its rule whether or not it has an amount or a wallet
		dueIds.add(b.billId);
		if (b.amount === null || b.unknownAmount || b.amount <= 0) continue;
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
			billId: b.billId
		});
	}
	// What a linked rule has set aside for a bill that is not held in full above
	for (const { link: l, dates } of ctx.links) {
		if (!ctx.active.has(l.accountId)) continue;
		const next = dates.find((d) => d.dueDate > asOf);
		if (!next) continue;
		if (next.dueDate < until && dueIds.has(next.billId)) continue;
		const previous = [...dates].reverse().find((d) => d.dueDate < next.dueDate);
		const since = previous ? addDays(previous.dueDate, 1) : l.effectiveFrom;
		const set = reservedFor(
			l,
			next.amount ?? 0,
			previous?.dueDate ?? null,
			ctx.paydays.filter((p) => p >= since && p <= asOf),
			addDays(asOf, 1),
			next.paid
		);
		const key = keyOf(l.accountId, plan.main);
		if (set > 0 && walletKeys.has(key))
			push(rules, key, {
				kind: 'rule',
				label: l.ruleLabel,
				amount: set,
				dueDate: next.dueDate,
				billId: l.billId
			});
	}
	return { wallets: settle(plan, wallets, bills, rules), unmatched, notes: [], until };
}
