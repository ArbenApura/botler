// THE PAYDAY SPLIT ENGINE: A PURE FUNCTION FROM THE PAY, THE COMMITMENTS AND THE RULES TO A SPLIT THAT SUMS EXACTLY TO THE PAY.
// Order: bills, the parents' share and goal contributions first (commitments), then the rules by position: fixed amounts, then
// percentages (of the pay, or of what is left after commitments and fixed amounts), then "the rest". What no rule claims goes to
// the "rest" rule; with none, to the first rule; with no rules at all, to the default account. All amounts are integer centavos
// and a percentage is floored, so the leftover centavos land on that one place, the same way every time.
// When the pay cannot cover it all, nothing is allocated: the result is the gap and what could be cut, and the person decides.

// -- TYPES -- //
import type { ManilaDate } from './dates';
import type { Rule } from './rules';
// -- MODULES -- //
import { isCentavos, mulDiv } from './money';
import { rulesFor, validateRules } from './rules';

// -- TYPES -- //

export type Commitment = {
	kind: 'bill' | 'parents' | 'goal';
	/** The bill id, or the goal id for a goal. */
	refId: string;
	label: string;
	amount: number;
	/** The account the money must be in to pay it. */
	accountId: string;
	/** A bill the person can push to the next payday if they have to. */
	deferrable: boolean;
};

export type SplitInput = {
	payday: ManilaDate;
	pay: number;
	/** The account the pay lands in. */
	incomeAccountId: string;
	/** Where money no rule claims goes when there are no rules. Defaults to the income account. */
	defaultAccountId?: string;
	commitments: readonly Commitment[];
	rules: readonly Rule[];
	/** The account that holds each goal, by goal id. */
	goalAccounts: Readonly<Record<string, string>>;
};

export type SplitLineKind = 'bill' | 'parents' | 'goal' | 'rule' | 'rest' | 'leftover';

export type SplitLine = {
	kind: SplitLineKind;
	/** The bill, goal or rule behind the line. */
	refId: string | null;
	label: string;
	amount: number;
	accountId: string;
	goalId: string | null;
};

export type CutOption = {
	kind: SplitLineKind;
	refId: string | null;
	label: string;
	amount: number;
};

/** One tap for the person: move this much from the account the pay landed in to another. */
export type Transfer = {
	fromAccountId: string;
	toAccountId: string;
	amount: number;
	labels: string[];
};

export type SplitResult =
	| {
			status: 'ok';
			pay: number;
			lines: SplitLine[];
			transfers: Transfer[];
			/** What stays in the income account. */
			staysInIncomeAccount: number;
	  }
	| {
			status: 'shortfall';
			pay: number;
			/** How much more the pay would need to be. */
			gap: number;
			lines: SplitLine[];
			/** Things the person can cut or defer, goals first, then deferrable bills, then rules. */
			cutOptions: CutOption[];
			transfers: [];
			staysInIncomeAccount: 0;
	  };

// -- FUNCTIONS -- //

const sum = (xs: readonly { amount: number }[]) => xs.reduce((s, x) => s + x.amount, 0);

/** Proposes the split. Throws a RangeError for input that is not valid (the caller shows it as a bad request). */
export function proposeSplit(input: SplitInput): SplitResult {
	if (!isCentavos(input.pay) || input.pay <= 0) throw new RangeError('The pay must be above zero.');
	for (const c of input.commitments)
		if (!isCentavos(c.amount) || c.amount <= 0)
			throw new RangeError(`"${c.label}" needs an amount above zero.`);
	const rules = rulesFor(input.rules, input.payday);
	// Fixed amounts above the pay are not an invalid rule set: they are a shortfall, with the gap and the cut options below
	const problems = validateRules(rules);
	if (problems[0]) throw new RangeError(problems[0]);

	const commitmentLines: SplitLine[] = input.commitments.map((c) => ({
		kind: c.kind,
		refId: c.refId,
		label: c.label,
		amount: c.amount,
		accountId: c.accountId,
		goalId: c.kind === 'goal' ? c.refId : null
	}));
	const committed = sum(commitmentLines);

	const where = (r: Rule) => {
		if (r.target.kind === 'account') return { accountId: r.target.id, goalId: null };
		const accountId = input.goalAccounts[r.target.id];
		if (!accountId) throw new RangeError('A rule points at a goal that has no account.');
		return { accountId, goalId: r.target.id };
	};
	const ruleLine = (r: Rule, amount: number, kind: SplitLineKind = 'rule'): SplitLine => ({
		kind,
		refId: r.id,
		label: r.label ?? 'Rule',
		amount,
		...where(r)
	});

	// Fixed amounts, then percentages
	const byRule = new Map<string, SplitLine>();
	let fixedTotal = 0;
	for (const r of rules)
		if (r.mode === 'fixed') {
			byRule.set(r.id, ruleLine(r, r.amount ?? 0));
			fixedTotal += r.amount ?? 0;
		}
	const afterFixed = Math.max(input.pay - committed - fixedTotal, 0);
	let percentTotal = 0;
	for (const r of rules)
		if (r.mode === 'percent') {
			const base = r.base === 'pay' ? input.pay : afterFixed;
			const amount = mulDiv(base, r.basisPoints ?? 0, 10_000);
			byRule.set(r.id, ruleLine(r, amount));
			percentTotal += amount;
		}

	const need = committed + fixedTotal + percentTotal;
	const inRuleOrder = () => rules.flatMap((r) => byRule.get(r.id) ?? []);

	if (need > input.pay) {
		const lines = [...commitmentLines, ...inRuleOrder()].filter((l) => l.amount > 0);
		const cut = (l: SplitLine): CutOption => ({
			kind: l.kind,
			refId: l.refId,
			label: l.label,
			amount: l.amount
		});
		const deferrable = new Set(input.commitments.filter((c) => c.deferrable).map((c) => c.refId));
		return {
			status: 'shortfall',
			pay: input.pay,
			gap: need - input.pay,
			lines,
			cutOptions: [
				...commitmentLines.filter((l) => l.kind === 'goal').map(cut),
				...commitmentLines
					.filter((l) => l.kind === 'bill' && deferrable.has(l.refId ?? ''))
					.map(cut),
				...inRuleOrder()
					.filter((l) => l.amount > 0)
					.map(cut)
			],
			transfers: [],
			staysInIncomeAccount: 0
		};
	}

	// What no fixed or percentage rule claimed
	const leftover = input.pay - need;
	const restRule = rules.find((r) => r.mode === 'rest');
	let extra: SplitLine | null = null;
	if (restRule) byRule.set(restRule.id, ruleLine(restRule, leftover, 'rest'));
	else if (leftover > 0) {
		const first = rules[0];
		const firstLine = first ? byRule.get(first.id) : undefined;
		if (firstLine) firstLine.amount += leftover;
		else
			extra = {
				kind: 'leftover',
				refId: null,
				label: 'Left over',
				amount: leftover,
				accountId: input.defaultAccountId ?? input.incomeAccountId,
				goalId: null
			};
	}

	const lines = [...commitmentLines, ...inRuleOrder(), ...(extra ? [extra] : [])].filter(
		(l) => l.amount > 0
	);
	if (sum(lines) !== input.pay) throw new Error('The split does not add up to the pay.');

	const moves = new Map<string, Transfer>();
	let stays = 0;
	for (const l of lines) {
		if (l.accountId === input.incomeAccountId) {
			stays += l.amount;
			continue;
		}
		const t = moves.get(l.accountId) ?? {
			fromAccountId: input.incomeAccountId,
			toAccountId: l.accountId,
			amount: 0,
			labels: []
		};
		t.amount += l.amount;
		t.labels.push(l.label);
		moves.set(l.accountId, t);
	}
	return {
		status: 'ok',
		pay: input.pay,
		lines,
		transfers: [...moves.values()],
		staysInIncomeAccount: stays
	};
}

/**
 * What a short pay can still do. The engine allocates nothing on a shortfall (the person decides what to cut), but a forecast must still
 * say where the money will sit, so this walks the same lines in the same order (commitments, then rules by position) and gives each what
 * is left of the pay, so the last line that fits gets a part and the rest get nothing. It never moves more than the pay.
 */
export function bestEffortTransfers(
	result: Extract<SplitResult, { status: 'shortfall' }>,
	incomeAccountId: string
): Transfer[] {
	let left = result.pay;
	const moves = new Map<string, Transfer>();
	for (const l of result.lines) {
		const amount = Math.min(l.amount, left);
		if (amount <= 0) continue;
		left -= amount;
		if (l.accountId === incomeAccountId) continue;
		const t = moves.get(l.accountId) ?? {
			fromAccountId: incomeAccountId,
			toAccountId: l.accountId,
			amount: 0,
			labels: []
		};
		t.amount += amount;
		t.labels.push(l.label);
		moves.set(l.accountId, t);
	}
	return [...moves.values()];
}
