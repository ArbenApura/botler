// THE BALANCE TIMELINE: WHAT EVERY WALLET HELD IN THE PAST AND WHAT IT WILL HOLD IN THE FUTURE, PERIOD BY PERIOD (BTL-20261029-0117)
// A pure function from loaded rows. Every number says where it comes from:
// - recorded: the ledger as it is (the latest count of a wallet plus the signed entries after it, finance/ledger.ts balanceOf).
// - replay: what today's plan would have done in a past period, started from the recorded balance at the START OF THAT PERIOD, so a
//   period gives the same replay and the same gap whatever range it was asked in. gap = recorded end - replay end.
// - simulated: the future, always run from today's real balances (active accounts) through to the end of the range, so a range years
//   ahead does not start from zero. The flows are the forecast's own (finance/planFlows.ts, mode future).
// - missed: a past payday with no income recorded on its account from the payday until the day before the next one, or a past bill
//   date with no payment. Only once that stretch is over, and only from the first record on.
// A period that holds today is mixed: recorded from its start up to now, simulated from today to its end.
// Wallets of different currencies are never added: totals convert at the stored rates, and a currency with no rate is named and left out.

// -- TYPES -- //
import type { ManilaDate } from './dates';
import type { Group, RangeLimits } from './forecast';
import type { Txn } from './ledger';
import type { PlanData, PlanFlow, PlanNote } from './planFlows';
// -- MODULES -- //
import { billOccurrences } from './billWindows';
import { addDays, dayStart, toLocalDate } from './dates';
import { checkRange, periodEnd, SIMULATE_LIMITS } from './forecast';
import { canConvert, convert } from './fx';
import { balanceOf, effectOn } from './ledger';
import { planFlows } from './planFlows';
import { occurrencesBetween } from './schedule';

// -- TYPES -- //

export type Source = 'recorded' | 'replay' | 'simulated' | 'missed';

/** A recorded ledger entry, with what the person sees. Voided entries are never passed. The bill and category group its spending. */
export type RecordedTxn = Txn & {
	id: string;
	label: string;
	billId?: string | null;
	category?: string | null;
};

export type RecordedSnapshot = {
	accountId: string;
	currency: string;
	amount: number;
	takenAt: Date;
};

export type SimulateInput = {
	from: ManilaDate;
	to: ManilaDate;
	group: Group;
	/** 0 is Sunday, 1 is Monday. */
	weekStart: number;
	today: ManilaDate;
	now: Date;
	/** The plan with the what-if applied: the replay and the simulation use it. */
	plan: PlanData;
	/** The plan as it really is: missed paydays and bills are judged against it. */
	basePlan: PlanData;
	/** Every wallet the person has (an account in one currency). */
	wallets: readonly { accountId: string; currency: string }[];
	snapshots: readonly RecordedSnapshot[];
	txns: readonly RecordedTxn[];
	/**
	 * The instant of the very first count or entry, when `snapshots` and `txns` are only the window a range needs (ops/simulate.ts loads
	 * just that). Left out, the first record is the earliest of the rows given.
	 */
	firstRecordAt?: Date | null;
	/** detail adds every entry of the range and the spending per group. */
	detail: boolean;
	/** Names of bills that are no longer in the plan (deleted or inactive), by id, for the labels of their spending. */
	billNames?: ReadonlyMap<string, string>;
	/**
	 * detail only: a page of the entries, optionally of one group. Left out, the answer is the older one: up to MAX_ENTRIES entries and the
	 * number omitted. With it, entries holds that slice of the one ordered list and entriesTotal counts the entries of the group.
	 */
	page?: { offset: number; limit: number; groupKey?: string };
	limits?: RangeLimits;
};

/** One group of spending: a bill, a category, or other. */
export type SpendGroup = {
	key: string;
	label: string;
	kind: 'bill' | 'category' | 'other';
	/** Main currency, the sum of the per-row figures (refunds count below zero). */
	amount: number;
	count: number;
};

export type SpendBreakdown = {
	/** The biggest groups by amount, at most BREAKDOWN_GROUPS. */
	groups: SpendGroup[];
	/** The rest of the groups together, or null when every group is listed. */
	more: { amount: number; count: number; groups: number } | null;
};

export type SimEntry = {
	/** Stable across requests: the ledger row's id for a recorded entry, source and position for the rest. */
	id: string;
	source: Source;
	kind: 'in' | 'out' | 'move';
	date: ManilaDate;
	label: string;
	accountId: string;
	accountName: string;
	toAccountId?: string;
	toAccountName?: string;
	currency: string;
	/** Minor units, above zero. Null only for a missed date whose amount was never known. */
	amount: number | null;
	amountMain: number | null;
	/**
	 * What the entry does to the period's totals, in the main currency. Present means it counts: groupKey and spentMain for spending
	 * (an expense, a transfer fee, a bill or other money out; a refund is below zero), receivedMain for income, untrackedMain for a
	 * negative balance count. Null is a currency with no rate: left out, never zero. A transfer between own accounts has none of them.
	 */
	groupKey?: string;
	spentMain?: number | null;
	receivedMain?: number | null;
	untrackedMain?: number | null;
	/** Money back for an earlier expense: it lowers spending and is not money received. */
	refund?: boolean;
	/** A one-off entry of a what-if. */
	pretend?: boolean;
};

export type SimWallet = {
	accountId: string;
	accountName: string;
	currency: string;
	/** Hidden since: its past is real, the plan no longer uses it. */
	archived: boolean;
	/** The end balance by each source, minor units of the wallet's currency. Null when that source has nothing for it (not open yet). */
	recorded: number | null;
	replay: number | null;
	simulated: number | null;
	/** The same balances in the main currency at the stored rates. Null when the wallet has no balance from that source, or its currency has no rate. */
	recordedMain: number | null;
	replayMain: number | null;
	simulatedMain: number | null;
};

export type SimPeriod = {
	from: ManilaDate;
	to: ManilaDate;
	part: 'past' | 'mixed' | 'future';
	/** True when the period ends before anything was recorded: there is nothing real to show or replay. */
	beforeFirstRecord: boolean;
	/** Totals in the main currency. Recorded: at the start, and at the end (now, for a mixed period). */
	recordedStart: number | null;
	recordedEnd: number | null;
	replayEnd: number | null;
	/** Simulated: at the start (the end of the day before, or now), and at the end. */
	simulatedStart: number | null;
	simulatedEnd: number | null;
	/** Recorded end less replay end, for a past period. */
	gap: number | null;
	/** How many paydays and bill dates the plan expected and were not recorded. */
	missed: number;
	/** A replayed or simulated wallet was under its account's minimum, or below zero, at the end of a day. */
	low: boolean;
	below: boolean;
	/**
	 * Money out and in during the period, in the main currency, each row converted on its own and added (never a conversion of a sum).
	 * Spent is expenses plus transfer fees minus refunds (finance/ledger.ts: a transfer between own accounts is never spending); received
	 * is income only; untracked is the negative balance counts, shown apart and never part of spent. Recorded runs to now, so the period
	 * of today has recorded so far and simulated for the rest. Replay and simulated are the plan's money out and in (bills, paydays and
	 * what-if entries), never its moves between accounts. Null when that source has nothing for the period. In the period of the first
	 * record the replay starts the day after it. A currency with no rate is left out and named in leftOut.
	 */
	recordedSpent: number | null;
	recordedReceived: number | null;
	recordedUntracked: number | null;
	replaySpent: number | null;
	replayReceived: number | null;
	simulatedSpent: number | null;
	simulatedReceived: number | null;
	leftOut: string[];
	/**
	 * The running total across the span between this period and today, same rule and same conversion as the figures above. A past
	 * period spans its start to today (recorded), a future one today to its end (simulated). Null for the period that holds today (it
	 * would repeat spent so far) and for a period before the first record. Its own left-out list keeps `leftOut` true to the period.
	 */
	spanFrom?: ManilaDate | null;
	spanTo?: ManilaDate | null;
	spanSource?: 'recorded' | 'simulated' | null;
	spanSpent?: number | null;
	spanReceived?: number | null;
	spanLeftOut?: string[];
	wallets: SimWallet[];
};

export type SimWarning = {
	source: 'replay' | 'simulated';
	kind: 'below_zero' | 'below_minimum';
	date: ManilaDate;
	accountId: string;
	accountName: string;
	currency: string;
	balance: number;
};

export type SimUnknown = {
	kind: 'income' | 'bill';
	label: string;
	count: number;
	first: ManilaDate;
};

export type Simulation = {
	from: ManilaDate;
	to: ManilaDate;
	group: Group;
	today: ManilaDate;
	currency: string;
	/** The day of the first count or entry, or null when nothing was ever recorded. */
	firstRecord: ManilaDate | null;
	periods: SimPeriod[];
	/** detail only: the entries of the range in one total order (date, source, time, id): a page of them, or cut at MAX_ENTRIES. */
	entries?: SimEntry[];
	entriesOmitted?: number;
	/** detail with a page: how many entries there are (of the group, when one was asked for), and where this page starts. */
	entriesTotal?: number;
	entriesOffset?: number;
	/** detail only: the spending of the whole range per group and per source, whatever group the entries were limited to. */
	breakdown?: { recorded: SpendBreakdown; replay: SpendBreakdown; simulated: SpendBreakdown };
	warnings: SimWarning[];
	unknown: SimUnknown[];
	notes: PlanNote[];
	/** Currencies held or moved with no rate: left out of every total. */
	missing: string[];
};

// -- CONSTANTS -- //

export const MAX_ENTRIES = 500;
/** The page size limits of a detail view that asks for a page. */
export const MAX_PAGE = 100;
/** The groups the spending breakdown lists one by one. */
export const BREAKDOWN_GROUPS = 30;
/** The group of spending with no bill and no category. */
export const OTHER_GROUP = 'other';
const MAX_WARNINGS = 30;
const ORDER = { in: 0, move: 1, out: 2 } as const;

// -- FUNCTIONS -- //

const key = (accountId: string, currency: string) => `${accountId}|${currency}`;

/** The last instant of a Manila day. */
const endOf = (d: ManilaDate) => new Date(dayStart(addDays(d, 1)).getTime() - 1);

/** The instant just before a Manila day starts. */
const before = (d: ManilaDate) => new Date(dayStart(d).getTime() - 1);

/** Works out the timeline. Throws a RangeError for a range that is backwards or too long for its grouping. */
export function simulate(input: SimulateInput): Simulation {
	const { from, to, group, today, now, plan, basePlan } = input;
	checkRange(from, to, group, input.limits ?? SIMULATE_LIMITS);
	const { main, rates } = plan;
	const missing = new Set<string>();
	const accounts = new Map(basePlan.accounts.map((a) => [a.id, a]));
	const nameOf = (id: string) => accounts.get(id)?.name ?? 'an account';
	const inMain = (amount: number, currency: string): number | null => {
		if (currency === main) return amount;
		if (canConvert(currency, main, rates)) return convert(amount, currency, main, rates);
		missing.add(currency);
		return null;
	};

	// -- RECORDED -- //

	// Each wallet's counts and the entries that touch it, so a balance at an instant reads only its own rows
	const walletKeys = new Map<string, { accountId: string; currency: string }>();
	const remember = (accountId: string, currency: string) =>
		walletKeys.set(key(accountId, currency), { accountId, currency });
	for (const w of input.wallets) remember(w.accountId, w.currency);
	for (const s of input.snapshots) remember(s.accountId, s.currency);
	for (const t of input.txns) {
		remember(t.accountId, t.currency);
		if (t.type === 'transfer' && t.toAccountId) remember(t.toAccountId, t.toCurrency ?? t.currency);
	}
	// Counts of each wallet, newest first and sorted once, so a balance at an instant takes the first one not after it
	const snapsOf = new Map<string, RecordedSnapshot[]>();
	for (const s of input.snapshots) {
		const k = key(s.accountId, s.currency);
		const list = snapsOf.get(k);
		if (list) list.push(s);
		else snapsOf.set(k, [s]);
	}
	for (const list of snapsOf.values())
		list.sort((a, b) => b.takenAt.getTime() - a.takenAt.getTime());
	// The entries that touch each account, once, so a wallet looks only at its own account's rows
	const txnsOfAccount = new Map<string, RecordedTxn[]>();
	for (const t of input.txns)
		for (const id of new Set([t.accountId, t.toAccountId])) {
			if (!id) continue;
			const list = txnsOfAccount.get(id);
			if (list) list.push(t);
			else txnsOfAccount.set(id, [t]);
		}
	const txnsOf = new Map<string, RecordedTxn[]>();
	for (const [k, w] of walletKeys)
		txnsOf.set(
			k,
			(txnsOfAccount.get(w.accountId) ?? []).filter(
				(t) => effectOn(t, w.accountId, w.currency) !== 0 || touches(t, w)
			)
		);
	let first: Date | null = input.firstRecordAt ?? null;
	for (const s of input.snapshots) if (!first || s.takenAt < first) first = s.takenAt;
	for (const t of input.txns) if (!first || t.occurredAt < first) first = t.occurredAt;
	const firstRecord = first ? toLocalDate(first) : null;

	/** Every wallet's recorded balance at an instant; null for a wallet with nothing recorded by then. */
	const recordedAt = (at: Date): Map<string, number | null> => {
		const out = new Map<string, number | null>();
		for (const [k, w] of walletKeys) {
			const snap = (snapsOf.get(k) ?? []).find((s) => s.takenAt <= at) ?? null;
			const rows = (txnsOf.get(k) ?? []).filter((t) => t.occurredAt <= at);
			out.set(
				k,
				!snap && rows.length === 0
					? null
					: balanceOf(
							w.accountId,
							w.currency,
							snap ? { amount: snap.amount, takenAt: snap.takenAt } : null,
							rows
						)
			);
		}
		return out;
	};
	/** The total in the main currency. `activeOnly` leaves out hidden accounts, as the plan does from today on. */
	const totalOf = (balances: ReadonlyMap<string, number | null>, activeOnly = false): number => {
		let sum = 0;
		for (const [k, b] of balances) {
			if (b === null) continue;
			if (activeOnly && accounts.get(walletKeys.get(k)?.accountId ?? '')?.archived) continue;
			const v = inMain(b, walletKeys.get(k)?.currency ?? main);
			if (v !== null) sum += v;
		}
		return sum;
	};

	// -- STEPPING THROUGH DAYS -- //

	const warnings: SimWarning[] = [];
	const minOf = (accountId: string, currency: string) =>
		currency === main ? (accounts.get(accountId)?.minBalance ?? 0) : 0;

	/** Applies flows day by day to a balance map from `start` to `end`, reporting low days. Returns the flags of the stretch. */
	function run(
		balance: Map<string, number | null>,
		flows: readonly PlanFlow[],
		start: ManilaDate,
		end: ManilaDate,
		source: 'replay' | 'simulated',
		state: { belowZero: Set<string>; belowMin: Set<string> },
		onDayEnd?: (day: ManilaDate, flags: { low: boolean; below: boolean }) => void
	) {
		const byDate = new Map<string, PlanFlow[]>();
		for (const f of flows)
			if (f.date >= start && f.date <= end) byDate.set(f.date, [...(byDate.get(f.date) ?? []), f]);
		let low = false;
		let below = false;
		for (let day = start; day <= end; day = addDays(day, 1)) {
			const todays = [...(byDate.get(day) ?? [])].sort(
				(a, b) =>
					ORDER[a.kind] - ORDER[b.kind] || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0)
			);
			const touched = new Set<string>();
			let dayLow = false;
			let dayBelow = false;
			for (const f of todays) {
				const k = key(f.accountId, f.currency);
				if (!walletKeys.has(k)) remember(f.accountId, f.currency);
				const sign = f.kind === 'in' ? 1 : -1;
				balance.set(k, (balance.get(k) ?? 0) + sign * f.amount);
				touched.add(k);
				if (f.kind === 'move') {
					const to = key(f.toAccountId ?? f.accountId, f.currency);
					if (!walletKeys.has(to)) remember(f.toAccountId ?? f.accountId, f.currency);
					balance.set(to, (balance.get(to) ?? 0) + f.amount);
					touched.add(to);
				}
			}
			// Judged at the end of the day, after the day's money in, moves and money out
			for (const [k, b] of balance) {
				if (b === null) continue;
				const w = walletKeys.get(k);
				if (!w) continue;
				const min = minOf(w.accountId, w.currency);
				if (b < 0) dayBelow = true;
				if (min > 0 && b < min) dayLow = true;
				if (!touched.has(k)) continue;
				const report = (kind: SimWarning['kind'], set: Set<string>, under: boolean) => {
					if (under && !set.has(k)) {
						set.add(k);
						if (warnings.length < MAX_WARNINGS)
							warnings.push({
								source,
								kind,
								date: day,
								accountId: w.accountId,
								accountName: nameOf(w.accountId),
								currency: w.currency,
								balance: b
							});
					} else if (!under) set.delete(k);
				};
				report('below_zero', state.belowZero, b < 0);
				if (min > 0) report('below_minimum', state.belowMin, b < min);
			}
			low ||= dayLow;
			below ||= dayBelow;
			onDayEnd?.(day, { low: dayLow, below: dayBelow });
		}
		return { low, below };
	}

	// -- THE FUTURE, ONCE -- //

	const futureEnds = new Map<ManilaDate, Map<string, number | null>>();
	const dayFlags = new Map<ManilaDate, { low: boolean; below: boolean }>();
	let future: ReturnType<typeof planFlows> | null = null;
	/** The total the simulation starts from: today's real balances of the active accounts. */
	let simStartTotal: number | null = null;
	if (to >= today) {
		const nowBalances = recordedAt(now);
		// Archived accounts are out of the plan from today on
		const start = new Map<string, number | null>();
		const mainNow = new Map<string, number>();
		for (const [k, b] of nowBalances) {
			const w = walletKeys.get(k);
			if (!w || accounts.get(w.accountId)?.archived) continue;
			start.set(k, b ?? 0);
			if (w.currency === main) mainNow.set(w.accountId, b ?? 0);
		}
		// The same flows as cashflow_forecast: active accounts, and today's main-currency balances so a split pays bills from money already there
		future = planFlows(
			{ ...plan, accounts: plan.accounts.filter((a) => !a.archived), balances: mainNow },
			{ mode: 'future', from: today, to, today }
		);
		// The ends of the periods the range asks for; days before the range only move the balances
		const ends = new Set<ManilaDate>();
		for (let s = from; s <= to;) {
			const e = periodEnd(s, to, group, input.weekStart);
			if (e >= today) ends.add(e);
			// And the day before a period starts, for its simulated start
			if (addDays(s, -1) >= today) ends.add(addDays(s, -1));
			s = addDays(e, 1);
		}
		simStartTotal = totalOf(start);
		const state = { belowZero: new Set<string>(), belowMin: new Set<string>() };
		run(start, future.flows, today, to, 'simulated', state, (day, flags) => {
			dayFlags.set(day, flags);
			if (ends.has(day)) futureEnds.set(day, new Map(start));
		});
	}
	/** Whether a simulated wallet was low or below zero on any day of a stretch. */
	const lowIn = (a: ManilaDate, b: ManilaDate) => {
		let low = false;
		let below = false;
		for (let d = a; d <= b; d = addDays(d, 1)) {
			const f = dayFlags.get(d);
			low ||= f?.low ?? false;
			below ||= f?.below ?? false;
		}
		return { low, below };
	};

	// -- MISSED -- //

	const missedEntries: SimEntry[] = [];
	let missedSeq = 0;
	const lastPast = addDays(today, -1);
	if (firstRecord && from <= lastPast) {
		const a = from > firstRecord ? from : firstRecord;
		const b = to < lastPast ? to : lastPast;
		if (a <= b) {
			for (const inc of basePlan.incomes) {
				const opts = { weekend: inc.weekendRule };
				for (const payday of occurrencesBetween(inc.schedule, a, b, opts)) {
					if (payday < inc.createdOn) continue;
					const next = occurrencesBetween(
						inc.schedule,
						addDays(payday, 1),
						addDays(payday, 800),
						opts
					)[0];
					const until = addDays(next ?? addDays(payday, 15), -1);
					// Still open: a pay logged late is not missed
					if (until >= today) continue;
					let seen = false;
					for (let d = payday; d <= until && !seen; d = addDays(d, 1))
						seen = basePlan.incomeDays.has(`${inc.accountId}|${d}`);
					if (seen) continue;
					missedEntries.push({
						id: `missed:${missedSeq++}`,
						source: 'missed',
						kind: 'in',
						date: payday,
						label: inc.label,
						accountId: inc.accountId,
						accountName: nameOf(inc.accountId),
						currency: main,
						amount: inc.expectedAmount,
						amountMain: inc.expectedAmount
					});
				}
			}
			const created = new Map(basePlan.bills.map((x) => [x.id, x.createdOn]));
			for (const d of billOccurrences(
				basePlan.bills,
				a,
				b,
				basePlan.overrides,
				basePlan.settled,
				new Map(basePlan.bills.map((x) => [x.id, x.usualAmount]))
			)) {
				if (d.paid || d.dueDate < (created.get(d.billId) ?? d.dueDate)) continue;
				missedEntries.push({
					id: `missed:${missedSeq++}`,
					source: 'missed',
					kind: 'out',
					date: d.dueDate,
					label: d.name,
					accountId: d.accountId,
					accountName: nameOf(d.accountId),
					currency: d.currency,
					amount: d.amount,
					amountMain: d.amount === null ? null : inMain(d.amount, d.currency)
				});
			}
		}
	}

	// -- PERIODS -- //

	const entries: SimEntry[] = [];
	// One wallet below zero over several past periods is reported once, not once per period
	const replayState = { belowZero: new Set<string>(), belowMin: new Set<string>() };
	const notes: PlanNote[] = [...(future?.notes ?? [])];
	const unknownRaw = [...(future?.unknown ?? [])];
	const periods: SimPeriod[] = [];

	// -- SPENDING GROUPS -- //

	const billNames = new Map<string, string>([
		...(input.billNames ?? []),
		...basePlan.bills.map((b) => [b.id, b.name] as const)
	]);
	/** Each group's label and kind, from the first entry that named it. */
	const groupInfo = new Map<string, { label: string; kind: SpendGroup['kind'] }>();
	const billGroup = (id: string, fallback: string): string => {
		const k = `bill:${id}`;
		if (!groupInfo.has(k)) groupInfo.set(k, { label: billNames.get(id) ?? fallback, kind: 'bill' });
		return k;
	};
	const categoryGroup = (category: string | null | undefined): string => {
		const name = (category ?? '').trim();
		if (!name) return OTHER_GROUP;
		const k = `cat:${name.toLowerCase()}`;
		if (!groupInfo.has(k)) groupInfo.set(k, { label: name, kind: 'category' });
		return k;
	};
	groupInfo.set(OTHER_GROUP, { label: '', kind: 'other' });
	/** Entries are ordered by date, source, then this key, then id: one total order whatever order the rows were read in. */
	const orderKey = new Map<SimEntry, string>();
	const seq = { replay: 0, simulated: 0 };

	const asEntry = (f: PlanFlow, source: 'replay' | 'simulated'): SimEntry => ({
		id: `${source}:${seq[source]++}`,
		source,
		kind: f.kind,
		date: f.date,
		label: f.label,
		accountId: f.accountId,
		accountName: f.accountName,
		...(f.toAccountId
			? { toAccountId: f.toAccountId, toAccountName: f.toAccountName ?? nameOf(f.toAccountId) }
			: {}),
		currency: f.currency,
		amount: f.amount,
		amountMain: inMain(f.amount, f.currency),
		...(f.origin === 'pretend' ? { pretend: true } : {})
	});
	/** A plan flow with what it does to the totals: money out is spending (its bill, else other), money in is received, a move is neither. */
	const flowEntry = (f: PlanFlow, source: 'replay' | 'simulated'): SimEntry => {
		const e = asEntry(f, source);
		if (f.kind === 'out') {
			e.groupKey = f.origin === 'bill' && f.refId ? billGroup(f.refId, f.label) : OTHER_GROUP;
			e.spentMain = e.amountMain;
		} else if (f.kind === 'in') e.receivedMain = e.amountMain;
		return e;
	};
	/** A recorded row as its entries: a transfer between own accounts is a move and spends nothing, but its fee is spending of its own. */
	const recordedEntries = (t: RecordedTxn): SimEntry[] => {
		const date = toLocalDate(t.occurredAt);
		const base = {
			id: t.id,
			source: 'recorded' as const,
			date,
			label: t.label,
			accountId: t.accountId,
			accountName: nameOf(t.accountId),
			currency: t.currency
		};
		const at = `${t.occurredAt.toISOString()}|${t.id}`;
		const out: SimEntry[] = [];
		const add = (e: SimEntry) => {
			orderKey.set(e, at);
			out.push(e);
		};
		const spending = () => (t.billId ? billGroup(t.billId, t.label) : categoryGroup(t.category));
		if (t.type === 'transfer') {
			const to = t.toAccountId ?? t.accountId;
			add({
				...base,
				kind: 'move',
				toAccountId: to,
				toAccountName: nameOf(to),
				amount: t.amount,
				amountMain: inMain(t.amount, t.currency)
			});
			if ((t.fee ?? 0) > 0) {
				const fee = t.fee ?? 0;
				const feeMain = inMain(fee, t.currency);
				add({
					...base,
					id: `${t.id}:fee`,
					label: 'Transfer fee',
					kind: 'out',
					amount: fee,
					amountMain: feeMain,
					groupKey: OTHER_GROUP,
					spentMain: feeMain
				});
			}
			return out;
		}
		const amount = Math.abs(t.amount);
		const amountMain = inMain(amount, t.currency);
		if (t.type === 'expense')
			add({
				...base,
				kind: 'out',
				amount,
				amountMain,
				groupKey: spending(),
				spentMain: amountMain
			});
		else if (t.type === 'refund')
			add({
				...base,
				kind: 'in',
				amount,
				amountMain,
				refund: true,
				groupKey: spending(),
				spentMain: amountMain === null ? null : -amountMain
			});
		else if (t.type === 'income')
			add({ ...base, kind: 'in', amount, amountMain, receivedMain: amountMain });
		// A reset is not spending (ops/ledger.ts), so a negative reset is an entry with no figure; any other negative count is untracked
		else if (t.amount < 0 && t.category !== 'reset')
			add({ ...base, kind: 'out', amount, amountMain, untrackedMain: amountMain });
		else if (t.amount < 0) add({ ...base, kind: 'out', amount, amountMain });
		else add({ ...base, kind: 'in', amount, amountMain });
		return out;
	};
	/** Adds up the entries that count, leaving out (and naming) a currency with no rate. */
	const sumOf = (list: readonly SimEntry[], left: Set<string>) => {
		let spent = 0;
		let received = 0;
		let untracked = 0;
		for (const e of list) {
			if (e.groupKey !== undefined) {
				if (e.spentMain === null || e.spentMain === undefined) left.add(e.currency);
				else spent += e.spentMain;
			} else if (e.receivedMain !== undefined) {
				if (e.receivedMain === null) left.add(e.currency);
				else received += e.receivedMain;
			} else if (e.untrackedMain !== undefined) {
				if (e.untrackedMain === null) left.add(e.currency);
				else untracked += e.untrackedMain;
			}
		}
		return { spent, received, untracked };
	};

	// Recorded entries once, by their Manila day, up to today: every period then adds its own days
	const recordedByDate = new Map<ManilaDate, SimEntry[]>();
	// Up to today even when the window ends earlier: the span totals of a past period run to today (a period reads its own days only)
	const lastRecordedDay = today;
	for (const t of input.txns) {
		const d = toLocalDate(t.occurredAt);
		if (d < from || d > lastRecordedDay) continue;
		const list = recordedByDate.get(d) ?? [];
		list.push(...recordedEntries(t));
		recordedByDate.set(d, list);
	}
	// The simulated flows once, by day
	const simulatedByDate = new Map<ManilaDate, SimEntry[]>();
	for (const f of future?.flows ?? []) {
		const list = simulatedByDate.get(f.date) ?? [];
		list.push(flowEntry(f, 'simulated'));
		simulatedByDate.set(f.date, list);
	}
	const entriesBetween = (
		byDate: ReadonlyMap<ManilaDate, SimEntry[]>,
		a: ManilaDate,
		b: ManilaDate
	) => {
		const out: SimEntry[] = [];
		for (let d = a; d <= b; d = addDays(d, 1)) out.push(...(byDate.get(d) ?? []));
		return out;
	};

	// -- SPAN TOTALS -- //

	// One pass over the days gives every period its running total across the span to today, so no period rescans entries.
	// Past periods: recorded, from the period start to today (a backward pass). Future periods: simulated, from today to the period end
	// (a forward pass). The period of today has none.
	type SpanSum = { spent: number; received: number; left: string[] };
	const pastSpan = new Map<ManilaDate, SpanSum>();
	const futureSpan = new Map<ManilaDate, SpanSum>();
	{
		const starts = new Set<ManilaDate>();
		const ends = new Set<ManilaDate>();
		for (let s = from; s <= to;) {
			const e = periodEnd(s, to, group, input.weekStart);
			if (e < today) starts.add(s);
			else if (s > today) ends.add(e);
			s = addDays(e, 1);
		}
		const keep = (spent: number, received: number, left: Set<string>): SpanSum => ({
			spent,
			received,
			left: [...left].sort()
		});
		if (starts.size > 0) {
			const left = new Set<string>();
			let spent = 0;
			let received = 0;
			for (let d = today; d >= from; d = addDays(d, -1)) {
				const sum = sumOf(recordedByDate.get(d) ?? [], left);
				spent += sum.spent;
				received += sum.received;
				if (starts.has(d)) pastSpan.set(d, keep(spent, received, left));
			}
		}
		if (ends.size > 0) {
			const left = new Set<string>();
			let spent = 0;
			let received = 0;
			for (let d = today; d <= to; d = addDays(d, 1)) {
				const sum = sumOf(simulatedByDate.get(d) ?? [], left);
				spent += sum.spent;
				received += sum.received;
				if (ends.has(d)) futureSpan.set(d, keep(spent, received, left));
			}
		}
	}

	for (let start = from; start <= to;) {
		const end = periodEnd(start, to, group, input.weekStart);
		const part: SimPeriod['part'] = end < today ? 'past' : start > today ? 'future' : 'mixed';
		const beforeFirst = !firstRecord || end < firstRecord;
		const lines = new Map<string, SimWallet>();
		const line = (k: string): SimWallet => {
			const seen = lines.get(k);
			if (seen) return seen;
			const w = walletKeys.get(k) ?? { accountId: '', currency: main };
			const made: SimWallet = {
				accountId: w.accountId,
				accountName: nameOf(w.accountId),
				currency: w.currency,
				archived: accounts.get(w.accountId)?.archived ?? false,
				recorded: null,
				replay: null,
				simulated: null,
				recordedMain: null,
				replayMain: null,
				simulatedMain: null
			};
			lines.set(k, made);
			return made;
		};
		let recordedStart: number | null = null;
		let recordedEnd: number | null = null;
		let replayEnd: number | null = null;
		let simulatedStart: number | null = null;
		let simulatedEnd: number | null = null;
		let low = false;
		let below = false;
		const left = new Set<string>();
		let recordedSpent: number | null = null;
		let recordedReceived: number | null = null;
		let recordedUntracked: number | null = null;
		let replaySpent: number | null = null;
		let replayReceived: number | null = null;
		let simulatedSpent: number | null = null;
		let simulatedReceived: number | null = null;

		if (part !== 'future' && !beforeFirst) {
			// What was recorded in the period, up to now for the period of today
			const done = entriesBetween(recordedByDate, start, part === 'past' ? end : today);
			const sum = sumOf(done, left);
			recordedSpent = sum.spent;
			recordedReceived = sum.received;
			recordedUntracked = sum.untracked;
			if (input.detail) entries.push(...done);
			const startBalances = recordedAt(before(start));
			const endBalances = recordedAt(part === 'past' ? endOf(end) : now);
			recordedStart = totalOf(startBalances);
			// Up to today a hidden account's money was real; from today on the plan no longer counts it, as the simulated start does not
			recordedEnd = totalOf(endBalances, part !== 'past');
			for (const [k, b] of endBalances) if (b !== null) line(k).recorded = b;
			if (part === 'past') {
				// The replay starts from what was really there when the period began. In the period of the first record it starts the day
				// after that record, from what was recorded by then, so an opening count is never read as money the plan failed to bring in
				const opening = firstRecord !== null && firstRecord > start;
				const replayFrom = opening && firstRecord ? addDays(firstRecord, 1) : start;
				const replay =
					replayFrom <= end
						? planFlows(plan, { mode: 'replay', from: replayFrom, to: end, today })
						: { flows: [], unknown: [], notes: [] };
				notes.push(...replay.notes);
				unknownRaw.push(...replay.unknown);
				const balance = new Map(
					opening && firstRecord ? recordedAt(endOf(firstRecord)) : startBalances
				);
				const flags = run(balance, replay.flows, replayFrom, end, 'replay', replayState);
				low ||= flags.low;
				below ||= flags.below;
				replayEnd = totalOf(balance);
				for (const [k, b] of balance) if (b !== null) line(k).replay = b;
				const replayed = replay.flows.map((f) => flowEntry(f, 'replay'));
				const replaySum = sumOf(replayed, left);
				replaySpent = replaySum.spent;
				replayReceived = replaySum.received;
				if (input.detail) entries.push(...replayed);
			}
		}
		if (part !== 'past' && future) {
			const ends = futureEnds.get(end);
			const dayBefore = futureEnds.get(addDays(start, -1));
			simulatedStart = part === 'mixed' || !dayBefore ? simStartTotal : totalOf(dayBefore);
			if (ends) {
				simulatedEnd = totalOf(ends);
				for (const [k, b] of ends) if (b !== null) line(k).simulated = b;
			}
			// Low and below in the simulated days of this period
			const lo = start > today ? start : today;
			const flags = lowIn(lo, end);
			low ||= flags.low;
			below ||= flags.below;
			const coming = entriesBetween(simulatedByDate, lo, end);
			const comingSum = sumOf(coming, left);
			simulatedSpent = comingSum.spent;
			simulatedReceived = comingSum.received;
			if (input.detail) entries.push(...coming);
		}
		// The span: past from its start to today (not before the first record), future from today to its end
		const spanSum =
			part === 'past' && !beforeFirst
				? pastSpan.get(start)
				: part === 'future'
					? futureSpan.get(end)
					: undefined;
		const missedHere = missedEntries.filter((m) => m.date >= start && m.date <= end);
		if (input.detail) entries.push(...missedHere);
		periods.push({
			from: start,
			to: end,
			part,
			beforeFirstRecord: beforeFirst,
			recordedStart,
			recordedEnd,
			replayEnd,
			simulatedStart,
			simulatedEnd,
			gap: recordedEnd !== null && replayEnd !== null ? recordedEnd - replayEnd : null,
			missed: missedHere.length,
			low,
			below,
			recordedSpent,
			recordedReceived,
			recordedUntracked,
			replaySpent,
			replayReceived,
			simulatedSpent,
			simulatedReceived,
			leftOut: [...left].sort(),
			spanFrom: spanSum ? (part === 'past' ? start : today) : null,
			spanTo: spanSum ? (part === 'past' ? today : end) : null,
			spanSource: spanSum ? (part === 'past' ? 'recorded' : 'simulated') : null,
			spanSpent: spanSum ? spanSum.spent : null,
			spanReceived: spanSum ? spanSum.received : null,
			spanLeftOut: spanSum ? spanSum.left : [],
			wallets: [...lines.values()]
				.filter((l) => !(l.archived && l.recorded === 0 && l.replay === 0))
				// The main-currency twin of each balance: a currency with no rate stays null (and is named in `missing`), never zero
				.map((l) => ({
					...l,
					recordedMain: l.recorded === null ? null : inMain(l.recorded, l.currency),
					replayMain: l.replay === null ? null : inMain(l.replay, l.currency),
					simulatedMain: l.simulated === null ? null : inMain(l.simulated, l.currency)
				}))
				.sort((a, b) =>
					a.accountName < b.accountName
						? -1
						: a.accountName > b.accountName
							? 1
							: a.currency < b.currency
								? -1
								: 1
				)
		});
		start = addDays(end, 1);
	}

	// -- THE ANSWER -- //

	const unknown = new Map<string, SimUnknown>();
	for (const u of unknownRaw) {
		const k = `${u.kind}|${u.label}`;
		const seen = unknown.get(k);
		if (seen) {
			seen.count++;
			if (u.date < seen.first) seen.first = u.date;
		} else unknown.set(k, { kind: u.kind, label: u.label, count: 1, first: u.date });
	}
	const sorted = entries.sort((a, b) => {
		if (a.date !== b.date) return a.date < b.date ? -1 : 1;
		if (a.source !== b.source) return SOURCE_ORDER[a.source] - SOURCE_ORDER[b.source];
		const ka = orderKey.get(a) ?? '';
		const kb = orderKey.get(b) ?? '';
		if (ka !== kb) return ka < kb ? -1 : 1;
		return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
	});
	// The spending of the whole range per source and group, from the same entries the totals add up (so the lines add up to spent)
	const breakdownOf = (source: Source): SpendBreakdown => {
		const sums = new Map<string, { amount: number; count: number }>();
		for (const e of sorted) {
			if (e.source !== source || e.groupKey === undefined) continue;
			if (e.spentMain === null || e.spentMain === undefined) continue;
			const seen = sums.get(e.groupKey) ?? { amount: 0, count: 0 };
			seen.amount += e.spentMain;
			seen.count += 1;
			sums.set(e.groupKey, seen);
		}
		const all = [...sums.entries()]
			.map(([key, v]) => ({ key, ...v }))
			.sort((a, b) => b.amount - a.amount || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
		const shown = all.slice(0, BREAKDOWN_GROUPS).map((g): SpendGroup => ({
			key: g.key,
			label: groupInfo.get(g.key)?.label ?? '',
			kind: groupInfo.get(g.key)?.kind ?? 'other',
			amount: g.amount,
			count: g.count
		}));
		const rest = all.slice(BREAKDOWN_GROUPS);
		return {
			groups: shown,
			more: rest.length
				? {
						amount: rest.reduce((a, g) => a + g.amount, 0),
						count: rest.reduce((a, g) => a + g.count, 0),
						groups: rest.length
					}
				: null
		};
	};
	const page = input.page;
	const inGroup =
		page?.groupKey === undefined ? sorted : sorted.filter((e) => e.groupKey === page.groupKey);
	missing.delete('');
	return {
		from,
		to,
		group,
		today,
		currency: main,
		firstRecord,
		periods,
		...(input.detail
			? {
					breakdown: {
						recorded: breakdownOf('recorded'),
						replay: breakdownOf('replay'),
						simulated: breakdownOf('simulated')
					},
					...(page
						? {
								entries: inGroup.slice(page.offset, page.offset + page.limit),
								entriesTotal: inGroup.length,
								entriesOffset: page.offset,
								...(inGroup.length > page.offset + page.limit
									? { entriesOmitted: inGroup.length - page.offset - page.limit }
									: {})
							}
						: {
								entries: sorted.slice(0, MAX_ENTRIES),
								...(sorted.length > MAX_ENTRIES
									? { entriesOmitted: sorted.length - MAX_ENTRIES }
									: {})
							})
				}
			: {}),
		warnings,
		unknown: [...unknown.values()].sort((a, b) =>
			a.first < b.first ? -1 : a.first > b.first ? 1 : 0
		),
		notes,
		missing: [...missing].sort()
	};
}

/** Recorded first, then the replay, the simulation and what was missed, on one day. */
const SOURCE_ORDER: Record<Source, number> = { recorded: 0, replay: 1, simulated: 2, missed: 3 };

/** A transfer into a wallet in another currency touches it even when its arrival is not yet known. */
function touches(t: RecordedTxn, w: { accountId: string; currency: string }): boolean {
	return (
		(t.accountId === w.accountId && t.currency === w.currency) ||
		(t.type === 'transfer' &&
			t.toAccountId === w.accountId &&
			(t.toCurrency ?? t.currency) === w.currency)
	);
}
