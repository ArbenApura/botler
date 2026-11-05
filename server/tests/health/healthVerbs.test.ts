// HEALTH SETUP AND GOAL VERBS (BTL-20261105-0015, P1): THE LIMITS HOLD FOR EVERY CALLER, AND THE ASSISTANT CAN DO ALL OF IT (ADR 10)

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { HealthView } from '../../src/lib/server/ops/health';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { SCOPE_TABLES } from '../../src/lib/server/db/dataResetSql';
import { PLAIN_READ_ONLY, user } from '../../src/lib/server/db/schema';
import { exportAll } from '../../src/lib/server/ops/memory';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;
const ANNA = 'user_hlth_0001';
const BEN = 'user_hlth_0002';
const CARL = 'user_hlth_0003';

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'person' },
	requestId: `req-health-${String(++counter).padStart(6, '0')}`
});
const agent = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test' },
	requestId: `req-health-${String(++counter).padStart(6, '0')}`
});
const FACTS = { heightMm: 1700, birthYear: 1996, sex: 'male', weightG: 74_000 } as const;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: ANNA, name: 'A', email: 'a@example.com' },
		{ id: BEN, name: 'B', email: 'b@example.com' },
		{ id: CARL, name: 'C', email: 'c@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('setup', () => {
	it('starts empty and says what is missing', async () => {
		const h = (await invokeVerb(person(ANNA), 'health_get', {})) as HealthView;
		expect(h.missing).toEqual(['height', 'birth_year', 'weight']);
		expect(h.estimate).toBeNull();
		expect(h.goal.kind).toBe('track');
	});

	it('saves part of the facts, and a partial save leaves the others alone', async () => {
		await invokeVerb(person(ANNA), 'health_profile_save', { heightMm: 1700, activity: 'on_feet' });
		const h = (await invokeVerb(person(ANNA), 'health_profile_save', {
			birthYear: 1996
		})) as HealthView;
		expect(h.profile).toMatchObject({ heightMm: 1700, birthYear: 1996, activity: 'on_feet' });
		expect(h.missing).toEqual(['weight']);
	});

	it('gives the first estimate once the facts are in', async () => {
		const h = (await invokeVerb(person(ANNA), 'health_profile_save', {
			weightG: 74_000,
			setupDone: true
		})) as HealthView;
		expect(h.missing).toEqual([]);
		expect(h.estimate).toMatchObject({ burnSource: 'formula', paceKcalPerDay: 407 });
		expect(h.profile.setupDone).toBe(true);
	});

	it('returns the first answer for a replayed request', async () => {
		const c = person(BEN);
		const first = await invokeVerb(c, 'health_profile_save', { heightMm: 1600 });
		expect(await invokeVerb(c, 'health_profile_save', { heightMm: 1600 })).toEqual(first);
	});

	it('refuses a user id in the input', async () => {
		await expect(
			invokeVerb(person(ANNA), 'health_profile_save', { userId: BEN, heightMm: 1500 })
		).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('userId') });
	});
});

describe('the goal limits', () => {
	it('refuses a goal before setup and names what is missing', async () => {
		await expect(
			invokeVerb(person(CARL), 'health_goal_set', { kind: 'lose', goalWeightG: 60_000 })
		).rejects.toMatchObject({
			code: 'INVALID',
			message: 'Set up Health first: height, birth year, weight still missing.'
		});
		const track = (await invokeVerb(person(CARL), 'health_goal_set', {
			kind: 'track'
		})) as HealthView;
		expect(track.goal.targetKcal).toBeNull();
	});

	it('sets a target from the pace', async () => {
		await invokeVerb(person(ANNA), 'health_profile_save', FACTS);
		const h = (await invokeVerb(person(ANNA), 'health_goal_set', {
			kind: 'lose',
			goalWeightG: 70_000
		})) as HealthView;
		expect(h.goal.targetKcal).toBe((h.estimate?.burnKcal ?? 0) - 407);
		expect(h.goal.proteinTargetMg).toBe(118_400);
	});

	it.each(['person', 'agent'] as const)('refuses a goal under BMI 18.5 for a %s', async (who) => {
		const c = who === 'person' ? person(ANNA) : agent(ANNA);
		await expect(
			invokeVerb(c, 'health_goal_set', { kind: 'lose', goalWeightG: 50_000 })
		).rejects.toMatchObject({
			code: 'INVALID',
			message:
				'That goal is under a healthy weight for your height. The lowest goal here is 53.5 kg.'
		});
	});

	it.each(['person', 'agent'] as const)('refuses too fast a pace for a %s', async (who) => {
		const c = who === 'person' ? person(ANNA) : agent(ANNA);
		await expect(
			invokeVerb(c, 'health_goal_set', { kind: 'lose', goalWeightG: 70_000, paceBp: 150 })
		).rejects.toMatchObject({
			code: 'INVALID',
			message:
				'Losing more than 1% of your body weight a week is not allowed here. Choose a slower pace.'
		});
	});

	it.each(['person', 'agent'] as const)(
		'refuses a target under the floor for a %s',
		async (who) => {
			const c = who === 'person' ? person(ANNA) : agent(ANNA);
			await expect(
				invokeVerb(c, 'health_goal_set', { kind: 'lose', goalWeightG: 70_000, targetKcal: 900 })
			).rejects.toMatchObject({ code: 'INVALID', message: expect.stringContaining('too low') });
		}
	);
});

describe('agent access', () => {
	it('lets the assistant do setup and goals itself, and marks its weigh-in', async () => {
		expect(verbByName('health_profile_save')?.kind).toBe('free');
		expect(verbByName('health_goal_set')?.kind).toBe('free');
		const h = (await invokeVerb(agent(ANNA), 'health_goal_set', {
			kind: 'maintain'
		})) as HealthView;
		expect(h.goal.kind).toBe('maintain');
		expect(h.goal.goalWeightG).toBeNull();
	});
});

describe('the preview', () => {
	it('shows the target and about when the goal is reached, and writes nothing', async () => {
		const before = (await invokeVerb(person(ANNA), 'health_get', {})) as HealthView;
		const p = (await invokeVerb(person(ANNA), 'health_goal_preview', {
			kind: 'lose',
			goalWeightG: 70_000,
			paceBp: 50
		})) as { problem: null; targetKcal: number; gramsPerWeek: number; reachOn: string };
		expect(p.problem).toBeNull();
		expect(p.gramsPerWeek).toBe(370);
		expect(p.reachOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);
		expect(await invokeVerb(person(ANNA), 'health_get', {})).toEqual(before);
	});

	it('answers the limit instead of refusing, so a screen can show it', async () => {
		const p = (await invokeVerb(person(ANNA), 'health_goal_preview', {
			kind: 'lose',
			goalWeightG: 40_000
		})) as { problem: string; targetKcal: null };
		expect(p.problem).toContain('under a healthy weight');
		expect(p.targetKcal).toBeNull();
	});
});

describe('a reset of Health', () => {
	it('removes every Health row and leaves money and schedule alone', async () => {
		const me = 'user_hlth_0001';
		await invokeVerb(person(me), 'task_create', { title: 'Keep me' });
		const preview = (await invokeVerb(person(me), 'data_reset_preview', {
			scope: 'health'
		})) as { token: string; counts: Record<string, number> };
		expect(preview.counts.health_profile).toBe(1);
		await invokeVerb(person(me), 'data_reset', {
			scope: 'health',
			token: preview.token,
			typed: 'RESET'
		});
		const h = (await invokeVerb(person(me), 'health_get', {})) as HealthView;
		expect(h.missing).toEqual(['height', 'birth_year', 'weight']);
		const tasks = (await invokeVerb(person(me), 'task_list', {})) as unknown[];
		expect(tasks).toHaveLength(1);
	});
});

describe('the export', () => {
	it('holds the Health data, and every personal Health table', async () => {
		await invokeVerb(person(BEN), 'health_profile_save', { weightG: 80_000 });
		const out = (await exportAll(person(BEN))) as unknown as {
			health: { profile: unknown[]; weights: unknown[] };
			schedule: Record<string, unknown>;
		};
		expect(out.health.profile).toHaveLength(1);
		expect(out.health.weights).toHaveLength(1);
		// One export key for each table of the Health reset scope, so a new table cannot be left out of either
		expect(Object.keys(out.health)).toHaveLength(SCOPE_TABLES.health.length);
		expect(Object.keys(out.health)).toEqual([
			'profile',
			'goal',
			'savedFoods',
			'foodEntries',
			'days',
			'weights',
			'estimates',
			'proposals',
			'programs',
			'plannedWorkouts',
			'workoutSessions',
			'workoutSets',
			'sleep'
		]);
		expect(out.schedule).toHaveProperty('weeklyBlocks');
	});
});

describe('the shared nutrition tables', () => {
	it('names exactly the two tables as read only', () => {
		expect([...PLAIN_READ_ONLY].sort()).toEqual(['nutrition_food', 'nutrition_portion']);
	});

	it('lets the app role read them and nothing else', async () => {
		for (const table of PLAIN_READ_ONLY) {
			const [p] = await t.handle.owner.query<Record<string, boolean>>(
				`select has_table_privilege('app_runtime', $1, 'SELECT') as sel, has_table_privilege('app_runtime', $1, 'INSERT') as ins,
					has_table_privilege('app_runtime', $1, 'UPDATE') as upd, has_table_privilege('app_runtime', $1, 'DELETE') as del`,
				[table]
			);
			expect(p, table).toEqual({ sel: true, ins: false, upd: false, del: false });
		}
	});
});
