// THE cashflow_forecast VERB: TODAY'S BALANCES, THE PAYDAYS, THE UNPAID BILLS AND THE APPROVED PAYDAY RULES, GATHERED INSIDE THE CALLER'S OWN
// TRANSACTION AND HANDED TO THE PURE FORECAST (finance/forecast.ts). It reads only. The numbers come from the same sources as everything else:
// the balances are the ledger's, the bills are bills.ts dueBills (per-date changes and paying accounts included, paid ones left out), the
// paydays are the income schedules, and the moves are what the payday split engine makes of the active rules. A payday whose split cannot
// be worked out (a bill with no amount yet, a missing rate, a shortfall) adds no moves and is named in the notes.

// -- TYPES -- //
import type { Ctx } from './context';
import type {
	Forecast,
	ForecastFlow,
	ForecastUnknown,
	ForecastWallet
} from '../../finance/forecast';
import type { Schedule } from '../../finance/schedule';
import type { Commitment } from '../../finance/split';
// -- DEP-MODULES -- //
import { and, eq, gte, isNull, lt } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, diffDays, manilaStart, toManilaDate } from '../../finance/dates';
import { canConvert, convertUp } from '../../finance/fx';
import { forecast, MAX_FORECAST_DAYS } from '../../finance/forecast';
import { occurrencesBetween } from '../../finance/schedule';
import { proposeSplit } from '../../finance/split';
import { account, allocationRule, goal, incomeSchedule, ledgerTxn } from '../db/schema';
import { cashflowForecastInput } from '../db/zod';
import { loadRates, refreshInBackground } from '../fx/store';
import { dueBills } from './bills';
import { OpsError, run } from './context';
import { balanceFor, walletCurrencies } from './ledger';
import { toRule } from './rules';
import { readSettings } from './settings';
import { parse } from './shared';

// -- TYPES -- //

export type ForecastView = Forecast & {
	today: string;
	/** Plain sentences about what was left out or could not be worked out. Read them before quoting a total. */
	notes: string[];
	rates: { asOf: string | null; stale: boolean };
	/** True when the lists of each period's money in, out and moved were cut to keep the answer short. The totals and wallets are whole. */
	itemsOmitted?: boolean;
};

// -- CONSTANTS -- //

/** An unpaid bill this many days past due still counts: it is money that has to go out. */
const OVERDUE_DAYS = 31;

/** The answer is cut to totals and wallets past this size, so a tool result is never truncated in the middle of a list. */
const MAX_VIEW_CHARS = 13_000;

// -- FUNCTIONS -- //

/**
 * The forecast from today to a date. Weeks start on the person's chosen day. The caller sees only their own data: every read runs in their
 * transaction, and the gathering is the same as the split's.
 */
export async function cashflowForecast(ctx: Ctx, raw: unknown): Promise<ForecastView> {
	const input = parse(cashflowForecastInput, raw);
	const now = new Date();
	const today = toManilaDate(now);
	if (input.to < today) throw new OpsError('INVALID', 'The end date is before today.');
	if (diffDays(input.to, today) + 1 > MAX_FORECAST_DAYS)
		throw new OpsError('INVALID', `A forecast covers at most ${MAX_FORECAST_DAYS} days.`);
	const group = input.group ?? 'week';

	const gathered = await run(ctx, async (tx, userId) => {
		const settings = await readSettings(tx, userId);
		const status = await loadRates(tx, now);
		const notes: string[] = [];

		// The balance of every wallet of every active account, now
		const accounts = await tx
			.select()
			.from(account)
			.where(and(eq(account.userId, userId), isNull(account.archivedAt)));
		const names = new Map(accounts.map((a) => [a.id, a.name]));
		const wallets: ForecastWallet[] = [];
		for (const a of accounts)
			for (const currency of await walletCurrencies(tx, userId, a.id, a.currency))
				wallets.push({
					accountId: a.id,
					accountName: a.name,
					currency,
					balance: (await balanceFor(tx, userId, a.id, currency, now)).balance
				});
		const nameOf = (id: string) => names.get(id) ?? 'an account';

		const flows: ForecastFlow[] = [];
		const unknown: ForecastUnknown[] = [];

		// Unpaid bills: the late ones count today, the rest on their due date (a date the person moved is the date they gave)
		const late = await dueBills(tx, userId, addDays(today, -OVERDUE_DAYS), addDays(today, -1));
		const ahead = await dueBills(tx, userId, today, input.to);
		for (const b of [...late.filter((x) => !x.paid), ...ahead.filter((x) => !x.paid)]) {
			const date = b.dueDate < today ? today : b.dueDate;
			const label = b.dueDate < today ? `${b.name} (late, was due ${b.dueDate})` : b.name;
			if (b.amount === null || b.unknownAmount) {
				unknown.push({ kind: 'bill', date, label });
				continue;
			}
			flows.push({
				kind: 'out',
				date,
				label,
				accountId: b.accountId,
				accountName: nameOf(b.accountId),
				currency: b.currency,
				amount: b.amount
			});
		}

		// Paydays: the pay lands in the income account's wallet in the main currency (the money plan is in the main currency)
		const incomes = await tx
			.select()
			.from(incomeSchedule)
			.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.active, true)));
		const goals = await tx
			.select()
			.from(goal)
			.where(and(eq(goal.userId, userId), eq(goal.active, true)));
		const live = new Set(goals.map((g) => g.id));
		// A rule on a switched-off goal is left out, as the payday split leaves it out, so the moves are the same ones
		const rules = (
			await tx
				.select()
				.from(allocationRule)
				.where(and(eq(allocationRule.userId, userId), eq(allocationRule.status, 'active')))
		).filter((r) => !r.targetGoalId || live.has(r.targetGoalId));
		const goalAccounts = Object.fromEntries(goals.map((g) => [g.id, g.accountId]));
		const ruleNames: Record<string, string> = {};
		for (const g of goals) ruleNames[g.id] = g.name;
		for (const a of accounts) ruleNames[a.id] = a.name;

		for (const inc of incomes) {
			const schedule = inc.schedule as Schedule;
			const opts = { weekend: inc.weekendRule };
			const paydays = occurrencesBetween(schedule, today, input.to, opts);
			// A pay already recorded today is in today's balance: counting it again would double it
			const recorded =
				paydays[0] === today
					? await tx
							.select({ id: ledgerTxn.id })
							.from(ledgerTxn)
							.where(
								and(
									eq(ledgerTxn.userId, userId),
									eq(ledgerTxn.accountId, inc.accountId),
									eq(ledgerTxn.type, 'income'),
									isNull(ledgerTxn.voidedAt),
									gte(ledgerTxn.occurredAt, manilaStart(today)),
									lt(ledgerTxn.occurredAt, manilaStart(addDays(today, 1)))
								)
							)
							.limit(1)
					: [];
			for (const payday of paydays) {
				if (payday === today && recorded.length > 0) continue;
				if (inc.expectedAmount === null) {
					unknown.push({ kind: 'income', date: payday, label: inc.label });
					continue;
				}
				flows.push({
					kind: 'in',
					date: payday,
					label: inc.label,
					accountId: inc.accountId,
					accountName: nameOf(inc.accountId),
					currency: settings.currency,
					amount: inc.expectedAmount
				});
				if (rules.length === 0) continue;

				// The moves: what the split engine does with this pay, the bills of its period, the goals and the active rules
				const next = occurrencesBetween(
					schedule,
					addDays(payday, 1),
					addDays(payday, 800),
					opts
				)[0];
				const periodEnd = addDays(next ?? addDays(payday, 15), -1);
				const due = (await dueBills(tx, userId, payday, periodEnd)).filter((b) => !b.paid);
				const missingAmount = due.find((b) => b.unknownAmount);
				if (missingAmount) {
					notes.push(
						`The payday split of ${payday} is not in the moves: "${missingAmount.name}" has no amount yet.`
					);
					continue;
				}
				let unrated: string | null = null;
				const commitments: Commitment[] = [
					...due.map((b) => {
						let amount = b.amount ?? 0;
						if (b.currency !== settings.currency) {
							if (canConvert(b.currency, settings.currency, status.rates))
								amount = convertUp(amount, b.currency, settings.currency, status.rates);
							else unrated = b.currency;
						}
						return {
							kind: b.category === 'parents' ? ('parents' as const) : ('bill' as const),
							refId: b.billId,
							label: b.name,
							amount,
							accountId: b.accountId,
							deferrable: b.deferrable
						};
					}),
					...goals
						.filter((g) => g.perPayday > 0)
						.map((g) => ({
							kind: 'goal' as const,
							refId: g.id,
							label: g.name,
							amount: g.perPayday,
							accountId: g.accountId,
							deferrable: false
						}))
				];
				if (unrated) {
					notes.push(
						`The payday split of ${payday} is not in the moves: ${unrated} has no exchange rate.`
					);
					continue;
				}
				try {
					const split = proposeSplit({
						payday,
						pay: inc.expectedAmount,
						incomeAccountId: inc.accountId,
						commitments,
						rules: rules.map((r) =>
							toRule(r, ruleNames[r.targetAccountId ?? r.targetGoalId ?? ''])
						),
						goalAccounts
					});
					if (split.status === 'shortfall') {
						notes.push(
							`The pay of ${payday} does not cover everything (short by ${split.gap} in the smallest unit), so its moves are not in the forecast.`
						);
						continue;
					}
					for (const t of split.transfers)
						flows.push({
							kind: 'move',
							date: payday,
							label: t.labels.join(', ') || 'Payday split',
							accountId: t.fromAccountId,
							accountName: nameOf(t.fromAccountId),
							toAccountId: t.toAccountId,
							toAccountName: nameOf(t.toAccountId),
							currency: settings.currency,
							amount: t.amount
						});
				} catch (e) {
					if (!(e instanceof RangeError)) throw e;
					notes.push(`The payday split of ${payday} could not be worked out: ${e.message}`);
				}
			}
		}
		return { settings, status, wallets, flows, unknown, notes };
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
	const view: ForecastView = {
		...result,
		today,
		notes,
		rates: { asOf: gathered.status.asOf, stale: gathered.status.stale }
	};
	// A long answer is cut to totals and wallets, never in the middle of a list
	if (JSON.stringify(view).length > MAX_VIEW_CHARS)
		return {
			...view,
			itemsOmitted: true,
			notes: [
				...notes,
				'Too long to list every payment: the lists are left out, the totals and wallets are whole. Ask for a shorter range to see the items.'
			],
			periods: view.periods.map((p) => ({ ...p, ins: [], outs: [], moves: [] }))
		};
	return view;
}
