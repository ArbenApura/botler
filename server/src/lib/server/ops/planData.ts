// THE MONEY PLAN AS ROWS, LOADED ONCE INSIDE THE CALLER'S OWN TRANSACTION (BTL-20261029-0117)
// The forecast verb and the simulation read the same plan from here and hand it to the pure flows (finance/planFlows.ts), so a payday split is
// worked out the same way for both, and the bill dates of 5 years of paydays come from rows in memory instead of a query per payday.
// It reads only. Every query runs in the transaction `run(ctx)` opened for the caller, as the app_runtime role, so row level security keeps
// it to the caller's own rows. Archived accounts are loaded too and flagged: their past is real, the plan no longer moves money with them.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { PlanData, PlanRule, RecordedIncome } from '../../finance/planFlows';
import type { Schedule } from '../../finance/schedule';
import type { SettledStretch } from '../../finance/billWindows';
import type { RatesStatus } from '../fx/store';
import type { SettingsView } from './settings';
// -- DEP-MODULES -- //
import { and, eq, gte, inArray, isNull } from 'drizzle-orm';
// -- MODULES -- //
import { toLocalDate } from '../../finance/dates';
import { ruleTargetIsLive } from '../../finance/rules';
import {
	account,
	allocationRule,
	bill,
	billOverride,
	billPayment,
	goal,
	incomeSchedule,
	ledgerTxn,
	splitPlan
} from '../db/schema';
import { loadRates } from '../fx/store';
import { estimatesOf } from './bills';
import { toRule } from './rules';
import { readSettings } from './settings';

// -- TYPES -- //

export type LoadedPlan = {
	settings: SettingsView;
	status: RatesStatus;
	plan: PlanData;
	/** Every account row, archived ones included. */
	accounts: (typeof account.$inferSelect)[];
};

// -- FUNCTIONS -- //

/**
 * The plan of the caller. `incomeSince` is the first instant whose recorded incomes are wanted (the forecast needs only today's, the
 * simulation all of them for missed paydays); null reads none.
 */
export async function loadPlan(
	tx: Tx,
	userId: string,
	opts: { now: Date; incomeSince: Date | null }
): Promise<LoadedPlan> {
	const settings = await readSettings(tx, userId);
	const status = await loadRates(tx, opts.now);
	const accounts = await tx.select().from(account).where(eq(account.userId, userId));
	const incomes = await tx
		.select()
		.from(incomeSchedule)
		.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.active, true)));
	const bills = await tx
		.select()
		.from(bill)
		.where(and(eq(bill.userId, userId), eq(bill.active, true)));
	const billIds = bills.map((b) => b.id);
	const payments =
		billIds.length === 0
			? []
			: await tx
					.select({
						billId: billPayment.billId,
						dueDate: billPayment.dueDate,
						windowStart: billPayment.windowStart,
						windowEnd: billPayment.windowEnd
					})
					.from(billPayment)
					.where(and(eq(billPayment.userId, userId), inArray(billPayment.billId, billIds)));
	// What each payment settled: its stored window, or just its due date on older rows
	const settled = new Map<string, SettledStretch[]>();
	for (const p of payments)
		settled.set(p.billId, [
			...(settled.get(p.billId) ?? []),
			{ start: p.windowStart ?? p.dueDate, end: p.windowEnd ?? p.dueDate }
		]);
	const overrideRows =
		billIds.length === 0
			? []
			: await tx
					.select()
					.from(billOverride)
					.where(and(eq(billOverride.userId, userId), inArray(billOverride.billId, billIds)));
	const overrides = new Map<string, (typeof billOverride.$inferSelect)[]>();
	for (const r of overrideRows) overrides.set(r.billId, [...(overrides.get(r.billId) ?? []), r]);
	const estimates = await estimatesOf(tx, userId, bills);
	const goals = await tx
		.select()
		.from(goal)
		.where(and(eq(goal.userId, userId), eq(goal.active, true)));
	const live = new Set(goals.map((g) => g.id));
	// A rule on a switched-off goal or into a hidden account is left out, through the same filter the payday split uses, so every view
	// of the plan makes the same moves
	const targets = {
		liveGoals: live,
		hiddenAccounts: new Set(accounts.filter((a) => a.archivedAt !== null).map((a) => a.id))
	};
	const ruleRows = (
		await tx
			.select()
			.from(allocationRule)
			.where(and(eq(allocationRule.userId, userId), eq(allocationRule.status, 'active')))
	).filter((r) => ruleTargetIsLive(toRule(r).target, targets));
	const incomeDays = new Set<string>();
	const incomeRecords: RecordedIncome[] = [];
	if (opts.incomeSince) {
		const recorded = await tx
			.select({
				accountId: ledgerTxn.accountId,
				occurredAt: ledgerTxn.occurredAt,
				amount: ledgerTxn.amount,
				currency: ledgerTxn.currency,
				splitId: ledgerTxn.splitId
			})
			.from(ledgerTxn)
			.where(
				and(
					eq(ledgerTxn.userId, userId),
					eq(ledgerTxn.type, 'income'),
					isNull(ledgerTxn.voidedAt),
					gte(ledgerTxn.occurredAt, opts.incomeSince)
				)
			);
		// An entry a split wrote belongs to that split's income schedule
		const splitIds = [...new Set(recorded.flatMap((r) => (r.splitId ? [r.splitId] : [])))];
		const scheduleOf = new Map(
			splitIds.length === 0
				? []
				: (
						await tx
							.select({ id: splitPlan.id, incomeScheduleId: splitPlan.incomeScheduleId })
							.from(splitPlan)
							.where(and(eq(splitPlan.userId, userId), inArray(splitPlan.id, splitIds)))
					).map((p) => [p.id, p.incomeScheduleId] as const)
		);
		for (const r of recorded) {
			const date = toLocalDate(r.occurredAt);
			incomeDays.add(`${r.accountId}|${date}`);
			incomeRecords.push({
				accountId: r.accountId,
				date,
				amount: r.amount,
				currency: r.currency,
				scheduleId: r.splitId ? (scheduleOf.get(r.splitId) ?? null) : null
			});
		}
	}

	const day = (d: Date) => toLocalDate(d);
	const plan: PlanData = {
		main: settings.currency,
		rates: status.rates,
		accounts: accounts.map((a) => ({
			id: a.id,
			name: a.name,
			minBalance: a.minBalance,
			archived: a.archivedAt !== null,
			createdOn: day(a.createdAt)
		})),
		incomes: incomes.map((i) => ({
			id: i.id,
			label: i.label,
			accountId: i.accountId,
			expectedAmount: i.expectedAmount,
			schedule: i.schedule as Schedule,
			weekendRule: i.weekendRule,
			createdOn: day(i.createdAt)
		})),
		bills: bills.map((b) => ({
			id: b.id,
			name: b.name,
			category: b.category,
			accountId: b.accountId,
			schedule: b.schedule,
			weekendRule: b.weekendRule,
			deferrable: b.deferrable,
			startsOn: b.startsOn,
			currency: b.currency,
			usualAmount: estimates.get(b.id)?.amount ?? null,
			createdOn: day(b.createdAt)
		})),
		goals: goals.map((g) => ({
			id: g.id,
			name: g.name,
			accountId: g.accountId,
			perPayday: g.perPayday,
			createdOn: day(g.createdAt)
		})),
		rules: ruleRows.map((r): PlanRule => ({
			...toRule(r),
			createdOn: day(r.createdAt),
			fundsBillId: r.fundsBillId,
			ownLabel: r.label
		})),
		overrides,
		settled,
		incomeDays,
		incomeRecords
	};
	return { settings, status, plan, accounts };
}
