// BOTLER CAN DO ALL OF HEALTH (BTL-20261105-0015, P8.3): EVERY HEALTH ACTION THE APP CALLS HAS A TOOL FOR THE ASSISTANT, EXCEPT THE RESET, AND THE ASSISTANT'S RULES HOLD: NO SHAME,
// NO CRASH DIETS, NO GOAL BELOW THE LIMITS, NO MEDICAL ADVICE. The model's words are its own, so what is tested here is what it is told and what the verbs refuse.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { SYSTEM_PREFIX } from '../../src/lib/server/agent/prompt';
import { user } from '../../src/lib/server/db/schema';
import { agentVerbs, invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const APP = join(process.cwd(), '..', 'app', 'lib');
/** The app-only verbs and why. meal_preview shows what a card would save: the assistant has meal_log and never needs a preview. */
const NOT_FOR_THE_ASSISTANT = new Set(['meal_preview']);
const ME = 'user_cov_00001';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const ctx = (kind: 'person' | 'agent' = 'agent'): Ctx => ({
	handle: t.handle,
	actor: { userId: ME, kind, ...(kind === 'agent' ? { tool: 'test' } : {}) },
	requestId: `req-cov-${String(++counter).padStart(6, '0')}`
});

/** Every verb name a Health screen or its state calls. */
function verbsTheAppCalls(): string[] {
	const dir = join(APP, 'features', 'health');
	const files = [
		...readdirSync(dir).map((f) => join(dir, f)),
		join(APP, 'state', 'health.dart'),
		join(APP, 'state', 'health_more.dart')
	];
	const names = new Set<string>();
	for (const f of files) {
		const text = readFileSync(f, 'utf8');
		for (const m of text.matchAll(
			/(?:verb|verbJson|verbList|writeOrQueue)\(\s*(?:ref,\s*)?'([a-z_]+)'/g
		))
			if (m[1]) names.add(m[1]);
		for (const m of text.matchAll(/_do\(\s*'([a-z_]+)'/g)) if (m[1]) names.add(m[1]);
		for (const m of text.matchAll(/_call\(\s*'([a-z_]+)'/g)) if (m[1]) names.add(m[1]);
	}
	return [...names].sort();
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values({ id: ME, name: 'P', email: 'cov@example.com' });
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('full agentic access', () => {
	it('finds the screens, so a change of pattern cannot empty this test', () => {
		const names = verbsTheAppCalls();
		for (const expected of ['weight_log', 'workout_set_log', 'sleep_log', 'proposal_answer'])
			expect(names).toContain(expected);
	});

	it('gives the assistant a tool for every Health action in the app', () => {
		const tools = new Set(agentVerbs().map((v) => v.name));
		const missing = verbsTheAppCalls().filter(
			(n) => !tools.has(n) && !NOT_FOR_THE_ASSISTANT.has(n)
		);
		expect(missing).toEqual([]);
	});

	it('never gives the assistant the reset', () => {
		const tools = new Set(agentVerbs().map((v) => v.name));
		expect(tools.has('data_reset')).toBe(false);
		expect(tools.has('data_reset_preview')).toBe(false);
	});

	it('holds setup, logging, editing, the target and planning a week as free tools', () => {
		for (const name of [
			'health_profile_save',
			'health_goal_set',
			'meal_log',
			'food_edit',
			'food_delete',
			'weight_log',
			'proposal_answer',
			'week_propose',
			'workout_log',
			'sleep_log',
			'availability_set'
		])
			expect(verbByName(name)?.kind, name).toBe('free');
	});
});

describe('what the assistant is told', () => {
	const prompt = SYSTEM_PREFIX;

	it.each([
		['no shame', /No shame about any food/],
		['no guilt', /no guilt about a missed workout/],
		['no praise for very little', /no praise for eating very little/],
		['the trend, not one morning', /talk about the trend/],
		['disordered eating is met gently', /fasting, purging or hating their body/],
		['not medical advice', /not medical advice/i],
		['limits are not worked around', /Never suggest a way around it/],
		['no eating back', /Do not offer to "eat back"/],
		['the check-in is theirs', /never decide it for them/],
		['no number in a notebook', /Never write weight, calories/],
		['sums go through calc', /goes through calc/],
		['no date from the forecast', /give no date when it gives none/],
		['a pattern is no cause', /never a cause/]
	])('%s', (_name, rule) => {
		expect(prompt).toMatch(rule);
	});
});

describe('what the verbs refuse', () => {
	it('a goal below the limits, for the assistant as for anyone', async () => {
		await invokeVerb(ctx('person'), 'health_profile_save', {
			heightMm: 1700,
			birthYear: 1996,
			sex: 'male',
			weightG: 74_000
		});
		await expect(
			invokeVerb(ctx(), 'health_goal_set', { kind: 'lose', goalWeightG: 40_000 })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('a crash diet target', async () => {
		await expect(
			invokeVerb(ctx(), 'health_goal_set', {
				kind: 'lose',
				goalWeightG: 70_000,
				targetKcal: 700
			})
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('a program the catalogue does not hold', async () => {
		await expect(
			invokeVerb(ctx(), 'program_start', { templateKey: 'run_every_day' })
		).rejects.toBeDefined();
	});
});
