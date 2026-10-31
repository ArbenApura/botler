// PAYDAY SPLIT VERBS: PROPOSE A SPLIT FROM THE BILLS, THE PARENTS' SHARE, THE GOALS AND THE RULES; THE PERSON APPROVES IT AND TAPS THROUGH THE TRANSFERS
// The engine (src/lib/finance/split.ts) decides the numbers. A shortfall is never approved: the person decides what to cut and asks again.
// Approving is for a person only. The split reads approved rules only (status active), so a rule the agent proposed changes nothing until approved.
// Since BTL-20261029-0119 the split first pays bills from money already in their account today (less what the same flows the forecast uses
// take out of it before the payday) and from the rules that save for them, so it moves only what is missing, the same moves the forecast shows.

// -- TYPES -- //
import type { Ctx } from './context';
import type { Plain } from './shared';
import type { Schedule } from '../../finance/schedule';
import type { BrokenLink } from '../../finance/funding';
import type { SplitResult } from '../../finance/split';
import type { SplitProposeInput } from '../db/zod';
// -- DEP-MODULES -- //
import { and, desc, eq, gte, inArray, isNull, lt, ne, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, manilaStart, toManilaDate } from '../../finance/dates';
import { canConvert, convertUp, showRate } from '../../finance/fx';
import { occurrencesBetween } from '../../finance/schedule';
import { fundingAt, planFlows, recordedPays } from '../../finance/planFlows';
import { ruleTargetIsLive } from '../../finance/rules';
import { proposeSplit } from '../../finance/split';
import { account, allocationRule, goal, incomeSchedule, ledgerTxn, splitPlan } from '../db/schema';
import { splitApproveInput, splitDeleteInput, splitProposeInput, splitSentInput } from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { loadRates } from '../fx/store';
import { dueBills } from './bills';
import { balanceFor, insertTxn } from './ledger';
import { loadPlan } from './planData';
import { readSettings } from './settings';
import { toRule } from './rules';
import { mapped, parse, plain, requireIncome, requirePerson } from './shared';

// -- TYPES -- //

/** What is stored with a plan: the engine result plus what the screen needs to show it. */
export type StoredSplit = SplitResult & {
	payday: string;
	/** The last day the pay has to last, the day before the next payday. */
	periodEnd: string;
	incomeAccountId: string;
	accountNames: Record<string, string>;
	/** Rules in force that were left out because the goal they point at is switched off: what each was for, and a sentence to show. */
	skippedRules?: { ruleId: string; goal: string; note: string }[];
	/** Rules that point at a bill but cannot save for it, and why: that bill came from the pay. */
	brokenLinks?: BrokenLink[];
	/** The bills in another currency that were counted at a rate: what each is, what it came to in the main currency, the rate and its date. */
	foreignBills?: {
		billId: string;
		name: string;
		dueDate: string;
		currency: string;
		amount: number;
		converted: number;
		rate: string;
		ratesAsOf: string | null;
	}[];
};

export type SplitPlanView = Omit<Plain<typeof splitPlan.$inferSelect>, 'result'> & {
	result: StoredSplit;
};

/** A bill with no amount yet: the person is asked before a split can be made. */
export type NeedsAmounts = {
	status: 'needs_amounts';
	bills: { billId: string; name: string; dueDate: string }[];
};

// -- FUNCTIONS -- //

const view = (row: typeof splitPlan.$inferSelect): SplitPlanView =>
	plain(row) as unknown as SplitPlanView;

/**
 * Proposes the split for a payday. Nothing is allocated when the pay cannot cover everything: the plan then has status shortfall,
 * with the gap and what could be cut. A bill with no amount yet comes back as needs_amounts and nothing is saved.
 */
export async function proposeSplitPlan(
	ctx: Ctx,
	raw: SplitProposeInput
): Promise<SplitPlanView | NeedsAmounts> {
	const input = parse(splitProposeInput, raw);
	const gathered = await run(ctx, async (tx, userId) => {
		const inc = await requireIncome(tx, userId, input.incomeScheduleId);
		if (!inc.active) throw new OpsError('INVALID', `"${inc.label}" is switched off.`);
		const schedule = inc.schedule as Schedule;
		const opts = { weekend: inc.weekendRule };
		const today = toManilaDate(new Date());
		const payday =
			input.payday ?? occurrencesBetween(schedule, today, addDays(today, 800), opts)[0];
		if (!payday) throw new OpsError('INVALID', 'There is no payday ahead for that income.');
		if (input.payday && occurrencesBetween(schedule, payday, payday, opts).length === 0) {
			// A date the pattern falls on but the person left out (skipped, or before the start or after the end) is said so
			const bare = occurrencesBetween(
				{ ...schedule, startsOn: undefined, endsOn: undefined, skipDates: undefined },
				payday,
				payday,
				opts
			);
			throw new OpsError(
				'INVALID',
				bare.length > 0
					? `${payday} is left out of "${inc.label}" (skipped, or outside its start and end dates).`
					: `${payday} is not a payday of "${inc.label}".`
			);
		}
		const pay = input.pay ?? inc.expectedAmount;
		if (!pay) throw new OpsError('INVALID', 'Say what the pay is this time.');
		const next = occurrencesBetween(schedule, addDays(payday, 1), addDays(payday, 800), opts)[0];
		const periodEnd = addDays(next ?? addDays(payday, 15), -1);

		const due = (await dueBills(tx, userId, payday, periodEnd)).filter((b) => !b.paid);
		const unknown = due.filter((b) => b.unknownAmount);
		const accounts = await tx
			.select({ id: account.id, name: account.name, archivedAt: account.archivedAt })
			.from(account)
			.where(eq(account.userId, userId));
		const everyGoal = await tx.select().from(goal).where(eq(goal.userId, userId));
		const goals = everyGoal.filter((g) => g.active);
		const live = new Set(goals.map((g) => g.id));
		const inForce = await tx
			.select()
			.from(allocationRule)
			.where(and(eq(allocationRule.userId, userId), eq(allocationRule.status, 'active')));
		// A rule that points at a goal that is switched off cannot be placed: it is left out before the totals and the checks, so the pay it
		// would have taken goes where unclaimed pay always goes, and the plan says which rule was skipped
		// A rule into an account the person hid is left out the same way, so money never goes to an account they no longer see
		const hidden = new Set(accounts.filter((a) => a.archivedAt !== null).map((a) => a.id));
		const targets = { liveGoals: live, hiddenAccounts: hidden };
		const rules = inForce.filter((r) => ruleTargetIsLive(toRule(r).target, targets));
		// What the split may take from money already in the accounts, and the rules that save for bills: the plan's own flows from today to
		// the day before this payday give each account's balance at its start, as the forecast does
		const now = new Date();
		const loaded = await loadPlan(tx, userId, { now, incomeSince: manilaStart(today) });
		const balances = new Map<string, number>();
		for (const a of loaded.accounts)
			if (a.archivedAt === null)
				balances.set(
					a.id,
					(await balanceFor(tx, userId, a.id, loaded.settings.currency, now)).balance
				);
		// A pay already in the balance (a payday in the past, or this income's pay recorded today) is this split's own money: it never pays its
		// bills twice. For a payday still ahead, what was recorded today is real money in the account and stays.
		if (payday < today || (payday === today && recordedPays(loaded.plan, today).has(inc.id)))
			balances.set(inc.accountId, 0);
		const plan = {
			...loaded.plan,
			accounts: loaded.plan.accounts.filter((a) => !a.archived),
			balances
		};
		const before =
			payday > today
				? planFlows(plan, { mode: 'future', from: today, to: addDays(payday, -1), today }).flows
				: [];
		const funding = fundingAt(plan, before, payday, today);
		const skipped = [
			...inForce
				.filter((r) => r.targetGoalId && !live.has(r.targetGoalId))
				.map((r) => {
					const goalName =
						everyGoal.find((g) => g.id === r.targetGoalId)?.name ?? 'a goal that is gone';
					return {
						ruleId: r.id,
						goal: goalName,
						note: `The rule for "${goalName}" was skipped because that goal is switched off. Its share stayed with the rest of the pay.`
					};
				}),
			...inForce
				.filter((r) => r.targetAccountId && hidden.has(r.targetAccountId))
				.map((r) => {
					const accountName =
						accounts.find((a) => a.id === r.targetAccountId)?.name ?? 'an account that is gone';
					return {
						ruleId: r.id,
						goal: accountName,
						note: `The rule for "${accountName}" was skipped because that account is hidden. Its share stayed with the rest of the pay.`
					};
				})
		];
		return {
			inc,
			payday,
			pay,
			periodEnd,
			due,
			unknown,
			accounts,
			goals,
			rules,
			skipped,
			funding,
			// The split is in the main currency, so a bill in another one is counted at the stored rate
			main: (await readSettings(tx, userId)).currency,
			rates: await loadRates(tx)
		};
	});

	if (gathered.unknown.length > 0)
		return {
			status: 'needs_amounts',
			bills: gathered.unknown.map((b) => ({ billId: b.billId, name: b.name, dueDate: b.dueDate }))
		};

	const names: Record<string, string> = {};
	for (const a of gathered.accounts) names[a.id] = a.name;
	for (const g of gathered.goals) names[g.id] = g.name;
	const counts = new Map<string, number>();
	for (const b of gathered.due) counts.set(b.billId, (counts.get(b.billId) ?? 0) + 1);

	// A bill in another currency is counted as its main currency value, rounded up so the reserve is never short. The rate and its date
	// are kept with the plan. Without a rate the split stops with a plain message instead of counting the bill as nothing.
	const foreignBills: NonNullable<StoredSplit['foreignBills']> = [];
	const amountInMain = (b: (typeof gathered.due)[number]): number => {
		const amount = b.amount ?? 0;
		if (b.currency === gathered.main) return amount;
		if (!canConvert(b.currency, gathered.main, gathered.rates.rates))
			throw new OpsError(
				'INVALID',
				`There is no exchange rate for ${b.currency} yet, so "${b.name}" cannot be counted in the split. Refresh the exchange rates and try again.`
			);
		const converted = convertUp(amount, b.currency, gathered.main, gathered.rates.rates);
		foreignBills.push({
			billId: b.billId,
			name: b.name,
			dueDate: b.dueDate,
			currency: b.currency,
			amount,
			converted,
			rate: showRate(b.currency, gathered.main, gathered.rates.rates),
			ratesAsOf: gathered.rates.asOf
		});
		return converted;
	};

	let result: SplitResult;
	try {
		result = proposeSplit({
			payday: gathered.payday,
			pay: gathered.pay,
			incomeAccountId: gathered.inc.accountId,
			commitments: [
				...gathered.due.map((b) => ({
					kind: b.category === 'parents' ? ('parents' as const) : ('bill' as const),
					refId: b.billId,
					// A bill that falls twice in one period shows its date, so the two lines can be told apart
					label: (counts.get(b.billId) ?? 0) > 1 ? `${b.name} (${b.dueDate})` : b.name,
					amount: amountInMain(b),
					accountId: b.accountId,
					deferrable: b.deferrable,
					dueDate: b.dueDate,
					// Money already in an account is in the main currency: it never pays a bill in another one
					coverable: b.currency === gathered.main
				})),
				...gathered.goals
					.filter((g) => g.perPayday > 0)
					.map((g) => ({
						kind: 'goal' as const,
						refId: g.id,
						label: g.name,
						amount: g.perPayday,
						accountId: g.accountId,
						deferrable: false
					}))
			],
			rules: gathered.rules.map((r) => toRule(r, names[r.targetAccountId ?? r.targetGoalId ?? ''])),
			goalAccounts: Object.fromEntries(gathered.goals.map((g) => [g.id, g.accountId])),
			available: gathered.funding.available,
			links: gathered.funding.links
		});
	} catch (e) {
		if (e instanceof RangeError) throw new OpsError('INVALID', e.message);
		throw e;
	}

	const stored: StoredSplit = {
		...result,
		payday: gathered.payday,
		periodEnd: gathered.periodEnd,
		incomeAccountId: gathered.inc.accountId,
		accountNames: names,
		...(gathered.skipped.length > 0
			? {
					skippedRules: gathered.skipped
				}
			: {}),
		...(foreignBills.length > 0 ? { foreignBills } : {}),
		...(gathered.funding.broken.length > 0 ? { brokenLinks: gathered.funding.broken } : {})
	};
	return mapped(() =>
		runWrite(ctx, 'split.propose', input, async (tx, userId) => {
			// One approved split per payday: the income row is locked so a propose racing an approve cannot slip past
			await tx
				.select({ id: incomeSchedule.id })
				.from(incomeSchedule)
				.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, gathered.inc.id)))
				.for('update');
			const [approved] = await tx
				.select({ id: splitPlan.id })
				.from(splitPlan)
				.where(
					and(
						eq(splitPlan.userId, userId),
						eq(splitPlan.incomeScheduleId, gathered.inc.id),
						eq(splitPlan.payday, gathered.payday),
						eq(splitPlan.status, 'approved')
					)
				)
				.limit(1);
			if (approved)
				throw new OpsError(
					'CONFLICT',
					`The split for ${gathered.payday} is already approved. Delete it first if you want to plan this payday again.`
				);
			// A newer proposal for the same payday replaces the open ones
			await tx
				.update(splitPlan)
				.set({ status: 'superseded', updatedAt: sql`now()` })
				.where(
					and(
						eq(splitPlan.userId, userId),
						eq(splitPlan.incomeScheduleId, gathered.inc.id),
						eq(splitPlan.payday, gathered.payday),
						inArray(splitPlan.status, ['proposed', 'shortfall'])
					)
				);
			const [row] = await tx
				.insert(splitPlan)
				.values({
					userId,
					incomeScheduleId: gathered.inc.id,
					payday: gathered.payday,
					pay: gathered.pay,
					status: result.status === 'ok' ? 'proposed' : 'shortfall',
					gap: result.status === 'shortfall' ? result.gap : 0,
					result: stored
				})
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The split could not be saved.');
			return view(row);
		})
	);
}

/** The person approves a split. A shortfall cannot be approved. Only a person can. */
export async function approveSplit(
	ctx: Ctx,
	raw: { splitId: string; recordIncome?: boolean }
): Promise<SplitPlanView & { payRecorded: boolean }> {
	requirePerson(ctx.actor.kind, 'approve a split');
	const input = parse(splitApproveInput, raw);
	return mapped(() =>
		runWrite(ctx, 'split.approve', input, async (tx, userId) => {
			const [plan] = await tx
				.select()
				.from(splitPlan)
				.where(and(eq(splitPlan.userId, userId), eq(splitPlan.id, input.splitId)));
			if (!plan) throw new OpsError('NOT_FOUND', 'That split does not exist.');
			if (plan.status === 'shortfall')
				throw new OpsError(
					'INVALID',
					'The pay does not cover this. Decide what to cut, then ask for a new split.'
				);
			if (plan.status !== 'proposed')
				throw new OpsError('CONFLICT', 'That split is not waiting for approval.');
			// Never two approved splits for one payday: the income row is locked for the check
			if (plan.incomeScheduleId) {
				await tx
					.select({ id: incomeSchedule.id })
					.from(incomeSchedule)
					.where(
						and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, plan.incomeScheduleId))
					)
					.for('update');
				const [other] = await tx
					.select({ id: splitPlan.id })
					.from(splitPlan)
					.where(
						and(
							eq(splitPlan.userId, userId),
							eq(splitPlan.incomeScheduleId, plan.incomeScheduleId),
							eq(splitPlan.payday, plan.payday),
							eq(splitPlan.status, 'approved'),
							ne(splitPlan.id, plan.id)
						)
					)
					.limit(1);
				if (other)
					throw new OpsError(
						'CONFLICT',
						`The split for ${plan.payday} is already approved. Delete it first if you want to use this one.`
					);
			}
			const stored = plan.result as StoredSplit;
			const today = toManilaDate(new Date());
			const [done] = await tx
				.update(splitPlan)
				.set({
					status: 'approved',
					approvedAt: sql`now()`,
					approvedBy: `${ctx.actor.kind}:${userId}`,
					updatedAt: sql`now()`
				})
				.where(
					and(
						eq(splitPlan.userId, userId),
						eq(splitPlan.id, plan.id),
						eq(splitPlan.status, 'proposed')
					)
				)
				.returning();
			if (!done) throw new OpsError('CONFLICT', 'That split changed while you approved it.');
			// The split is a money plan, so the pay lands in the main currency wallet of the income account (opened if need be)
			// A pay the person already recorded that day (same account, same amount) is not recorded a second time
			let payRecorded = false;
			if (input.recordIncome ?? plan.payday <= today) {
				const [already] = await tx
					.select({ id: ledgerTxn.id })
					.from(ledgerTxn)
					.where(
						and(
							eq(ledgerTxn.userId, userId),
							eq(ledgerTxn.accountId, stored.incomeAccountId),
							eq(ledgerTxn.type, 'income'),
							eq(ledgerTxn.amount, plan.pay),
							isNull(ledgerTxn.voidedAt),
							ne(ledgerTxn.source, 'split'),
							gte(ledgerTxn.occurredAt, manilaStart(plan.payday)),
							lt(ledgerTxn.occurredAt, manilaStart(addDays(plan.payday, 1)))
						)
					)
					.limit(1);
				if (!already) {
					await insertTxn(
						tx,
						userId,
						ctx.requestId,
						{
							type: 'income',
							accountId: stored.incomeAccountId,
							amount: plan.pay,
							currency: (await readSettings(tx, userId)).currency,
							category: 'income',
							note: 'Pay',
							source: 'split',
							splitId: plan.id,
							// A split for a day gone by records its pay on that day (midday in Manila), not now
							...(plan.payday < today
								? { occurredAt: new Date(manilaStart(plan.payday).getTime() + 12 * 3_600_000) }
								: {})
						},
						{ journal: false }
					);
					payRecorded = true;
				}
			}
			return { ...view(done), payRecorded };
		})
	);
}

/** Records that the person made one transfer of the approved split. It becomes a transfer in the ledger, so it is never spending. */
export async function markTransferSent(
	ctx: Ctx,
	raw: { splitId: string; index: number }
): Promise<{ txnId: string; index: number; plan: SplitPlanView }> {
	const input = parse(splitSentInput, raw);
	return mapped(() =>
		runWrite(ctx, 'split.markSent', input, async (tx, userId) => {
			const [plan] = await tx
				.select()
				.from(splitPlan)
				.where(and(eq(splitPlan.userId, userId), eq(splitPlan.id, input.splitId)))
				// The row is held until this transfer is saved, so a double tap or a second phone cannot send it twice
				.for('update');
			if (!plan) throw new OpsError('NOT_FOUND', 'That split does not exist.');
			if (plan.status !== 'approved') throw new OpsError('INVALID', 'Approve the split first.');
			const stored = plan.result as StoredSplit;
			const t = stored.transfers[input.index];
			if (!t) throw new OpsError('NOT_FOUND', 'There is no such transfer in this split.');
			const sent = Array.isArray(plan.sentTransfers)
				? (plan.sentTransfers as { index: number; txnId: string }[])
				: [];
			if (sent.some((s) => s.index === input.index))
				throw new OpsError('CONFLICT', 'That transfer is already marked sent.');
			const main = (await readSettings(tx, userId)).currency;
			const txn = await insertTxn(tx, userId, ctx.requestId, {
				type: 'transfer',
				accountId: t.fromAccountId,
				toAccountId: t.toAccountId,
				amount: t.amount,
				currency: main,
				toCurrency: main,
				note: t.labels.join(', ').slice(0, 200),
				source: 'split',
				splitId: plan.id
			});
			const [updated] = await tx
				.update(splitPlan)
				.set({
					sentTransfers: [...sent, { index: input.index, txnId: txn.id }],
					updatedAt: sql`now()`
				})
				.where(and(eq(splitPlan.userId, userId), eq(splitPlan.id, plan.id)))
				.returning();
			if (!updated) throw new OpsError('NOT_FOUND', 'That split does not exist.');
			return { txnId: txn.id, index: input.index, plan: view(updated) };
		})
	);
}

/**
 * Removes recorded payday splits for good: one, or every one of the person, whatever their status (proposed, shortfall, approved,
 * replaced). The person and the assistant may both do it (owner decision 2026-10-31). The money that really moved stays in the ledger as
 * plain entries unless removeEntries is set, which voids the pay and the transfers the splits wrote so the balances go back. Nothing else
 * is touched: bills, rules and paydays stay. The audit trail keeps every delete. The answer lists what was removed.
 */
export async function deleteSplits(
	ctx: Ctx,
	raw: unknown
): Promise<{
	deleted: number;
	entriesVoided: number;
	voidedTxnIds: string[];
	/** One split deleted: the whole removed row, so it can be read back. Many: a short line each (the newest 50). */
	splits: (SplitPlanView | { id: string; payday: string; pay: number; status: string })[];
}> {
	const input = parse(splitDeleteInput, raw);
	// Taking the pay and transfers out of the balances changes what the person sees in every account, so it is theirs to do: the assistant
	// asks with a card (a free verb that needs the person comes back as one)
	if (input.removeEntries) requirePerson(ctx.actor.kind, 'take split entries out of the balances');
	return mapped(() =>
		runWrite(ctx, 'split.delete', input, async (tx, userId) => {
			const rows = await tx
				.select()
				.from(splitPlan)
				.where(
					input.splitId
						? and(eq(splitPlan.userId, userId), eq(splitPlan.id, input.splitId))
						: eq(splitPlan.userId, userId)
				);
			if (input.splitId && rows.length === 0)
				throw new OpsError('NOT_FOUND', 'That split does not exist.');
			const ids = rows.map((r) => r.id);
			let voidedTxnIds: string[] = [];
			if (input.removeEntries && ids.length > 0) {
				const voided = await tx
					.update(ledgerTxn)
					.set({ voidedAt: sql`now()`, updatedAt: sql`now()` })
					.where(
						and(
							eq(ledgerTxn.userId, userId),
							inArray(ledgerTxn.splitId, ids),
							isNull(ledgerTxn.voidedAt)
						)
					)
					.returning({ id: ledgerTxn.id });
				voidedTxnIds = voided.map((v) => v.id);
			}
			if (ids.length > 0)
				await tx
					.delete(splitPlan)
					.where(and(eq(splitPlan.userId, userId), inArray(splitPlan.id, ids)));
			return {
				deleted: rows.length,
				entriesVoided: voidedTxnIds.length,
				voidedTxnIds,
				splits: input.splitId
					? rows.map(view)
					: rows
							.sort((a, b) => (a.payday < b.payday ? 1 : -1))
							.slice(0, 50)
							.map((r) => ({ id: r.id, payday: r.payday, pay: r.pay, status: r.status }))
			};
		})
	);
}

export async function listSplits(
	ctx: Ctx,
	limit = 10,
	includeReplaced = false
): Promise<SplitPlanView[]> {
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(splitPlan)
			// A split replaced by a newer proposal is not shown unless asked for: it would use up the rows of the list
			.where(
				includeReplaced
					? eq(splitPlan.userId, userId)
					: and(eq(splitPlan.userId, userId), ne(splitPlan.status, 'superseded'))
			)
			.orderBy(desc(splitPlan.createdAt))
			.limit(Math.min(Math.max(limit, 1), 50))
	);
	return rows.map(view);
}

/** The paydays ahead, with the open (proposed or approved) plan of each, for the home screen. */
export async function upcomingPaydays(ctx: Ctx, count = 3) {
	return run(ctx, async (tx, userId) => {
		const incomes = await tx
			.select()
			.from(incomeSchedule)
			.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.active, true)));
		const today = toManilaDate(new Date());
		const out: { incomeId: string; label: string; payday: string }[] = [];
		for (const inc of incomes)
			for (const d of occurrencesBetween(inc.schedule as Schedule, today, addDays(today, 800), {
				weekend: inc.weekendRule
			}).slice(0, count))
				out.push({ incomeId: inc.id, label: inc.label, payday: d });
		return out.sort((a, b) => (a.payday < b.payday ? -1 : 1)).slice(0, count);
	});
}
