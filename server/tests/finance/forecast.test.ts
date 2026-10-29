// THE CASH-FLOW FORECAST ENGINE: PERIODS, WEEK STARTS, THE ORDER WITHIN A DAY, MOVES THAT NEVER CHANGE THE TOTAL, BELOW ZERO, CURRENCIES AND RATES

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import type { Rates } from '../../src/lib/finance/fx';
import {
	forecast,
	MAX_DAILY_DAYS,
	MAX_FORECAST_DAYS,
	MAX_SIMULATE_DAYS,
	SIMULATE_LIMITS,
	type ForecastFlow,
	type ForecastInput,
	type ForecastWallet
} from '../../src/lib/finance/forecast';
import { addDays } from '../../src/lib/finance/dates';

// -- CONSTANTS -- //

const RATES: Rates = { PHP: '56', JPY: '157', EUR: '0.92' };

const RCBC = { accountId: 'rcbc', accountName: 'RCBC' };
const GCASH = { accountId: 'gcash', accountName: 'GCash' };
const MAYA = { accountId: 'maya', accountName: 'Maya' };

const wallets: ForecastWallet[] = [
	{ ...RCBC, currency: 'PHP', balance: 5_000_00 },
	{ ...GCASH, currency: 'PHP', balance: 1_000_00 },
	{ ...MAYA, currency: 'PHP', balance: 0 }
];

// -- FUNCTIONS -- //

const flow = (
	kind: 'in' | 'out',
	date: string,
	label: string,
	who: { accountId: string; accountName: string },
	amount: number,
	currency = 'PHP'
): ForecastFlow => ({ kind, date, label, ...who, currency, amount });

const move = (
	date: string,
	from: typeof RCBC,
	to: typeof RCBC,
	amount: number,
	currency = 'PHP'
): ForecastFlow => ({
	kind: 'move',
	date,
	label: 'Split',
	...from,
	toAccountId: to.accountId,
	toAccountName: to.accountName,
	currency,
	amount
});

function run(over: Partial<ForecastInput> = {}) {
	return forecast({
		from: '2026-10-27',
		to: '2026-12-31',
		group: 'week',
		weekStart: 1,
		main: 'PHP',
		rates: RATES,
		wallets,
		flows: [],
		...over
	});
}

/** Every number anywhere in a result is a whole number. */
function allIntegers(value: unknown): boolean {
	if (typeof value === 'number') return Number.isInteger(value);
	if (Array.isArray(value)) return value.every(allIntegers);
	if (value && typeof value === 'object') return Object.values(value).every(allIntegers);
	return true;
}

// -- TESTS -- //

describe('periods', () => {
	it('splits a range into weeks that start on the chosen day, the first and last may be partial', () => {
		// 2026-10-27 is a Tuesday
		const monday = run({ to: '2026-11-15', weekStart: 1 });
		expect(monday.periods.map((p) => [p.from, p.to])).toEqual([
			['2026-10-27', '2026-11-01'],
			['2026-11-02', '2026-11-08'],
			['2026-11-09', '2026-11-15']
		]);
		const sunday = run({ to: '2026-11-15', weekStart: 0 });
		expect(sunday.periods.map((p) => [p.from, p.to])).toEqual([
			['2026-10-27', '2026-10-31'],
			['2026-11-01', '2026-11-07'],
			['2026-11-08', '2026-11-14'],
			['2026-11-15', '2026-11-15']
		]);
	});

	it('splits by month through the end of each month, and by day', () => {
		const months = run({ group: 'month', to: '2027-01-10' });
		expect(months.periods.map((p) => [p.from, p.to])).toEqual([
			['2026-10-27', '2026-10-31'],
			['2026-11-01', '2026-11-30'],
			['2026-12-01', '2026-12-31'],
			['2027-01-01', '2027-01-10']
		]);
		const days = run({ group: 'day', to: '2026-10-29' });
		expect(days.periods.map((p) => p.from)).toEqual(['2026-10-27', '2026-10-28', '2026-10-29']);
		expect(run({ group: 'week', to: '2026-10-27' }).periods).toHaveLength(1);
	});

	it('covers every day exactly once, with each period starting where the last ended', () => {
		for (const group of ['day', 'week', 'month'] as const) {
			const out = run({ group, to: '2026-12-20', weekStart: 0 });
			expect(out.periods[0]?.from).toBe('2026-10-27');
			expect(out.periods.at(-1)?.to).toBe('2026-12-20');
			for (let i = 1; i < out.periods.length; i++)
				expect(out.periods[i]?.from).toBe(addDays(out.periods[i - 1]?.to ?? '', 1));
		}
	});

	it('refuses a range that is backwards, over 366 days, or by day over 62', () => {
		expect(() => run({ to: '2026-10-26' })).toThrow(RangeError);
		expect(() => run({ to: '2027-10-28' })).toThrow(/at most 366/);
		expect(run({ to: '2027-10-27', group: 'month' }).periods.length).toBeGreaterThan(10);
		expect(MAX_FORECAST_DAYS).toBe(366);
		expect(() => run({ group: 'day', to: addDays('2026-10-27', MAX_DAILY_DAYS) })).toThrow(
			/at most 62/
		);
		expect(
			run({ group: 'day', to: addDays('2026-10-27', MAX_DAILY_DAYS - 1) }).periods
		).toHaveLength(62);
	});
});

describe('money in, out and moved', () => {
	const flows = [
		flow('in', '2026-10-30', 'Salary', RCBC, 25_000_00),
		flow('out', '2026-11-01', 'Rent', RCBC, 8_000_00),
		flow('out', '2026-11-03', 'Meralco', GCASH, 1_500_00),
		flow('in', '2026-11-15', 'Salary', RCBC, 25_000_00),
		flow('out', '2026-11-20', 'Internet', GCASH, 1_000_00),
		move('2026-10-30', RCBC, MAYA, 2_000_00)
	];

	it('adds the balance of each wallet as the days pass', () => {
		const out = run({ flows, to: '2026-11-30', group: 'month' });
		expect(out.startTotal).toBe(6_000_00);
		// 6000 + 25000 - 8000 - 1500 + 25000 - 1000 = 45500
		expect(out.endTotal).toBe(45_500_00);
		const [oct, nov] = out.periods;
		expect(oct).toMatchObject({
			startTotal: 6_000_00,
			endTotal: 31_000_00,
			inTotal: 25_000_00,
			outTotal: 0
		});
		expect(nov).toMatchObject({
			startTotal: 31_000_00,
			endTotal: 45_500_00,
			inTotal: 25_000_00,
			outTotal: 10_500_00
		});
		const end = Object.fromEntries(out.endWallets.map((w) => [w.accountId, w.end]));
		expect(end).toEqual({
			rcbc: 5_000_00 + 25_000_00 - 2_000_00 - 8_000_00 + 25_000_00,
			gcash: 1_000_00 - 2_500_00,
			maya: 2_000_00
		});
	});

	it('keeps the total when money moves between accounts, and shows where it went', () => {
		const withMove = run({ flows, to: '2026-11-30' });
		const without = run({ flows: flows.filter((f) => f.kind !== 'move'), to: '2026-11-30' });
		expect(withMove.endTotal).toBe(without.endTotal);
		expect(withMove.periods.map((p) => p.endTotal)).toEqual(without.periods.map((p) => p.endTotal));
		const weekOfMove = withMove.periods.find((p) => p.moves.length > 0);
		expect(weekOfMove?.moves[0]).toMatchObject({
			amount: 2_000_00,
			amountMain: 2_000_00,
			toAccountName: 'Maya'
		});
		// A move is neither money in nor out
		expect(weekOfMove?.inTotal).toBe(25_000_00);
		expect(weekOfMove?.wallets.map((w) => w.accountId).sort()).toEqual(['maya', 'rcbc']);
	});

	it('lists, for each period, only the wallets that changed, with their start and end', () => {
		const out = run({ flows, to: '2026-11-30', group: 'month' });
		const nov = out.periods[1];
		// Maya did not change in November
		expect(nov?.wallets.map((w) => [w.accountId, w.start, w.end])).toEqual([
			['gcash', 1_000_00, -1_500_00],
			['rcbc', 28_000_00, 45_000_00]
		]);
	});

	it('is the same every time for the same input', () => {
		expect(JSON.stringify(run({ flows }))).toBe(JSON.stringify(run({ flows })));
	});

	it('puts money in first, then moves, then money out, within a day', () => {
		const out = run({
			group: 'day',
			to: '2026-10-28',
			wallets: [{ ...RCBC, currency: 'PHP', balance: 0 }],
			flows: [
				flow('out', '2026-10-28', 'Rent', RCBC, 1_000_00),
				flow('in', '2026-10-28', 'Salary', RCBC, 1_000_00)
			]
		});
		// Paid out of the pay of the same day: no dip
		expect(out.warnings).toEqual([]);
		expect(out.endTotal).toBe(0);
	});

	it('gives whole numbers only', () => {
		const out = run({ flows, to: '2026-12-31', group: 'week' });
		expect(allIntegers(out)).toBe(true);
	});
});

describe('the 9-week tally from the live chat', () => {
	// One chat counted a monthly bill of 1,000 as 10,000 after adding week by week answers by hand. Here the same bills, week by week,
	// are checked against a plain day by day count.
	const bills = [
		flow('out', '2026-11-01', 'Water', GCASH, 1_000_00),
		flow('out', '2026-11-05', 'Phone', GCASH, 899_00),
		flow('out', '2026-11-20', 'Internet', GCASH, 1_699_00),
		flow('out', '2026-12-01', 'Water', GCASH, 1_000_00),
		flow('out', '2026-12-05', 'Phone', GCASH, 899_00),
		flow('out', '2026-12-20', 'Internet', GCASH, 1_699_00),
		flow('out', '2026-10-28', 'Rent', RCBC, 8_000_00),
		flow('out', '2026-11-28', 'Rent', RCBC, 8_000_00)
	];
	const pay = [
		flow('in', '2026-10-30', 'Salary', RCBC, 25_000_00),
		flow('in', '2026-11-15', 'Salary', RCBC, 25_000_00),
		flow('in', '2026-11-30', 'Salary', RCBC, 25_000_00),
		flow('in', '2026-12-15', 'Salary', RCBC, 25_000_00)
	];

	it('counts each bill once, and every week ends where the next begins', () => {
		const out = run({ flows: [...bills, ...pay], to: '2026-12-29', group: 'week' });
		expect(out.periods).toHaveLength(10);
		for (let i = 1; i < out.periods.length; i++)
			expect(out.periods[i]?.startTotal).toBe(out.periods[i - 1]?.endTotal);
		const billsOut = out.periods.reduce((s, p) => s + p.outTotal, 0);
		const paid = out.periods.reduce((s, p) => s + p.inTotal, 0);
		expect(billsOut).toBe(bills.reduce((s, f) => s + f.amount, 0));
		expect(paid).toBe(100_000_00);
		expect(out.endTotal).toBe(out.startTotal + paid - billsOut);
		// The water bill of 1,000 shows once in November and once in December, never ten times
		const water = out.periods.flatMap((p) => p.outs).filter((f) => f.label === 'Water');
		expect(water.map((f) => [f.date, f.amount])).toEqual([
			['2026-11-01', 1_000_00],
			['2026-12-01', 1_000_00]
		]);
	});

	it('agrees with a day by day count, whatever the grouping', () => {
		const flows = [...bills, ...pay];
		const byDay = run({ flows, to: '2026-12-29', group: 'month' });
		for (const group of ['week', 'month'] as const) {
			const out = run({ flows, to: '2026-12-29', group });
			expect(out.endTotal).toBe(byDay.endTotal);
			expect(out.endWallets).toEqual(byDay.endWallets);
		}
		let total = 6_000_00;
		for (const f of flows) total += f.kind === 'in' ? f.amount : -f.amount;
		expect(byDay.endTotal).toBe(total);
	});
});

describe('below zero', () => {
	it('reports the first day a wallet falls below zero, even when the week ends above it', () => {
		const out = run({
			group: 'week',
			to: '2026-11-08',
			wallets: [{ ...GCASH, currency: 'PHP', balance: 500_00 }],
			flows: [
				flow('out', '2026-10-29', 'Phone', GCASH, 900_00),
				flow('in', '2026-11-05', 'Top up', GCASH, 2_000_00)
			]
		});
		expect(out.warnings).toEqual([
			{
				accountId: 'gcash',
				accountName: 'GCash',
				currency: 'PHP',
				date: '2026-10-29',
				balance: -400_00,
				already: false
			}
		]);
		expect(out.periods[1]?.endTotal).toBe(1_600_00);
	});

	it('reports it again when the wallet recovers and falls again, and once while it stays below', () => {
		const out = run({
			group: 'month',
			to: '2026-11-30',
			wallets: [{ ...GCASH, currency: 'PHP', balance: 100_00 }],
			flows: [
				flow('out', '2026-10-28', 'A', GCASH, 200_00),
				flow('out', '2026-10-29', 'B', GCASH, 200_00),
				flow('in', '2026-11-02', 'C', GCASH, 1_000_00),
				flow('out', '2026-11-10', 'D', GCASH, 2_000_00)
			]
		});
		expect(out.warnings.map((w) => [w.date, w.balance])).toEqual([
			['2026-10-28', -100_00],
			['2026-11-10', -1_300_00]
		]);
	});

	it('names a wallet that starts below zero, once', () => {
		const out = run({
			to: '2026-10-30',
			wallets: [{ ...GCASH, currency: 'PHP', balance: -300_00 }],
			flows: [flow('out', '2026-10-28', 'Fee', GCASH, 10_00)]
		});
		expect(out.warnings).toEqual([
			{
				accountId: 'gcash',
				accountName: 'GCash',
				currency: 'PHP',
				date: '2026-10-27',
				balance: -300_00,
				already: true
			}
		]);
	});

	it('starts a wallet the account does not hold yet at zero, and warns when a bill takes it below', () => {
		const out = run({
			to: '2026-10-30',
			wallets: [{ ...RCBC, currency: 'PHP', balance: 1_000_00 }],
			flows: [flow('out', '2026-10-28', 'Netflix', RCBC, 549_00, 'USD')]
		});
		expect(out.endWallets.find((w) => w.currency === 'USD')?.end).toBe(-549_00);
		expect(out.warnings[0]).toMatchObject({ currency: 'USD', accountId: 'rcbc' });
	});
});

describe('currencies and rates', () => {
	const usd: ForecastWallet = { ...RCBC, currency: 'USD', balance: 100_00 };

	it('converts a wallet to the main currency at the stored rate, never adding the currencies', () => {
		const out = run({ to: '2026-10-28', wallets: [wallets[0]!, usd] });
		// 100.00 USD at 56 pesos
		expect(out.startTotal).toBe(5_000_00 + 5_600_00);
		const usdLine = out.endWallets.find((w) => w.currency === 'USD');
		expect(usdLine).toMatchObject({ end: 100_00, endMain: 5_600_00 });
	});

	it('counts a bill in another currency at its own wallet, and converts it for the totals', () => {
		const out = run({
			to: '2026-10-30',
			wallets: [wallets[0]!, usd],
			flows: [flow('out', '2026-10-28', 'Netflix', RCBC, 10_00, 'USD')]
		});
		const bill = out.periods.flatMap((p) => p.outs)[0];
		expect(bill).toMatchObject({ currency: 'USD', amount: 10_00, amountMain: 560_00 });
		expect(out.endWallets.find((w) => w.currency === 'USD')?.end).toBe(90_00);
		expect(out.endTotal).toBe(5_000_00 + 5_040_00);
	});

	it('names a currency with no rate and leaves it out of every total, never as zero', () => {
		const out = run({
			to: '2026-10-30',
			wallets: [wallets[0]!, { ...GCASH, currency: 'CHF', balance: 50_00 }],
			flows: [flow('out', '2026-10-28', 'Fee', GCASH, 5_00, 'CHF')]
		});
		expect(out.missing).toEqual(['CHF']);
		expect(out.startTotal).toBe(5_000_00);
		expect(out.endTotal).toBe(5_000_00);
		expect(out.endWallets.find((w) => w.currency === 'CHF')).toMatchObject({
			end: 45_00,
			endMain: null
		});
		const fee = out.periods.flatMap((p) => p.outs)[0];
		expect(fee?.amountMain).toBeNull();
		expect(out.periods[0]?.outTotal).toBe(0);
	});

	it('moves money between two wallets of one currency without changing the total', () => {
		const out = run({
			to: '2026-10-30',
			wallets: [wallets[0]!, { ...GCASH, currency: 'USD', balance: 0 }, usd],
			flows: [move('2026-10-28', RCBC, GCASH, 40_00, 'USD')]
		});
		const before = run({
			to: '2026-10-30',
			wallets: [wallets[0]!, { ...GCASH, currency: 'USD', balance: 0 }, usd]
		});
		expect(out.endTotal).toBe(before.endTotal);
		expect(out.endWallets.find((w) => w.accountId === 'gcash' && w.currency === 'USD')?.end).toBe(
			40_00
		);
		expect(out.endWallets.find((w) => w.accountId === 'rcbc' && w.currency === 'USD')?.end).toBe(
			60_00
		);
	});

	it('lists what has no amount yet, in date order, without counting it', () => {
		const out = run({
			to: '2026-11-30',
			unknown: [
				{ kind: 'bill', date: '2026-11-20', label: 'Meralco' },
				{ kind: 'income', date: '2026-11-05', label: 'Freelance' }
			]
		});
		expect(out.unknown.map((u) => u.label)).toEqual(['Freelance', 'Meralco']);
		expect(out.endTotal).toBe(out.startTotal);
	});

	it('ignores a flow outside the range', () => {
		const out = run({
			to: '2026-10-30',
			flows: [
				flow('out', '2026-10-26', 'Old', RCBC, 99_00),
				flow('out', '2026-11-30', 'Later', RCBC, 99_00)
			]
		});
		expect(out.endTotal).toBe(out.startTotal);
		expect(out.periods.flatMap((p) => p.outs)).toHaveLength(0);
	});

	it('groups by year, partial at both ends, with a leap year whole', () => {
		const out = run({
			from: '2027-06-10',
			to: '2029-03-01',
			group: 'year',
			limits: SIMULATE_LIMITS,
			flows: [flow('in', '2028-02-29', 'Leap pay', RCBC, 10_00)]
		});
		expect(out.periods.map((p) => [p.from, p.to])).toEqual([
			['2027-06-10', '2027-12-31'],
			['2028-01-01', '2028-12-31'],
			['2029-01-01', '2029-03-01']
		]);
		expect(out.periods[1]?.inTotal).toBe(10_00);
	});

	it('reaches 5 years only with the simulation limits, and by week at most 2 years', () => {
		expect(MAX_SIMULATE_DAYS).toBe(1827);
		const long = { from: '2026-01-01', to: addDays('2026-01-01', MAX_SIMULATE_DAYS - 1) };
		expect(() => run({ ...long, group: 'month' })).toThrow(/at most 366/);
		expect(run({ ...long, group: 'month', limits: SIMULATE_LIMITS }).periods).toHaveLength(61);
		expect(() =>
			run({ ...long, to: addDays(long.to, 1), group: 'year', limits: SIMULATE_LIMITS })
		).toThrow(/at most 1827/);
		expect(() => run({ ...long, group: 'week', limits: SIMULATE_LIMITS })).toThrow(
			/By week it covers at most 731/
		);
	});
});
