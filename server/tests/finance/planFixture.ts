// A SMALL MONEY PLAN FOR THE PURE FLOW, WHAT-IF AND SIMULATION TESTS: TWO PAYDAYS A MONTH, RENT, A DEFERRABLE INTERNET BILL, A GOAL AND TWO RULES

// -- TYPES -- //
import type { PlanData } from '../../src/lib/finance/planFlows';

// -- CONSTANTS -- //

export const PAY = 2_500_000;
export const RENT = 1_500_000;
export const NET = 150_000;
export const GOAL_PER_PAY = 100_000;
export const FIXED_RULE = 500_000;

// -- FUNCTIONS -- //

/** The plan, made on 2026-01-01 unless said otherwise. Ids are short words, as the pure functions never check their shape. */
export function plan(over: Partial<PlanData> = {}): PlanData {
	const createdOn = '2026-01-01';
	return {
		main: 'PHP',
		rates: { PHP: '56', USD: '1', JPY: '157' },
		accounts: [
			{ id: 'rcbc', name: 'RCBC', minBalance: 0, archived: false, createdOn },
			{ id: 'gcash', name: 'GCash', minBalance: 200_000, archived: false, createdOn },
			{ id: 'save', name: 'Savings', minBalance: 0, archived: false, createdOn }
		],
		incomes: [
			{
				id: 'pay',
				label: 'Salary',
				accountId: 'rcbc',
				expectedAmount: PAY,
				schedule: { kind: 'semi_monthly', days: [15, 30] },
				weekendRule: 'before',
				createdOn
			}
		],
		bills: [
			{
				id: 'rent',
				name: 'Rent',
				category: 'rent',
				accountId: 'gcash',
				schedule: { kind: 'monthly', day: 5 },
				weekendRule: 'none',
				deferrable: false,
				startsOn: null,
				currency: 'PHP',
				usualAmount: RENT,
				createdOn
			},
			{
				id: 'net',
				name: 'Internet',
				category: 'utilities',
				accountId: 'gcash',
				schedule: { kind: 'monthly', day: 20 },
				weekendRule: 'none',
				deferrable: true,
				startsOn: null,
				currency: 'PHP',
				usualAmount: NET,
				createdOn
			}
		],
		goals: [
			{
				id: 'fund',
				name: 'Emergency',
				accountId: 'save',
				perPayday: GOAL_PER_PAY,
				createdOn
			}
		],
		rules: [
			{
				id: 'r1',
				position: 1,
				target: { kind: 'account', id: 'gcash' },
				mode: 'fixed',
				amount: FIXED_RULE,
				basisPoints: null,
				base: 'pay',
				effectiveFrom: '2025-01-01',
				version: 1,
				createdOn
			},
			{
				id: 'r2',
				position: 2,
				target: { kind: 'account', id: 'save' },
				mode: 'rest',
				amount: null,
				basisPoints: null,
				base: 'pay',
				effectiveFrom: '2025-01-01',
				version: 1,
				createdOn
			}
		],
		overrides: new Map(),
		settled: new Map(),
		incomeDays: new Set(),
		...over
	};
}
