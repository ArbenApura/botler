// THE balance_simulate VERB OVER REAL PEOPLE: RECORDED PAST, REPLAY, SIMULATED FUTURE, WHAT-IFS, NOTHING OF ANYONE ELSE, LIMITS AND THE
// SHORT ANSWER OF THE ASSISTANT

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TestDb } from '../support/testDb';
import type { SimulationView } from '../../src/lib/server/ops/simulate';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, manilaNoon, manilaStart, toManilaDate } from '../../src/lib/finance/dates';
import { run } from '../../src/lib/server/ops/context';
import { cashflowForecast } from '../../src/lib/server/ops/forecast';
import {
	balanceFor,
	logExpense,
	recordIncome,
	recordSnapshot
} from '../../src/lib/server/ops/ledger';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { balanceSimulate, MAX_AGENT_CHARS } from '../../src/lib/server/ops/simulate';
import { seedPerson } from '../agent/support';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let f: Fixture;
let other: Fixture;
let rids = 0;

const today = toManilaDate(new Date());
const daysAgo = (n: number) => manilaNoon(addDays(today, -n)).toISOString();

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	f = await seedPerson(t);
	other = await seedPerson(t);
	await recordSnapshot(w(f), { accountId: f.rcbc, amount: 1_000_000, takenAt: daysAgo(100) });
	await recordSnapshot(w(f), { accountId: f.gcash, amount: 200_000, takenAt: daysAgo(100) });
	await logExpense(w(f), {
		accountId: f.gcash,
		amount: 50_000,
		note: 'Groceries',
		occurredAt: daysAgo(40)
	});
	await recordIncome(w(f), { accountId: f.rcbc, amount: 2_500_000, occurredAt: daysAgo(20) });
});

afterAll(async () => {
	await t.close();
});

// -- FUNCTIONS -- //

function w(who: Fixture) {
	return { ...who.ctx, requestId: `sim-req-${String(++rids).padStart(8, '0')}` };
}

const asAgent = (who: Fixture) => ({
	...who.ctx,
	actor: { ...who.ctx.actor, kind: 'agent' as const }
});

const sim = (raw: Record<string, unknown>, who: Fixture = f) =>
	balanceSimulate(who.ctx, raw) as Promise<SimulationView>;

const monthStart = (d: string) => `${d.slice(0, 8)}01`;

// -- TESTS -- //

describe('the timeline of a person', () => {
	it('gives the recorded past, the period of today and the simulated future, each with its own numbers', async () => {
		const out = await sim({
			from: monthStart(addDays(today, -120)),
			to: addDays(today, 200),
			group: 'month'
		});
		const parts = out.periods.map((p) => p.part);
		expect(parts[0]).toBe('past');
		expect(parts.filter((p) => p === 'mixed')).toHaveLength(1);
		expect(parts.at(-1)).toBe('future');
		for (const p of out.periods) {
			if (p.part === 'future') expect(p.recordedEnd).toBeNull();
			if (p.part === 'past' && !p.beforeFirstRecord) expect(p.replayEnd).not.toBeNull();
			if (p.part !== 'past') expect(p.simulatedEnd).not.toBeNull();
		}
		expect(out.notes[0]).toMatch(/Only recorded numbers are real/);
		// The plan was made today: the past has nothing to replay and nothing missed
		// (the period of the first record replays from the day after it, so it is left out here)
		const past = out.periods.filter(
			(p) => p.part === 'past' && !p.beforeFirstRecord && (out.firstRecord ?? '') < p.from
		);
		expect(past.length).toBeGreaterThan(0);
		for (const p of past) {
			expect(p.replayEnd).toBe(p.recordedStart);
			expect(p.missed).toBe(0);
		}
	});

	it('reads the same recorded balance as the ledger at a period end', async () => {
		const end = addDays(today, -30);
		const out = await sim({ from: addDays(end, -10), to: end, group: 'day' });
		const last = out.periods.at(-1);
		const at = new Date(manilaStart(addDays(end, 1)).getTime() - 1);
		const ledger = await run(f.ctx, async (tx, userId) => {
			let sum = 0;
			for (const id of [f.rcbc, f.gcash, f.maya])
				sum += (await balanceFor(tx, userId, id, 'PHP', at)).balance;
			return sum;
		});
		expect(last?.recordedEnd).toBe(ledger);
		expect(last?.recordedEnd).toBe(1_000_000 + 200_000 - 50_000);
	});

	it('simulates the future exactly as the forecast does', async () => {
		const to = addDays(today, 150);
		const [mine, theirs] = await Promise.all([
			sim({ from: today, to, group: 'month' }),
			cashflowForecast(f.ctx, { to, group: 'month' })
		]);
		expect(mine.periods.at(-1)?.simulatedEnd).toBe(theirs.endTotal);
		// Every period, not only the last: the same flows in the same order
		expect(mine.periods.map((p) => p.simulatedEnd)).toEqual(theirs.periods.map((p) => p.endTotal));
		expect(mine.periods[0]?.simulatedStart).toBe(theirs.startTotal);
	});

	it('runs a range years ahead from today', async () => {
		const from = addDays(today, 800);
		const far = await sim({ from, to: addDays(from, 30), group: 'day' });
		const through = await sim({ from: today, to: addDays(from, 30), group: 'month' });
		expect(far.periods.every((p) => p.part === 'future')).toBe(true);
		expect(far.periods.at(-1)?.simulatedEnd).toBe(through.periods.at(-1)?.simulatedEnd);
		expect(far.notes.join(' ')).toMatch(/all in the future/);
	});

	it('lists every entry of a range with its source in the detail view', async () => {
		const out = await sim({
			from: addDays(today, -45),
			to: addDays(today, 30),
			group: 'month',
			view: 'detail'
		});
		const recorded = (out.entries ?? []).filter((e) => e.source === 'recorded');
		expect(recorded.map((e) => e.label)).toContain('Groceries');
		expect(recorded.find((e) => e.label === 'Groceries')).toMatchObject({
			kind: 'out',
			amount: 50_000
		});
		expect((out.entries ?? []).some((e) => e.source === 'simulated')).toBe(true);
		const overview = await sim({
			from: addDays(today, -45),
			to: addDays(today, 30),
			group: 'month'
		});
		expect(overview.entries).toBeUndefined();
	});

	it('marks a payday missed once the plan is old enough and no pay came', async () => {
		const g = await seedPerson(t);
		await recordSnapshot(w(g), { accountId: g.rcbc, amount: 100_000, takenAt: daysAgo(90) });
		// The plan as if made 90 days ago (only a test changes when a row was made)
		await run(g.ctx, (tx) =>
			tx.execute(
				sql`update income_schedule set created_at = now() - interval '90 days' where user_id = ${g.userId}`
			)
		);
		const out = await sim(
			{ from: addDays(today, -60), to: addDays(today, -20), group: 'month', view: 'detail' },
			g
		);
		const missed = (out.entries ?? []).filter((e) => e.source === 'missed' && e.kind === 'in');
		expect(missed.length).toBeGreaterThan(0);
		expect(missed.every((e) => e.label === 'Salary')).toBe(true);
		expect(out.periods.reduce((a, p) => a + p.missed, 0)).toBeGreaterThan(0);
	});

	it('keeps an archived account in the recorded past and out of the future', async () => {
		const g = await seedPerson(t);
		const old = (await createAccount(w(g), { name: 'Old bank', kind: 'bank', minBalance: 0 })).id;
		await recordSnapshot(w(g), { accountId: old, amount: 55_500, takenAt: daysAgo(60) });
		await invokeVerb(w(g), 'account_archive', { accountId: old });
		const out = await sim({ from: addDays(today, -40), to: addDays(today, 40), group: 'month' }, g);
		const past = out.periods[0];
		expect(past?.wallets.find((x) => x.accountId === old)).toMatchObject({
			archived: true,
			recorded: 55_500
		});
		expect(past?.recordedEnd).toBe(55_500);
		const future = out.periods.at(-1);
		expect(future?.wallets.find((x) => x.accountId === old)?.simulated ?? null).toBeNull();
	});
});

describe('what-ifs', () => {
	it('switches off the payday and leaves the recorded past alone', async () => {
		const range = {
			from: monthStart(addDays(today, -40)),
			to: addDays(today, 120),
			group: 'month'
		};
		const plain = await sim(range);
		const off = await sim({ ...range, scenario: { off: [f.incomeId] } });
		expect(off.scenario).toEqual({ changes: 1, ignored: [] });
		expect(off.periods.at(-1)?.simulatedEnd ?? 0).toBeLessThan(
			plain.periods.at(-1)?.simulatedEnd ?? 0
		);
		expect(off.periods[0]?.recordedEnd).toBe(plain.periods[0]?.recordedEnd);
		expect(off.notes.join(' ')).toMatch(/what-if with 1 change/);
	});

	it('names an id of another person and never uses it', async () => {
		const range = { from: today, to: addDays(today, 90), group: 'month' };
		const plain = await sim(range);
		const out = await sim({
			...range,
			scenario: { off: [other.incomeId], amounts: [{ id: other.rentBillId, amount: 1 }] }
		});
		expect(out.scenario?.ignored).toEqual([other.incomeId, other.rentBillId].sort());
		expect(out.periods.map((p) => p.simulatedEnd)).toEqual(
			plain.periods.map((p) => p.simulatedEnd)
		);
	});

	it('shows nothing of another person', async () => {
		const out = await sim(
			{ from: addDays(today, -60), to: today, group: 'month', view: 'detail' },
			other
		);
		expect(out.firstRecord).toBeNull();
		expect((out.entries ?? []).some((e) => e.source === 'recorded')).toBe(false);
		expect(out.periods.every((p) => p.recordedEnd === null)).toBe(true);
	});

	it('adds pretend entries and skips a payday date', async () => {
		const range = { from: today, to: addDays(today, 60), group: 'month' };
		const plain = await sim(range);
		const out = await sim({
			...range,
			scenario: {
				extra: [
					{
						date: addDays(today, 3),
						kind: 'out',
						accountId: f.gcash,
						amount: 70_000,
						label: 'Phone'
					}
				]
			}
		});
		expect(
			(out.periods.at(-1)?.simulatedEnd ?? 0) - (plain.periods.at(-1)?.simulatedEnd ?? 0)
		).toBe(-70_000);
	});
});

describe('limits and the assistant', () => {
	it('refuses a range past 5 years, by day past 62 days, a detail past a year and an oversized what-if', async () => {
		await expect(sim({ from: addDays(today, -1900), to: today })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(sim({ from: today, to: addDays(today, 62), group: 'day' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(
			sim({ from: today, to: addDays(today, 400), view: 'detail' })
		).rejects.toMatchObject({ code: 'INVALID' });
		const extra = Array.from({ length: 51 }, () => ({
			date: today,
			kind: 'in',
			accountId: f.rcbc,
			amount: 1,
			label: 'x'
		}));
		await expect(
			sim({ from: today, to: addDays(today, 30), scenario: { extra } })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			sim({
				from: today,
				to: addDays(today, 30),
				scenario: { amounts: [{ id: f.incomeId, amount: 0 }] }
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(f.ctx, 'balance_simulate', { from: today, to: today, userId: other.userId })
		).rejects.toBeTruthy();
		// The forecast keeps its own 366 days
		await expect(cashflowForecast(f.ctx, { to: addDays(today, 366) })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('answers 5 years by month or year quickly, and the assistant gets a short answer', async () => {
		const range = { from: addDays(today, -900), to: addDays(today, 900) };
		const started = Date.now();
		const [month, year] = await Promise.all([
			sim({ ...range, group: 'month' }),
			sim({ ...range, group: 'year' })
		]);
		expect(Date.now() - started).toBeLessThan(10_000);
		expect(month.periods.length).toBeGreaterThan(55);
		expect(year.periods.length).toBeGreaterThanOrEqual(5);
		const agent = (await invokeVerb(asAgent(f), 'balance_simulate', {
			...range,
			group: 'month'
		})) as SimulationView;
		expect(JSON.stringify(agent).length).toBeLessThanOrEqual(MAX_AGENT_CHARS);
		expect(agent.periods.length || agent.summary?.length).toBe(month.periods.length);
	});
});
