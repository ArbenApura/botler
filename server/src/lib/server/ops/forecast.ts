// THE cashflow_forecast VERB: TODAY'S BALANCES, THE PAYDAYS, THE UNPAID BILLS AND THE APPROVED PAYDAY RULES, GATHERED INSIDE THE CALLER'S OWN
// TRANSACTION AND HANDED TO THE PURE FORECAST (finance/forecast.ts). It reads only. The numbers come from the same sources as everything else:
// the balances are the ledger's, the bills are bills.ts dueBills (per-date changes and paying accounts included, paid ones left out), the
// paydays are the income schedules, and the moves are what the payday split engine makes of the active rules. A payday whose split cannot
// be worked out (a bill with no amount yet, a missing rate) adds no moves and is named in the notes. A shortfall still moves what the pay can fund.
// Since BTL-20261029-0117 the plan is loaded once (ops/planData.ts) and the flows come from the pure finance/planFlows.ts in its future
// mode, shared with the simulation; the numbers and the notes are the same as before.
// Since BTL-20261029-0119 it passes today's balances, so each payday split first pays bills from money already in their account and from the
// rules that save for them: a bill that is covered makes no move at all. The answer lists those parts per payday (funding) and the rules
// whose link to a bill cannot count (brokenLinks), with a sentence for each in the notes.

// -- TYPES -- //
import type { Ctx } from './context';
import type { Forecast, ForecastFlow, ForecastWallet, Warning } from '../../finance/forecast';
import type { BrokenLink, UnlinkedSaver } from '../../finance/funding';
import type { PaydayFunding, PlanNote } from '../../finance/planFlows';
// -- MODULES -- //
import { diffDays, dayStart, toLocalDate } from '../../finance/dates';
import { forecast, MAX_FORECAST_DAYS } from '../../finance/forecast';
import { placeBills, planFlows } from '../../finance/planFlows';
import { cashflowForecastInput } from '../db/zod';
import { refreshInBackground } from '../fx/store';
import { OpsError, run } from './context';
import { balanceFor, walletCurrencies } from './ledger';
import { loadPlan } from './planData';
import { parse } from './shared';

// -- TYPES -- //

export type ForecastView = Forecast & {
	today: string;
	/** Plain sentences about what was left out or could not be worked out. Read them before quoting a total. */
	notes: string[];
	rates: { asOf: string | null; stale: boolean };
	/** True when the lists of each period's money in, out and moved were cut to keep the answer short. The totals and wallets are whole. */
	itemsOmitted?: boolean;
	/**
	 * Per payday, the parts of its bills that did not come from the pay: covered (paid from money already in the account, so nothing moves
	 * for it), funded (paid from what a rule saves for it) and unfunded (what that rule's savings do not reach, taken from the pay).
	 */
	funding: ForecastFunding[];
	/** Rules that point at a bill but cannot save for it, and why. */
	brokenLinks: BrokenLink[];
};

// -- CONSTANTS -- //

// An unpaid bill up to 31 days past due still counts: it is money that has to go out (OVERDUE_DAYS in finance/planFlows.ts).

/** The answer is cut to totals and wallets past this size, so a tool result is never truncated in the middle of a list. */
const MAX_VIEW_CHARS = 13_000;

// -- FUNCTIONS -- //

/** The sentence of a payday note, as the forecast has always worded it. */
export function noteText(n: PlanNote): string {
	switch (n.kind) {
		case 'missing_amount':
			return `The payday split of ${n.payday} is not in the moves: "${n.bill}" has no amount yet.`;
		case 'unrated':
			return `The payday split of ${n.payday} is not in the moves: ${n.currency} has no exchange rate.`;
		case 'shortfall':
			return `The pay of ${n.payday} is short by ${n.gap} (smallest unit): its moves fund bills and goals first, then the rules in their order until the pay runs out. That is what the pay alone cannot fund: money already in an account may still cover a bill, so read the warnings and the wallet lines before saying money is missing.`;
		case 'split_error':
			return `The payday split of ${n.payday} could not be worked out: ${n.message}`;
	}
}

/** A payday's parts of its bills that did not come from the pay, short: names and amounts in the smallest unit, no ids. */
export type ForecastFunding = {
	payday: string;
	/** Paid from money already in the account, so nothing moves for it. */
	covered: { bill: string; account: string; amount: number }[];
	/** Paid from what a rule saves for the bill. */
	funded: { bill: string; rule: string; amount: number }[];
	/** Beyond what the rule saved, so it comes from the pay. */
	unfunded: { bill: string; amount: number }[];
};

/** The funding of the paydays in the short form of the answer. */
export function shortFunding(
	funding: readonly PaydayFunding[],
	nameOf: (accountId: string) => string
): ForecastFunding[] {
	return funding.map((p) => ({
		payday: p.payday,
		covered: p.covered.map((c) => ({
			bill: c.label,
			account: nameOf(c.accountId),
			amount: c.amount
		})),
		funded: p.funded.map((x) => ({ bill: x.label, rule: x.ruleLabel, amount: x.amount })),
		unfunded: p.unfunded.map((u) => ({ bill: u.label, amount: u.amount }))
	}));
}

/** The sentences that tell the reader where to find what the pay did not fund, and which links to bills cannot count. */
export function fundingNotes(
	funding: readonly PaydayFunding[],
	broken: readonly BrokenLink[],
	unlinked: readonly UnlinkedSaver[] = []
) {
	const out: string[] = [];
	// A rule that saves into the account that pays a bill of its name, not linked to it: the pay is asked for the bill and for the rule
	for (const u of unlinked)
		out.push(
			`The rule "${u.ruleLabel}" saves ${u.perPayday} (smallest unit) every payday into the account that pays "${u.billName}", but it is not linked to that bill, so the pay is asked for the bill AND for the rule: the same money counted twice, and a pay can look short when it is not. Offer to link the rule to the bill (rule_update, fundsBillId), and it counts once.`
		);
	if (funding.length > 0)
		out.push(
			'funding: per payday, bill money already in its account (covered, nothing moves), saved by a rule (funded) or still needed. Quote it.'
		);
	for (const b of broken)
		out.push(
			`The rule "${b.ruleLabel}" points at "${b.billName ?? 'a bill'}" but cannot save for it: ${b.reason}. That bill is funded from the pay.`
		);
	return out;
}

/**
 * Why each wallet that goes below zero does: the bills that leave it that day and what came in before. The model quotes this and never
 * has to trace it by hand (in the chat of 6 Nov the first guess at GCash was the wrong bill, and it took three answers to find the right one).
 */
export function warningNotes(
	warnings: readonly Warning[],
	flows: readonly ForecastFlow[],
	wallets: readonly ForecastWallet[],
	from: string
): string[] {
	const out: string[] = [];
	for (const w of warnings) {
		if (w.already) {
			out.push(`${w.accountName} is already below zero today (${w.balance}, smallest unit).`);
			continue;
		}
		const sameWallet = (f: ForecastFlow) =>
			f.accountId === w.accountId && f.currency === w.currency;
		const leaving = flows.filter((f) => f.kind === 'out' && f.date === w.date && sameWallet(f));
		const movedAway = flows.filter((f) => f.kind === 'move' && f.date === w.date && sameWallet(f));
		const moves = flows.filter(
			(f) =>
				f.kind === 'move' &&
				f.toAccountId === w.accountId &&
				f.currency === w.currency &&
				f.date >= from &&
				f.date <= w.date
		);
		const started = wallets.find((x) => x.accountId === w.accountId && x.currency === w.currency);
		const days = [...new Set(moves.map((m) => m.date))];
		const putIn = moves.reduce((s, m) => s + m.amount, 0);
		const pays = [...leaving, ...movedAway].map((f) => `${f.label} ${f.amount}`);
		out.push(
			`${w.accountName} goes below zero on ${w.date} (${w.balance}, smallest unit). It held ${started?.balance ?? 0} today; ` +
				`${days.length > 0 ? `${putIn} was put in on ${days.length} payday${days.length > 1 ? 's' : ''} before it (${days.join(', ')})` : 'nothing is put in before it'}; ` +
				`that day it pays ${pays.length > 0 ? pays.join(', ') : 'nothing listed'}. ` +
				`If a rule saves for that bill, it needs more paydays or a bigger amount, or the bill belongs on another account.`
		);
	}
	return out;
}

/** The bills the plan counts as paid today although they are overdue and still unpaid (finance/planFlows.ts words them "(late, was due DATE)"). */
export function overdueNotes(flows: readonly ForecastFlow[]): string[] {
	const late = flows.filter(
		(f) => f.kind === 'out' && /\(late, was due \d{4}-\d{2}-\d{2}\)/.test(f.label)
	);
	if (late.length === 0) return [];
	return [
		`OVERDUE and still unpaid, counted as going out today so the totals are safe: ${late.map((f) => `${f.label} ${f.amount}`).join(', ')}. Say they are overdue, never that they are paid.`
	];
}

/**
 * The forecast from today to a date. Weeks start on the person's chosen day. The caller sees only their own data: every read runs in their
 * transaction, and the gathering is the same as the split's.
 */
export async function cashflowForecast(ctx: Ctx, raw: unknown): Promise<ForecastView> {
	const input = parse(cashflowForecastInput, raw);
	const now = new Date();
	const today = toLocalDate(now);
	if (input.to < today) throw new OpsError('INVALID', 'The end date is before today.');
	if (diffDays(input.to, today) + 1 > MAX_FORECAST_DAYS)
		throw new OpsError('INVALID', `A forecast covers at most ${MAX_FORECAST_DAYS} days.`);
	const group = input.group ?? 'week';

	const gathered = await run(ctx, async (tx, userId) => {
		// The plan once, in memory: the bill dates of every payday come from it, not from a query each (ops/planData.ts)
		const { settings, status, plan, accounts } = await loadPlan(tx, userId, {
			now,
			incomeSince: dayStart(today)
		});
		const notes: string[] = [];

		// The balance of every wallet of every active account, now
		const wallets: ForecastWallet[] = [];
		for (const a of accounts.filter((x) => x.archivedAt === null))
			for (const currency of await walletCurrencies(tx, userId, a.id, a.currency))
				wallets.push({
					accountId: a.id,
					accountName: a.name,
					currency,
					balance: (await balanceFor(tx, userId, a.id, currency, now)).balance
				});

		// Unpaid bills (the late ones today), paydays and the payday moves of the active rules: the pure flows of the plan. Today's balances
		// in the main currency let each split pay bills from money already there first
		const balances = new Map(
			wallets.filter((x) => x.currency === settings.currency).map((x) => [x.accountId, x.balance])
		);
		const made = planFlows(
			{ ...plan, accounts: plan.accounts.filter((x) => !x.archived), balances },
			{ mode: 'future', from: today, to: input.to, today }
		);
		for (const n of made.notes) notes.push(noteText(n));
		// Bills go on the wallets that exist, the same way the calendar's forecast does; one with no wallet to be paid from is named
		const placed = placeBills(made.flows, wallets, settings.currency, status.rates);
		if (placed.unplaced.length > 0)
			notes.push(
				`${placed.unplaced.length} bill payment${placed.unplaced.length > 1 ? 's are' : ' is'} not in the balances: the account they are paid from holds no wallet to pay them (${[...new Set(placed.unplaced.map((x) => x.label))].slice(0, 5).join(', ')}).`
			);
		const names = new Map(accounts.map((a) => [a.id, a.name]));
		const funding = shortFunding(made.funding ?? [], (id) => names.get(id) ?? 'an account');
		const brokenLinks = made.brokenLinks ?? [];
		notes.push(...fundingNotes(made.funding ?? [], brokenLinks, made.unlinkedSavers ?? []));
		return {
			settings,
			status,
			wallets,
			flows: placed.flows.map(({ origin: _origin, refId: _refId, ...f }): ForecastFlow => f),
			unknown: made.unknown,
			notes,
			funding,
			brokenLinks
		};
	});
	refreshInBackground(ctx.handle, gathered.status);

	let result: Forecast;
	try {
		result = forecast({
			from: today,
			to: input.to,
			group,
			weekStart: gathered.settings.weekStartsOn,
			main: gathered.settings.currency,
			rates: gathered.status.rates,
			wallets: gathered.wallets,
			flows: gathered.flows,
			unknown: gathered.unknown
		});
	} catch (e) {
		if (e instanceof RangeError) throw new OpsError('INVALID', e.message);
		throw e;
	}
	const notes = [...gathered.notes];
	if (result.missing.length > 0)
		notes.push(
			`No exchange rate for ${result.missing.join(', ')}: those wallets and amounts are left out of every total.`
		);
	if (result.unknown.length > 0)
		notes.push(
			'Some pay or bills have no amount yet: they are listed under unknown and not counted.'
		);
	if (gathered.status.stale)
		notes.push('The exchange rates are older than a day; the totals use the stored ones.');
	notes.push(
		'Paid bills are not counted. Bills late by up to 31 days count today. A pay already recorded today is not counted again.'
	);
	notes.push(...warningNotes(result.warnings, gathered.flows, gathered.wallets, today));
	notes.push(...overdueNotes(gathered.flows));
	const view: ForecastView = {
		...result,
		today,
		notes,
		rates: { asOf: gathered.status.asOf, stale: gathered.status.stale },
		funding: gathered.funding,
		brokenLinks: gathered.brokenLinks
	};
	// A long answer is cut, never in the middle of a list: first the funding (the moves already leave covered bills out), then the lists
	const fits = (v: ForecastView) => JSON.stringify(v).length <= MAX_VIEW_CHARS;
	if (fits(view)) return view;
	const fewer: ForecastView = {
		...view,
		funding: [],
		notes:
			view.funding.length > 0
				? [
						...notes.filter((n) => !n.startsWith('funding: ')),
						`funding (bills paid from money already there or a rule's savings) is left out for length. Ask for a shorter range.`
					]
				: notes
	};
	if (fits(fewer)) return fewer;
	return {
		...fewer,
		itemsOmitted: true,
		notes: [
			...fewer.notes,
			'Too long to list every payment: the lists and funding are left out, the totals and wallets are whole. Ask for a shorter range to see the items.'
		],
		periods: view.periods.map((p) => ({ ...p, ins: [], outs: [], moves: [] })),
		funding: []
	};
}
