// THE CASH-FLOW FORECAST: A PURE FUNCTION FROM TODAY'S WALLET BALANCES AND THE MONEY THAT WILL COME IN, GO OUT AND BE MOVED, TO THE BALANCES AT
// THE END OF EACH DAY, WEEK OR MONTH. The assistant used to add bills up by hand and got the weeks wrong; here the code does it, once, and
// the assistant quotes it. Rules that hold:
// - Every amount is an integer in the smallest unit of its own currency. Wallets of different currencies are never added: each is converted
//   to the main currency at the stored rates (integer maths, finance/fx.ts) for the totals, and a currency with no rate is named and left
//   out of every total, never counted as zero.
// - A wallet is an account in one currency. Money in lands in a wallet, money out leaves one, and a move between two own wallets in the
//   same currency changes the accounts and never the total.
// - Within a day: money in first, then moves, then money out. A wallet that falls below zero is reported on the first day it does (and once
//   more if it falls again after being back above), so a dip inside a week is not hidden by the week's end balance.
// - The range is at most 366 days. Weeks start on the person's chosen day, the first and last period may be partial.

// -- TYPES -- //
import type { ManilaDate } from './dates';
import type { Rates } from './fx';
// -- MODULES -- //
import { addDays, daysInMonth, diffDays, parseDate, weekday } from './dates';
import { canConvert, convert } from './fx';

export type Group = 'day' | 'week' | 'month' | 'year';

/** How long a range may be, in days, in all and by day and by week. The forecast verb keeps its 366 days; the simulation passes its own. */
export type RangeLimits = { maxDays: number; maxDailyDays: number; maxWeeklyDays: number };

export type ForecastWallet = {
	accountId: string;
	accountName: string;
	currency: string;
	/** Minor units. Negative for an overdraft. */
	balance: number;
};

export type ForecastFlow = {
	kind: 'in' | 'out' | 'move';
	date: ManilaDate;
	label: string;
	/** The wallet money lands in (in), leaves (out), or leaves (move). */
	accountId: string;
	accountName: string;
	/** Only for a move: the wallet it lands in. */
	toAccountId?: string;
	toAccountName?: string;
	currency: string;
	/** Minor units, above zero. */
	amount: number;
};

/** Something that will happen but whose amount is not known: listed, never counted. */
export type ForecastUnknown = { kind: 'income' | 'bill'; date: ManilaDate; label: string };

export type ForecastInput = {
	from: ManilaDate;
	to: ManilaDate;
	group: Group;
	/** 0 is Sunday, 1 is Monday. */
	weekStart: number;
	main: string;
	rates: Rates;
	wallets: readonly ForecastWallet[];
	flows: readonly ForecastFlow[];
	unknown?: readonly ForecastUnknown[];
	/** The range limits. The forecast verb's own when not given. */
	limits?: RangeLimits;
};

export type PeriodFlow = ForecastFlow & {
	/** The amount in the main currency, or null when its currency has no rate. */
	amountMain: number | null;
};

export type WalletLine = {
	accountId: string;
	accountName: string;
	currency: string;
	start: number;
	end: number;
	/** The end balance in the main currency, or null when its currency has no rate. */
	endMain: number | null;
};

export type Period = {
	from: ManilaDate;
	to: ManilaDate;
	/** The total of every wallet with a rate, in the main currency, at the start and at the end of the period. */
	startTotal: number;
	endTotal: number;
	/** Money in and out of the person's accounts in the period, in the main currency. Moves are in neither. */
	inTotal: number;
	outTotal: number;
	/**
	 * What rounding each wallet and each flow on its own to the main currency leaves over, so that
	 * endTotal = startTotal + inTotal - outTotal + rounding always holds. Zero when everything is in the main currency.
	 */
	rounding: number;
	ins: PeriodFlow[];
	outs: PeriodFlow[];
	moves: PeriodFlow[];
	/** The wallets that changed in the period. */
	wallets: WalletLine[];
};

export type Warning = {
	date: ManilaDate;
	accountId: string;
	accountName: string;
	currency: string;
	/** The balance after that day's flows, minor units. */
	balance: number;
	/** True when the wallet was already below zero at the start. */
	already: boolean;
};

export type Forecast = {
	from: ManilaDate;
	to: ManilaDate;
	group: Group;
	currency: string;
	startTotal: number;
	endTotal: number;
	/** The sum of the periods' rounding: endTotal = startTotal + all money in - all money out + rounding. */
	rounding: number;
	periods: Period[];
	/** Every wallet at the end of the range. */
	endWallets: WalletLine[];
	/** Currencies held or moved with no rate: left out of every total. */
	missing: string[];
	unknown: ForecastUnknown[];
	warnings: Warning[];
};

// -- CONSTANTS -- //

export const MAX_FORECAST_DAYS = 366;
/** A forecast by day is long to read: past this many days it is by week or month. */
export const MAX_DAILY_DAYS = 62;
/** The simulation reaches 5 years each way (BTL-20261029-0117): 1827 days, by week at most 2 years. */
export const MAX_SIMULATE_DAYS = 1827;
export const MAX_WEEKLY_DAYS = 731;
export const FORECAST_LIMITS: RangeLimits = {
	maxDays: MAX_FORECAST_DAYS,
	maxDailyDays: MAX_DAILY_DAYS,
	maxWeeklyDays: MAX_FORECAST_DAYS
};
export const SIMULATE_LIMITS: RangeLimits = {
	maxDays: MAX_SIMULATE_DAYS,
	maxDailyDays: MAX_DAILY_DAYS,
	maxWeeklyDays: MAX_WEEKLY_DAYS
};
const MAX_WARNINGS = 30;
const ORDER = { in: 0, move: 1, out: 2 } as const;

// -- FUNCTIONS -- //

/** The last day of the period that starts on `start`, for the grouping, never past `to`. */
export function periodEnd(
	start: ManilaDate,
	to: ManilaDate,
	group: Group,
	weekStart: number
): ManilaDate {
	let end: ManilaDate = start;
	if (group === 'week') {
		// Up to the day before the next week starts
		const toNext = (((weekStart - weekday(start)) % 7) + 7) % 7 || 7;
		end = addDays(start, toNext - 1);
	} else if (group === 'month') {
		const p = parseDate(start);
		if (p) end = `${start.slice(0, 8)}${String(daysInMonth(p.year, p.month)).padStart(2, '0')}`;
	} else if (group === 'year') {
		end = `${start.slice(0, 4)}-12-31`;
	}
	return end > to ? to : end;
}

const key = (accountId: string, currency: string) => `${accountId}|${currency}`;

/** An amount in the main currency, or null when its currency has no known rate. The same currency needs none. */
function inMain(amount: number, currency: string, main: string, rates: Rates): number | null {
	if (currency === main) return amount;
	return canConvert(currency, main, rates) ? convert(amount, currency, main, rates) : null;
}

/** Throws a RangeError for a range that is backwards or longer than the limits allow for its grouping. */
export function checkRange(
	from: ManilaDate,
	to: ManilaDate,
	group: Group,
	limits: RangeLimits = FORECAST_LIMITS
): number {
	const days = diffDays(to, from) + 1;
	if (days < 1) throw new RangeError('The end date is before the start date.');
	if (days > limits.maxDays)
		throw new RangeError(`A forecast covers at most ${limits.maxDays} days.`);
	if (group === 'day' && days > limits.maxDailyDays)
		throw new RangeError(
			`By day it covers at most ${limits.maxDailyDays} days: use week or month.`
		);
	if (group === 'week' && days > limits.maxWeeklyDays)
		throw new RangeError(
			`By week it covers at most ${limits.maxWeeklyDays} days: use month or year.`
		);
	return days;
}

/** Works out the forecast. Throws a RangeError for a range that is backwards, longer than 366 days, or by day for more than 62. */
export function forecast(input: ForecastInput): Forecast {
	checkRange(input.from, input.to, input.group, input.limits);

	const { main, rates } = input;
	const missing = new Set<string>();
	const names = new Map<string, { accountId: string; accountName: string; currency: string }>();
	const balance = new Map<string, number>();
	const remember = (accountId: string, accountName: string, currency: string) => {
		const k = key(accountId, currency);
		if (!names.has(k)) {
			names.set(k, { accountId, accountName, currency });
			balance.set(k, balance.get(k) ?? 0);
		}
		return k;
	};
	for (const w of input.wallets)
		balance.set(remember(w.accountId, w.accountName, w.currency), w.balance);
	// A wallet a flow needs but the account does not hold yet starts at zero
	for (const f of input.flows) {
		remember(f.accountId, f.accountName, f.currency);
		if (f.kind === 'move' && f.toAccountId)
			remember(f.toAccountId, f.toAccountName ?? '', f.currency);
	}

	const total = (): number => {
		let sum = 0;
		for (const [k, b] of balance) {
			const v = inMain(b, names.get(k)?.currency ?? main, main, rates);
			if (v === null) missing.add(names.get(k)?.currency ?? '');
			else sum += v;
		}
		return sum;
	};
	const snapshot = () => new Map(balance);
	const lineOf = (k: string, start: number, end: number): WalletLine => {
		const n = names.get(k);
		const currency = n?.currency ?? main;
		return {
			accountId: n?.accountId ?? '',
			accountName: n?.accountName ?? '',
			currency,
			start,
			end,
			endMain: inMain(end, currency, main, rates)
		};
	};
	const withMain = (f: ForecastFlow): PeriodFlow => {
		const amountMain = inMain(f.amount, f.currency, main, rates);
		if (amountMain === null) missing.add(f.currency);
		return { ...f, amountMain };
	};

	const byDate = new Map<string, ForecastFlow[]>();
	for (const f of input.flows) {
		if (f.date < input.from || f.date > input.to) continue;
		byDate.set(f.date, [...(byDate.get(f.date) ?? []), f]);
	}

	const periods: Period[] = [];
	const warnings: Warning[] = [];
	const below = new Set<string>();
	// A wallet that is already below zero is reported once, at the start
	for (const [k, b] of balance)
		if (b < 0) {
			below.add(k);
			const n = names.get(k);
			if (n && warnings.length < MAX_WARNINGS)
				warnings.push({ ...n, date: input.from, balance: b, already: true });
		}

	const startTotal = total();
	for (let start = input.from; start <= input.to;) {
		const end = periodEnd(start, input.to, input.group, input.weekStart);
		const before = snapshot();
		const beforeTotal = total();
		const ins: PeriodFlow[] = [];
		const outs: PeriodFlow[] = [];
		const moves: PeriodFlow[] = [];
		for (let day = start; day <= end; day = addDays(day, 1)) {
			const todays = [...(byDate.get(day) ?? [])].sort(
				(a, b) =>
					ORDER[a.kind] - ORDER[b.kind] || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0)
			);
			const touched = new Set<string>();
			for (const f of todays) {
				const k = key(f.accountId, f.currency);
				const flow = withMain(f);
				if (f.kind === 'in') {
					balance.set(k, (balance.get(k) ?? 0) + f.amount);
					ins.push(flow);
				} else if (f.kind === 'out') {
					balance.set(k, (balance.get(k) ?? 0) - f.amount);
					outs.push(flow);
				} else {
					balance.set(k, (balance.get(k) ?? 0) - f.amount);
					const to = key(f.toAccountId ?? f.accountId, f.currency);
					balance.set(to, (balance.get(to) ?? 0) + f.amount);
					moves.push(flow);
					touched.add(to);
				}
				touched.add(k);
			}
			// Below zero is judged at the end of the day, after the day's money in, moves and money out
			for (const k of touched) {
				const b = balance.get(k) ?? 0;
				if (b < 0 && !below.has(k)) {
					below.add(k);
					const n = names.get(k);
					if (n && warnings.length < MAX_WARNINGS)
						warnings.push({ ...n, date: day, balance: b, already: false });
				} else if (b >= 0) below.delete(k);
			}
		}
		const wallets: WalletLine[] = [];
		for (const [k, now] of balance) {
			const was = before.get(k) ?? 0;
			if (now !== was) wallets.push(lineOf(k, was, now));
		}
		const periodEndTotal = total();
		const inTotal = ins.reduce((s, f) => s + (f.amountMain ?? 0), 0);
		const outTotal = outs.reduce((s, f) => s + (f.amountMain ?? 0), 0);
		periods.push({
			from: start,
			to: end,
			startTotal: beforeTotal,
			endTotal: periodEndTotal,
			inTotal,
			outTotal,
			rounding: periodEndTotal - beforeTotal - inTotal + outTotal,
			ins,
			outs,
			moves,
			wallets: wallets.sort((a, b) =>
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

	const start = new Map<string, number>();
	for (const w of input.wallets) start.set(key(w.accountId, w.currency), w.balance);
	const endWallets = [...balance]
		.map(([k, end]) => lineOf(k, start.get(k) ?? 0, end))
		.sort((a, b) =>
			a.accountName < b.accountName
				? -1
				: a.accountName > b.accountName
					? 1
					: a.currency < b.currency
						? -1
						: 1
		);
	missing.delete('');
	return {
		from: input.from,
		to: input.to,
		group: input.group,
		currency: main,
		startTotal,
		endTotal: total(),
		rounding: periods.reduce((sum, p) => sum + p.rounding, 0),
		periods,
		endWallets,
		missing: [...missing].sort(),
		unknown: [...(input.unknown ?? [])].sort((a, b) =>
			a.date < b.date ? -1 : a.date > b.date ? 1 : 0
		),
		warnings
	};
}
