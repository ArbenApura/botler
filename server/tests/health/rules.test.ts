// THE HEALTH RULES (BTL-20261105-0015, ADR 5): THE FIRST ESTIMATE AND EVERY SAFETY LIMIT AT ITS EDGE

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	bmiTenths,
	dailyBurn,
	goalProblem,
	MAX_DEFICIT_KCAL,
	MIN_TARGET_KCAL,
	minGoalWeightG,
	minTargetKcal,
	paceKcalPerDay,
	proteinTargetMg,
	restingBurn,
	targetFor,
	targetProblem
} from '../../src/lib/health/rules';

// -- CONSTANTS -- //

const BODY = { weightG: 74_000, heightMm: 1700, birthYear: 1996, sex: 'male' as const };

// -- TESTS -- //

describe('the first estimate', () => {
	it('is the Mifflin-St Jeor sum for each sex, with a midpoint when skipped', () => {
		// 10 x 74 + 6.25 x 170 - 5 x 30 = 1652.5
		expect(restingBurn(BODY, 2026)).toBe(1658);
		expect(restingBurn({ ...BODY, sex: 'female' }, 2026)).toBe(1492);
		expect(restingBurn({ ...BODY, sex: 'skip' }, 2026)).toBe(1575);
	});

	it('multiplies by how active a day is', () => {
		expect(dailyBurn(BODY, 'sitting', 2026)).toBe(1990);
		expect(dailyBurn(BODY, 'very_active', 2026)).toBe(2852);
	});
});

describe('the pace', () => {
	it('turns a share of body weight into a daily gap', () => {
		// 0.5% of 74 kg is 370 g a week, which is 407 kcal a day at 7,700 kcal per kg
		expect(paceKcalPerDay(74_000, 50)).toBe(407);
		expect(paceKcalPerDay(74_000, 100)).toBe(814);
	});
});

describe('goal limits', () => {
	const lose = (goalWeightG: number | null, paceBp = 50) => ({
		kind: 'lose' as const,
		goalWeightG,
		paceBp
	});

	it('finds the lowest goal weight from BMI 18.5, rounded up', () => {
		expect(minGoalWeightG(1700)).toBe(53_500);
		expect(bmiTenths(74_000, 1700)).toBe(256);
	});

	it('refuses a goal under BMI 18.5 and names the lowest', () => {
		expect(goalProblem(lose(53_400), 74_000, 1700)).toBe(
			'That goal is under a healthy weight for your height. The lowest goal here is 53.5 kg.'
		);
		expect(goalProblem(lose(53_500), 74_000, 1700)).toBeNull();
	});

	it('refuses a weight loss goal to someone already at the floor', () => {
		expect(goalProblem(lose(50_000), 53_500, 1700)).toContain('already at the lower end');
	});

	it('refuses a pace over 1% a week, and allows exactly 1%', () => {
		expect(goalProblem(lose(70_000, 101), 74_000, 1700)).toContain('more than 1%');
		expect(goalProblem(lose(70_000, 100), 74_000, 1700)).toBeNull();
	});

	it('refuses a gain over 0.5% a week and a goal that is not higher', () => {
		const gain = (g: number, p: number) => ({ kind: 'gain' as const, goalWeightG: g, paceBp: p });
		expect(goalProblem(gain(80_000, 51), 74_000, 1700)).toContain('more than 0.5%');
		expect(goalProblem(gain(70_000, 50), 74_000, 1700)).toContain('over your current weight');
	});

	it('asks nothing of maintain and track', () => {
		expect(goalProblem({ kind: 'track', goalWeightG: null, paceBp: 50 }, 74_000, 1700)).toBeNull();
		expect(
			goalProblem({ kind: 'maintain', goalWeightG: null, paceBp: 50 }, 74_000, 1700)
		).toBeNull();
	});
});

describe('calorie targets', () => {
	it('keeps the floor at resting burn and never under 1,310', () => {
		expect(minTargetKcal(1000)).toBe(MIN_TARGET_KCAL);
		expect(minTargetKcal(1658)).toBe(1658);
	});

	it('takes the pace off the burn', () => {
		expect(targetFor({ kind: 'lose', goalWeightG: 70_000, paceBp: 50 }, 74_000, 2257, 1500)).toBe(
			1850
		);
	});

	it('caps the gap at 1,000 kcal', () => {
		const t = targetFor({ kind: 'lose', goalWeightG: 90_000, paceBp: 100 }, 150_000, 4000, 2000);
		expect(t).toBe(4000 - MAX_DEFICIT_KCAL);
	});

	it('stops at the floor rather than going lower', () => {
		expect(targetFor({ kind: 'lose', goalWeightG: 50_000, paceBp: 100 }, 60_000, 1700, 1300)).toBe(
			1310
		);
	});

	it('gives no target to track, and burn to maintain', () => {
		expect(
			targetFor({ kind: 'track', goalWeightG: null, paceBp: 50 }, 74_000, 2200, 1500)
		).toBeNull();
		expect(targetFor({ kind: 'maintain', goalWeightG: null, paceBp: 50 }, 74_000, 2200, 1500)).toBe(
			2200
		);
	});

	it('refuses a target under the floor or too far under the burn, and names the lowest', () => {
		expect(targetProblem(1309, 1000, 1700)).toBe(
			'That target is too low. The lowest target for you is 1,310 kcal a day.'
		);
		expect(targetProblem(1310, 1000, 1700)).toBeNull();
		expect(targetProblem(1500, 1400, 2600)).toBe(
			'That target is too far under what you burn. The lowest target for you now is 1,600 kcal a day.'
		);
	});
});

describe('protein', () => {
	it('is grams per kg of body weight, in milligrams', () => {
		expect(proteinTargetMg(74_000, 16)).toBe(118_400);
	});
});
