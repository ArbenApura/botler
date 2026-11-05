// WEIGHT AND THE WEEKLY CHECK-IN (BTL-20261105-0015, P5): THE JOB ONLY PROPOSES, THE ANSWER IS CHECKED, AND A STALE ONE IS REFUSED

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { Push } from '../../src/lib/server/push/fcm';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, toManilaDate } from '../../src/lib/finance/dates';
import { job, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { jobHandlers } from '../../src/lib/server/jobs/handlers';
import { createPushHandlers } from '../../src/lib/server/jobs/push';
import { enqueue, scheduleMaintenance, runBatch } from '../../src/lib/server/jobs/queue';
import { registerDevice } from '../../src/lib/server/ops/devices';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { reviewSuggestion, runWeekly, runWeeklyReview } from '../../src/lib/server/ops/weight';
import { createTestDb } from '../support/testDb';
import { eq } from 'drizzle-orm';

// -- TYPES -- //

type Trend = {
	trendG: number | null;
	changeG: number | null;
	forecast: { reason: string | null; reachOn: string | null } | null;
	lowIntake: boolean;
	points: unknown[];
};
type Proposal = { id: string; kind: string; payload: { toKcal: number; fromKcal: number } };
type HealthGet = { goal: { targetKcal: number } };

// -- CONSTANTS -- //

const ME = 'user_wgt_00001';
const TODAY = toManilaDate(new Date());
const NOISE = [120, -240, 310, -90, 160, -350, 30, 280, -110, 150];

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const ctxFor = (id: string, kind: 'person' | 'agent' = 'person'): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind, ...(kind === 'agent' ? { tool: 'test' } : {}) },
	requestId: `req-wgt-${String(++counter).padStart(6, '0')}`
});
const person = () => ctxFor(ME);

/** Four weeks of complete days eating `eaten`, on a person who really burns `burn`. */
async function fill(id: string, eaten: number, burn: number) {
	let grams = 74_000;
	for (let i = 27; i >= 0; i--) {
		const day = addDays(TODAY, -i);
		grams += (eaten - burn) / 7.7;
		await invokeVerb(ctxFor(id), 'weight_log', {
			day,
			grams: Math.round(grams + (NOISE[i % NOISE.length] ?? 0))
		});
		await invokeVerb(ctxFor(id), 'meal_log', {
			day,
			items: [{ manual: { name: 'Food', kcal: eaten } }]
		});
		await invokeVerb(ctxFor(id), 'food_day_mark', { day, complete: true });
	}
}

const enqueue2 = (id: string) =>
	withUser(t.handle, id, (tx) =>
		enqueue(tx, { userId: id, kind: 'push.health', key: 'test-week' })
	);
const weekly = (id: string) => withUser(t.handle, id, (tx) => runWeekly(tx, id, TODAY));
const proposals = async (id: string) =>
	(await invokeVerb(ctxFor(id), 'proposals_list', {})) as Proposal[];

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values(
		[1, 2, 3, 4, 5, 6].map((n) => ({
			id: `user_wgt_0000${n}`,
			name: 'P',
			email: `p${n}@example.com`
		}))
	);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('weigh-ins', () => {
	it('replaces a second one on the same day, and is free for the assistant', async () => {
		const day = addDays(TODAY, -1);
		await invokeVerb(person(), 'weight_log', { day, grams: 74_000 });
		const r = (await invokeVerb(ctxFor(ME, 'agent'), 'weight_log', {
			day,
			grams: 73_500
		})) as Trend;
		expect(r.trendG).toBe(73_500);
		expect(r.points).toHaveLength(1);
		expect(verbByName('weight_log')?.kind).toBe('free');
	});

	it('answers what a delete removed', async () => {
		const day = addDays(TODAY, -2);
		await invokeVerb(person(), 'weight_log', { day, grams: 74_100 });
		expect(await invokeVerb(person(), 'weight_delete', { day })).toEqual({
			removed: { day, grams: 74_100 }
		});
	});
});

describe('the weekly job', () => {
	const id = 'user_wgt_00002';

	it('waits until there is enough data', async () => {
		expect(await weekly(id)).toEqual({ proposed: false, reason: 'not_enough_data' });
	});

	it('proposes a change and changes nothing itself', async () => {
		await invokeVerb(ctxFor(id), 'health_profile_save', {
			heightMm: 1700,
			birthYear: 1996,
			sex: 'male',
			weightG: 74_000
		});
		await invokeVerb(ctxFor(id), 'health_goal_set', {
			kind: 'lose',
			goalWeightG: 70_000,
			targetKcal: 1900
		});
		await fill(id, 1900, 2150);
		const r = await weekly(id);
		expect(r.proposed).toBe(true);
		const [p] = await proposals(id);
		expect(p?.kind).toBe('target');
		expect(Math.abs((p?.payload.toKcal ?? 0) - 1900)).toBeLessThanOrEqual(150);
		const h = (await invokeVerb(ctxFor(id), 'health_get', {})) as HealthGet;
		expect(h.goal.targetKcal).toBe(1900);
	});

	it('replaces the open proposal, so only one is open', async () => {
		await weekly(id);
		expect(await proposals(id)).toHaveLength(1);
	});

	it('refuses a value other than the one shown', async () => {
		const [p] = await proposals(id);
		await expect(
			invokeVerb(ctxFor(id), 'proposal_answer', {
				proposalId: p?.id,
				accept: true,
				value: (p?.payload.toKcal ?? 0) - 500
			})
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('This check-in proposes')
		});
	});

	it('refuses after the data under it changed', async () => {
		const [p] = await proposals(id);
		await invokeVerb(ctxFor(id), 'weight_log', { day: addDays(TODAY, -5), grams: 90_000 });
		await expect(
			invokeVerb(ctxFor(id), 'proposal_answer', {
				proposalId: p?.id,
				accept: true,
				value: p?.payload.toKcal
			})
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('changed after')
		});
		await invokeVerb(ctxFor(id), 'weight_log', { day: addDays(TODAY, -5), grams: 73_400 });
	});

	it('refuses after the goal changed, and says why', async () => {
		const other = 'user_wgt_00003';
		await invokeVerb(ctxFor(other), 'health_profile_save', {
			heightMm: 1700,
			birthYear: 1996,
			sex: 'male',
			weightG: 74_000
		});
		await invokeVerb(ctxFor(other), 'health_goal_set', {
			kind: 'lose',
			goalWeightG: 70_000,
			targetKcal: 1900
		});
		await fill(other, 1900, 2150);
		await weekly(other);
		const [p] = await proposals(other);
		await invokeVerb(ctxFor(other), 'health_goal_set', { kind: 'track' });
		await expect(
			invokeVerb(ctxFor(other), 'proposal_answer', {
				proposalId: p?.id,
				accept: true,
				value: p?.payload.toKcal
			})
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('goal changed')
		});
		await invokeVerb(ctxFor(other), 'proposal_answer', { proposalId: p?.id, accept: false });
	});

	it('refuses a replaced proposal', async () => {
		const [old] = await proposals(id);
		await weekly(id);
		await expect(
			invokeVerb(ctxFor(id), 'proposal_answer', {
				proposalId: old?.id,
				accept: true,
				value: old?.payload.toKcal
			})
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('newer check-in')
		});
	});

	it('applies the target when the assistant says yes for the person, and a replay is the first answer', async () => {
		const [p] = await proposals(id);
		const c = ctxFor(id, 'agent');
		const args = { proposalId: p?.id, accept: true, value: p?.payload.toKcal };
		const first = await invokeVerb(c, 'proposal_answer', args);
		expect(await invokeVerb(c, 'proposal_answer', args)).toEqual(first);
		const h = (await invokeVerb(ctxFor(id), 'health_get', {})) as HealthGet;
		expect(h.goal.targetKcal).toBe(p?.payload.toKcal);
		expect(await proposals(id)).toHaveLength(0);
	});

	it('keeps the target on a no', async () => {
		const other = 'user_wgt_00006';
		await invokeVerb(ctxFor(other), 'health_profile_save', {
			heightMm: 1700,
			birthYear: 1996,
			sex: 'male',
			weightG: 74_000
		});
		await invokeVerb(ctxFor(other), 'health_goal_set', {
			kind: 'lose',
			goalWeightG: 70_000,
			targetKcal: 1900
		});
		await fill(other, 1900, 2150);
		await weekly(other);
		const [p] = await proposals(other);
		await invokeVerb(ctxFor(other), 'proposal_answer', { proposalId: p?.id, accept: false });
		const h = (await invokeVerb(ctxFor(other), 'health_get', {})) as HealthGet;
		expect(h.goal.targetKcal).toBe(1900);
	});
});

describe('the schedule', () => {
	it('makes one job a week per person, and repeats do nothing, with no backfill', async () => {
		await scheduleMaintenance(t.handle);
		await scheduleMaintenance(t.handle);
		const rows = await t.handle.db
			.select({ key: job.key, userId: job.userId })
			.from(job)
			.where(eq(job.kind, 'health.weekly'));
		const mine = rows.filter((r) => r.userId === 'user_wgt_00004');
		expect(mine).toHaveLength(1);
		expect(mine[0]?.key).toMatch(/^\d{4}-W\d{2}$/);
		expect(jobHandlers['health.weekly']).toBeTypeOf('function');
		expect(await runBatch(t.handle, jobHandlers)).toBeGreaterThanOrEqual(0);
	});
});

describe('the weekly review', () => {
	it('picks one suggestion, the first that applies', () => {
		const w = {
			completeDays: 7,
			weighIns: 7,
			minutes: 200,
			minutesGoal: 150,
			averageSleepMinutes: 420
		};
		expect(reviewSuggestion(w)).toBe('keep_going');
		expect(reviewSuggestion({ ...w, minutes: 60 })).toBe('move_more');
		expect(reviewSuggestion({ ...w, minutes: 60, weighIns: 1 })).toBe('weigh_more');
		expect(reviewSuggestion({ ...w, minutes: 60, weighIns: 1, completeDays: 2 })).toBe('log_food');
		expect(reviewSuggestion({ ...w, completeDays: 2, averageSleepMinutes: 300 })).toBe(
			'sleep_earlier'
		);
		expect(reviewSuggestion({ ...w, averageSleepMinutes: null })).toBe('keep_going');
	});

	it('makes no card for a week with nothing in it', async () => {
		const empty = 'user_wgt_00004';
		const r = await withUser(t.handle, empty, (tx) => runWeeklyReview(tx, empty, TODAY));
		expect(r.proposed).toBe(false);
	});

	it('sums last week, keeps it as a proposal with no model call, and its answer closes it', async () => {
		const id = 'user_wgt_00002';
		const r = await withUser(t.handle, id, (tx) => runWeeklyReview(tx, id, TODAY));
		expect(r.proposed).toBe(true);
		const all = (await invokeVerb(ctxFor(id), 'proposals_list', {})) as {
			id: string;
			kind: string;
			payload: { completeDays: number; averageKcal: number; suggestion: string };
		}[];
		const review = all.find((p) => p.kind === 'review');
		expect(review?.payload.completeDays).toBeGreaterThan(0);
		expect(review?.payload.averageKcal).toBe(1900);
		await invokeVerb(ctxFor(id, 'agent'), 'proposal_answer', {
			proposalId: review?.id,
			accept: false
		});
		const after = (await invokeVerb(ctxFor(id), 'proposals_list', {})) as { kind: string }[];
		expect(after.some((p) => p.kind === 'review')).toBe(false);
	});
});

describe('the push', () => {
	it('has no number in it', async () => {
		const id = 'user_wgt_00001';
		await registerDevice(ctxFor(id), {
			platform: 'android',
			pushToken: 'tok-wgt-0000001',
			label: 'Phone'
		});
		const sent: Push[] = [];
		const handlers = createPushHandlers({
			pusher: () => ({
				send: async (p: Push) => {
					sent.push(p);
					return { ok: true } as never;
				}
			})
		});
		await t.handle.db.delete(job);
		await enqueue2(id);
		await runBatch(t.handle, handlers);
		expect(sent.length).toBeGreaterThan(0);
		expect(JSON.stringify(sent)).not.toMatch(/d+s*(kcal|kg)/i);
		expect(JSON.stringify(sent)).toContain('check-in');
	});
});

describe('the trend answer', () => {
	const id = 'user_wgt_00005';

	it('gives no date from a couple of weigh-ins', async () => {
		const few = 'user_wgt_00004';
		await invokeVerb(ctxFor(few), 'health_goal_set', { kind: 'lose', goalWeightG: 50_000 }).catch(
			() => undefined
		);
		await invokeVerb(ctxFor(few), 'weight_log', { day: addDays(TODAY, -1), grams: 70_000 });
		await invokeVerb(ctxFor(few), 'weight_log', { day: TODAY, grams: 69_000 });
		const r = (await invokeVerb(ctxFor(few), 'weight_trend', {})) as Trend;
		expect(r.forecast?.reachOn).toBeNull();
	});

	it('hands over the entries with who made them, for the mark and the remove', async () => {
		const c = ctxFor(ME, 'agent');
		await invokeVerb(c, 'weight_log', { grams: 73_000 });
		const r = (await invokeVerb(ctxFor(ME), 'weight_trend', {})) as Trend & {
			entries: { day: string; byAgent: boolean }[];
		};
		expect(r.entries[0]).toMatchObject({ day: TODAY, byAgent: true });
	});

	it('gives no forecast date from a flat trend, and flags very low eating gently', async () => {
		await invokeVerb(ctxFor(id), 'health_goal_set', { kind: 'track' });
		for (let i = 6; i >= 0; i--) {
			const day = addDays(TODAY, -i);
			await invokeVerb(ctxFor(id), 'weight_log', { day, grams: 70_000 });
			await invokeVerb(ctxFor(id), 'meal_log', {
				day,
				items: [{ manual: { name: 'Small', kcal: 500 } }]
			});
			await invokeVerb(ctxFor(id), 'food_day_mark', { day, complete: true });
		}
		const r = (await invokeVerb(ctxFor(id), 'weight_trend', {})) as Trend;
		expect(r.forecast?.reachOn).toBeNull();
		expect(r.lowIntake).toBe(true);
	});
});
