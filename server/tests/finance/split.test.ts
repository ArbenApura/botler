// THE SPLIT ENGINE (P2.6) AND RULE VALIDATION (P2.9): FIXED, PERCENT, REST, SHORTFALL, ROUNDING TO CENTAVOS AND THE SUM INVARIANT

// -- TYPES -- //
import type { Rule } from '../../src/lib/finance/rules';
import type { Commitment, SplitInput } from '../../src/lib/finance/split';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { validateRules } from '../../src/lib/finance/rules';
import { bestEffortTransfers, proposeSplit } from '../../src/lib/finance/split';

// -- CONSTANTS -- //

const rule = (r: Partial<Rule> & Pick<Rule, 'id' | 'mode'>): Rule => ({
	position: 1,
	target: { kind: 'account', id: 'gcash' },
	amount: null,
	basisPoints: null,
	base: 'pay',
	effectiveFrom: '2026-01-01',
	version: 1,
	...r
});

const bill = (id: string, amount: number, accountId = 'rcbc', deferrable = false): Commitment => ({
	kind: 'bill',
	refId: id,
	label: id,
	amount,
	accountId,
	deferrable
});

const base = (over: Partial<SplitInput> = {}): SplitInput => ({
	payday: '2026-10-30',
	pay: 2_000_000,
	incomeAccountId: 'rcbc',
	commitments: [],
	rules: [],
	goalAccounts: { goal1: 'maya' },
	...over
});

const total = (r: ReturnType<typeof proposeSplit>) => r.lines.reduce((s, l) => s + l.amount, 0);

// -- TESTS -- //

describe('split engine', () => {
	it('pays bills first, then fixed, then the rest, and lists the transfers', () => {
		const r = proposeSplit(
			base({
				commitments: [bill('rent', 500_000), bill('internet', 150_000, 'gcash')],
				rules: [
					rule({
						id: 'r1',
						mode: 'fixed',
						amount: 300_000,
						position: 1,
						target: { kind: 'goal', id: 'goal1' }
					}),
					rule({ id: 'r2', mode: 'rest', position: 2, target: { kind: 'account', id: 'maya' } })
				]
			})
		);
		expect(r.status).toBe('ok');
		expect(total(r)).toBe(2_000_000);
		expect(r.transfers).toEqual([
			{ fromAccountId: 'rcbc', toAccountId: 'gcash', amount: 150_000, labels: ['internet'] },
			{
				fromAccountId: 'rcbc',
				toAccountId: 'maya',
				amount: 300_000 + 1_050_000,
				labels: ['Rule', 'Rule']
			}
		]);
		// The rent is paid from the income account, so it stays there
		expect(r.status === 'ok' && r.staysInIncomeAccount).toBe(500_000);
	});

	it('floors percentages and puts the leftover centavos on the rest rule', () => {
		const r = proposeSplit(
			base({
				pay: 1_000_001,
				rules: [
					rule({
						id: 'p1',
						mode: 'percent',
						basisPoints: 3333,
						position: 1,
						target: { kind: 'account', id: 'maya' }
					}),
					rule({
						id: 'p2',
						mode: 'percent',
						basisPoints: 3333,
						position: 2,
						target: { kind: 'account', id: 'gcash' }
					}),
					rule({ id: 'rest', mode: 'rest', position: 3, target: { kind: 'account', id: 'rcbc' } })
				]
			})
		);
		expect(r.lines.map((l) => l.amount)).toEqual([333_300, 333_300, 333_401]);
		expect(total(r)).toBe(1_000_001);
	});

	it('puts the remainder on the first rule when there is no rest rule', () => {
		const r = proposeSplit(
			base({
				pay: 1_000_001,
				rules: [
					rule({ id: 'p1', mode: 'percent', basisPoints: 5000, position: 1 }),
					rule({
						id: 'p2',
						mode: 'percent',
						basisPoints: 2500,
						position: 2,
						target: { kind: 'account', id: 'maya' }
					})
				]
			})
		);
		expect(r.lines.map((l) => l.amount)).toEqual([500_000 + 250_001, 250_000]);
		expect(total(r)).toBe(1_000_001);
	});

	it('sends everything unclaimed to the default account when there are no rules', () => {
		const r = proposeSplit(
			base({ commitments: [bill('rent', 500_000)], defaultAccountId: 'maya' })
		);
		expect(r.lines.at(-1)).toMatchObject({
			kind: 'leftover',
			amount: 1_500_000,
			accountId: 'maya'
		});
		expect(total(r)).toBe(2_000_000);
	});

	it('takes a percentage of what is left after commitments and fixed amounts', () => {
		const r = proposeSplit(
			base({
				commitments: [bill('rent', 500_000)],
				rules: [
					rule({ id: 'f', mode: 'fixed', amount: 500_000, position: 1 }),
					rule({
						id: 'p',
						mode: 'percent',
						basisPoints: 5000,
						base: 'remaining',
						position: 2,
						target: { kind: 'account', id: 'maya' }
					})
				]
			})
		);
		const p = r.lines.find((l) => l.refId === 'p');
		expect(p?.amount).toBe(500_000);
		expect(total(r)).toBe(2_000_000);
	});

	it('applies only the rules that are effective by the payday', () => {
		const r = proposeSplit(
			base({
				rules: [
					rule({ id: 'later', mode: 'fixed', amount: 100_000, effectiveFrom: '2026-12-01' }),
					rule({
						id: 'now',
						mode: 'fixed',
						amount: 200_000,
						position: 2,
						target: { kind: 'account', id: 'maya' }
					})
				]
			})
		);
		expect(r.lines.some((l) => l.refId === 'later')).toBe(false);
		expect(total(r)).toBe(2_000_000);
	});

	it('returns the gap and what could be cut when the pay is too small', () => {
		const r = proposeSplit(
			base({
				pay: 600_000,
				commitments: [
					bill('rent', 500_000),
					bill('streaming', 30_000, 'rcbc', true),
					{
						kind: 'goal',
						refId: 'goal1',
						label: 'Emergency fund',
						amount: 150_000,
						accountId: 'maya',
						deferrable: false
					}
				]
			})
		);
		expect(r.status).toBe('shortfall');
		if (r.status !== 'shortfall') return;
		expect(r.gap).toBe(80_000);
		expect(r.transfers).toEqual([]);
		expect(r.cutOptions.map((c) => c.label)).toEqual(['Emergency fund', 'streaming']);
	});

	it('is a shortfall when fixed amounts do not fit after the bills', () => {
		const r = proposeSplit(
			base({
				pay: 600_000,
				commitments: [bill('rent', 500_000)],
				rules: [rule({ id: 'f', mode: 'fixed', amount: 200_000 })]
			})
		);
		expect(r.status).toBe('shortfall');
		expect(r.status === 'shortfall' && r.gap).toBe(100_000);
	});

	it('refuses input that is not valid', () => {
		expect(() => proposeSplit(base({ pay: 0 }))).toThrow();
		expect(() => proposeSplit(base({ commitments: [bill('x', -5)] }))).toThrow();
		expect(() =>
			proposeSplit(
				base({
					rules: [
						rule({ id: 'g', mode: 'fixed', amount: 100, target: { kind: 'goal', id: 'nope' } })
					]
				})
			)
		).toThrow(/goal/);
	});

	it('always adds up to the pay, for many pays and rule sets', () => {
		// A seeded generator keeps the property test repeatable
		let seed = 42;
		const rnd = (n: number) => {
			seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648;
			return seed % n;
		};
		for (let i = 0; i < 300; i++) {
			const pay = 100_000 + rnd(9_000_000);
			const commitments = Array.from({ length: rnd(4) }, (_, k) => bill(`b${k}`, 1 + rnd(200_000)));
			const rules: Rule[] = [];
			let share = 10_000;
			for (let k = 0; k < rnd(4); k++) {
				if (share <= 0) break;
				const bp = 1 + rnd(Math.max(1, Math.min(share, 4000)));
				share -= bp;
				rules.push(
					rule({
						id: `p${k}`,
						mode: 'percent',
						basisPoints: bp,
						position: k + 1,
						target: { kind: 'account', id: k % 2 ? 'maya' : 'gcash' }
					})
				);
			}
			if (rnd(2))
				rules.push(
					rule({ id: 'rest', mode: 'rest', position: 9, target: { kind: 'account', id: 'rcbc' } })
				);
			const r = proposeSplit(base({ pay, commitments, rules }));
			if (r.status === 'ok') {
				expect(total(r)).toBe(pay);
				expect(r.lines.every((l) => Number.isInteger(l.amount) && l.amount > 0)).toBe(true);
			} else {
				expect(r.gap).toBeGreaterThan(0);
			}
		}
	});
});

describe('rule validation', () => {
	it('accepts a sensible set', () => {
		expect(
			validateRules([
				rule({ id: 'a', mode: 'fixed', amount: 100 }),
				rule({ id: 'b', mode: 'percent', basisPoints: 5000 }),
				rule({ id: 'c', mode: 'rest' })
			])
		).toEqual([]);
	});

	it('refuses percentages above 100%, a second rest and a fixed amount above the pay', () => {
		const over = validateRules([
			rule({ id: 'a', mode: 'percent', basisPoints: 6000 }),
			rule({ id: 'b', mode: 'percent', basisPoints: 5000 })
		]);
		expect(over.join(' ')).toMatch(/more than 100%/);
		// Percentages of different bases are counted apart
		expect(
			validateRules([
				rule({ id: 'a', mode: 'percent', basisPoints: 6000 }),
				rule({ id: 'b', mode: 'percent', basisPoints: 6000, base: 'remaining' })
			])
		).toEqual([]);
		expect(
			validateRules([rule({ id: 'a', mode: 'rest' }), rule({ id: 'b', mode: 'rest' })]).join(' ')
		).toMatch(/Only one/);
		expect(validateRules([rule({ id: 'a', mode: 'fixed', amount: 500 })], 400).join(' ')).toMatch(
			/more than the pay/
		);
	});

	it('refuses a fixed rule without an amount and a percentage without a share', () => {
		expect(validateRules([rule({ id: 'a', mode: 'fixed' })])).toHaveLength(1);
		expect(validateRules([rule({ id: 'a', mode: 'percent', basisPoints: 0 })])).toHaveLength(1);
		expect(validateRules([rule({ id: 'a', mode: 'percent', basisPoints: 10_001 })])).toHaveLength(
			1
		);
	});
});

describe('best effort transfers on a shortfall', () => {
	const short = () => {
		const r = proposeSplit(
			base({
				pay: 1_900_000,
				commitments: [bill('wifi', 150_000, 'gcash'), bill('meralco', 300_000, 'rcbc')],
				rules: [
					rule({
						id: 'r1',
						mode: 'fixed',
						amount: 700_000,
						position: 1,
						target: { kind: 'account', id: 'stash' }
					}),
					rule({
						id: 'r2',
						mode: 'fixed',
						amount: 1_000_000,
						position: 2,
						target: { kind: 'account', id: 'wise' }
					}),
					rule({ id: 'r3', mode: 'percent', basisPoints: 5000, base: 'remaining', position: 3 })
				]
			})
		);
		if (r.status !== 'shortfall') throw new Error('expected a shortfall');
		return r;
	};

	it('funds commitments first, then rules in order, and caps the last one at what is left', () => {
		const out = bestEffortTransfers(short(), 'rcbc');
		const to = Object.fromEntries(out.map((t) => [t.toAccountId, t.amount]));
		// 1,900,000 pay: wifi 150,000 to gcash, meralco 300,000 stays, stash 700,000, wise gets the remaining 750,000 of its 1,000,000
		expect(to).toEqual({ gcash: 150_000, stash: 700_000, wise: 750_000 });
		expect(out.every((t) => t.fromAccountId === 'rcbc')).toBe(true);
	});

	it('never moves more than the pay and gives the same answer every time', () => {
		const a = bestEffortTransfers(short(), 'rcbc');
		expect(a.reduce((s, t) => s + t.amount, 0)).toBeLessThanOrEqual(1_900_000);
		expect(bestEffortTransfers(short(), 'rcbc')).toEqual(a);
	});

	it('lets a percent of the pay ahead of a fixed rule take its share first, in rule order', () => {
		const r = proposeSplit(
			base({
				pay: 1_000_000,
				commitments: [bill('rent', 400_000, 'rcbc')],
				rules: [
					rule({
						id: 'p',
						mode: 'percent',
						basisPoints: 5000,
						position: 1,
						target: { kind: 'account', id: 'wise' }
					}),
					rule({
						id: 'f',
						mode: 'fixed',
						amount: 600_000,
						position: 2,
						target: { kind: 'account', id: 'stash' }
					})
				]
			})
		);
		if (r.status !== 'shortfall') throw new Error('expected a shortfall');
		const to = Object.fromEntries(
			bestEffortTransfers(r, 'rcbc').map((t) => [t.toAccountId, t.amount])
		);
		// Rent 400,000 stays; wise takes its 500,000 of the pay; stash gets the 100,000 left of its 600,000
		expect(to).toEqual({ wise: 500_000, stash: 100_000 });
	});

	it('funds nothing for rules when the commitments alone use the pay, and skips the income account but spends from it', () => {
		const r = proposeSplit(
			base({
				pay: 500_000,
				commitments: [bill('a', 300_000, 'rcbc'), bill('b', 400_000, 'gcash')],
				rules: [
					rule({ id: 'f', mode: 'fixed', amount: 100_000, target: { kind: 'account', id: 'wise' } })
				]
			})
		);
		if (r.status !== 'shortfall') throw new Error('expected a shortfall');
		const out = bestEffortTransfers(r, 'rcbc');
		// 300,000 stays in rcbc, gcash gets the 200,000 left of its bill, wise nothing
		expect(out).toEqual([
			{ fromAccountId: 'rcbc', toAccountId: 'gcash', amount: 200_000, labels: ['b'] }
		]);
	});

	it('merges lines to one account and treats fixed rules above the pay as a shortfall, not a bad rule set', () => {
		const r = proposeSplit(
			base({
				pay: 300_000,
				commitments: [bill('x', 100_000, 'gcash'), bill('y', 50_000, 'gcash')],
				rules: [
					rule({ id: 'f', mode: 'fixed', amount: 900_000, target: { kind: 'account', id: 'wise' } })
				]
			})
		);
		if (r.status !== 'shortfall') throw new Error('expected a shortfall');
		expect(r.gap).toBe(750_000);
		const out = bestEffortTransfers(r, 'rcbc');
		expect(out.find((t) => t.toAccountId === 'gcash')).toMatchObject({
			amount: 150_000,
			labels: ['x', 'y']
		});
		expect(out.find((t) => t.toAccountId === 'wise')?.amount).toBe(150_000);
	});
});

describe('money already in an account and rules that save for a bill (BTL-20261029-0119)', () => {
	// The owner's 2 Nov payday: salary 19,000.00 into RCBC, GCash already holds 1,502.73
	const acct = (id: string) => ({ kind: 'account' as const, id });
	const ownerRules = [
		rule({ id: 'parents', mode: 'fixed', amount: 350_000, position: 1, target: acct('rcbc') }),
		rule({ id: 'wise', mode: 'fixed', amount: 300_000, position: 2, target: acct('wise') }),
		rule({ id: 'mommy', mode: 'fixed', amount: 25_000, position: 3, target: acct('gcash') }),
		rule({ id: 'pocket', mode: 'fixed', amount: 300_000, position: 4, target: acct('rcbc') })
	];
	const due = (id: string, amount: number, accountId: string, dueDate: string): Commitment => ({
		...bill(id, amount, accountId),
		dueDate
	});
	const link = (billId: string, ruleId: string, perPayday: number, reserved = 0) => ({
		billId,
		ruleId,
		ruleLabel: ruleId,
		perPayday,
		reserved
	});

	it('pays WiFi from the GCash balance and moves only the Mommy 250.00', () => {
		const r = proposeSplit(
			base({
				payday: '2026-11-02',
				pay: 1_900_000,
				commitments: [
					due('meralco', 300_000, 'rcbc', '2026-11-02'),
					due('pocketBill', 300_000, 'rcbc', '2026-11-04'),
					due('wifi', 150_000, 'gcash', '2026-11-04')
				],
				rules: ownerRules,
				available: { gcash: 150_273, rcbc: 2_496 },
				links: [link('pocketBill', 'pocket', 300_000)]
			})
		);
		expect(r.status).toBe('ok');
		expect(total(r)).toBe(1_900_000);
		expect(r.transfers.find((t) => t.toAccountId === 'gcash')?.amount).toBe(25_000);
		expect(r.transfers.find((t) => t.toAccountId === 'wise')?.amount).toBe(300_000);
		expect(r.covered).toEqual([
			{ refId: 'meralco', label: 'meralco', accountId: 'rcbc', amount: 2_496 },
			{ refId: 'wifi', label: 'wifi', accountId: 'gcash', amount: 150_000 }
		]);
		expect(r.funded).toEqual([
			{
				refId: 'pocketBill',
				label: 'pocketBill',
				accountId: 'rcbc',
				ruleId: 'pocket',
				ruleLabel: 'pocket',
				amount: 300_000
			}
		]);
		expect(r.lines.find((l) => l.refId === 'meralco')).toMatchObject({
			amount: 297_504,
			label: 'meralco (top-up)'
		});
		expect(r.lines.some((l) => l.refId === 'wifi' || l.refId === 'pocketBill')).toBe(false);
	});

	it('does not count a bill and the rule that saves for it twice (no false shortfall on 9 Nov)', () => {
		const commitments: Commitment[] = [
			due('meralco3', 300_000, 'rcbc', '2026-11-09'),
			{ ...due('parentsBill', 700_000, 'rcbc', '2026-11-11'), kind: 'parents' },
			due('pocketBill', 300_000, 'rcbc', '2026-11-11')
		];
		const without = proposeSplit(
			base({ payday: '2026-11-09', pay: 1_900_000, commitments, rules: ownerRules })
		);
		expect(without.status).toBe('shortfall');
		const r = proposeSplit(
			base({
				payday: '2026-11-09',
				pay: 1_900_000,
				commitments,
				rules: ownerRules,
				links: [
					link('parentsBill', 'parents', 350_000, 350_000),
					link('pocketBill', 'pocket', 300_000)
				]
			})
		);
		expect(r.status).toBe('ok');
		expect(total(r)).toBe(1_900_000);
		expect(r.unfunded).toEqual([]);
		expect(r.funded.map((f) => [f.refId, f.amount])).toEqual([
			['parentsBill', 700_000],
			['pocketBill', 300_000]
		]);
	});

	it('takes what the savings do not reach from the pay as still needed', () => {
		const r = proposeSplit(
			base({
				payday: '2026-11-09',
				pay: 1_900_000,
				commitments: [{ ...due('parentsBill', 700_000, 'rcbc', '2026-11-11'), kind: 'parents' }],
				rules: ownerRules,
				links: [link('parentsBill', 'parents', 350_000, 0)]
			})
		);
		expect(r.unfunded).toEqual([
			{ refId: 'parentsBill', label: 'parentsBill', accountId: 'rcbc', amount: 350_000 }
		]);
		expect(r.lines.find((l) => l.refId === 'parentsBill')).toMatchObject({
			amount: 350_000,
			label: 'parentsBill (still needed)'
		});
		expect(total(r)).toBe(1_900_000);
	});

	it('shares one rule between two dates of the same bill, earliest first', () => {
		const r = proposeSplit(
			base({
				commitments: [
					due('pocket2', 300_000, 'rcbc', '2026-11-11'),
					due('pocket2', 300_000, 'rcbc', '2026-11-04')
				],
				rules: [rule({ id: 'p', mode: 'fixed', amount: 300_000, target: acct('rcbc') })],
				links: [link('pocket2', 'p', 300_000)]
			})
		);
		expect(r.funded).toHaveLength(1);
		expect(r.unfunded).toEqual([
			{ refId: 'pocket2', label: 'pocket2', accountId: 'rcbc', amount: 300_000 }
		]);
		expect(total(r)).toBe(2_000_000);
	});

	it('ignores a link whose rule is not in force on the payday, or is not a fixed amount', () => {
		const r = proposeSplit(
			base({
				commitments: [due('b', 100_000, 'gcash', '2026-11-01')],
				rules: [
					rule({ id: 'later', mode: 'fixed', amount: 100_000, effectiveFrom: '2027-01-01' }),
					rule({ id: 'pct', mode: 'percent', basisPoints: 1000, position: 2 })
				],
				links: [link('b', 'later', 100_000, 100_000), link('b', 'pct', 0, 100_000)]
			})
		);
		expect(r.funded).toEqual([]);
		expect(r.lines.find((l) => l.refId === 'b')?.amount).toBe(100_000);
	});

	it('never covers a goal or a bill marked not coverable, and never takes more than there is', () => {
		const r = proposeSplit(
			base({
				commitments: [
					{ ...due('usd', 50_000, 'gcash', '2026-11-01'), coverable: false },
					{
						kind: 'goal',
						refId: 'goal1',
						label: 'Fund',
						amount: 40_000,
						accountId: 'maya',
						deferrable: false
					},
					due('w', 100_000, 'gcash', '2026-11-02')
				],
				available: { gcash: 60_000, maya: 1_000_000 }
			})
		);
		expect(r.covered).toEqual([{ refId: 'w', label: 'w', accountId: 'gcash', amount: 60_000 }]);
		expect(r.lines.find((l) => l.refId === 'usd')?.amount).toBe(50_000);
		expect(r.lines.find((l) => l.refId === 'goal1')?.amount).toBe(40_000);
		expect(r.lines.find((l) => l.refId === 'w')?.amount).toBe(40_000);
		expect(total(r)).toBe(2_000_000);
	});

	it('still adds up to the pay with balances and links, the same way every time', () => {
		for (let pay = 100_000; pay <= 3_000_000; pay += 290_001) {
			const input = base({
				pay,
				commitments: [
					due('a', 120_000, 'gcash', '2026-11-01'),
					due('b', 77_777, 'rcbc', '2026-11-03')
				],
				rules: [
					rule({ id: 'r', mode: 'fixed', amount: 50_000, target: acct('gcash') }),
					rule({ id: 'rest', mode: 'rest', position: 2 })
				],
				available: { gcash: 33_333, rcbc: 1 },
				links: [link('a', 'r', 50_000, 20_000)]
			});
			const r = proposeSplit(input);
			expect(proposeSplit(input)).toEqual(r);
			if (r.status === 'ok') expect(total(r)).toBe(pay);
		}
	});
});
