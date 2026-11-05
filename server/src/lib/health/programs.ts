// THE WORKOUT CATALOGUE (BTL-20261105-0015, P6). CODE DATA WITH NO TABLE: TWO PROGRAMS THAT NEED NO EQUIPMENT, HOME STRENGTH AND WALK TO RUN.
// A movement is a ladder of versions from easier to harder, so a person can always go down one instead of stopping. The assistant can only start a program by its key: it
// cannot write a session of its own, so it can never add more work than these hold. The owner reads this text before using it (P6.2).

// -- TYPES -- //

export type Exercise = {
	key: string;
	name: string;
	how: string;
};

export type Movement = {
	key: string;
	name: string;
	/** Reps count up, a hold counts seconds. */
	measure: 'reps' | 'seconds';
	sets: number;
	low: number;
	high: number;
	/** Easier to harder. */
	ladder: readonly Exercise[];
};

export type RunStep = { run: number; walk: number; repeat: number };

export type RunWeek = { week: number; steps: RunStep; note: string };

// -- CONSTANTS -- //

export const WARM_UP_WALK_MIN = 5;
export const COOL_DOWN_WALK_MIN = 5;

export const MOVEMENTS: readonly Movement[] = [
	{
		key: 'push',
		name: 'Push-ups',
		measure: 'reps',
		sets: 3,
		low: 8,
		high: 12,
		ladder: [
			{ key: 'push_wall', name: 'Wall push-ups', how: 'Hands on a wall, body straight.' },
			{
				key: 'push_incline',
				name: 'Incline push-ups',
				how: 'Hands on a sturdy table, body straight.'
			},
			{ key: 'push_knee', name: 'Knee push-ups', how: 'Knees on the floor, hips in line.' },
			{ key: 'push_full', name: 'Push-ups', how: 'Hands and toes on the floor, body straight.' }
		]
	},
	{
		key: 'squat',
		name: 'Squats',
		measure: 'reps',
		sets: 3,
		low: 10,
		high: 15,
		ladder: [
			{
				key: 'squat_chair',
				name: 'Sit to stand',
				how: 'Stand up from a chair and sit back slowly.'
			},
			{ key: 'squat_free', name: 'Squats', how: 'Feet shoulder width, sit back, knees over toes.' },
			{
				key: 'squat_split',
				name: 'Split squats',
				how: 'One foot ahead, lower straight down. The reps are for each leg.'
			}
		]
	},
	{
		key: 'hinge',
		name: 'Glute bridge',
		measure: 'reps',
		sets: 3,
		low: 10,
		high: 15,
		ladder: [
			{
				key: 'hinge_bridge',
				name: 'Glute bridge',
				how: 'On your back, knees bent, lift your hips.'
			},
			{
				key: 'hinge_single',
				name: 'One-leg bridge',
				how: 'The same with one foot lifted. The reps are for each leg.'
			}
		]
	},
	{
		key: 'core',
		name: 'Plank',
		measure: 'seconds',
		sets: 3,
		low: 20,
		high: 45,
		ladder: [
			{ key: 'core_knee', name: 'Knee plank', how: 'Forearms and knees down, body straight.' },
			{ key: 'core_plank', name: 'Plank', how: 'Forearms and toes down, body straight.' }
		]
	}
];

export const STRENGTH_WEEKS = 8;
export const STRENGTH_PER_WEEK = 3;
/** Fewer than this in a week is still fine: two strength days is the health guideline. */
export const STRENGTH_GOAL_DAYS = 2;
export const MINUTES_GOAL = 150;

/** Walk to run, three times a week. Seconds of running and of walking, repeated. A week is only repeated, never made longer than this. */
export const RUN_WEEKS: readonly RunWeek[] = [
	{ week: 1, steps: { run: 30, walk: 120, repeat: 8 }, note: 'Slow enough to talk.' },
	{ week: 2, steps: { run: 60, walk: 120, repeat: 7 }, note: 'Slow enough to talk.' },
	{ week: 3, steps: { run: 90, walk: 120, repeat: 6 }, note: 'Easy pace, you can still talk.' },
	{ week: 4, steps: { run: 120, walk: 120, repeat: 5 }, note: 'Easy pace, you can still talk.' },
	{ week: 5, steps: { run: 180, walk: 120, repeat: 4 }, note: 'Slow down if you cannot talk.' },
	{ week: 6, steps: { run: 300, walk: 120, repeat: 3 }, note: 'Slow down if you cannot talk.' },
	{ week: 7, steps: { run: 480, walk: 120, repeat: 2 }, note: 'Slow down if you cannot talk.' },
	{ week: 8, steps: { run: 720, walk: 120, repeat: 2 }, note: 'Slow down if you cannot talk.' },
	{ week: 9, steps: { run: 1200, walk: 0, repeat: 1 }, note: 'Twenty minutes, at an easy pace.' },
	{ week: 10, steps: { run: 1800, walk: 0, repeat: 1 }, note: 'Thirty minutes, at an easy pace.' }
];

export const RUN_PER_WEEK = 3;

export const PROGRAMS = {
	home_strength: {
		key: 'home_strength',
		name: 'Home strength',
		kind: 'strength' as const,
		weeks: STRENGTH_WEEKS,
		perWeek: STRENGTH_PER_WEEK,
		line: 'Four movements with no equipment, about 20 minutes.'
	},
	walk_to_run: {
		key: 'walk_to_run',
		name: 'Walk to run',
		kind: 'run' as const,
		weeks: RUN_WEEKS.length,
		perWeek: RUN_PER_WEEK,
		line: 'From short jogs to 30 minutes, three times a week.'
	}
} as const;

export type ProgramKey = keyof typeof PROGRAMS;

export const PROGRAM_KEYS = Object.keys(PROGRAMS) as ProgramKey[];

/** Asked before a program starts. A yes to any means talking to a clinician first. It is not a medical check. */
export const READINESS: readonly string[] = [
	'Has a doctor told you to avoid exercise, or that you have a heart problem?',
	'Do you get chest pain or feel faint when you are active?',
	'Do you have an injury or a joint problem that gets worse when you move?',
	'Are you pregnant, or have you just had a baby?'
];

// -- FUNCTIONS -- //

export const movementOf = (key: string): Movement | undefined =>
	MOVEMENTS.find((m) => m.key === key);

/** The movement an exercise key belongs to. */
export const movementOfExercise = (exerciseKey: string): Movement | undefined =>
	MOVEMENTS.find((m) => m.ladder.some((e) => e.key === exerciseKey));

export const exerciseAt = (m: Movement, level: number): Exercise => {
	const at = m.ladder[Math.max(0, Math.min(m.ladder.length - 1, level))];
	// A ladder always has a first version: the data above is written that way
	return at ?? (m.ladder[0] as Exercise);
};

export const runWeek = (week: number): RunWeek => {
	const at = RUN_WEEKS[Math.max(1, Math.min(RUN_WEEKS.length, week)) - 1];
	return at ?? (RUN_WEEKS[0] as RunWeek);
};

/** How long a walk to run session takes, warm up and cool down included. */
export function runMinutes(week: number): number {
	const { steps } = runWeek(week);
	const moving = ((steps.run + steps.walk) * steps.repeat) / 60;
	return Math.ceil(moving) + WARM_UP_WALK_MIN + COOL_DOWN_WALK_MIN;
}

/** What is asked in a session: the sets of each movement at the levels the person has reached. */
export function strengthSession(levels: Record<string, number>) {
	return MOVEMENTS.map((m) => {
		const level = levels[m.key] ?? 0;
		const exercise = exerciseAt(m, level);
		return {
			movement: m.key,
			exerciseKey: exercise.key,
			name: exercise.name,
			how: exercise.how,
			measure: m.measure,
			sets: m.sets,
			low: m.low,
			high: m.high,
			level,
			ladder: m.ladder.map((e) => e.name)
		};
	});
}

/** The fixed title of a workout. It holds no calories or weight, so it is safe on a lock screen. */
export function workoutTitle(sessionKey: string, kind: string): string {
	if (sessionKey.startsWith('home_strength') || kind === 'strength') return 'Home strength';
	if (sessionKey.startsWith('walk_to_run')) return 'Walk to run';
	if (kind === 'walk') return 'Walk';
	if (kind === 'run') return 'Run';
	return 'Workout';
}

/** A routine counts as exercise on the Train screen when its title names it. Routines have no kind, so the words decide. */
const EXERCISE_WORDS =
	/\b(exercise|workout|work out|jog|jogging|run|running|walk|walking|stretch|abs|yoga|strength|training|train|cardio|bike|cycling|hiit|video)\b/i;
export const looksLikeExercise = (title: string): boolean => EXERCISE_WORDS.test(title);
