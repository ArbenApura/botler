// WHAT A PAYDAY SPLIT MAY TAKE FROM MONEY ALREADY IN AN ACCOUNT, AND WHAT A RULE THAT SAVES FOR A BILL HAS SET ASIDE (BTL-20261029-0119).
// Pure functions, no database. Rules that hold:
// - A rule saves for a bill only when the rule is fixed and active, points at an account, and the bill is switched on, in the main currency
//   and paid from that same account. Any other link is broken: the bill is funded from the pay as before and the link is named.
// - What a linked rule has set aside for the bill's next date is the rule's amount for every payday after the bill's previous date (and
//   from the rule's own start), before the payday being split, never more than the bill. Once that date is paid nothing is set aside.
// - What an account can still give to its bills is the money the caller counts in it (finance/planFlows.ts: today's balance less what leaves
//   it before the payday, never money still to arrive), less its minimum balance and what its linked rules had set aside, never below zero.
//   An account that holds a goal gives nothing: its money is saved for the goal.

// -- TYPES -- //
import type { ManilaDate } from './dates';

// -- TYPES -- //

/** What the link check needs of a rule row. */
export type LinkRuleLike = {
	id: string;
	label: string | null;
	mode: 'fixed' | 'percent' | 'rest';
	status: string;
	amount: number | null;
	targetAccountId: string | null;
	effectiveFrom: ManilaDate;
	fundsBillId: string | null;
};

/** What the link check needs of a bill row. */
export type LinkBillLike = {
	id: string;
	name: string;
	active: boolean;
	accountId: string;
	currency: string;
};

/** A rule that saves for a bill, checked. */
export type FundingLink = {
	ruleId: string;
	ruleLabel: string;
	billId: string;
	billName: string;
	accountId: string;
	/** What the rule puts in on each payday, minor units of the main currency. */
	perPayday: number;
	effectiveFrom: ManilaDate;
};

/** A link that cannot count, and why, in plain words. */
export type BrokenLink = {
	ruleId: string;
	ruleLabel: string;
	billId: string;
	billName: string | null;
	reason: string;
};

/** A rule that probably saves for a bill but is not linked to it, so the pay is asked for both. */
export type UnlinkedSaver = {
	ruleId: string;
	ruleLabel: string;
	billId: string;
	billName: string;
	/** What the rule puts in on each payday, minor units of the main currency. */
	perPayday: number;
};

// -- FUNCTIONS -- //

/** The first word of a name, lower case, when it is long enough to mean something. */
const firstWord = (name: string | null): string | null => {
	const w = (name ?? '').trim().split(/\s+/)[0]?.toLowerCase() ?? '';
	return w.length >= 3 ? w : null;
};

/**
 * The fixed rules that fill the account which pays a bill of the same first word (a rule "Parents" and a bill "Parents allowance" both on
 * RCBC) but are not linked to it. Such a rule is meant to save for that bill, yet the split asks the pay for the bill AND for the rule, so the
 * same money is counted twice (BTL-20261106-1502). A hint only: the person or the assistant links the rule to the bill and it counts once.
 * A bill another rule already saves for is not offered again.
 */
export function findUnlinkedSavers(
	rules: readonly LinkRuleLike[],
	bills: readonly LinkBillLike[],
	main: string
): UnlinkedSaver[] {
	const taken = new Set(
		rules.flatMap((r) => (r.status === 'active' && r.fundsBillId ? [r.fundsBillId] : []))
	);
	const out: UnlinkedSaver[] = [];
	for (const r of rules) {
		const word = firstWord(r.label);
		if (!word || r.status !== 'active' || r.fundsBillId) continue;
		if (r.mode !== 'fixed' || !r.amount || r.amount <= 0 || !r.targetAccountId) continue;
		const bill = bills.find(
			(b) =>
				b.active &&
				!taken.has(b.id) &&
				b.accountId === r.targetAccountId &&
				b.currency === main &&
				firstWord(b.name) === word
		);
		if (!bill) continue;
		taken.add(bill.id);
		out.push({
			ruleId: r.id,
			ruleLabel: r.label ?? 'A rule',
			billId: bill.id,
			billName: bill.name,
			perPayday: r.amount
		});
	}
	return out;
}

/** The name a rule is shown by: its label, or the bill it saves for. */
const ruleName = (r: LinkRuleLike, bill: LinkBillLike | undefined) =>
	r.label ?? (bill ? `Saving for ${bill.name}` : 'A rule');

/**
 * Splits the active rules that point at a bill into links that count and broken ones. A rule that is only proposed or retired funds
 * nothing and is not reported.
 */
export function checkLinks(
	rules: readonly LinkRuleLike[],
	bills: readonly LinkBillLike[],
	main: string
): { links: FundingLink[]; broken: BrokenLink[] } {
	const byId = new Map(bills.map((b) => [b.id, b]));
	const links: FundingLink[] = [];
	const broken: BrokenLink[] = [];
	for (const r of rules) {
		if (r.status !== 'active' || !r.fundsBillId) continue;
		const b = byId.get(r.fundsBillId);
		const base = {
			ruleId: r.id,
			ruleLabel: ruleName(r, b),
			billId: r.fundsBillId,
			billName: b?.name ?? null
		};
		let reason: string | null = null;
		if (!b || !b.active) reason = 'the bill is switched off or gone';
		else if (r.mode !== 'fixed' || !r.amount || r.amount <= 0)
			reason = 'only a fixed amount can save for a bill';
		else if (!r.targetAccountId) reason = 'the rule puts money into a goal, not an account';
		else if (b.currency !== main) reason = `the bill is in ${b.currency}, not ${main}`;
		else if (b.accountId !== r.targetAccountId)
			reason = 'the bill is paid from another account than the one the rule fills';
		if (reason || !b || !r.amount || !r.targetAccountId) {
			broken.push({ ...base, reason: reason ?? 'the link cannot count' });
			continue;
		}
		links.push({
			...base,
			billName: b.name,
			accountId: r.targetAccountId,
			perPayday: r.amount,
			effectiveFrom: r.effectiveFrom
		});
	}
	return { links, broken };
}

/**
 * What a linked rule has set aside for the bill's next date, as of the start of `payday`: its amount for every payday strictly after
 * `previousDue` (the bill's date before that one, or null for none), on or after the rule's start and before `payday`, at most `billAmount`.
 * Zero when that date is already paid.
 */
export function reservedFor(
	link: Pick<FundingLink, 'perPayday' | 'effectiveFrom'>,
	billAmount: number,
	previousDue: ManilaDate | null,
	paydays: readonly ManilaDate[],
	payday: ManilaDate,
	paid = false
): number {
	if (paid || billAmount <= 0) return 0;
	let n = 0;
	for (const p of new Set(paydays))
		if (p < payday && p >= link.effectiveFrom && (previousDue === null || p > previousDue)) n++;
	return Math.min(n * link.perPayday, billAmount);
}

/** What an account can still give to its bills at the start of a payday. */
export function availableFor(a: {
	projected: number;
	minBalance: number;
	reserved: number;
	holdsGoal: boolean;
}): number {
	if (a.holdsGoal) return 0;
	return Math.max(0, a.projected - a.minBalance - a.reserved);
}
