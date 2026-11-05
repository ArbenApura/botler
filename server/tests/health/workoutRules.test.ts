// THE PROGRAMS, HOW THEY MOVE ON AND THE WEEK PLANNER (BTL-20261105-0015, P6.2 TO P6.4)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, weekday } from '../../src/lib/finance/dates';
import { moveSuggestion, planWeek, stillFits } from '../../src/lib/health/planner';
import {
	MOVEMENTS,
	movementOf,
	runMinutes,
	RUN_WEEKS,
	strengthSession,
	workoutTitle
} from '../../src/lib/health/programs';
import { nextAim, nextLevels, nextRunWeek, nextStrengthWeek } from '../../src/lib/health/progress';
import { freeSlots } from '../../src/lib/schedule/availability';

// -- CONSTANTS -- //

const MONDAY = '2030-01-07';
const WORK = [1, 2, 3, 4, 5].map((w) => ({
	weekday: w,
	startMinute: 420,
	endMinute: 1110,
	kind: 'work' as const
}));
const SETTINGS = { wakeStartMinute: 360, wakeEndMinute: 1320, travelMinutes: 30 };
const STRENGTH = {
	kind: 'strength' as const,
	sessionKey: 'home_strength',
	programId: null,
	shortMinutes: 20,
	longMinutes: 35
};
const WALK = {
	kind: 'walk' as const,
	sessionKey: 'walk',
	programId: null,
	shortMinutes: 30,
	longMinutes: 40
};

// -- FUNCTIONS -- //

function plan(
	overrides: { day: string; off: boolean; blocks: typeof WORK }[] = [],
	wanted = [STRENGTH, STRENGTH, STRENGTH, WALK, WALK, WALK]
) {
	const input = { weekly: WORK, overrides, settings: SETTINGS, events: [] };
	const slots = freeSlots(MONDAY, addDays(MONDAY, 6), input, 15);
	const workDays = new Set(
		[0, 1, 2, 3, 4, 5, 6]
			.map((i) => addDays(MONDAY, i))
			.filter((d) => {
				const o = overrides.find((x) => x.day === d);
				return o ? o.blocks.length > 0 : [1, 2, 3, 4, 5].includes(weekday(d));
			})
	);
	return { result: planWeek({ monday: MONDAY, slots, workDays, wanted }), slots, workDays };
}

// -- TESTS -- //

describe('the catalogue', () => {
	it('every movement can be made easier, and no key repeats', () => {
		const keys = MOVEMENTS.flatMap((m) => m.ladder.map((e) => e.key));
		expect(new Set(keys).size).toBe(keys.length);
		for (const m of MOVEMENTS) expect(m.ladder.length).toBeGreaterThanOrEqual(2);
	});

	it('a walk to run session is never over about 45 minutes', () => {
		for (const w of RUN_WEEKS) expect(runMinutes(w.week)).toBeLessThanOrEqual(45);
	});

	it('titles carry no numbers about the body', () => {
		expect(workoutTitle('home_strength', 'strength')).toBe('Home strength');
		expect(workoutTitle('walk_to_run', 'run')).toBe('Walk to run');
		expect(workoutTitle('walk', 'walk')).toBe('Walk');
	});

	it('a session follows the level reached', () => {
		const s = strengthSession({ push: 1 });
		expect(s[0]?.name).toBe('Incline push-ups');
		expect(s[1]?.level).toBe(0);
	});
});

describe('moving on', () => {
	const push = movementOf('push');
	const sets = (reps: number[], done = true) =>
		reps.map((r) => ({ exerciseKey: 'push_incline', reps: r, seconds: null, done }));

	it('adds reps inside the range before anything else', () => {
		expect(push && nextAim(push, 9)).toBe(10);
		expect(push && nextAim(push, 12)).toBe(12);
		expect(push && nextAim(push, null)).toBe(8);
	});

	it('moves to a harder version only when every set reached the top', () => {
		expect(nextLevels({ push: 1 }, sets([12, 12, 12])).levels.push).toBe(2);
		expect(nextLevels({ push: 1 }, sets([12, 12, 11])).levels.push).toBe(1);
		expect(nextLevels({ push: 1 }, sets([12, 12])).levels.push).toBe(1);
		expect(nextLevels({ push: 1 }, sets([12, 12, 12], false)).levels.push).toBe(1);
	});

	it('stops at the last version', () => {
		const top = [15, 15, 15].map((r) => ({
			exerciseKey: 'push_full',
			reps: r,
			seconds: null,
			done: true
		}));
		expect(nextLevels({ push: 3 }, top).levels.push).toBe(3);
	});

	it('holds get longer in steps of 5 seconds', () => {
		const core = movementOf('core');
		expect(core && nextAim(core, 30)).toBe(35);
		expect(core && nextAim(core, 45)).toBe(45);
	});

	it('walk to run moves up after all sessions, repeats after a miss, and never passes the template', () => {
		expect(nextRunWeek(3, 3)).toEqual({ week: 4, moved: 'up' });
		expect(nextRunWeek(3, 2)).toEqual({ week: 3, moved: 'repeat' });
		expect(nextRunWeek(10, 3)).toEqual({ week: 10, moved: 'finished' });
	});

	it('home strength moves on after two of three', () => {
		expect(nextStrengthWeek(1, 2).moved).toBe('up');
		expect(nextStrengthWeek(1, 1).moved).toBe('repeat');
		expect(nextStrengthWeek(8, 3).moved).toBe('finished');
	});
});

describe('the week planner', () => {
	it('fits a 07:00 to 18:30 week: evenings on work days, longer on free days', () => {
		const { result } = plan();
		expect(result.unplaced).toEqual([]);
		for (const p of result.placed) {
			const isFree = [0, 6].includes(weekday(p.day));
			if (isFree) expect(p.minutes).toBeGreaterThan(30);
			else {
				expect(p.time >= '19:00').toBe(true);
				expect(p.minutes).toBeLessThanOrEqual(30);
			}
		}
		expect(result.movingMinutes).toBeGreaterThan(100);
	});

	it('keeps strength days apart and leaves one day empty', () => {
		const { result } = plan();
		const days = result.placed.filter((p) => p.kind === 'strength').map((p) => p.day);
		for (const d of days) {
			expect(days).not.toContain(addDays(d, 1));
		}
		expect(new Set(result.placed.map((p) => p.day)).size).toBeLessThanOrEqual(6);
	});

	it('a suddenly working Saturday takes the short session, away from work', () => {
		const saturday = addDays(MONDAY, 5);
		const { result } = plan([
			{
				day: saturday,
				off: false,
				blocks: [{ weekday: 6, startMinute: 540, endMinute: 900, kind: 'work' }]
			}
		]);
		const sat = result.placed.find((p) => p.day === saturday);
		if (sat) {
			expect(sat.minutes).toBeLessThanOrEqual(30);
			expect(sat.time >= '15:30').toBe(true);
		}
	});

	it('says what did not fit', () => {
		const wanted = [WALK];
		const busy = [0, 1, 2, 3, 4, 5, 6].map((i) => ({
			day: addDays(MONDAY, i),
			off: false,
			blocks: [{ weekday: 0, startMinute: 360, endMinute: 1320, kind: 'work' as const }]
		}));
		expect(plan(busy, wanted).result.unplaced).toHaveLength(1);
	});

	it('knows when a placed session no longer fits, and suggests a time', () => {
		const { result, slots } = plan();
		const p = result.placed[0];
		expect(p && stillFits(slots, p.day, new Date(p.startsAt), p.minutes)).toBe(true);
		expect(p && stillFits([], p.day, new Date(p.startsAt), p.minutes)).toBe(false);
		expect(moveSuggestion(slots, addDays(MONDAY, 1), 30, true)).toBe('19:15');
		expect(moveSuggestion([], addDays(MONDAY, 1), 30, true)).toBeNull();
	});
});
