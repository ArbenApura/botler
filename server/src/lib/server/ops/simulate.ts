// THE balance_simulate VERB: THE BALANCE TIMELINE OF THE CALLER FROM UP TO 5 YEARS BACK TO 5 YEARS AHEAD, BY DAY, WEEK, MONTH OR YEAR
// (BTL-20261029-0117). It reads only and writes nothing, so it leaves no audit row. Everything is gathered inside the caller's own
// transaction (run(ctx), the app_runtime role and the tenant context), handed to the pure timeline (finance/simulate.ts), and worded:
// - recorded numbers are the ledger's, replayed ones are today's plan run over a past period, simulated ones are the future. The answer
//   says which is which on every period and every entry, and its notes say plainly that only recorded numbers are real.
// - a what-if (scenario) changes only the replay and the simulation, is never saved, and ignores ids that are not the caller's.
// - the assistant gets a shorter answer (the entries, then the wallets, then the period details are dropped) so a tool result is never
//   cut in the middle; the app gets the whole answer of what it asked for.

// -- TYPES -- //
import type { Ctx } from './context';
import type { PlanData, PlanNote } from '../../finance/planFlows';
import type { Scenario } from '../../finance/scenario';
import type { ScenarioInput } from '../db/zod';
import type { RecordedSnapshot, RecordedTxn, Simulation } from '../../finance/simulate';
// -- DEP-MODULES -- //
import { and, eq, isNull, lte } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, diffDays, toManilaDate } from '../../finance/dates';
import { applyScenario } from '../../finance/scenario';
import { simulate } from '../../finance/simulate';
import { accountWallet, balanceSnapshot, ledgerTxn } from '../db/schema';
import { balanceSimulateInput } from '../db/zod';
import { refreshInBackground } from '../fx/store';
import { OpsError, run } from './context';
import { loadPlan } from './planData';
import { parse } from './shared';

// -- TYPES -- //

export type SimulationView = Omit<Simulation, 'notes'> & {
	view: 'overview' | 'detail';
	/** Plain sentences: what is real, what is simulated, what was left out. Read them before quoting a number. */
	notes: string[];
	rates: { asOf: string | null; stale: boolean };
	/** The what-if, when one was sent: how many changes it made and the ids that were not the person's. */
	scenario?: { changes: number; ignored: string[] };
	/** The assistant's answer was cut to stay short: entries, then per-period wallets, then period details were left out. */
	itemsOmitted?: boolean;
	walletsOmitted?: boolean;
	detailsOmitted?: boolean;
	/** With detailsOmitted: each period's end totals only (periods is then empty). */
	summary?: {
		from: string;
		to: string;
		part: 'past' | 'mixed' | 'future';
		recorded: number | null;
		replay: number | null;
		simulated: number | null;
		gap: number | null;
		missed: number;
	}[];
};

// -- CONSTANTS -- //

/** How far back and ahead of today a range may reach: 5 years each way. */
export const REACH_DAYS = 1827;

/** A detail view (every entry) covers at most a year. */
export const MAX_DETAIL_DAYS = 366;

/** The assistant's answer stays under this many characters, below the tool result cap of the chat loop (16,000). */
export const MAX_AGENT_CHARS = 13_000;

// -- FUNCTIONS -- //

/** The notes of the payday splits, one line per kind of problem, never one per payday. */
function groupedNotes(notes: readonly PlanNote[]): string[] {
	const groups = new Map<
		string,
		{ text: (n: number, first: string) => string; n: number; first: string }
	>();
	const add = (key: string, payday: string, text: (n: number, first: string) => string) => {
		const g = groups.get(key);
		if (g) {
			g.n++;
			if (payday < g.first) g.first = payday;
		} else groups.set(key, { text, n: 1, first: payday });
	};
	for (const note of notes) {
		if (note.kind === 'missing_amount')
			add(
				`m|${note.bill}`,
				note.payday,
				(n, first) =>
					`The payday split is left out on ${n} payday${n > 1 ? 's' : ''} from ${first}: "${note.bill}" has no amount yet.`
			);
		else if (note.kind === 'unrated')
			add(
				`u|${note.currency}`,
				note.payday,
				(n, first) =>
					`The payday split is left out on ${n} payday${n > 1 ? 's' : ''} from ${first}: ${note.currency} has no exchange rate.`
			);
		else if (note.kind === 'shortfall')
			add(
				's',
				note.payday,
				(n, first) =>
					`${n} pay${n > 1 ? 's are' : ' is'} short from ${first}: the moves fund bills and goals first, then the rules in order until the pay runs out.`
			);
		else
			add(
				`e|${note.message}`,
				note.payday,
				(n, first) =>
					`The payday split of ${n} payday${n > 1 ? 's' : ''} from ${first} could not be worked out: ${note.message}`
			);
	}
	return [...groups.values()].map((g) => g.text(g.n, g.first));
}

/**
 * The what-if of the input in the shape of finance/scenario.ts. An id is sorted by what it is in the plan; one that is nothing of the
 * person's goes to the paydays list, where applyScenario names it back as ignored. A skipped date skips every payday on it.
 */
export function toScenario(input: ScenarioInput | undefined, plan: PlanData): Scenario | undefined {
	if (!input) return undefined;
	const bills = new Set(plan.bills.map((b) => b.id));
	const rules = new Set(plan.rules.map((r) => r.id));
	const goals = new Set(plan.goals.map((g) => g.id));
	const off: Required<NonNullable<Scenario['off']>> = {
		incomes: [],
		bills: [],
		rules: [],
		goals: []
	};
	for (const id of input.off ?? [])
		(bills.has(id)
			? off.bills
			: rules.has(id)
				? off.rules
				: goals.has(id)
					? off.goals
					: off.incomes
		).push(id);
	const amounts = input.amounts ?? [];
	return {
		off,
		incomeAmounts: amounts.filter((a) => !bills.has(a.id)),
		billAmounts: amounts.filter((a) => bills.has(a.id)),
		skipPaydays: (input.skipDates ?? []).flatMap((date) =>
			plan.incomes.map((i) => ({ incomeId: i.id, date }))
		),
		billDelayDays: input.lateDays,
		deferDeferrable: input.defer,
		extra: (input.extra ?? []).map((e) => ({ ...e, currency: plan.main }))
	};
}

/** The label a recorded entry shows: its note, else its category, else its type. */
const labelOf = (r: typeof ledgerTxn.$inferSelect) =>
	r.note.trim() || r.category || (r.type === 'adjustment' ? 'Balance count' : r.type);

/**
 * The timeline of the caller from `from` to `to`. The caller sees only their own rows: every read runs in their transaction, and a
 * what-if id that is not theirs is never found, only named back.
 */
export async function balanceSimulate(ctx: Ctx, raw: unknown): Promise<SimulationView> {
	const input = parse(balanceSimulateInput, raw);
	const now = new Date();
	const today = toManilaDate(now);
	const group = input.group ?? 'month';
	const view = input.view ?? 'overview';
	if (input.from < addDays(today, -REACH_DAYS) || input.to > addDays(today, REACH_DAYS))
		throw new OpsError(
			'INVALID',
			'The range reaches at most 5 years back and 5 years ahead of today.'
		);
	if (view === 'detail' && diffDays(input.to, input.from) + 1 > MAX_DETAIL_DAYS)
		throw new OpsError(
			'INVALID',
			`The detail of every entry covers at most ${MAX_DETAIL_DAYS} days.`
		);
	for (const e of input.scenario?.extra ?? [])
		if (e.date < addDays(today, -REACH_DAYS) || e.date > addDays(today, REACH_DAYS))
			throw new OpsError('INVALID', 'A pretend entry is dated within 5 years of today.');

	const gathered = await run(ctx, async (tx, userId) => {
		// The plan, with every recorded pay day for the missed paydays
		const loaded = await loadPlan(tx, userId, { now, incomeSince: new Date(0) });
		const walletRows = await tx
			.select({ accountId: accountWallet.accountId, currency: accountWallet.currency })
			.from(accountWallet)
			.where(eq(accountWallet.userId, userId));
		const snapshots: RecordedSnapshot[] = (
			await tx
				.select()
				.from(balanceSnapshot)
				.where(and(eq(balanceSnapshot.userId, userId), lte(balanceSnapshot.takenAt, now)))
		).map((s) => ({
			accountId: s.accountId,
			currency: s.currency,
			amount: s.amount,
			takenAt: s.takenAt
		}));
		// Every entry up to now, once: the balances at each period's start and end are sliced from these rows (finance/ledger.ts balanceOf)
		const txns: RecordedTxn[] = (
			await tx
				.select()
				.from(ledgerTxn)
				.where(
					and(
						eq(ledgerTxn.userId, userId),
						isNull(ledgerTxn.voidedAt),
						lte(ledgerTxn.occurredAt, now)
					)
				)
		).map((r) => ({
			id: r.id,
			label: labelOf(r),
			type: r.type,
			accountId: r.accountId,
			toAccountId: r.toAccountId,
			amount: r.amount,
			currency: r.currency,
			toCurrency: r.toCurrency,
			toAmount: r.toAmount,
			fee: r.fee,
			occurredAt: r.occurredAt
		}));
		const wallets = [
			...loaded.accounts.map((a) => ({ accountId: a.id, currency: a.currency })),
			...walletRows
		];
		return { ...loaded, wallets, snapshots, txns };
	});
	refreshInBackground(ctx.handle, gathered.status);

	let result: Simulation;
	let applied: ReturnType<typeof applyScenario>;
	try {
		applied = applyScenario(gathered.plan, toScenario(input.scenario, gathered.plan));
		result = simulate({
			from: input.from,
			to: input.to,
			group,
			weekStart: gathered.settings.weekStartsOn,
			today,
			now,
			plan: applied.plan,
			basePlan: gathered.plan,
			wallets: gathered.wallets,
			snapshots: gathered.snapshots,
			txns: gathered.txns,
			detail: view === 'detail'
		});
	} catch (e) {
		if (e instanceof RangeError) throw new OpsError('INVALID', e.message);
		throw e;
	}

	const notes: string[] = [
		"Only recorded numbers are real. Replay numbers are what today's plan would have done in that past period, started from the recorded balance at its start; simulated numbers are the future from today's balances and the plan. Say which is which when you quote them."
	];
	if (input.to < today)
		notes.push("This range is all in the past: recorded, with a replay of today's plan.");
	else if (input.from > today)
		notes.push('This range is all in the future: every number is simulated.');
	notes.push(...groupedNotes(result.notes));
	if (result.firstRecord === null) notes.push('Nothing was recorded yet: the past has no numbers.');
	else if (input.from < result.firstRecord)
		notes.push(
			`The first record is on ${result.firstRecord}: periods before it have no recorded or replayed numbers.`
		);
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
	notes.push('Totals of other currencies, past and future, use the latest stored exchange rates.');
	if (applied.changes > 0)
		notes.push(
			`A what-if with ${applied.changes} change${applied.changes > 1 ? 's' : ''} is on: it changes the replay and the simulation, never what was recorded, and nothing is saved.`
		);
	if (applied.ignored.length > 0)
		notes.push(
			`Some what-if ids are not yours or not active and were left out: ${applied.ignored.join(', ')}.`
		);

	const answer: SimulationView = {
		...result,
		view,
		notes,
		rates: { asOf: gathered.status.asOf, stale: gathered.status.stale },
		...(input.scenario ? { scenario: { changes: applied.changes, ignored: applied.ignored } } : {})
	};
	return ctx.actor.kind === 'agent' ? forAgent(answer) : answer;
}

/** The assistant's answer, cut in steps until it fits, never in the middle of a list. */
export function forAgent(answer: SimulationView): SimulationView {
	const fits = (v: SimulationView) => JSON.stringify(v).length <= MAX_AGENT_CHARS;
	if (fits(answer)) return answer;
	const short =
		'Too long to list everything: ask for a shorter range or group by month or year to see more.';
	let v: SimulationView = {
		...answer,
		entries: undefined,
		itemsOmitted: true,
		notes: [...answer.notes, short]
	};
	if (answer.entries === undefined) v = { ...answer, notes: [...answer.notes, short] };
	if (fits(v)) return v;
	v = { ...v, walletsOmitted: true, periods: v.periods.map((p) => ({ ...p, wallets: [] })) };
	if (fits(v)) return v;
	// Last: each period's end totals only, by source
	v = {
		...v,
		warnings: v.warnings.slice(0, 5),
		unknown: v.unknown.slice(0, 5),
		detailsOmitted: true,
		notes: [...v.notes, 'Each period is in summary: its end totals by source.'],
		periods: [],
		summary: v.periods.map((p) => ({
			from: p.from,
			to: p.to,
			part: p.part,
			recorded: p.recordedEnd,
			replay: p.replayEnd,
			simulated: p.simulatedEnd,
			gap: p.gap,
			missed: p.missed
		}))
	};
	if (fits(v)) return v;
	throw new OpsError(
		'INVALID',
		'That range is too long to answer at once: ask for fewer periods (group by year, or a shorter range).'
	);
}
