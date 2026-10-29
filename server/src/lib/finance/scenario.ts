// A WHAT-IF: CHANGES TO THE MONEY PLAN THAT ARE NEVER SAVED, APPLIED TO THE LOADED PLAN BEFORE THE FLOWS ARE MADE (BTL-20261029-0117)
// The app builds one from switches, amounts and ready-made presets; the assistant can send the same shape. It changes only the replay of
// the past and the simulation of the future, never what was recorded. Rules that hold:
// - An id that is not one of the person's own (or not active) is ignored and named back, never an error and never someone else's row.
// - Every amount is a whole number of minor units between 1 and 10^12, so sums of 50 pretend entries over 5 years stay safe integers.
// - An empty what-if changes nothing: the plan comes back as it was.

// -- TYPES -- //
import type { ManilaDate } from './dates';
import type { PlanData, PretendEntry, WhatIf } from './planFlows';

// -- TYPES -- //

export type Scenario = {
	/** Ids switched off: paydays (incomes), bills, rules and goals. */
	off?: { incomes?: string[]; bills?: string[]; rules?: string[]; goals?: string[] };
	/** A pay that would be another amount, in the main currency. */
	incomeAmounts?: { id: string; amount: number }[];
	/** A bill that would be another amount on every date, in its own currency. */
	billAmounts?: { id: string; amount: number }[];
	/** Single paydays that would not come. */
	skipPaydays?: { incomeId: string; date: ManilaDate }[];
	/** Every bill paid this many days late (0 to 60). */
	billDelayDays?: number;
	/** Deferrable bills wait for the next payday. */
	deferDeferrable?: boolean;
	/** One-off pretend money in or out. */
	extra?: PretendEntry[];
};

export type AppliedScenario = {
	plan: PlanData;
	/** Ids in the what-if that are not the person's (or not active): left out. */
	ignored: string[];
	/** How many changes the what-if makes, for the band in the app and the notes. */
	changes: number;
};

// -- CONSTANTS -- //

export const SCENARIO_LIMITS = {
	ids: 100,
	entries: 50,
	maxAmount: 1_000_000_000_000,
	maxDelayDays: 60,
	labelChars: 40
} as const;

// -- FUNCTIONS -- //

/** How many separate changes a what-if makes. Zero for an empty one. */
export function scenarioChanges(s: Scenario | undefined): number {
	if (!s) return 0;
	const off = s.off ?? {};
	return (
		(off.incomes?.length ?? 0) +
		(off.bills?.length ?? 0) +
		(off.rules?.length ?? 0) +
		(off.goals?.length ?? 0) +
		(s.incomeAmounts?.length ?? 0) +
		(s.billAmounts?.length ?? 0) +
		(s.skipPaydays?.length ?? 0) +
		((s.billDelayDays ?? 0) > 0 ? 1 : 0) +
		(s.deferDeferrable ? 1 : 0) +
		(s.extra?.length ?? 0)
	);
}

/** The plan as the what-if would have it. Throws a RangeError for an amount or a delay out of bounds. */
export function applyScenario(plan: PlanData, s: Scenario | undefined): AppliedScenario {
	const changes = scenarioChanges(s);
	if (!s || changes === 0) return { plan, ignored: [], changes: 0 };
	const ignored = new Set<string>();
	const delay = s.billDelayDays ?? 0;
	if (!Number.isInteger(delay) || delay < 0 || delay > SCENARIO_LIMITS.maxDelayDays)
		throw new RangeError(`Bills can be late by 0 to ${SCENARIO_LIMITS.maxDelayDays} days.`);
	const amountOk = (n: number) => Number.isInteger(n) && n >= 1 && n <= SCENARIO_LIMITS.maxAmount;
	for (const a of [...(s.incomeAmounts ?? []), ...(s.billAmounts ?? []), ...(s.extra ?? [])])
		if (!amountOk(a.amount))
			throw new RangeError(`A what-if amount is between 1 and ${SCENARIO_LIMITS.maxAmount}.`);

	// Ids that are the person's own; anything else is named back and left out
	const known = (ids: readonly string[] | undefined, own: ReadonlySet<string>) => {
		const out = new Set<string>();
		for (const id of ids ?? []) (own.has(id) ? out : ignored).add(id);
		return out;
	};
	const incomeIds = new Set(plan.incomes.map((i) => i.id));
	const billIds = new Set(plan.bills.map((b) => b.id));
	const ruleIds = new Set(plan.rules.map((r) => r.id));
	const goalIds = new Set(plan.goals.map((g) => g.id));
	const activeAccounts = new Set(plan.accounts.filter((a) => !a.archived).map((a) => a.id));

	const offIncomes = known(s.off?.incomes, incomeIds);
	const offBills = known(s.off?.bills, billIds);
	const offRules = known(s.off?.rules, ruleIds);
	const offGoals = known(s.off?.goals, goalIds);
	const payAmounts = new Map<string, number>();
	for (const a of s.incomeAmounts ?? [])
		if (incomeIds.has(a.id)) payAmounts.set(a.id, a.amount);
		else ignored.add(a.id);
	const billAmounts = new Map<string, number>();
	for (const a of s.billAmounts ?? [])
		if (billIds.has(a.id)) billAmounts.set(a.id, a.amount);
		else ignored.add(a.id);
	const skip = new Set<string>();
	for (const p of s.skipPaydays ?? [])
		if (incomeIds.has(p.incomeId)) skip.add(`${p.incomeId}|${p.date}`);
		else ignored.add(p.incomeId);
	const extra: PretendEntry[] = [];
	for (const e of s.extra ?? [])
		if (activeAccounts.has(e.accountId)) extra.push(e);
		else ignored.add(e.accountId);

	const whatIf: WhatIf = {
		skip,
		billAmounts,
		delayDays: delay,
		deferDeferrable: s.deferDeferrable === true,
		extra
	};
	return {
		plan: {
			...plan,
			incomes: plan.incomes
				.filter((i) => !offIncomes.has(i.id))
				.map((i) =>
					payAmounts.has(i.id) ? { ...i, expectedAmount: payAmounts.get(i.id) ?? null } : i
				),
			bills: plan.bills.filter((b) => !offBills.has(b.id)),
			goals: plan.goals.filter((g) => !offGoals.has(g.id)),
			// A rule into a switched-off goal goes with it, as the payday split leaves out a rule on an inactive goal
			rules: plan.rules.filter(
				(r) => !offRules.has(r.id) && !(r.target.kind === 'goal' && offGoals.has(r.target.id))
			),
			whatIf
		},
		ignored: [...ignored].sort(),
		changes
	};
}
