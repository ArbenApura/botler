// HOW A PROGRAM MOVES ON (BTL-20261105-0015, P6.3). PURE. ADD REPS, THEN A HARDER VERSION, THEN LONGER HOLDS. WALK TO RUN MOVES UP ONLY AFTER FINISHED SESSIONS.
// A week that went badly is repeated without any fuss. Nothing here can ask for more than the template holds.

// -- TYPES -- //
import type { Movement } from './programs';
// -- MODULES -- //
import {
	exerciseAt,
	MOVEMENTS,
	RUN_PER_WEEK,
	RUN_WEEKS,
	STRENGTH_PER_WEEK,
	STRENGTH_WEEKS
} from './programs';

// -- TYPES -- //

export type DoneSet = {
	exerciseKey: string;
	reps: number | null;
	seconds: number | null;
	done: boolean;
};

export type StrengthResult = {
	levels: Record<string, number>;
	/** The movements that moved up to a harder version. */
	levelledUp: string[];
};

export type WeekResult = { week: number; moved: 'up' | 'repeat' | 'finished' };

// -- FUNCTIONS -- //

/** Whether every set of a movement in this session reached the top of its range. */
function reachedTop(m: Movement, level: number, sets: readonly DoneSet[]): boolean {
	const key = exerciseAt(m, level).key;
	const mine = sets.filter((s) => s.exerciseKey === key);
	if (mine.length < m.sets) return false;
	return mine.every(
		(s) => s.done && (m.measure === 'reps' ? (s.reps ?? 0) : (s.seconds ?? 0)) >= m.high
	);
}

/** The levels after a session. Each movement moves up at most one version, and the last version is where it stays. */
export function nextLevels(
	levels: Record<string, number>,
	sets: readonly DoneSet[]
): StrengthResult {
	const next: Record<string, number> = { ...levels };
	const levelledUp: string[] = [];
	for (const m of MOVEMENTS) {
		const level = levels[m.key] ?? 0;
		if (level < m.ladder.length - 1 && reachedTop(m, level, sets)) {
			next[m.key] = level + 1;
			levelledUp.push(m.key);
		}
	}
	return { levels: next, levelledUp };
}

/** What to aim for on a set: one more than last time inside the range, or the top of the range. */
export function nextAim(m: Movement, last: number | null): number {
	if (last === null) return m.low;
	const step = m.measure === 'reps' ? 1 : 5;
	return Math.max(m.low, Math.min(m.high, last + step));
}

/**
 * The week of walk to run after a week ends. It moves up only when all of that week's sessions were finished; a missed one repeats the week, and it never goes past the
 * last week of the template.
 */
export function nextRunWeek(week: number, finished: number): WeekResult {
	if (finished < RUN_PER_WEEK) return { week, moved: 'repeat' };
	if (week >= RUN_WEEKS.length) return { week: RUN_WEEKS.length, moved: 'finished' };
	return { week: week + 1, moved: 'up' };
}

/** The week of home strength after a week ends. Two sessions out of three is enough to move on. */
export function nextStrengthWeek(week: number, finished: number): WeekResult {
	if (finished < Math.min(2, STRENGTH_PER_WEEK)) return { week, moved: 'repeat' };
	if (week >= STRENGTH_WEEKS) return { week: STRENGTH_WEEKS, moved: 'finished' };
	return { week: week + 1, moved: 'up' };
}
