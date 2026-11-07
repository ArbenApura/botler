// NET BALANCE READS (BTL-20261030-0546): accounts_balances AND assets_summary CARRY WHAT EACH WALLET HOLDS BACK FOR BILLS AND GOALS, THE GROSS FIELDS STAY
// AS THEY WERE, A SCHEDULE THAT CANNOT BE READ LEAVES THE NET OUT WITHOUT BREAKING THE BALANCES, AND THE ASSISTANT MAY READ BOTH. RUN AS app_runtime IN THE TENANT CONTEXT.
// The plan is read as of 2027-01-21 (after the 15 Jan pay, next pay 30 Jan): Rent of 1 Jan (late) and Meralco of 20 Jan (late) are held, Rent of 1 Feb
// is not due before the next pay (the 30th is a Saturday: the pay moves to Fri 29 Jan), so it is not held, and neither is what the rule for it has set aside.

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { fxRate } from '../../src/lib/server/db/schema';
import { configureFx } from '../../src/lib/server/fx/config';
import { recordIncome } from '../../src/lib/server/ops/ledger';
import { accountBalancesWithNet, assetsSummaryWithNet } from '../../src/lib/server/ops/net';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { approveRule, proposeRule } from '../../src/lib/server/ops/rules';
import { seedPerson } from '../agent/support';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const NOW = new Date('2027-01-21T04:00:00Z');

// -- STATES -- //

let t: TestDb;
let rids = 0;

// -- FUNCTIONS -- //

const w = (who: Fixture) => ({
	...who.ctx,
	requestId: `net-req-${String(++rids).padStart(8, '0')}`
});

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	configureFx(null);
	for (const [code, rate] of Object.entries({ PHP: '56' }))
		await t.handle.db
			.insert(fxRate)
			.values({ code, rate, fetchedAt: new Date(), source: 'test' })
			.onConflictDoUpdate({ target: fxRate.code, set: { rate, fetchedAt: new Date() } });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('net balance reads', () => {
	it('holds the bills due before the next payday and a goal account, never what a rule saved for a later bill, per wallet and in the total', async () => {
		const f = await seedPerson(t);
		// A fixed rule into RCBC that saves for the rent
		const rule = await proposeRule(w(f), {
			label: 'Rent fund',
			mode: 'fixed',
			amount: 40_000,
			targetAccountId: f.rcbc,
			fundsBillId: f.rentBillId
		});
		await approveRule(w(f), { ruleId: rule.id });
		await recordIncome(w(f), { accountId: f.rcbc, amount: 1_500_000 });
		await recordIncome(w(f), { accountId: f.maya, amount: 200_000 });
		await recordIncome(w(f), { accountId: f.gcash, amount: 50_000 });
		await recordIncome(w(f), { accountId: f.gcash, amount: 5_000, currency: 'USD' });

		const rows = await accountBalancesWithNet(f.ctx, NOW);
		const rcbc = rows.find((r) => r.id === f.rcbc);
		// Gross is untouched; net is balance less 800 000 + 300 000 due (the 40 000 the rule saved for the rent of 1 Feb is not held)
		expect(rcbc).toMatchObject({
			balance: 1_500_000,
			netBalance: 400_000,
			held: 1_100_000,
			shortfall: 0,
			netUntil: '2027-01-29',
			netNotice: null
		});
		expect(rcbc?.holds.map((h) => [h.kind, h.label, h.amount, h.dueDate])).toEqual([
			['bill', 'Rent', 800_000, '2027-01-01'],
			['bill', 'Meralco', 300_000, '2027-01-20']
		]);
		expect(rcbc?.wallets[0]).toMatchObject({ balance: 1_500_000, netBalance: 400_000 });
		// The goal account keeps its whole balance for the goal
		expect(rows.find((r) => r.id === f.maya)).toMatchObject({
			balance: 200_000,
			netBalance: 0,
			held: 200_000
		});
		// A wallet nothing is owed from is its own balance, in each currency
		const gcash = rows.find((r) => r.id === f.gcash);
		expect(gcash).toMatchObject({ netBalance: 50_000, held: 0 });
		expect(gcash?.wallets.find((x) => x.currency === 'USD')).toMatchObject({
			balance: 5_000,
			netBalance: 5_000
		});

		const view = await assetsSummaryWithNet(f.ctx, NOW);
		// 400 000 + 0 + 50 000 + 50.00 dollars at 56 (280 000), and the gross total is unchanged
		expect(view.netTotal).toBe(400_000 + 50_000 + 280_000);
		expect(view.shortfallTotal).toBe(0);
		expect(view.total).toBe(1_500_000 + 200_000 + 50_000 + 280_000);
		expect(view.accounts.find((a) => a.accountId === f.rcbc)?.netSubtotal).toBe(400_000);
		expect(view.wallets.find((x) => x.accountId === f.gcash && x.currency === 'USD')).toMatchObject(
			{ netBalance: 5_000, netValue: 280_000 }
		);
	});

	it('shows a shortfall for what a due bill lacks, and the assistant can read both verbs', async () => {
		const f = await seedPerson(t);
		await recordIncome(w(f), { accountId: f.rcbc, amount: 1_000_000 });
		const row = (await accountBalancesWithNet(f.ctx, NOW)).find((r) => r.id === f.rcbc);
		// 1 000 000 against 800 000 + 300 000 due
		expect(row).toMatchObject({ netBalance: 0, held: 1_100_000, shortfall: 100_000 });
		expect((await assetsSummaryWithNet(f.ctx, NOW)).shortfallTotal).toBe(100_000);
		const agent = { ...f.ctx, actor: { userId: f.userId, kind: 'agent' as const, tool: 'test' } };
		expect(await invokeVerb(agent, 'accounts_balances', {})).toBeInstanceOf(Array);
		expect(await invokeVerb(agent, 'assets_summary', {})).toMatchObject({ currency: 'PHP' });
	});

	it('leaves the net out, with a notice, when a stored schedule cannot be read, and keeps the balances', async () => {
		const f = await seedPerson(t);
		await recordIncome(w(f), { accountId: f.rcbc, amount: 700_000 });
		// Written as the owner on purpose (the ops layer would refuse this schedule), with forced row level security lifted for this one
		// statement as the migrations do; it is put back at once
		const owner = await t.handle.pinOwner();
		try {
			await owner.exec(`ALTER TABLE bill NO FORCE ROW LEVEL SECURITY`);
			await owner.exec(
				`UPDATE bill SET schedule = '{"kind":"monthly","day":99}' WHERE id = '${f.rentBillId}'`
			);
			await owner.exec(`ALTER TABLE bill FORCE ROW LEVEL SECURITY`);
		} finally {
			owner.release();
		}
		const row = (await accountBalancesWithNet(f.ctx, NOW)).find((r) => r.id === f.rcbc);
		expect(row).toMatchObject({
			balance: 700_000,
			belowMinimum: false,
			netBalance: null,
			held: null,
			netUntil: null
		});
		expect(row?.netNotice).toMatch(/could not be worked out/);
		expect(row?.wallets[0]).toMatchObject({ balance: 700_000, netBalance: null });
		const view = await assetsSummaryWithNet(f.ctx, NOW);
		expect(view.netTotal).toBeNull();
		expect(view.total).toBeGreaterThanOrEqual(700_000);
	});
});
