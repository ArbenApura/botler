// HEALTH (BTL-20261105-0015): FOOD, WEIGHT, WORKOUTS, SLEEP AND THE WEEKLY PROPOSALS OF ONE PERSON, PLUS THE SHARED NUTRITION TABLES
// Amounts are whole numbers: grams of body weight, kcal, milligrams of the main nutrients, nanograms in the map of the others. A day is a Manila date.
// A food entry keeps its own numbers from the moment it is logged, so a new import or a changed saved food never moves a past day.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import {
	boolean,
	check,
	date,
	foreignKey,
	index,
	integer,
	jsonb,
	text,
	timestamp,
	unique,
	uniqueIndex,
	uuid
} from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { ACTIVITIES, GOAL_KINDS, SEXES } from '../../../health/rules';
import { user } from './auth';
import { id, oneOf, plainTable, stamps, userTable, version } from './helpers';

// -- CONSTANTS -- //

export const MEAL_KINDS = ['breakfast', 'lunch', 'merienda', 'dinner', 'snack'] as const;
/** Where the numbers of a food entry came from. An estimate is the model's guess of protein, carbs and fat; rough is a quick total. */
export const FOOD_SOURCES = [
	'usda',
	'filipino',
	'saved',
	'off',
	'usda_branded',
	'label',
	'estimate',
	'manual',
	'rough'
] as const;
export const SAVED_FOOD_SOURCES = ['label', 'barcode', 'manual', 'chat'] as const;
export const PROPOSAL_KINDS = ['target', 'week', 'review'] as const;
export const PROPOSAL_STATUSES = ['open', 'accepted', 'kept', 'superseded', 'expired'] as const;
export const WORKOUT_KINDS = ['strength', 'walk', 'run', 'other'] as const;
export const PLANNED_STATUSES = ['planned', 'done', 'skipped'] as const;
export const BLOCK_KINDS = ['work', 'busy', 'free'] as const;

export type FoodSource = (typeof FOOD_SOURCES)[number];
export type MealKind = (typeof MEAL_KINDS)[number];
export type ProposalKind = (typeof PROPOSAL_KINDS)[number];
export type WorkoutKind = (typeof WORKOUT_KINDS)[number];
export type BlockKind = (typeof BLOCK_KINDS)[number];
/** Nanograms per nutrient code. The codes and their display units live in lib/health/nutrients.ts. */
export type NutrientMap = Record<string, number>;

// -- COLUMNS -- //

/** The main nutrients in milligrams, null when the source does not say. Unknown is never zero. */
const coreNutrients = () => ({
	proteinMg: integer('protein_mg'),
	carbsMg: integer('carbs_mg'),
	sugarMg: integer('sugar_mg'),
	fibreMg: integer('fibre_mg'),
	fatMg: integer('fat_mg'),
	satFatMg: integer('sat_fat_mg'),
	sodiumMg: integer('sodium_mg')
});

// -- PROFILE AND GOAL -- //

/** One row per person. Setup can be left half done, so every fact is optional until the person gives it. */
export const healthProfile = userTable(
	'health_profile',
	() => user.id,
	{
		id: id(),
		heightMm: integer('height_mm'),
		birthYear: integer('birth_year'),
		sex: text('sex', { enum: SEXES }).notNull().default('skip'),
		activity: text('activity', { enum: ACTIVITIES }).notNull().default('sitting'),
		setupDoneAt: timestamp('setup_done_at', { withTimezone: true }),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('health_profile_user_uq').on(t.userId),
		oneOf('health_profile_sex_chk', t.sex, SEXES),
		oneOf('health_profile_activity_chk', t.activity, ACTIVITIES),
		check(
			'health_profile_height_chk',
			sql`${t.heightMm} is null or ${t.heightMm} between 1000 and 2500`
		),
		check(
			'health_profile_birth_chk',
			sql`${t.birthYear} is null or ${t.birthYear} between 1900 and 2100`
		)
	]
);

/** One row per person: what they want and the calorie target in force. */
export const healthGoal = userTable(
	'health_goal',
	() => user.id,
	{
		id: id(),
		kind: text('kind', { enum: GOAL_KINDS }).notNull().default('track'),
		goalWeightG: integer('goal_weight_g'),
		paceBp: integer('pace_bp').notNull().default(50),
		targetKcal: integer('target_kcal'),
		proteinTenths: integer('protein_tenths').notNull().default(16),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('health_goal_user_uq').on(t.userId),
		oneOf('health_goal_kind_chk', t.kind, GOAL_KINDS),
		check('health_goal_weight_chk', sql`${t.goalWeightG} is null or ${t.goalWeightG} > 0`),
		check('health_goal_pace_chk', sql`${t.paceBp} between 25 and 100`),
		check('health_goal_target_chk', sql`${t.targetKcal} is null or ${t.targetKcal} > 0`),
		check('health_goal_protein_chk', sql`${t.proteinTenths} between 14 and 20`)
	]
);

// -- FOOD -- //

/** A food the person saved: per 100 g. It is archived, never deleted, so old entries can still point at it. */
export const foodItem = userTable(
	'food_item',
	() => user.id,
	{
		id: id(),
		name: text('name').notNull(),
		barcode: text('barcode'),
		source: text('source', { enum: SAVED_FOOD_SOURCES }).notNull().default('manual'),
		kcal: integer('kcal').notNull(),
		...coreNutrients(),
		nutrients: jsonb('nutrients').$type<NutrientMap>().notNull().default({}),
		/** Grams in one serving or piece, when known. */
		servingG: integer('serving_g'),
		archivedAt: timestamp('archived_at', { withTimezone: true }),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('food_item_user_id_uq').on(t.userId, t.id),
		index('food_item_user_barcode_idx').on(t.userId, t.barcode),
		oneOf('food_item_source_chk', t.source, SAVED_FOOD_SOURCES),
		check('food_item_name_chk', sql`length(${t.name}) between 1 and 120`),
		check('food_item_barcode_chk', sql`${t.barcode} is null or ${t.barcode} ~ '^[0-9]{8,14}$'`),
		check('food_item_kcal_chk', sql`${t.kcal} between 0 and 900`),
		check('food_item_serving_chk', sql`${t.servingG} is null or ${t.servingG} > 0`)
	]
);

/** One food eaten on a day, with its numbers as they were when it was logged. */
export const foodEntry = userTable(
	'food_entry',
	() => user.id,
	{
		id: id(),
		day: date('day', { mode: 'string' }).notNull(),
		meal: text('meal', { enum: MEAL_KINDS }).notNull(),
		/** Foods logged together share this. */
		mealGroup: uuid('meal_group').notNull(),
		name: text('name').notNull(),
		grams: integer('grams'),
		kcal: integer('kcal').notNull(),
		lowKcal: integer('low_kcal').notNull(),
		highKcal: integer('high_kcal').notNull(),
		...coreNutrients(),
		nutrients: jsonb('nutrients').$type<NutrientMap>().notNull().default({}),
		sourceKind: text('source_kind', { enum: FOOD_SOURCES }).notNull(),
		/** The id inside that source (a USDA id, a barcode). Text and no reference, so a new import cannot touch the entry. */
		sourceRef: text('source_ref'),
		foodItemId: uuid('food_item_id'),
		/** The assistant made this entry, so the app can mark it. */
		byAgent: boolean('by_agent').notNull().default(false),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('food_entry_user_id_uq').on(t.userId, t.id),
		index('food_entry_user_day_idx').on(t.userId, t.day),
		foreignKey({
			name: 'food_entry_item_fk',
			columns: [t.userId, t.foodItemId],
			foreignColumns: [foodItem.userId, foodItem.id]
		}),
		oneOf('food_entry_meal_chk', t.meal, MEAL_KINDS),
		oneOf('food_entry_source_chk', t.sourceKind, FOOD_SOURCES),
		check('food_entry_name_chk', sql`length(${t.name}) between 1 and 120`),
		check('food_entry_grams_chk', sql`${t.grams} is null or ${t.grams} between 1 and 10000`),
		check('food_entry_kcal_chk', sql`${t.kcal} between 0 and 20000`),
		check('food_entry_range_chk', sql`${t.lowKcal} <= ${t.kcal} and ${t.kcal} <= ${t.highKcal}`)
	]
);

/** Whether a day's food is all logged. Only complete days feed the burn estimate; a day with no row is not complete. */
export const dayStatus = userTable(
	'day_status',
	() => user.id,
	{
		id: id(),
		day: date('day', { mode: 'string' }).notNull(),
		complete: boolean('complete').notNull().default(false),
		...stamps()
	},
	(t) => [unique('day_status_user_day_uq').on(t.userId, t.day)]
);

// -- WEIGHT AND THE WEEKLY WORK -- //

/** One weigh-in a day: a second one the same day replaces it. */
export const weightEntry = userTable(
	'weight_entry',
	() => user.id,
	{
		id: id(),
		day: date('day', { mode: 'string' }).notNull(),
		grams: integer('grams').notNull(),
		/** The assistant made this entry, so the app can mark it. */
		byAgent: boolean('by_agent').notNull().default(false),
		...stamps()
	},
	(t) => [
		unique('weight_entry_user_day_uq').on(t.userId, t.day),
		check('weight_entry_grams_chk', sql`${t.grams} between 20000 and 400000`)
	]
);

/** What the weekly job worked out, one row a week. */
export const energyEstimate = userTable(
	'energy_estimate',
	() => user.id,
	{
		id: id(),
		weekKey: text('week_key').notNull(),
		trendG: integer('trend_g').notNull(),
		burnKcal: integer('burn_kcal').notNull(),
		intakeKcal: integer('intake_kcal').notNull(),
		completeDays: integer('complete_days').notNull(),
		weighIns: integer('weigh_ins').notNull(),
		...stamps()
	},
	(t) => [unique('energy_estimate_user_week_uq').on(t.userId, t.weekKey)]
);

/** Something the server worked out for the person to accept: a target, a week of workouts or a review. A new one replaces the open one of its kind. */
export const healthProposal = userTable(
	'health_proposal',
	() => user.id,
	{
		id: id(),
		kind: text('kind', { enum: PROPOSAL_KINDS }).notNull(),
		weekKey: text('week_key').notNull(),
		status: text('status', { enum: PROPOSAL_STATUSES }).notNull().default('open'),
		payload: jsonb('payload').notNull(),
		/** A fingerprint of the data it was worked out from: accepting it after that changed is refused. */
		basisHash: text('basis_hash').notNull(),
		expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
		answeredAt: timestamp('answered_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [
		unique('health_proposal_user_id_uq').on(t.userId, t.id),
		uniqueIndex('health_proposal_open_uq')
			.on(t.userId, t.kind)
			.where(sql`${t.status} = 'open'`),
		oneOf('health_proposal_kind_chk', t.kind, PROPOSAL_KINDS),
		oneOf('health_proposal_status_chk', t.status, PROPOSAL_STATUSES)
	]
);

// -- WORKOUTS -- //

/** A training program the person is following. The exercises and sessions are code data, named by its template key. */
export const program = userTable(
	'program',
	() => user.id,
	{
		id: id(),
		templateKey: text('template_key').notNull(),
		startedOn: date('started_on', { mode: 'string' }).notNull(),
		stoppedAt: timestamp('stopped_at', { withTimezone: true }),
		week: integer('week').notNull().default(1),
		/** Which easier or harder version of each movement the person is on, by movement key. */
		levels: jsonb('levels').$type<Record<string, number>>().notNull().default({}),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('program_user_id_uq').on(t.userId, t.id),
		check('program_week_chk', sql`${t.week} >= 1`)
	]
);

/** A workout placed on a day, after the person accepted the week. */
export const plannedWorkout = userTable(
	'planned_workout',
	() => user.id,
	{
		id: id(),
		programId: uuid('program_id'),
		day: date('day', { mode: 'string' }).notNull(),
		startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
		minutes: integer('minutes').notNull(),
		kind: text('kind', { enum: WORKOUT_KINDS }).notNull(),
		/** The session inside the program template, or a plain title key. */
		sessionKey: text('session_key').notNull(),
		status: text('status', { enum: PLANNED_STATUSES }).notNull().default('planned'),
		weekKey: text('week_key').notNull(),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('planned_workout_user_id_uq').on(t.userId, t.id),
		index('planned_workout_user_day_idx').on(t.userId, t.day),
		foreignKey({
			name: 'planned_workout_program_fk',
			columns: [t.userId, t.programId],
			foreignColumns: [program.userId, program.id]
		}),
		oneOf('planned_workout_kind_chk', t.kind, WORKOUT_KINDS),
		oneOf('planned_workout_status_chk', t.status, PLANNED_STATUSES),
		check('planned_workout_minutes_chk', sql`${t.minutes} between 1 and 600`)
	]
);

/** A workout that happened or is running. */
export const workoutSession = userTable(
	'workout_session',
	() => user.id,
	{
		id: id(),
		plannedId: uuid('planned_id'),
		programId: uuid('program_id'),
		day: date('day', { mode: 'string' }).notNull(),
		kind: text('kind', { enum: WORKOUT_KINDS }).notNull(),
		title: text('title').notNull(),
		minutes: integer('minutes'),
		distanceM: integer('distance_m'),
		startedAt: timestamp('started_at', { withTimezone: true }),
		finishedAt: timestamp('finished_at', { withTimezone: true }),
		/** The assistant made this entry, so the app can mark it. */
		byAgent: boolean('by_agent').notNull().default(false),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('workout_session_user_id_uq').on(t.userId, t.id),
		index('workout_session_user_day_idx').on(t.userId, t.day),
		foreignKey({
			name: 'workout_session_planned_fk',
			columns: [t.userId, t.plannedId],
			foreignColumns: [plannedWorkout.userId, plannedWorkout.id]
		}),
		foreignKey({
			name: 'workout_session_program_fk',
			columns: [t.userId, t.programId],
			foreignColumns: [program.userId, program.id]
		}),
		oneOf('workout_session_kind_chk', t.kind, WORKOUT_KINDS),
		check('workout_session_title_chk', sql`length(${t.title}) between 1 and 120`),
		check(
			'workout_session_minutes_chk',
			sql`${t.minutes} is null or ${t.minutes} between 0 and 1440`
		),
		check('workout_session_distance_chk', sql`${t.distanceM} is null or ${t.distanceM} >= 0`)
	]
);

/** One set of one exercise in a session: reps, seconds or both left out until it is done. There is no load: the workouts need no equipment. */
export const workoutSet = userTable(
	'workout_set',
	() => user.id,
	{
		id: id(),
		sessionId: uuid('session_id').notNull(),
		exerciseKey: text('exercise_key').notNull(),
		position: integer('position').notNull(),
		reps: integer('reps'),
		seconds: integer('seconds'),
		done: boolean('done').notNull().default(false),
		...stamps()
	},
	(t) => [
		unique('workout_set_user_id_uq').on(t.userId, t.id),
		unique('workout_set_position_uq').on(t.userId, t.sessionId, t.exerciseKey, t.position),
		foreignKey({
			name: 'workout_set_session_fk',
			columns: [t.userId, t.sessionId],
			foreignColumns: [workoutSession.userId, workoutSession.id]
		}).onDelete('cascade'),
		check('workout_set_reps_chk', sql`${t.reps} is null or ${t.reps} between 0 and 1000`),
		check('workout_set_seconds_chk', sql`${t.seconds} is null or ${t.seconds} between 0 and 36000`)
	]
);

// -- SLEEP -- //

/** One sleep, dated by the day the person woke, so a night shift and a nap both land on the right day. */
export const sleepEntry = userTable(
	'sleep_entry',
	() => user.id,
	{
		id: id(),
		day: date('day', { mode: 'string' }).notNull(),
		startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
		endsAt: timestamp('ends_at', { withTimezone: true }).notNull(),
		nap: boolean('nap').notNull().default(false),
		/** The assistant made this entry, so the app can mark it. */
		byAgent: boolean('by_agent').notNull().default(false),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('sleep_entry_user_id_uq').on(t.userId, t.id),
		index('sleep_entry_user_day_idx').on(t.userId, t.day),
		check('sleep_entry_time_chk', sql`${t.endsAt} > ${t.startsAt}`)
	]
);

// -- AVAILABILITY -- //

/** A repeating part of a week. It belongs to the day it starts on, and an end before its start runs past midnight. */
export const weeklyBlock = userTable(
	'weekly_block',
	() => user.id,
	{
		id: id(),
		/** 0 is Sunday, 6 is Saturday. */
		weekday: integer('weekday').notNull(),
		startMinute: integer('start_minute').notNull(),
		endMinute: integer('end_minute').notNull(),
		kind: text('kind', { enum: BLOCK_KINDS }).notNull(),
		label: text('label'),
		...stamps()
	},
	(t) => [
		index('weekly_block_user_day_idx').on(t.userId, t.weekday),
		oneOf('weekly_block_kind_chk', t.kind, BLOCK_KINDS),
		check('weekly_block_weekday_chk', sql`${t.weekday} between 0 and 6`),
		check('weekly_block_start_chk', sql`${t.startMinute} between 0 and 1439`),
		check('weekly_block_end_chk', sql`${t.endMinute} between 0 and 1440`),
		check('weekly_block_length_chk', sql`${t.startMinute} <> ${t.endMinute}`),
		check('weekly_block_label_chk', sql`${t.label} is null or length(${t.label}) <= 60`)
	]
);

/** One date that differs from the week: it has its own blocks, or none at all when off is true. */
export const availabilityOverride = userTable(
	'availability_override',
	() => user.id,
	{
		id: id(),
		day: date('day', { mode: 'string' }).notNull(),
		off: boolean('off').notNull().default(false),
		blocks: jsonb('blocks')
			.$type<{ startMinute: number; endMinute: number; kind: BlockKind; label?: string }[]>()
			.notNull()
			.default([]),
		...stamps()
	},
	(t) => [unique('availability_override_user_day_uq').on(t.userId, t.day)]
);

/** One row per person: the waking hours used when no free time is named, the buffer around work, and the wind-down reminder. */
export const availabilitySetting = userTable(
	'availability_setting',
	() => user.id,
	{
		id: id(),
		wakeStartMinute: integer('wake_start_minute').notNull().default(360),
		wakeEndMinute: integer('wake_end_minute').notNull().default(1320),
		travelMinutes: integer('travel_minutes').notNull().default(30),
		windDown: boolean('wind_down').notNull().default(false),
		...stamps()
	},
	(t) => [
		unique('availability_setting_user_uq').on(t.userId),
		check('availability_setting_wake_chk', sql`${t.wakeStartMinute} < ${t.wakeEndMinute}`),
		check('availability_setting_travel_chk', sql`${t.travelMinutes} between 0 and 240`)
	]
);

// -- SHARED NUTRITION DATA -- //

/** A food from a public source, per 100 g. Nobody's data, read by everyone, written only by the loader as the owner role. */
export const nutritionFood = plainTable(
	'nutrition_food',
	{
		/** The source and its own id, so a repeat load updates the same row: usda:171287. */
		id: text('id').primaryKey(),
		source: text('source').notNull(),
		dataType: text('data_type').notNull(),
		name: text('name').notNull(),
		kcal: integer('kcal').notNull(),
		...coreNutrients(),
		nutrients: jsonb('nutrients').$type<NutrientMap>().notNull().default({}),
		loadedAt: timestamp('loaded_at', { withTimezone: true }).notNull().defaultNow()
	},
	(t) => [
		index('nutrition_food_name_trgm_idx').using('gin', sql`${t.name} gin_trgm_ops`),
		check('nutrition_food_kcal_chk', sql`${t.kcal} between 0 and 900`)
	],
	{ readOnly: true }
);

/** A household amount of a food in grams: a cup, a piece. In tenths of a gram. */
export const nutritionPortion = plainTable(
	'nutrition_portion',
	{
		id: text('id').primaryKey(),
		foodId: text('food_id')
			.notNull()
			.references(() => nutritionFood.id, { onDelete: 'cascade' }),
		label: text('label').notNull(),
		gramsTenths: integer('grams_tenths').notNull()
	},
	(t) => [
		index('nutrition_portion_food_idx').on(t.foodId),
		check('nutrition_portion_grams_chk', sql`${t.gramsTenths} > 0`)
	],
	{ readOnly: true }
);
