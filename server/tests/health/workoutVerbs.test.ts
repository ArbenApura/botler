// WORKOUT VERBS (BTL-20261105-0015, P6.5, P6.6): A PROPOSAL WRITES NOTHING UNTIL IT IS ACCEPTED, A STALE WEEK IS REFUSED, NOBODY CAN ADD WORK BEYOND THE TEMPLATE, AND THE
// CALENDAR AND THE REMINDERS FOLLOW A MOVE OR A SKIP.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addDays, toManilaDate } from '../../src/lib/finance/dates';
import {
	healthProposal,
	job,
	plannedWorkout,
	program,
	reminder,
	user,
	workoutSession
} from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { weekKeyOf } from '../../src/lib/health/energy';
import { jobHandlers } from '../../src/lib/server/jobs/handlers';
import { enqueue, runBatch } from '../../src/lib/server/jobs/queue';
import { calendarRange } from '../../src/lib/server/ops/calendarRange';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { advancePrograms, mondayOf } from '../../src/lib/server/ops/workouts';
import { createTestDb } from '../support/testDb';

// -- TYPES -- //

type Week = {
	proposalId: string;
	monday: string;
	placed: { day: string; time: string; minutes: number; kind: string; title: string }[];
	unplaced: unknown[];
	movingMinutes: number;
	strengthDays: number;
};
type Session = {
	id: string;
	title: string;
	exercises: {
		exerciseKey: string;
		name: string;
		aim: number;
		sets: { position: number; reps: number | null; done: boolean }[];
	}[];
};
type Train = {
	minutes: number;
	strengthDays: number;
	needsMove: { id: string; suggestion: string | null }[];
	programs: { templateKey: string; week: number }[];
	next: { id: string; time: string } | null;
	todayState: string;
	todayRoutines: { title: string; time: string }[];
	todayDone: { title: string }[];
	programsDue: { templateKey: string; asked: number; toPlace: number }[];
	days: { day: string; state: string; routineDay: boolean }[];
};

// -- CONSTANTS -- //

const TODAY = toManilaDate(new Date());
const WORK_WEEK = {
	days: [
		{
			weekdays: [1, 2, 3, 4, 5],
			blocks: [{ start: '07:00', end: '18:30', kind: 'work' }]
		}
	]
};

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const ctxFor = (id: string, kind: 'person' | 'agent' = 'person'): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind, ...(kind === 'agent' ? { tool: 'test' } : {}) },
	requestId: `req-wrk-${String(++counter).padStart(6, '0')}`
});

const planned = (id: string) =>
	withUser(t.handle, id, (tx) =>
		tx.select().from(plannedWorkout).where(eq(plannedWorkout.userId, id))
	);

async function acceptNextWeek(id: string) {
	const week = (await invokeVerb(ctxFor(id), 'week_propose', {})) as Week;
	await invokeVerb(ctxFor(id), 'proposal_answer', { proposalId: week.proposalId, accept: true });
	return week;
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values(
		[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => ({
			id: `user_wrk_0000${n}`,
			name: 'P',
			email: `w${n}@example.com`
		}))
	);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('a planned week', () => {
	const id = 'user_wrk_00001';

	it('is only a proposal: it writes no session until it is accepted', async () => {
		await invokeVerb(ctxFor(id), 'availability_set', WORK_WEEK);
		const week = (await invokeVerb(ctxFor(id, 'agent'), 'week_propose', {})) as Week;
		expect(week.placed.length).toBeGreaterThanOrEqual(4);
		expect(week.strengthDays).toBe(2);
		expect(await planned(id)).toHaveLength(0);
		const answer = await invokeVerb(ctxFor(id), 'proposal_answer', {
			proposalId: week.proposalId,
			accept: true
		});
		expect(answer).toMatchObject({ accepted: true, applied: { placed: week.placed.length } });
		expect(await planned(id)).toHaveLength(week.placed.length);
	});

	it('puts work day sessions after work', async () => {
		const rows = await planned(id);
		const inManila = (d: Date) =>
			new Intl.DateTimeFormat('en-GB', {
				hour: '2-digit',
				minute: '2-digit',
				timeZone: 'Asia/Manila'
			}).format(d);
		const weekdayRows = rows.filter((r) => {
			const w = new Date(`${r.day}T00:00:00Z`).getUTCDay();
			return w >= 1 && w <= 5;
		});
		for (const r of weekdayRows) expect(inManila(r.startsAt) >= '19:00').toBe(true);
	});

	it('refuses a stale week when the free time changed', async () => {
		const other = 'user_wrk_00002';
		await invokeVerb(ctxFor(other), 'availability_set', WORK_WEEK);
		const week = (await invokeVerb(ctxFor(other), 'week_propose', {})) as Week;
		const first = week.placed[0];
		await invokeVerb(ctxFor(other), 'availability_override_set', {
			day: first?.day,
			blocks: [{ start: '06:00', end: '23:00', kind: 'work' }]
		});
		await expect(
			invokeVerb(ctxFor(other), 'proposal_answer', { proposalId: week.proposalId, accept: true })
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('no longer fits')
		});
		expect(await planned(other)).toHaveLength(0);
	});

	it('refuses a week with a part already gone by', async () => {
		const other = 'user_wrk_00008';
		await invokeVerb(ctxFor(other), 'availability_set', WORK_WEEK);
		const week = (await invokeVerb(ctxFor(other), 'week_propose', {})) as Week;
		const old = new Date(Date.now() - 14 * 86_400_000).toISOString();
		await withUser(t.handle, other, async (tx) => {
			const [row] = await tx.select().from(healthProposal).where(eq(healthProposal.userId, other));
			const payload = row?.payload as { placed: { startsAt: string }[] };
			const first = payload.placed[0];
			if (first) first.startsAt = old;
			await tx.update(healthProposal).set({ payload }).where(eq(healthProposal.userId, other));
		});
		await expect(
			invokeVerb(ctxFor(other), 'proposal_answer', { proposalId: week.proposalId, accept: true })
		).rejects.toMatchObject({
			code: 'CONFLICT',
			message: expect.stringContaining('gone by')
		});
	});

	it('flags a session that no longer fits when the week is read, and offers a time', async () => {
		const other = 'user_wrk_00003';
		await invokeVerb(ctxFor(other), 'availability_set', WORK_WEEK);
		const week = await acceptNextWeek(other);
		const saturday = week.placed.find((p) => {
			const w = new Date(`${p.day}T00:00:00Z`).getUTCDay();
			return w === 6;
		});
		const target = saturday ?? week.placed[0];
		await invokeVerb(ctxFor(other), 'availability_override_set', {
			day: target?.day,
			blocks: [{ start: '06:00', end: '15:00', kind: 'work' }]
		});
		const train = (await invokeVerb(ctxFor(other), 'train_get', {})) as Train;
		expect(train.needsMove.length).toBe(1);
		expect(train.needsMove[0]?.suggestion).toBeTruthy();
	});

	it('moves to a free time and refuses one that is not', async () => {
		const [row] = await planned(id);
		await expect(
			invokeVerb(ctxFor(id), 'workout_move', {
				plannedId: row?.id,
				day: mondayOf(addDays(TODAY, 7)),
				time: '12:00'
			})
		).rejects.toMatchObject({ code: 'CONFLICT' });
		await invokeVerb(ctxFor(id, 'agent'), 'workout_move', {
			plannedId: row?.id,
			day: mondayOf(addDays(TODAY, 7)),
			time: '20:30'
		});
		const [moved] = (await planned(id)).filter((r) => r.id === row?.id);
		expect(moved?.startsAt.toISOString()).toBe(
			new Date(`${mondayOf(addDays(TODAY, 7))}T12:30:00Z`).toISOString()
		);
	});

	it('shows on the calendar with its own layer, and leaves when skipped', async () => {
		const monday = mondayOf(addDays(TODAY, 7));
		const range = () =>
			calendarRange(ctxFor(id), {
				from: monday,
				to: addDays(monday, 6),
				layers: ['workouts']
			});
		const before = (await range()).items;
		expect(before.length).toBeGreaterThan(0);
		expect(before[0]).toMatchObject({ type: 'workout', status: 'planned' });
		await invokeVerb(ctxFor(id), 'workout_skip', { plannedId: before[0]?.id });
		expect((await range()).items.length).toBe(before.length - 1);
	});

	it('has reminders with fixed titles that follow a skip and a move', async () => {
		const rows = await withUser(t.handle, id, (tx) =>
			tx
				.select()
				.from(reminder)
				.where(and(eq(reminder.userId, id), eq(reminder.kind, 'workout')))
		);
		const scheduled = rows.filter((r) => r.status === 'scheduled');
		const live = (await planned(id)).filter((p) => p.status === 'planned');
		expect(scheduled.length).toBe(live.length);
		for (const r of scheduled) {
			expect(r.refKey).toMatch(/^workout:/);
			expect(r.title).toMatch(/^(Home strength|Walk|Run|Walk to run) at /);
			expect(r.title).not.toMatch(/kcal|kg/i);
		}
		const cancelled = rows.filter((r) => r.status === 'cancelled');
		expect(cancelled.length).toBe(1);
	});
});

describe('programs and the template limit', () => {
	const id = 'user_wrk_00004';

	it('starts by key only, once, and hands over the readiness questions', async () => {
		const a = (await invokeVerb(ctxFor(id, 'agent'), 'program_start', {
			templateKey: 'home_strength'
		})) as { program: { week: number }; readiness: string[] };
		expect(a.program.week).toBe(1);
		expect(a.readiness.length).toBeGreaterThan(0);
		await invokeVerb(ctxFor(id), 'program_start', { templateKey: 'home_strength' });
		const rows = await withUser(t.handle, id, (tx) =>
			tx.select().from(program).where(eq(program.userId, id))
		);
		expect(rows).toHaveLength(1);
		await expect(
			invokeVerb(ctxFor(id), 'program_start', { templateKey: 'make_me_run_100km' })
		).rejects.toBeDefined();
	});

	it('a set outside the template is refused, for the assistant and the person', async () => {
		const s = (await invokeVerb(ctxFor(id), 'workout_start', {
			templateKey: 'home_strength'
		})) as Session;
		expect(s.exercises.map((e) => e.name)).toEqual([
			'Wall push-ups',
			'Sit to stand',
			'Glute bridge',
			'Knee plank'
		]);
		for (const c of [ctxFor(id, 'agent'), ctxFor(id)])
			await expect(
				invokeVerb(c, 'workout_set_log', {
					sessionId: s.id,
					exerciseKey: 'push_wall',
					position: 9,
					reps: 100
				})
			).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(ctxFor(id, 'agent'), 'workout_set_log', {
				sessionId: s.id,
				exerciseKey: 'push_full',
				position: 0,
				reps: 10
			})
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('closes a session forgotten on an earlier day: gone with nothing done, and never counted by the clock', async () => {
		const other = 'user_wrk_00005';
		const empty = (await invokeVerb(ctxFor(other), 'workout_start', {})) as Session;
		const yesterday = addDays(TODAY, -1);
		const age = (id: string) =>
			withUser(t.handle, other, (tx) =>
				tx
					.update(workoutSession)
					.set({ day: yesterday, startedAt: new Date(Date.now() - 86_400_000) })
					.where(and(eq(workoutSession.userId, other), eq(workoutSession.id, id)))
			);
		await age(empty.id);
		const next = (await invokeVerb(ctxFor(other), 'workout_start', {})) as Session;
		expect(next.id).not.toBe(empty.id);
		await invokeVerb(ctxFor(other), 'workout_set_log', {
			sessionId: next.id,
			exerciseKey: next.exercises[0]?.exerciseKey,
			position: 0,
			reps: 8
		});
		await age(next.id);
		const third = (await invokeVerb(ctxFor(other), 'workout_start', {})) as Session;
		expect(third.id).not.toBe(next.id);
		const rows = await withUser(t.handle, other, (tx) =>
			tx.select().from(workoutSession).where(eq(workoutSession.id, next.id))
		);
		expect(rows[0]?.minutes).toBeLessThanOrEqual(60);
		const done = (await invokeVerb(ctxFor(other), 'workout_finish', { sessionId: third.id })) as {
			session: { minutes: number };
		};
		expect(done.session.minutes).toBeLessThanOrEqual(180);
	});

	it('answers the running session instead of starting a second', async () => {
		const a = (await invokeVerb(ctxFor(id), 'workout_start', {})) as Session;
		const b = (await invokeVerb(ctxFor(id), 'workout_start', {})) as Session;
		expect(a.id).toBe(b.id);
	});

	it('moves up one version when every set reached the top, and says so', async () => {
		const s = (await invokeVerb(ctxFor(id), 'workout_start', {})) as Session;
		for (const position of [0, 1, 2])
			await invokeVerb(ctxFor(id), 'workout_set_log', {
				sessionId: s.id,
				exerciseKey: 'push_wall',
				position,
				reps: 12
			});
		const f = (await invokeVerb(ctxFor(id), 'workout_finish', { sessionId: s.id })) as {
			levelledUp: string[];
		};
		expect(f.levelledUp).toEqual(['Incline push-ups']);
		const next = (await invokeVerb(ctxFor(id), 'workout_start', {})) as Session;
		expect(next.exercises[0]?.name).toBe('Incline push-ups');
		await invokeVerb(ctxFor(id), 'workout_finish', { sessionId: next.id });
	});

	it('goes down a version, and refuses to go past the end of the ladder', async () => {
		const s = (await invokeVerb(ctxFor(id), 'workout_start', {})) as Session;
		const swapped = (await invokeVerb(ctxFor(id, 'agent'), 'workout_swap', {
			sessionId: s.id,
			exerciseKey: 'push_incline',
			direction: 'easier'
		})) as Session;
		expect(swapped.exercises[0]?.name).toBe('Wall push-ups');
		await expect(
			invokeVerb(ctxFor(id), 'workout_swap', {
				sessionId: s.id,
				exerciseKey: 'push_wall',
				direction: 'easier'
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		await invokeVerb(ctxFor(id), 'workout_finish', { sessionId: s.id });
	});

	it('moves up after a whole week of finished sessions, once, through the job and its tenant context', async () => {
		const other = 'user_wrk_00007';
		await invokeVerb(ctxFor(other), 'program_start', { templateKey: 'walk_to_run' });
		const lastMonday = addDays(mondayOf(TODAY), -7);
		await withUser(t.handle, other, (tx) =>
			tx.update(program).set({ startedOn: lastMonday }).where(eq(program.userId, other))
		);
		// Told in chat, so this also proves a logged run counts for its program
		for (const i of [0, 2, 4])
			await invokeVerb(ctxFor(other, 'agent'), 'workout_log', {
				kind: 'run',
				minutes: 30,
				day: addDays(lastMonday, i)
			});
		const week = async () =>
			(
				await withUser(t.handle, other, (tx) =>
					tx.select().from(program).where(eq(program.userId, other))
				)
			)[0]?.week;
		await t.handle.db.delete(job);
		const key = weekKeyOf(TODAY);
		const add = () =>
			withUser(t.handle, other, (tx) => enqueue(tx, { userId: other, kind: 'health.weekly', key }));
		expect(await add()).toBe(true);
		await runBatch(t.handle, jobHandlers);
		expect(await week()).toBe(2);
		// The same week again makes no job, so a program can never move twice
		expect(await add()).toBe(false);
		await runBatch(t.handle, jobHandlers);
		expect(await week()).toBe(2);
	});

	it('moves the week only from a whole week, once, by the job', async () => {
		const other = 'user_wrk_00005';
		await invokeVerb(ctxFor(other), 'program_start', { templateKey: 'walk_to_run' });
		await withUser(t.handle, other, (tx) => advancePrograms(tx, other, TODAY));
		const week = async () =>
			(
				await withUser(t.handle, other, (tx) =>
					tx.select().from(program).where(eq(program.userId, other))
				)
			)[0]?.week;
		// Started this week: not a whole week yet
		expect(await week()).toBe(1);
		const lastMonday = addDays(mondayOf(TODAY), -7);
		await withUser(t.handle, other, (tx) =>
			tx.update(program).set({ startedOn: lastMonday }).where(eq(program.userId, other))
		);
		// A whole week with no sessions repeats it, with no fuss
		await withUser(t.handle, other, (tx) => advancePrograms(tx, other, TODAY));
		expect(await week()).toBe(1);
	});
});

describe('logging by chat', () => {
	const id = 'user_wrk_00006';

	it('logs a walk, counts it, marks by the assistant, and a delete gives it back', async () => {
		const row = (await invokeVerb(ctxFor(id, 'agent'), 'workout_log', {
			kind: 'walk',
			minutes: 30,
			distanceM: 2500
		})) as { id: string; byAgent: boolean; title: string };
		expect(row).toMatchObject({ byAgent: true, title: 'Walk' });
		const train = (await invokeVerb(ctxFor(id), 'train_get', {})) as Train;
		expect(train.minutes).toBe(30);
		const removed = await invokeVerb(ctxFor(id, 'agent'), 'workout_delete', { id: row.id });
		expect(removed).toMatchObject({ removed: { minutes: 30, kind: 'walk' } });
		expect(verbByName('workout_delete')?.kind).toBe('free');
		expect(((await invokeVerb(ctxFor(id), 'train_get', {})) as Train).minutes).toBe(0);
	});

	it('the weekly job handler is there', () => {
		expect(jobHandlers['health.weekly']).toBeTypeOf('function');
	});
});

describe('the Train screen tells the truth', () => {
	const id = 'user_wrk_00009';
	const everyDay = { freq: 'daily', time: '19:00' };

	it('says rest only when nothing is due', async () => {
		const train = (await invokeVerb(ctxFor(id), 'train_get', {})) as Train;
		expect(train.todayState).toBe('rest');
	});

	it('shows a program with sessions still to place instead of rest', async () => {
		await invokeVerb(ctxFor(id), 'program_start', { templateKey: 'walk_to_run' });
		const train = (await invokeVerb(ctxFor(id), 'train_get', {})) as Train;
		expect(train.todayState).toBe('program');
		expect(train.programsDue[0]).toMatchObject({
			templateKey: 'walk_to_run',
			asked: 3,
			toPlace: 3
		});
	});

	it('warns when a second program starts, and still starts it', async () => {
		const r = (await invokeVerb(ctxFor(id), 'program_start', { templateKey: 'home_strength' })) as {
			warning?: string;
		};
		expect(r.warning).toContain('already running');
		await invokeVerb(ctxFor(id), 'program_stop', { templateKey: 'home_strength' });
		await invokeVerb(ctxFor(id), 'program_stop', { templateKey: 'walk_to_run' });
	});

	it('shows an exercise routine due today, and ignores one that is not exercise', async () => {
		await invokeVerb(ctxFor(id), 'routine_create', { title: 'Brush teeth', recurrence: everyDay });
		expect(((await invokeVerb(ctxFor(id), 'train_get', {})) as Train).todayState).toBe('rest');
		await invokeVerb(ctxFor(id), 'routine_create', { title: 'Night jog', recurrence: everyDay });
		const train = (await invokeVerb(ctxFor(id), 'train_get', {})) as Train;
		expect(train.todayState).toBe('routine');
		expect(train.todayRoutines).toEqual([
			expect.objectContaining({ title: 'Night jog', time: '19:00' })
		]);
		expect(train.days.every((d) => d.routineDay)).toBe(true);
	});

	it('shows a finished session as done, not rest', async () => {
		await invokeVerb(ctxFor(id), 'workout_log', { kind: 'walk', minutes: 20 });
		const train = (await invokeVerb(ctxFor(id), 'train_get', {})) as Train;
		expect(train.todayState).toBe('done');
		expect(train.todayDone).toHaveLength(1);
	});
});
