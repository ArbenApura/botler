// ALLOCATION RULES: WHERE THE MONEY LEFT AFTER BILLS GOES ON PAYDAY. A RULE IS A FIXED PESO AMOUNT, A PERCENTAGE, OR "THE REST".
// A rule carries its effective date, a version and what its percentage is taken of (the whole pay, or what is left after the bills).

// -- TYPES -- //
import type { ManilaDate } from './dates';

// -- TYPES -- //

export type RuleMode = 'fixed' | 'percent' | 'rest';
/** What a percentage is a share of: the whole pay, or what remains after bills, goals and fixed amounts. */
export type RuleBase = 'pay' | 'remaining';

export type Rule = {
	id: string;
	/** What the person sees on the split, for example "Savings". */
	label?: string;
	/** Rules run in this order, lowest first. */
	position: number;
	target: { kind: 'account' | 'goal'; id: string };
	mode: RuleMode;
	/** Centavos, for a fixed rule. */
	amount: number | null;
	/** Hundredths of a percent: 2000 is 20%. For a percent rule. */
	basisPoints: number | null;
	base: RuleBase;
	effectiveFrom: ManilaDate;
	version: number;
};

// -- CONSTANTS -- //

export const RULE_MODES = ['fixed', 'percent', 'rest'] as const;
export const RULE_BASES = ['pay', 'remaining'] as const;

// -- FUNCTIONS -- //

/** Every problem with a set of rules, in plain words. An empty list means the set can be saved. `pay` adds the fixed-above-pay check. */
export function validateRules(rules: readonly Rule[], pay?: number): string[] {
	const problems: string[] = [];
	let rest = 0;
	let fixedTotal = 0;
	const percent: Record<RuleBase, number> = { pay: 0, remaining: 0 };
	for (const r of rules) {
		if (r.mode === 'fixed') {
			if (!r.amount || !Number.isInteger(r.amount) || r.amount <= 0)
				problems.push('A fixed rule needs an amount above zero.');
			else fixedTotal += r.amount;
		} else if (r.mode === 'percent') {
			if (
				!r.basisPoints ||
				!Number.isInteger(r.basisPoints) ||
				r.basisPoints <= 0 ||
				r.basisPoints > 10_000
			)
				problems.push('A percentage rule needs a share between 0.01% and 100%.');
			else percent[r.base] += r.basisPoints;
		} else {
			rest++;
		}
	}
	if (rest > 1) problems.push('Only one rule can take "the rest".');
	if (percent.pay > 10_000) problems.push('The percentages of the pay add up to more than 100%.');
	if (percent.remaining > 10_000)
		problems.push('The percentages of what is left add up to more than 100%.');
	if (pay !== undefined && fixedTotal > pay)
		problems.push('The fixed amounts are more than the pay.');
	return problems;
}

/**
 * Things that are allowed but probably not meant, in plain words. A percentage of the pay and a percentage of what is left after bills are
 * both worked out from the same pay (the second is not taken after the first), so together they can ask for more than the pay when the bills
 * are small: the split then comes back short. An empty list means nothing to say. Saved rules are not refused for these.
 */
export function ruleWarnings(rules: readonly Rule[]): string[] {
	const warnings: string[] = [];
	let pay = 0;
	let remaining = 0;
	for (const r of rules) {
		if (r.mode !== 'percent' || !r.basisPoints || r.basisPoints <= 0) continue;
		if (r.base === 'pay') pay += r.basisPoints;
		else remaining += r.basisPoints;
	}
	// Each alone is already refused above 100%; here they are added: with no bills the share of what is left is the whole pay
	if (pay <= 10_000 && remaining <= 10_000 && pay + remaining > 10_000)
		warnings.push(
			'The percentages of the pay and the percentages of what is left add up to more than the pay when the bills are small, so the split can come back short.'
		);
	return warnings;
}

/** A rule's target is still there to receive money: a goal that is switched on, or an account that is not hidden. */
export type RuleTargets = {
	liveGoals: ReadonlySet<string>;
	hiddenAccounts: ReadonlySet<string>;
};

/** Whether the target of a rule can receive money today. */
export const ruleTargetIsLive = (
	target: { kind: 'account' | 'goal'; id: string },
	live: RuleTargets
): boolean =>
	target.kind === 'goal' ? live.liveGoals.has(target.id) : !live.hiddenAccounts.has(target.id);

/**
 * The rules that can be placed: those whose goal is switched off or whose account is hidden are left out, so money never goes to a place the
 * person no longer sees. The payday split, the forecast, the simulation and the calendar all keep their rules through this one filter.
 */
export function liveRules<T extends { target: { kind: 'account' | 'goal'; id: string } }>(
	rules: readonly T[],
	live: RuleTargets
): T[] {
	return rules.filter((r) => ruleTargetIsLive(r.target, live));
}

/** The rules that apply on a payday: effective by then, in order. */
export function rulesFor(rules: readonly Rule[], payday: ManilaDate): Rule[] {
	return rules
		.filter((r) => r.effectiveFrom <= payday)
		.sort((a, b) => a.position - b.position || (a.id < b.id ? -1 : 1));
}
