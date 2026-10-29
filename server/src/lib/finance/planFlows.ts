// THE MONEY THE PLAN MOVES BETWEEN TWO DAYS: PAYDAYS, BILLS AND THE PAYDAY SPLIT OF THE ACTIVE RULES, FROM ROWS ALREADY LOADED (BTL-20261029-0117)
// A pure function. The forecast verb (ops/forecast.ts) and the simulation (finance/simulate.ts) both read their flows from here, so a payday
// split in the future and in a replay of the past are worked out by the same lines. Two modes:
// - future: what will happen from today. Paid bill dates are left out, an unpaid one up to 31 days late counts today, and a pay already
//   recorded today is not counted again. This is exactly what cashflow_forecast has always counted.
// - replay: what the plan would have done in a stretch of the past. Every payday and bill date counts, paid or not, at the plan's amount
//   (never the amount really paid), and a payday, bill, goal or rule counts only from the day it was made (a rule also from its
//   effective date and from the day its target was made).
// A payday whose split cannot be worked out (a bill with no amount yet, a missing rate) adds no moves and says why in the notes.
// With today's balances (future mode, BTL-20261029-0119) the paydays run in date order and each split first pays bills from money already
// in their account today (less what leaves it before the payday, its minimum and what linked rules set aside) and from the rules that save
// for a bill, so only what is missing moves. Without balances (replay, the simulation) the flows are as they were.

// -- TYPES -- //
import type { DueBill, SettledStretch, BillLike } from './billWindows';
import type { ManilaDate } from './dates';
import type { ForecastFlow, ForecastUnknown } from './forecast';
import type { Rates } from './fx';
import type { OverrideLike } from './occurrence';
import type { Rule } from './rules';
import type { Schedule, WeekendRule } from './schedule';
import type { BrokenLink } from './funding';
import type { Commitment, CoveredLine, FundedLine, SplitLink, UnfundedLine } from './split';
// -- MODULES -- //
import { billOccurrences } from './billWindows';
import { availableFor, checkLinks, reservedFor } from './funding';
import { addDays } from './dates';
import { canConvert, convertUp } from './fx';
import { occurrencesBetween } from './schedule';
import { bestEffortTransfers, proposeSplit } from './split';

// -- TYPES -- //

export type PlanAccount = {
	id: string;
	name: string;
	/** The balance the person wants to keep, in the main currency. */
	minBalance: number;
	/** Hidden: its history is real, but the plan no longer moves money in or out of it. */
	archived: boolean;
	createdOn: ManilaDate;
};

export type PlanIncome = {
	id: string;
	label: string;
	accountId: string;
	expectedAmount: number | null;
	schedule: Schedule;
	weekendRule: WeekendRule;
	createdOn: ManilaDate;
};

export type PlanBill = BillLike & {
	/** The bill's own or learned amount, or null when it is not known yet. */
	usualAmount: number | null;
	createdOn: ManilaDate;
};

export type PlanGoal = {
	id: string;
	name: string;
	accountId: string;
	perPayday: number;
	createdOn: ManilaDate;
};

export type PlanRule = Rule & {
	createdOn: ManilaDate;
	/** The bill the rule saves for (BTL-20261029-0119), or null. */
	fundsBillId?: string | null;
	/** The rule's own label, before the flows name it after its target. */
	ownLabel?: string | null;
};

/** A one-off pretend entry of a what-if. */
export type PretendEntry = {
	date: ManilaDate;
	kind: 'in' | 'out';
	accountId: string;
	currency: string;
	amount: number;
	label: string;
};

/** What a what-if changes in how the flows are made (finance/scenario.ts fills it; the lists of the plan are already filtered). */
export type WhatIf = {
	/** `incomeId|date` of paydays to skip. */
	skip: ReadonlySet<string>;
	/** Bill amounts that replace every date's amount. */
	billAmounts: ReadonlyMap<string, number>;
	delayDays: number;
	deferDeferrable: boolean;
	extra: readonly PretendEntry[];
};

/** Everything the flows are made from, loaded once. Active items only, archived accounts included and flagged. */
export type PlanData = {
	main: string;
	rates: Rates;
	accounts: readonly PlanAccount[];
	incomes: readonly PlanIncome[];
	bills: readonly PlanBill[];
	goals: readonly PlanGoal[];
	rules: readonly PlanRule[];
	overrides: ReadonlyMap<string, readonly OverrideLike[]>;
	settled: ReadonlyMap<string, readonly SettledStretch[]>;
	/** `accountId|date` of every day an income was recorded on an account. */
	incomeDays: ReadonlySet<string>;
	whatIf?: WhatIf;
	/**
	 * Each account's balance in the main currency now (BTL-20261029-0119). Given only in future mode: the splits then take bills from money
	 * already in their account and from the rules that save for them first. Left out, every bill comes from the pay.
	 */
	balances?: ReadonlyMap<string, number>;
};

/** What a payday's split took from money already in the accounts and from rules that save for bills (BTL-20261029-0119). */
export type PaydayFunding = {
	incomeId: string;
	payday: ManilaDate;
	covered: CoveredLine[];
	funded: FundedLine[];
	unfunded: UnfundedLine[];
};

/** What the split of one payday may take from money already there: by account, and the rules that save for bills. */
export type FundingAt = {
	available: Record<string, number>;
	links: SplitLink[];
	broken: BrokenLink[];
};

/** Why a payday split is not in the moves, or is short. One per payday; callers word or group them. */
export type PlanNote =
	| { kind: 'missing_amount'; payday: ManilaDate; bill: string }
	| { kind: 'unrated'; payday: ManilaDate; currency: string }
	| { kind: 'shortfall'; payday: ManilaDate; gap: number }
	| { kind: 'split_error'; payday: ManilaDate; message: string };

/** A flow with where it came from: a payday, a bill date, a payday move or a pretend entry of a what-if. */
export type PlanFlow = ForecastFlow & {
	origin: 'pay' | 'bill' | 'split' | 'pretend';
	/** The income or bill behind it, when there is one. */
	refId?: string;
};

export type PlanFlowsOptions = {
	mode: 'future' | 'replay';
	from: ManilaDate;
	to: ManilaDate;
	today: ManilaDate;
};

export type PlanFlows = {
	flows: PlanFlow[];
	unknown: ForecastUnknown[];
	notes: PlanNote[];
	/** Per payday, the parts of its bills that did not come from the pay. Only with balances, and only paydays that have some. */
	funding?: PaydayFunding[];
	/** Rules that point at a bill but cannot save for it, and why. Only with balances. */
	brokenLinks?: BrokenLink[];
};

// -- CONSTANTS -- //

/** An unpaid bill this many days past due still counts: it is money that has to go out. */
export const OVERDUE_DAYS = 31;

/** How far back a bill date can sit and still land in a range after a what-if moves it later (late by up to 60 days, deferred a pay period). */
const SHIFT_REACH_DAYS = 60 + 93;

// -- FUNCTIONS -- //

/** The latest of some dates. */
const latest = (...dates: ManilaDate[]): ManilaDate => dates.reduce((a, b) => (a > b ? a : b));

/** The bill dates whose due date falls in a range, after the what-if moves them, each with the amount it will be. */
function datedBills(
	plan: PlanData,
	from: ManilaDate,
	to: ManilaDate,
	paydays: readonly ManilaDate[]
) {
	const w = plan.whatIf;
	const shifts = w !== undefined && (w.delayDays > 0 || w.deferDeferrable);
	const raw = billOccurrences(
		plan.bills,
		shifts ? addDays(from, -SHIFT_REACH_DAYS) : from,
		to,
		plan.overrides,
		plan.settled,
		new Map(plan.bills.map((b) => [b.id, b.usualAmount]))
	);
	if (!w) return raw;
	const out: DueBill[] = [];
	for (const b of raw) {
		const forced = w.billAmounts.get(b.billId);
		let dueDate = addDays(b.dueDate, w.delayDays);
		// A deferrable bill waits for the first payday after its date
		if (w.deferDeferrable && b.deferrable) dueDate = paydays.find((p) => p > dueDate) ?? dueDate;
		if (dueDate < from || dueDate > to) continue;
		out.push({
			...b,
			dueDate,
			amount: forced ?? b.amount,
			unknownAmount: forced === undefined ? b.unknownAmount : false
		});
	}
	return out.sort((a, b) =>
		a.dueDate < b.dueDate ? -1 : a.dueDate > b.dueDate ? 1 : a.name < b.name ? -1 : 1
	);
}

/** The links of the plan's rules to bills, checked (finance/funding.ts). */
export function planLinks(plan: PlanData) {
	return checkLinks(
		plan.rules.map((r) => ({
			id: r.id,
			label: r.ownLabel ?? r.label ?? null,
			mode: r.mode,
			status: 'active',
			amount: r.amount,
			targetAccountId: r.target.kind === 'account' ? r.target.id : null,
			effectiveFrom: r.effectiveFrom,
			fundsBillId: r.fundsBillId ?? null
		})),
		plan.bills.map((b) => ({ ...b, active: true })),
		plan.main
	);
}

/**
 * What the split of `payday` may take from money already in the accounts, given the flows before it (`earlier`, in any order: only the
 * ones dated before the payday and in the main currency count). Only money that is there TODAY counts, never money the plan expects to
 * arrive: each account's balance now, less what leaves it before the payday (its bills and the moves out of it), less its minimum balance
 * and what its linked rules had set aside before today, never below zero; nothing from an account that holds a goal. So a far payday is not
 * paid from pay that a person may well spend first.
 */
export function fundingAt(
	plan: PlanData,
	earlier: readonly ForecastFlow[],
	payday: ManilaDate,
	today: ManilaDate
): FundingAt {
	const { links, broken } = planLinks(plan);
	const left = new Map(plan.balances ?? []);
	for (const f of earlier) {
		if (f.date >= payday || f.currency !== plan.main || f.kind === 'in') continue;
		left.set(f.accountId, (left.get(f.accountId) ?? 0) - f.amount);
	}
	// A payday today (or before) has no earlier flows, but the bills already late are owed from the same money (later paydays get them
	// through `earlier`, where the forecast dates them today)
	if (payday <= today)
		for (const b of billOccurrences(
			plan.bills,
			addDays(today, -OVERDUE_DAYS),
			addDays(today, -1),
			plan.overrides,
			plan.settled,
			new Map(plan.bills.map((x) => [x.id, x.usualAmount]))
		))
			if (!b.paid && b.amount !== null && b.currency === plan.main)
				left.set(b.accountId, (left.get(b.accountId) ?? 0) - b.amount);
	// The paydays a rule could have put money in since a bill's previous date
	const paydaysBetween = (from: ManilaDate, to: ManilaDate) =>
		from > to
			? []
			: plan.incomes
					.filter((i) => (i.expectedAmount ?? 0) > 0)
					.flatMap((i) => occurrencesBetween(i.schedule, from, to, { weekend: i.weekendRule }));
	const splitLinks: SplitLink[] = [];
	// What the rules had set aside before today: it is in today's balance and belongs to its bill
	const held = new Map<string, number>();
	for (const l of links) {
		const b = plan.bills.find((x) => x.id === l.billId);
		if (!b) continue;
		const dates = billOccurrences(
			[b],
			addDays(payday, -400),
			addDays(payday, 400),
			plan.overrides,
			plan.settled,
			new Map([[b.id, b.usualAmount]])
		);
		const next = dates.find((d) => d.dueDate >= payday);
		const previous = [...dates].reverse().find((d) => d.dueDate < (next?.dueDate ?? payday));
		const since = previous ? addDays(previous.dueDate, 1) : l.effectiveFrom;
		const set = next
			? reservedFor(
					l,
					next.amount ?? 0,
					previous?.dueDate ?? null,
					paydaysBetween(since, addDays(payday, -1)),
					payday,
					next.paid
				)
			: 0;
		const before = next
			? reservedFor(
					l,
					next.amount ?? 0,
					previous?.dueDate ?? null,
					paydaysBetween(since, addDays(payday < today ? payday : today, -1)),
					payday,
					next.paid
				)
			: 0;
		held.set(l.accountId, (held.get(l.accountId) ?? 0) + before);
		splitLinks.push({
			billId: l.billId,
			ruleId: l.ruleId,
			ruleLabel: l.ruleLabel,
			perPayday: l.perPayday,
			reserved: set
		});
	}
	const goalAccounts = new Set(plan.goals.map((g) => g.accountId));
	const available: Record<string, number> = {};
	for (const a of plan.accounts) {
		if (a.archived) continue;
		const n = availableFor({
			projected: left.get(a.id) ?? 0,
			minBalance: a.minBalance,
			reserved: held.get(a.id) ?? 0,
			holdsGoal: goalAccounts.has(a.id)
		});
		if (n > 0) available[a.id] = n;
	}
	return { available, links: splitLinks, broken };
}

/** The flows of the plan between `from` and `to`, inclusive. Throws only on a bad schedule (a RangeError). */
export function planFlows(plan: PlanData, opts: PlanFlowsOptions): PlanFlows {
	const { mode, from, to, today } = opts;
	const replay = mode === 'replay';
	const names = new Map(plan.accounts.map((a) => [a.id, a.name]));
	const nameOf = (id: string) => names.get(id) ?? 'an account';
	const createdOf = new Map<string, ManilaDate>(plan.accounts.map((a) => [a.id, a.createdOn]));
	const billCreated = new Map(plan.bills.map((b) => [b.id, b.createdOn]));
	const counts = (b: DueBill) => !replay || b.dueDate >= (billCreated.get(b.billId) ?? b.dueDate);
	const flows: PlanFlow[] = [];
	const unknown: ForecastUnknown[] = [];
	const notes: PlanNote[] = [];

	// Every payday of every income near the range, for deferring a bill to the next one
	const allPaydays = plan.whatIf?.deferDeferrable
		? [
				...new Set(
					plan.incomes.flatMap((inc) =>
						occurrencesBetween(inc.schedule, addDays(from, -SHIFT_REACH_DAYS), addDays(to, 800), {
							weekend: inc.weekendRule
						})
					)
				)
			].sort()
		: [];

	// Bills: in the future the unpaid ones, the late ones today; in a replay every date of the range
	const billDates = replay
		? datedBills(plan, from, to, allPaydays).filter(counts)
		: [
				...datedBills(plan, addDays(today, -OVERDUE_DAYS), addDays(today, -1), allPaydays).filter(
					(x) => !x.paid
				),
				...datedBills(plan, today, to, allPaydays).filter((x) => !x.paid)
			];
	// A late bill of the future counts today
	const first = replay ? from : today;
	for (const b of billDates) {
		const date = b.dueDate < first ? first : b.dueDate;
		const label = b.dueDate < first ? `${b.name} (late, was due ${b.dueDate})` : b.name;
		if (b.amount === null || b.unknownAmount) {
			unknown.push({ kind: 'bill', date, label });
			continue;
		}
		flows.push({
			kind: 'out',
			origin: 'bill',
			refId: b.billId,
			date,
			label,
			accountId: b.accountId,
			accountName: nameOf(b.accountId),
			currency: b.currency,
			amount: b.amount
		});
	}

	const goalAccounts = Object.fromEntries(plan.goals.map((g) => [g.id, g.accountId]));
	const goalCreated = new Map(plan.goals.map((g) => [g.id, g.createdOn]));
	const ruleNames: Record<string, string> = {};
	for (const g of plan.goals) ruleNames[g.id] = g.name;
	for (const a of plan.accounts) ruleNames[a.id] = a.name;
	// In a replay a rule applies from the day it and its target were made, as well as from its effective date
	const funded = plan.balances !== undefined && !replay;
	const funding: PaydayFunding[] = [];
	const rules: Rule[] = plan.rules.map((r) => ({
		...r,
		label: ruleNames[r.target.id] ?? r.label,
		effectiveFrom: replay
			? latest(
					r.effectiveFrom,
					r.createdOn,
					(r.target.kind === 'goal' ? goalCreated.get(r.target.id) : createdOf.get(r.target.id)) ??
						r.createdOn
				)
			: r.effectiveFrom
	}));

	// Every payday of every income in date order, so a payday sees the moves of the ones before it
	const paydays = plan.incomes
		.flatMap((inc) =>
			occurrencesBetween(inc.schedule, from, to, { weekend: inc.weekendRule })
				.filter((d) => !replay || d >= inc.createdOn)
				.map((payday) => ({ inc, payday }))
		)
		.sort((a, b) => (a.payday < b.payday ? -1 : a.payday > b.payday ? 1 : 0));
	for (const { inc, payday } of paydays) {
		const opts = { weekend: inc.weekendRule };
		// A pay already recorded today is in today's balance: counting it again would double it
		if (!replay && payday === today && plan.incomeDays.has(`${inc.accountId}|${today}`)) continue;
		if (plan.whatIf?.skip.has(`${inc.id}|${payday}`)) continue;
		if (inc.expectedAmount === null) {
			unknown.push({ kind: 'income', date: payday, label: inc.label });
			continue;
		}
		flows.push({
			kind: 'in',
			origin: 'pay',
			refId: inc.id,
			date: payday,
			label: inc.label,
			accountId: inc.accountId,
			accountName: nameOf(inc.accountId),
			currency: plan.main,
			amount: inc.expectedAmount
		});

		// A pay of nothing moves nothing (and the engine refuses it)
		if (inc.expectedAmount <= 0) continue;

		// The moves: what the split engine does with this pay, the bills of its period, the goals and the active rules
		const next = occurrencesBetween(
			inc.schedule,
			addDays(payday, 1),
			addDays(payday, 800),
			opts
		)[0];
		const periodEnd = addDays(next ?? addDays(payday, 15), -1);
		const due = datedBills(plan, payday, periodEnd, allPaydays).filter((b) =>
			replay ? counts(b) : !b.paid
		);
		const missingAmount = due.find((b) => b.unknownAmount);
		if (missingAmount) {
			notes.push({ kind: 'missing_amount', payday, bill: missingAmount.name });
			continue;
		}
		let unrated: string | null = null;
		const commitments: Commitment[] = [
			...due.map((b) => {
				let amount = b.amount ?? 0;
				if (b.currency !== plan.main) {
					if (canConvert(b.currency, plan.main, plan.rates))
						amount = convertUp(amount, b.currency, plan.main, plan.rates);
					else unrated = b.currency;
				}
				return {
					kind: b.category === 'parents' ? ('parents' as const) : ('bill' as const),
					refId: b.billId,
					label: b.name,
					amount,
					accountId: b.accountId,
					deferrable: b.deferrable,
					dueDate: b.dueDate,
					// Money already in an account is in the main currency: it never pays a bill in another one
					coverable: b.currency === plan.main
				};
			}),
			...plan.goals
				.filter((g) => g.perPayday > 0 && (!replay || g.createdOn <= payday))
				.map((g) => ({
					kind: 'goal' as const,
					refId: g.id,
					label: g.name,
					amount: g.perPayday,
					accountId: g.accountId,
					deferrable: false
				}))
		];
		// A bill that comes to nothing needs no money moved, and the engine refuses an amount of zero
		const needed = commitments.filter((c) => c.amount > 0);
		if (unrated) {
			notes.push({ kind: 'unrated', payday, currency: unrated });
			continue;
		}
		try {
			const at = funded ? fundingAt(plan, flows, payday, today) : null;
			const split = proposeSplit({
				payday,
				pay: inc.expectedAmount,
				incomeAccountId: inc.accountId,
				commitments: needed,
				rules,
				goalAccounts,
				...(at ? { available: at.available, links: at.links } : {})
			});
			if (split.covered.length + split.funded.length + split.unfunded.length > 0)
				funding.push({
					incomeId: inc.id,
					payday,
					covered: split.covered,
					funded: split.funded,
					unfunded: split.unfunded
				});
			// A short pay still goes where the engine would put it first: the moves are what the pay can fund, in the engine's order
			if (split.status === 'shortfall') notes.push({ kind: 'shortfall', payday, gap: split.gap });
			const transfers =
				split.status === 'shortfall' ? bestEffortTransfers(split, inc.accountId) : split.transfers;
			for (const t of transfers)
				flows.push({
					kind: 'move',
					origin: 'split',
					refId: inc.id,
					date: payday,
					label: t.labels.join(', ') || 'Payday split',
					accountId: t.fromAccountId,
					accountName: nameOf(t.fromAccountId),
					toAccountId: t.toAccountId,
					toAccountName: nameOf(t.toAccountId),
					currency: plan.main,
					amount: t.amount
				});
		} catch (e) {
			if (!(e instanceof RangeError)) throw e;
			notes.push({ kind: 'split_error', payday, message: e.message });
		}
	}

	// Pretend entries of a what-if: the past ones only in a replay, the rest only in the future
	for (const e of plan.whatIf?.extra ?? []) {
		if (e.date < from || e.date > to) continue;
		if (replay ? e.date >= today : e.date < today) continue;
		flows.push({
			kind: e.kind,
			origin: 'pretend',
			date: e.date,
			label: e.label,
			accountId: e.accountId,
			accountName: nameOf(e.accountId),
			currency: e.currency,
			amount: e.amount
		});
	}
	return funded
		? { flows, unknown, notes, funding, brokenLinks: planLinks(plan).broken }
		: { flows, unknown, notes };
}
