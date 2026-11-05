// THE WEIGHT TREND AND THE BURN (BTL-20261105-0015, P5.2), TESTED ON SIMULATED PEOPLE: NOISY SCALES, GAPS, STEADY UNDER-LOGGING AND DAYS LEFT OUT

// -- TYPES -- //
import type { IntakeDay, WeighIn } from '../../src/lib/health/energy';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	estimateBurn,
	forecastGoal,
	MAX_WEEKLY_CHANGE_KCAL,
	nextTarget,
	trendOf,
	weekKeyOf
} from '../../src/lib/health/energy';
import { addDays } from '../../src/lib/finance/dates';

// -- CONSTANTS -- //

const START = '2030-01-01';
const NOISE = [
	120, -340, 410, -90, 260, -450, 30, 380, -210, 150, -60, 500, -300, 90, -420, 240, 70, -180, 330,
	-30
];
const GOAL = { kind: 'lose' as const, goalWeightG: 70_000, paceBp: 50 };

// -- FUNCTIONS -- //

/** A person who really burns `burn` and really eats `eaten` a day, for `days` days. */
function simulate(opts: {
	burn: number;
	eaten: number;
	days: number;
	underLogged?: number;
	weighEvery?: number;
	skipDays?: (i: number) => boolean;
	inflatedOnSkipped?: number;
}) {
	const weighIns: WeighIn[] = [];
	const intake: IntakeDay[] = [];
	let grams = 74_000;
	for (let i = 0; i < opts.days; i++) {
		const day = addDays(START, i);
		grams += (opts.eaten - opts.burn) / 7.7;
		if (i % (opts.weighEvery ?? 1) === 0)
			weighIns.push({ day, grams: Math.round(grams + (NOISE[i % NOISE.length] ?? 0)) });
		if (!opts.skipDays?.(i)) intake.push({ day, kcal: opts.eaten - (opts.underLogged ?? 0) });
	}
	return { weighIns, intake, asOf: addDays(START, opts.days - 1) };
}

// -- TESTS -- //

describe('the burn estimate on simulated people', () => {
	it('finds the real burn through a noisy scale, within 100 kcal', () => {
		const s = simulate({ burn: 2200, eaten: 1800, days: 28 });
		const e = estimateBurn(s.asOf, s.weighIns, s.intake);
		expect(Math.abs((e?.burnKcal ?? 0) - 2200)).toBeLessThanOrEqual(100);
	});

	it('steady under-logging comes out as a lower burn, so the target still works', () => {
		const s = simulate({ burn: 2200, eaten: 1800, days: 28, underLogged: 200 });
		const e = estimateBurn(s.asOf, s.weighIns, s.intake);
		expect(Math.abs((e?.burnKcal ?? 0) - 2000)).toBeLessThanOrEqual(100);
	});

	it('copes with gaps between weigh-ins', () => {
		const s = simulate({ burn: 2500, eaten: 2000, days: 28, weighEvery: 3 });
		const e = estimateBurn(s.asOf, s.weighIns, s.intake);
		expect(Math.abs((e?.burnKcal ?? 0) - 2500)).toBeLessThanOrEqual(150);
	});

	it('leaves out days that are not complete', () => {
		const s = simulate({ burn: 2200, eaten: 1800, days: 28, skipDays: (i) => i % 3 === 0 });
		const e = estimateBurn(s.asOf, s.weighIns, s.intake);
		expect(e?.completeDays).toBeLessThan(28);
		expect(e?.intakeKcal).toBe(1800);
	});

	it('waits for 14 complete days and 8 weigh-ins', () => {
		const few = simulate({ burn: 2200, eaten: 1800, days: 13 });
		expect(estimateBurn(few.asOf, few.weighIns, few.intake)).toBeNull();
		const rare = simulate({ burn: 2200, eaten: 1800, days: 28, weighEvery: 5 });
		expect(estimateBurn(rare.asOf, rare.weighIns, rare.intake)).toBeNull();
	});
});

describe('the trend', () => {
	it('moves far less than the scale does', () => {
		const s = simulate({ burn: 2200, eaten: 2200, days: 20 });
		const trend = trendOf(s.weighIns);
		const swing = (v: number[]) => Math.max(...v) - Math.min(...v);
		expect(swing(trend.map((t) => t.trendG))).toBeLessThan(
			swing(s.weighIns.map((w) => w.grams)) / 2
		);
	});

	it('starts at the first weigh-in and handles one', () => {
		expect(trendOf([{ day: START, grams: 70_000 }])).toEqual([
			{ day: START, trendG: 70_000, grams: 70_000 }
		]);
		expect(trendOf([])).toEqual([]);
	});
});

describe('the next target', () => {
	it('moves at most 150 kcal a week', () => {
		const down = nextTarget(2000, 1500, 1200, 74_000, 1700, GOAL);
		expect(down).toBe(2000 - MAX_WEEKLY_CHANGE_KCAL);
		const up = nextTarget(1400, 2600, 1200, 74_000, 1700, GOAL);
		expect(up).toBe(1400 + MAX_WEEKLY_CHANGE_KCAL);
	});

	it('takes a small step exactly', () => {
		expect(nextTarget(1850, 2180, 1500, 74_000, 1700, GOAL)).toBe(1773);
	});

	it('never goes under the floor when the floor is above what the burn asks', () => {
		expect(nextTarget(1500, 1400, 1450, 74_000, 1700, GOAL)).toBe(1450);
		expect(nextTarget(1310, 1300, 1000, 74_000, 1700, GOAL)).toBe(1310);
	});

	it('stops asking to lose at the lowest healthy weight', () => {
		expect(nextTarget(1500, 1600, 1200, 53_000, 1700, GOAL)).toBe(1600);
	});

	it('has no target for track', () => {
		expect(
			nextTarget(1800, 2000, 1200, 74_000, 1700, { kind: 'track', goalWeightG: null, paceBp: 50 })
		).toBeNull();
	});
});

describe('the forecast', () => {
	const today = '2030-02-01';

	it('gives a date while the trend is heading for the goal', () => {
		const f = forecastGoal(today, 73_000, -50, 70_000);
		expect(f).toEqual({ reachOn: '2030-04-02', weeks: 9, reason: null });
	});

	it('gives a date for gaining too', () => {
		expect(forecastGoal(today, 60_000, 50, 61_000).reason).toBeNull();
	});

	it('never gives a date from a flat trend', () => {
		expect(forecastGoal(today, 73_000, -1, 70_000)).toEqual({
			reachOn: null,
			weeks: null,
			reason: 'flat'
		});
		expect(forecastGoal(today, 73_000, 0, 70_000).reason).toBe('flat');
	});

	it('never gives a date from a trend going the wrong way', () => {
		expect(forecastGoal(today, 73_000, 40, 70_000).reason).toBe('wrong_way');
	});

	it('caps how far ahead it looks', () => {
		expect(forecastGoal(today, 100_000, -11, 60_000).reason).toBe('too_far');
	});

	it('knows when there is no goal, or it is reached', () => {
		expect(forecastGoal(today, 73_000, -50, null).reason).toBe('no_goal');
		expect(forecastGoal(today, 70_050, -50, 70_000).reason).toBe('reached');
		expect(forecastGoal(today, 70_500, null, 70_000).reason).toBe('no_goal');
	});
});

describe('week keys', () => {
	it('follows the ISO weeks across a new year', () => {
		expect(weekKeyOf('2026-11-26')).toBe('2026-W48');
		expect(weekKeyOf('2026-01-01')).toBe('2026-W01');
		expect(weekKeyOf('2027-01-03')).toBe('2026-W53');
		expect(weekKeyOf('2027-01-04')).toBe('2027-W01');
	});
});
