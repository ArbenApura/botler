// WORKOUT VERBS (BTL-20261105-0015, P6). THE PERSON AND THE ASSISTANT CAN DO ALL OF IT, BUT ONLY WITHIN THE TEMPLATES: A SESSION IS MADE FROM CODE DATA AND A SET THE TEMPLATE
// DOES NOT HOLD IS REFUSED, SO NOBODY CAN TALK THE APP INTO MORE WORK. A WEEK IS ONLY A PROPOSAL UNTIL IT IS ACCEPTED; ITS FREE TIME IS CHECKED AGAIN AT THAT MOMENT.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { WorkoutKind } from '../db/schema';
import type { WantedSession } from '../../health/planner';
import type { ProgramKey } from '../../health/programs';
import type { AvailabilityInput } from '../../schedule/availability';
import type { Ctx } from './context';
import type {
	ProgramKeyInput,
	WeekProposeInput,
	WorkoutDeleteInput,
	WorkoutFinishInput,
	WorkoutLastInput,
	WorkoutLogInput,
	WorkoutMoveInput,
	WorkoutSetLogInput,
	WorkoutSkipInput,
	WorkoutStartInput,
	WorkoutSwapInput
} from '../db/zod';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
import {
	and,
	asc,
	desc,
	eq,
	gte,
	inArray,
	isNotNull,
	isNull,
	lte,
	notExists,
	sql
} from 'drizzle-orm';
// -- MODULES -- //
import { addDays, toManilaDate, weekday } from '../../finance/dates';
import { weekKeyOf } from '../../health/energy';
import { moveSuggestion, planWeek, stillFits } from '../../health/planner';
import {
	exerciseAt,
	MINUTES_GOAL,
	movementOf,
	MOVEMENTS,
	movementOfExercise,
	PROGRAM_KEYS,
	PROGRAMS,
	READINESS,
	RUN_PER_WEEK,
	runMinutes,
	runWeek,
	STRENGTH_GOAL_DAYS,
	STRENGTH_PER_WEEK,
	strengthSession,
	workoutTitle
} from '../../health/programs';
import { nextAim, nextLevels, nextRunWeek, nextStrengthWeek } from '../../health/progress';
import { blocksOn, freeSlots, timeOf } from '../../schedule/availability';
import { atManilaTime } from '../../schedule/recurrence';
import { plannedWorkout, program, workoutSession, workoutSet } from '../db/schema';
import {
	programKeyInput,
	weekProposeInput,
	workoutDeleteInput,
	workoutFinishInput,
	workoutLastInput,
	workoutLogInput,
	workoutMoveInput,
	workoutSetLogInput,
	workoutSkipInput,
	workoutStartInput,
	workoutSwapInput
} from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { readAvailability } from './availability';
import { supersedeAndPropose } from './proposals';
import { afterScheduleChange } from './schedule';
import { mapped, parse, plain } from './shared';

// -- TYPES -- //

type ProposedWeek = {
	monday: string;
	placed: {
		day: string;
		startsAt: string;
		time: string;
		minutes: number;
		kind: WorkoutKind;
		sessionKey: string;
		programId: string | null;
		title: string;
	}[];
	unplaced: { kind: string; title: string }[];
	movingMinutes: number;
	strengthDays: number;
};

// -- CONSTANTS -- //

const SLOT_MIN_MINUTES = 15;
const PLAIN_WALKS = 3;
const WALK_SHORT = 30;
const WALK_LONG = 40;
const STRENGTH_SHORT = 20;
const STRENGTH_LONG = 35;
const WEEKS_AHEAD_MAX = 8;
/** A finish with no minutes given counts the clock, at most this long. */
const LONGEST_AUTO_MINUTES = 180;
/** A run or strength workout told in chat counts for its program. A plain walk does not. */
const PROGRAM_OF_KIND: Partial<Record<WorkoutKind, ProgramKey>> = {
	run: 'walk_to_run',
	strength: 'home_strength'
};

// -- FUNCTIONS -- //

const isAgent = (ctx: Ctx) => ctx.actor.kind === 'agent' || ctx.onBehalfOf === 'agent';

/** The Monday of the week a date is in. */
export const mondayOf = (day: string): string => addDays(day, -((weekday(day) + 6) % 7));

const workDaysOf = (days: readonly string[], input: AvailabilityInput) =>
	new Set(
		days.filter((d) => blocksOn(d, input.weekly, input.overrides).some((b) => b.kind === 'work'))
	);

const weekDays = (monday: string) => [0, 1, 2, 3, 4, 5, 6].map((i) => addDays(monday, i));

const activePrograms = (tx: Tx, userId: string) =>
	tx
		.select()
		.from(program)
		.where(and(eq(program.userId, userId), isNull(program.stoppedAt)))
		.orderBy(asc(program.createdAt));

function programView(p: typeof program.$inferSelect) {
	const template = PROGRAMS[p.templateKey as ProgramKey];
	return {
		id: p.id,
		templateKey: p.templateKey,
		name: template?.name ?? p.templateKey,
		line: template?.line ?? '',
		week: p.week,
		weeks: template?.weeks ?? p.week,
		percent: template ? Math.round(((p.week - 1) / template.weeks) * 100) : 0,
		startedOn: p.startedOn
	};
}

/** The programs that exist, the ones running, and the questions to ask before starting. */
export async function listPrograms(ctx: Ctx) {
	return run(ctx, async (tx, userId) => ({
		templates: PROGRAM_KEYS.map((k) => ({
			key: k,
			name: PROGRAMS[k].name,
			line: PROGRAMS[k].line,
			weeks: PROGRAMS[k].weeks,
			perWeek: PROGRAMS[k].perWeek
		})),
		active: (await activePrograms(tx, userId)).map(programView),
		readiness: READINESS
	}));
}

/** Starts a program by its key. There is nothing else to give, so a session can only ever be what the template holds. */
export async function startProgram(ctx: Ctx, raw: ProgramKeyInput) {
	const { templateKey } = parse(programKeyInput, raw);
	return mapped(() =>
		runWrite(ctx, 'program.start', { templateKey }, async (tx, userId) => {
			const running = (await activePrograms(tx, userId)).find((p) => p.templateKey === templateKey);
			if (running) return { program: programView(running), readiness: READINESS };
			const [row] = await tx
				.insert(program)
				.values({ userId, templateKey, startedOn: toManilaDate(new Date()) })
				.returning();
			if (!row) throw new OpsError('INVALID', 'The program could not be started.');
			return { program: programView(row), readiness: READINESS };
		})
	);
}

/** Stops a program. What was done stays, and the sessions still ahead are let go. */
export async function stopProgram(ctx: Ctx, raw: ProgramKeyInput) {
	const { templateKey } = parse(programKeyInput, raw);
	return mapped(() =>
		runWrite(ctx, 'program.stop', { templateKey }, async (tx, userId) => {
			const running = (await activePrograms(tx, userId)).find((p) => p.templateKey === templateKey);
			if (!running) throw new OpsError('NOT_FOUND', 'That program is not running.');
			await tx
				.update(program)
				.set({
					stoppedAt: new Date(),
					version: sql`${program.version} + 1`,
					updatedAt: new Date()
				})
				.where(and(eq(program.userId, userId), eq(program.id, running.id)));
			await tx
				.update(plannedWorkout)
				.set({
					status: 'skipped',
					version: sql`${plannedWorkout.version} + 1`,
					updatedAt: new Date()
				})
				.where(
					and(
						eq(plannedWorkout.userId, userId),
						eq(plannedWorkout.programId, running.id),
						eq(plannedWorkout.status, 'planned')
					)
				);
			await afterScheduleChange(tx, userId);
			return { stopped: templateKey };
		})
	);
}

/** What a week should hold: what the running programs ask for, otherwise two strength days and walks towards 150 minutes. */
function wantedFor(programs: readonly (typeof program.$inferSelect)[]): WantedSession[] {
	const strength = programs.find((p) => p.templateKey === 'home_strength');
	const runner = programs.find((p) => p.templateKey === 'walk_to_run');
	const out: WantedSession[] = [];
	for (let i = 0; i < (strength ? STRENGTH_PER_WEEK : STRENGTH_GOAL_DAYS); i++)
		out.push({
			kind: 'strength',
			sessionKey: 'home_strength',
			programId: strength?.id ?? null,
			shortMinutes: STRENGTH_SHORT,
			longMinutes: STRENGTH_LONG
		});
	if (runner) {
		const minutes = runMinutes(runner.week);
		for (let i = 0; i < RUN_PER_WEEK; i++)
			out.push({
				kind: 'run',
				sessionKey: 'walk_to_run',
				programId: runner.id,
				shortMinutes: minutes,
				longMinutes: minutes
			});
	} else
		for (let i = 0; i < PLAIN_WALKS; i++)
			out.push({
				kind: 'walk',
				sessionKey: 'walk',
				programId: null,
				shortMinutes: WALK_SHORT,
				longMinutes: WALK_LONG
			});
	return out;
}

/** Works out a week and keeps it as a proposal. It writes no session. Next week unless a Monday is given. */
export async function proposeWeek(ctx: Ctx, raw: WeekProposeInput) {
	const input = parse(weekProposeInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.week_propose', input, async (tx, userId) => {
			const today = toManilaDate(new Date());
			const thisMonday = mondayOf(today);
			const monday = input.monday ? mondayOf(input.monday) : addDays(thisMonday, 7);
			if (monday < thisMonday || monday > addDays(thisMonday, WEEKS_AHEAD_MAX * 7))
				throw new OpsError('INVALID', 'Plan this week or one of the next 8 weeks.');
			const days = weekDays(monday);
			const sunday = addDays(monday, 6);
			const availability = await readAvailability(tx, userId, monday, sunday);
			// Days already gone cannot hold a session
			const startedBy = Date.now();
			const slots = freeSlots(monday, sunday, availability, SLOT_MIN_MINUTES).filter(
				(s) => Date.parse(s.startsAt) > startedBy
			);
			const wanted = wantedFor(await activePrograms(tx, userId));
			const plan = planWeek({
				monday,
				slots,
				workDays: workDaysOf(days, availability),
				wanted
			});
			const payload: ProposedWeek = {
				monday,
				placed: plan.placed.map((p) => ({
					...p,
					title: workoutTitle(p.sessionKey, p.kind)
				})),
				unplaced: plan.unplaced.map((w) => ({
					kind: w.kind,
					title: workoutTitle(w.sessionKey, w.kind)
				})),
				movingMinutes: plan.movingMinutes,
				strengthDays: plan.strengthDays
			};
			const row = await supersedeAndPropose(tx, userId, {
				kind: 'week',
				weekKey: weekKeyOf(monday),
				payload,
				basisHash: createHash('sha256').update(JSON.stringify(slots)).digest('hex')
			});
			return plain({ proposalId: row?.id, ...payload });
		})
	);
}

/** Writes the sessions of an accepted week, after checking each one still has room. Sessions of that week not yet started are replaced. */
export async function acceptWeekProposal(
	tx: Tx,
	userId: string,
	raw: unknown,
	weekKey: string
): Promise<unknown> {
	const week = raw as ProposedWeek;
	const sunday = addDays(week.monday, 6);
	const now = Date.now();
	if (week.placed.some((p) => Date.parse(p.startsAt) <= now))
		throw new OpsError('CONFLICT', 'Part of this week has already gone by. Ask for a new week.');
	const availability = await readAvailability(tx, userId, week.monday, sunday);
	const slots = freeSlots(week.monday, sunday, availability, SLOT_MIN_MINUTES);
	const lost = week.placed.find((p) => !stillFits(slots, p.day, new Date(p.startsAt), p.minutes));
	if (lost)
		throw new OpsError(
			'CONFLICT',
			`${lost.title} on ${lost.day} no longer fits your free time. Ask for a new week.`
		);
	await tx.delete(plannedWorkout).where(
		and(
			eq(plannedWorkout.userId, userId),
			eq(plannedWorkout.weekKey, weekKey),
			eq(plannedWorkout.status, 'planned'),
			// What already went by stays as it was: only what is still ahead is replaced
			gte(plannedWorkout.startsAt, new Date(now)),
			notExists(
				tx
					.select({ one: sql`1` })
					.from(workoutSession)
					.where(
						and(eq(workoutSession.userId, userId), eq(workoutSession.plannedId, plannedWorkout.id))
					)
			)
		)
	);
	if (week.placed.length)
		await tx.insert(plannedWorkout).values(
			week.placed.map((p) => ({
				userId,
				programId: p.programId,
				day: p.day,
				startsAt: new Date(p.startsAt),
				minutes: p.minutes,
				kind: p.kind,
				sessionKey: p.sessionKey,
				weekKey
			}))
		);
	await afterScheduleChange(tx, userId);
	return { placed: week.placed.length };
}

/** A session as the screen and the assistant read it: each movement with its sets, the aim from last time, and the path to harder versions. */
async function sessionView(tx: Tx, userId: string, s: typeof workoutSession.$inferSelect) {
	const sets = await tx
		.select()
		.from(workoutSet)
		.where(and(eq(workoutSet.userId, userId), eq(workoutSet.sessionId, s.id)))
		.orderBy(asc(workoutSet.position));
	const [p] = s.programId
		? await tx
				.select()
				.from(program)
				.where(and(eq(program.userId, userId), eq(program.id, s.programId)))
		: [];
	const exercises = [];
	for (const m of MOVEMENTS) {
		const mine = sets.filter((x) => movementOfExercise(x.exerciseKey)?.key === m.key);
		if (!mine.length) continue;
		const key = mine.at(-1)?.exerciseKey ?? '';
		const level = m.ladder.findIndex((e) => e.key === key);
		exercises.push({
			movement: m.key,
			exerciseKey: key,
			name: exerciseAt(m, level).name,
			how: exerciseAt(m, level).how,
			measure: m.measure,
			low: m.low,
			high: m.high,
			level,
			ladder: m.ladder.map((e) => e.name),
			aim: nextAim(m, await lastBest(tx, userId, key, s.id)),
			sets: plain(
				mine.map((x) => ({ position: x.position, reps: x.reps, seconds: x.seconds, done: x.done }))
			)
		});
	}
	const runner = s.kind === 'run' && p ? runWeek(p.week) : null;
	return {
		id: s.id,
		title: s.title,
		kind: s.kind,
		plannedId: s.plannedId,
		day: s.day,
		startedAt: s.startedAt?.toISOString() ?? null,
		finishedAt: s.finishedAt?.toISOString() ?? null,
		minutes: s.minutes,
		distanceM: s.distanceM,
		byAgent: s.byAgent,
		exercises,
		run: runner
			? { week: runner.week, ...runner.steps, note: runner.note, minutes: runMinutes(runner.week) }
			: null
	};
}

/** The best set of an exercise in the last session that held it. */
async function lastBest(tx: Tx, userId: string, exerciseKey: string, notSession: string) {
	const rows = await tx
		.select({
			reps: workoutSet.reps,
			seconds: workoutSet.seconds,
			sessionId: workoutSet.sessionId
		})
		.from(workoutSet)
		.innerJoin(
			workoutSession,
			and(eq(workoutSession.userId, workoutSet.userId), eq(workoutSession.id, workoutSet.sessionId))
		)
		.where(
			and(
				eq(workoutSet.userId, userId),
				eq(workoutSet.exerciseKey, exerciseKey),
				eq(workoutSet.done, true),
				isNotNull(workoutSession.finishedAt),
				sql`${workoutSet.sessionId} <> ${notSession}`
			)
		)
		.orderBy(desc(workoutSession.finishedAt))
		.limit(10);
	const first = rows[0];
	if (!first) return null;
	const same = rows.filter((r) => r.sessionId === first.sessionId);
	return Math.max(...same.map((r) => r.reps ?? r.seconds ?? 0));
}

async function sessionById(tx: Tx, userId: string, id: string) {
	const [s] = await tx
		.select()
		.from(workoutSession)
		.where(and(eq(workoutSession.userId, userId), eq(workoutSession.id, id)));
	if (!s) throw new OpsError('NOT_FOUND', 'That workout is not there.');
	return s;
}

async function plannedById(tx: Tx, userId: string, id: string) {
	const [p] = await tx
		.select()
		.from(plannedWorkout)
		.where(and(eq(plannedWorkout.userId, userId), eq(plannedWorkout.id, id)));
	if (!p) throw new OpsError('NOT_FOUND', 'That planned workout is not there.');
	return p;
}

/**
 * A session started on an earlier day and never finished. With sets done it counts as finished at its planned length, because the clock cannot tell how long it really took.
 * With nothing done it goes away, and a planned one it held is open again.
 */
async function closeForgotten(tx: Tx, userId: string, s: typeof workoutSession.$inferSelect) {
	const sets = await tx
		.select({ done: workoutSet.done })
		.from(workoutSet)
		.where(and(eq(workoutSet.userId, userId), eq(workoutSet.sessionId, s.id)));
	const mine = and(eq(workoutSession.userId, userId), eq(workoutSession.id, s.id));
	if (!sets.some((x) => x.done)) {
		await tx.delete(workoutSession).where(mine);
		return;
	}
	const planned = s.plannedId ? await plannedById(tx, userId, s.plannedId) : null;
	await tx
		.update(workoutSession)
		.set({
			finishedAt: new Date(),
			minutes: planned?.minutes ?? STRENGTH_SHORT,
			version: sql`${workoutSession.version} + 1`,
			updatedAt: new Date()
		})
		.where(mine);
	await closePlanned(tx, userId, s.plannedId, s.day, s.kind);
}

/** Starts a workout from a planned one or from a program, and answers the running one if there is one. A plain walk is logged with workout_log instead. */
export async function startWorkout(ctx: Ctx, raw: WorkoutStartInput) {
	const input = parse(workoutStartInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.start', input, async (tx, userId) => {
			const [running] = await tx
				.select()
				.from(workoutSession)
				.where(
					and(
						eq(workoutSession.userId, userId),
						isNotNull(workoutSession.startedAt),
						isNull(workoutSession.finishedAt)
					)
				);
			const today = toManilaDate(new Date());
			if (running && running.day >= today) return sessionView(tx, userId, running);
			if (running) await closeForgotten(tx, userId, running);
			const planned = input.plannedId ? await plannedById(tx, userId, input.plannedId) : null;
			if (planned && planned.status !== 'planned')
				throw new OpsError('CONFLICT', 'That workout is already done or skipped.');
			const programs = await activePrograms(tx, userId);
			const sessionKey = planned?.sessionKey ?? input.templateKey ?? 'home_strength';
			const kind: WorkoutKind =
				planned?.kind ?? (sessionKey === 'walk_to_run' ? 'run' : 'strength');
			const p =
				programs.find((x) => x.id === planned?.programId) ??
				programs.find((x) => x.templateKey === sessionKey);
			const now = new Date();
			const [s] = await tx
				.insert(workoutSession)
				.values({
					userId,
					plannedId: planned?.id ?? null,
					programId: p?.id ?? null,
					day: toManilaDate(now),
					kind,
					title: workoutTitle(sessionKey, kind),
					startedAt: now,
					byAgent: isAgent(ctx)
				})
				.returning();
			if (!s) throw new OpsError('INVALID', 'The workout could not be started.');
			if (kind === 'strength') {
				const rows = strengthSession(p?.levels ?? {}).flatMap((e) =>
					Array.from({ length: e.sets }, (_, position) => ({
						userId,
						sessionId: s.id,
						exerciseKey: e.exerciseKey,
						position
					}))
				);
				await tx.insert(workoutSet).values(rows);
			}
			return sessionView(tx, userId, s);
		})
	);
}

/** Logs one set of the session. A set the template did not place is refused, so the work can never grow past it. */
export async function logSet(ctx: Ctx, raw: WorkoutSetLogInput) {
	const input = parse(workoutSetLogInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.set_log', input, async (tx, userId) => {
			const s = await sessionById(tx, userId, input.sessionId);
			if (s.finishedAt) throw new OpsError('CONFLICT', 'That workout is already finished.');
			const updated = await tx
				.update(workoutSet)
				.set({
					reps: input.reps ?? null,
					seconds: input.seconds ?? null,
					done: input.done ?? true,
					updatedAt: new Date()
				})
				.where(
					and(
						eq(workoutSet.userId, userId),
						eq(workoutSet.sessionId, s.id),
						eq(workoutSet.exerciseKey, input.exerciseKey),
						eq(workoutSet.position, input.position)
					)
				)
				.returning({ id: workoutSet.id });
			if (!updated.length) throw new OpsError('INVALID', 'That set is not part of this workout.');
			return sessionView(tx, userId, s);
		})
	);
}

/** Moves a movement one version easier or harder, for the sets not done yet and for the next sessions too. */
export async function swapExercise(ctx: Ctx, raw: WorkoutSwapInput) {
	const input = parse(workoutSwapInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.swap', input, async (tx, userId) => {
			const s = await sessionById(tx, userId, input.sessionId);
			if (s.finishedAt) throw new OpsError('CONFLICT', 'That workout is already finished.');
			const m = movementOfExercise(input.exerciseKey);
			if (!m) throw new OpsError('INVALID', 'That exercise is not part of the catalogue.');
			const level = m.ladder.findIndex((e) => e.key === input.exerciseKey);
			const to = level + (input.direction === 'easier' ? -1 : 1);
			const target = m.ladder[to];
			if (!target)
				throw new OpsError(
					'INVALID',
					`There is no ${input.direction} version of ${exerciseAt(m, level).name}.`
				);
			await tx
				.update(workoutSet)
				.set({ exerciseKey: target.key, updatedAt: new Date() })
				.where(
					and(
						eq(workoutSet.userId, userId),
						eq(workoutSet.sessionId, s.id),
						eq(workoutSet.exerciseKey, input.exerciseKey),
						eq(workoutSet.done, false)
					)
				);
			if (s.programId)
				await tx
					.update(program)
					.set({
						levels: sql`${program.levels} || ${JSON.stringify({ [m.key]: to })}::jsonb`,
						version: sql`${program.version} + 1`,
						updatedAt: new Date()
					})
					.where(and(eq(program.userId, userId), eq(program.id, s.programId)));
			return sessionView(tx, userId, s);
		})
	);
}

/** Marks a planned workout done, the one named or today's of the same kind. */
async function closePlanned(
	tx: Tx,
	userId: string,
	plannedId: string | null | undefined,
	day: string,
	kind: WorkoutKind
) {
	if (plannedId) {
		await tx
			.update(plannedWorkout)
			.set({
				status: 'done',
				version: sql`${plannedWorkout.version} + 1`,
				updatedAt: new Date()
			})
			.where(and(eq(plannedWorkout.userId, userId), eq(plannedWorkout.id, plannedId)));
		return plannedId;
	}
	const [same] = await tx
		.select({ id: plannedWorkout.id })
		.from(plannedWorkout)
		.where(
			and(
				eq(plannedWorkout.userId, userId),
				eq(plannedWorkout.day, day),
				eq(plannedWorkout.kind, kind),
				eq(plannedWorkout.status, 'planned')
			)
		);
	if (!same) return null;
	return closePlanned(tx, userId, same.id, day, kind);
}

/** Finishes the running workout. Strength moves on by the rules: every set at the top of its range brings the next version. */
export async function finishWorkout(ctx: Ctx, raw: WorkoutFinishInput) {
	const input = parse(workoutFinishInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.finish', input, async (tx, userId) => {
			const s = await sessionById(tx, userId, input.sessionId);
			if (s.finishedAt) throw new OpsError('CONFLICT', 'That workout is already finished.');
			const now = new Date();
			const started = s.startedAt ?? now;
			const minutes =
				input.minutes ??
				Math.min(
					LONGEST_AUTO_MINUTES,
					Math.max(1, Math.round((now.getTime() - started.getTime()) / 60_000))
				);
			const [done] = await tx
				.update(workoutSession)
				.set({
					finishedAt: now,
					minutes,
					distanceM: input.distanceM ?? null,
					version: sql`${workoutSession.version} + 1`,
					updatedAt: now
				})
				.where(and(eq(workoutSession.userId, userId), eq(workoutSession.id, s.id)))
				.returning();
			if (!done) throw new OpsError('NOT_FOUND', 'That workout is not there.');
			await closePlanned(tx, userId, s.plannedId, s.day, s.kind);
			let levelledUp: string[] = [];
			if (s.programId && s.kind === 'strength') {
				const [p] = await tx
					.select()
					.from(program)
					.where(and(eq(program.userId, userId), eq(program.id, s.programId)));
				const sets = await tx
					.select()
					.from(workoutSet)
					.where(and(eq(workoutSet.userId, userId), eq(workoutSet.sessionId, s.id)));
				if (p) {
					const result = nextLevels(p.levels, sets);
					levelledUp = result.levelledUp.map((k) => {
						const m = movementOf(k);
						return m ? exerciseAt(m, result.levels[k] ?? 0).name : k;
					});
					if (levelledUp.length)
						await tx
							.update(program)
							.set({
								levels: result.levels,
								version: sql`${program.version} + 1`,
								updatedAt: now
							})
							.where(and(eq(program.userId, userId), eq(program.id, p.id)));
				}
			}
			await afterScheduleChange(tx, userId);
			return { session: await sessionView(tx, userId, done), levelledUp };
		})
	);
}

/** Logs a workout that already happened, such as a walk told in chat. A planned one of the same kind that day counts as done. */
export async function logWorkout(ctx: Ctx, raw: WorkoutLogInput) {
	const input = parse(workoutLogInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.log', input, async (tx, userId) => {
			const now = new Date();
			const day = input.day ?? toManilaDate(now);
			const plannedId = await closePlanned(tx, userId, null, day, input.kind);
			const templateKey = PROGRAM_OF_KIND[input.kind];
			const counted = (await activePrograms(tx, userId)).find((p) => p.templateKey === templateKey);
			const [row] = await tx
				.insert(workoutSession)
				.values({
					userId,
					plannedId,
					programId: counted?.id ?? null,
					day,
					kind: input.kind,
					title: input.title ?? workoutTitle(input.kind, input.kind),
					minutes: input.minutes,
					distanceM: input.distanceM ?? null,
					finishedAt: now,
					byAgent: isAgent(ctx)
				})
				.returning();
			if (!row) throw new OpsError('INVALID', 'The workout could not be saved.');
			await afterScheduleChange(tx, userId);
			return plain(row);
		})
	);
}

/** Removes a workout and answers what was removed. A planned one it had closed is open again. */
export async function deleteWorkout(ctx: Ctx, raw: WorkoutDeleteInput) {
	const input = parse(workoutDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.delete', input, async (tx, userId) => {
			const s = await sessionById(tx, userId, input.id);
			await tx
				.delete(workoutSession)
				.where(and(eq(workoutSession.userId, userId), eq(workoutSession.id, s.id)));
			if (s.plannedId)
				await tx
					.update(plannedWorkout)
					.set({
						status: 'planned',
						version: sql`${plannedWorkout.version} + 1`,
						updatedAt: new Date()
					})
					.where(and(eq(plannedWorkout.userId, userId), eq(plannedWorkout.id, s.plannedId)));
			await afterScheduleChange(tx, userId);
			return {
				removed: plain({
					id: s.id,
					day: s.day,
					kind: s.kind,
					title: s.title,
					minutes: s.minutes,
					distanceM: s.distanceM
				})
			};
		})
	);
}

/** The latest finished workouts, newest first. */
export async function lastWorkouts(ctx: Ctx, raw: WorkoutLastInput) {
	const input = parse(workoutLastInput, raw);
	return run(ctx, async (tx, userId) => {
		const rows = await tx
			.select()
			.from(workoutSession)
			.where(
				and(
					eq(workoutSession.userId, userId),
					isNotNull(workoutSession.finishedAt),
					...(input.kind ? [eq(workoutSession.kind, input.kind)] : [])
				)
			)
			.orderBy(desc(workoutSession.day), desc(workoutSession.finishedAt))
			.limit(input.limit ?? 5);
		const out = [];
		for (const r of rows) out.push(await sessionView(tx, userId, r));
		return out;
	});
}

/** Moves a planned workout to a time that is free. */
export async function moveWorkout(ctx: Ctx, raw: WorkoutMoveInput) {
	const input = parse(workoutMoveInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.move', input, async (tx, userId) => {
			const p = await plannedById(tx, userId, input.plannedId);
			if (p.status !== 'planned')
				throw new OpsError('CONFLICT', 'That workout is already done or skipped.');
			const day = input.day ?? p.day;
			const at = atManilaTime(day, input.time);
			const availability = await readAvailability(tx, userId, day, day);
			const slots = freeSlots(day, day, availability, SLOT_MIN_MINUTES);
			if (!stillFits(slots, day, at, p.minutes)) {
				const better = moveSuggestion(
					slots,
					day,
					p.minutes,
					workDaysOf([day], availability).has(day)
				);
				throw new OpsError(
					'CONFLICT',
					better
						? `That time is not free on ${day}. ${better} would fit.`
						: `There is no free time for ${p.minutes} minutes on ${day}.`
				);
			}
			const [row] = await tx
				.update(plannedWorkout)
				.set({
					day,
					startsAt: at,
					weekKey: weekKeyOf(day),
					version: sql`${plannedWorkout.version} + 1`,
					updatedAt: new Date()
				})
				.where(and(eq(plannedWorkout.userId, userId), eq(plannedWorkout.id, p.id)))
				.returning();
			await afterScheduleChange(tx, userId);
			return plain(row);
		})
	);
}

/** Lets a planned workout go, with no fuss. */
export async function skipWorkout(ctx: Ctx, raw: WorkoutSkipInput) {
	const input = parse(workoutSkipInput, raw);
	return mapped(() =>
		runWrite(ctx, 'workout.skip', input, async (tx, userId) => {
			const p = await plannedById(tx, userId, input.plannedId);
			if (p.status !== 'planned')
				throw new OpsError('CONFLICT', 'That workout is already done or skipped.');
			await tx
				.update(plannedWorkout)
				.set({
					status: 'skipped',
					version: sql`${plannedWorkout.version} + 1`,
					updatedAt: new Date()
				})
				.where(and(eq(plannedWorkout.userId, userId), eq(plannedWorkout.id, p.id)));
			await afterScheduleChange(tx, userId);
			return { skipped: p.id, day: p.day };
		})
	);
}

/** This week on the Train screen: today's session, the seven days, the minutes and strength days, the programs, and whatever now needs a move. */
export async function readTrain(tx: Tx, userId: string, today: string) {
	const monday = mondayOf(today);
	const sunday = addDays(monday, 6);
	const planned = await tx
		.select()
		.from(plannedWorkout)
		.where(
			and(
				eq(plannedWorkout.userId, userId),
				gte(plannedWorkout.day, monday),
				lte(plannedWorkout.day, addDays(sunday, 7))
			)
		)
		.orderBy(asc(plannedWorkout.startsAt));
	const sessions = await tx
		.select()
		.from(workoutSession)
		.where(
			and(
				eq(workoutSession.userId, userId),
				gte(workoutSession.day, monday),
				lte(workoutSession.day, sunday),
				isNotNull(workoutSession.finishedAt)
			)
		);
	const [running] = await tx
		.select({ id: workoutSession.id })
		.from(workoutSession)
		.where(
			and(
				eq(workoutSession.userId, userId),
				eq(workoutSession.day, today),
				isNotNull(workoutSession.startedAt),
				isNull(workoutSession.finishedAt)
			)
		);
	const view = (p: typeof plannedWorkout.$inferSelect) => ({
		id: p.id,
		day: p.day,
		time: new Intl.DateTimeFormat('en-GB', {
			hour: '2-digit',
			minute: '2-digit',
			timeZone: 'Asia/Manila'
		}).format(p.startsAt),
		startsAt: p.startsAt.toISOString(),
		minutes: p.minutes,
		kind: p.kind,
		sessionKey: p.sessionKey,
		status: p.status,
		title: workoutTitle(p.sessionKey, p.kind)
	});
	const open = planned.filter((p) => p.status === 'planned' && p.day >= today);
	const availability = open.length
		? await readAvailability(tx, userId, today, addDays(sunday, 7))
		: null;
	const slots = availability
		? freeSlots(today, addDays(sunday, 7), availability, SLOT_MIN_MINUTES)
		: [];
	const needsMove = availability
		? open
				.filter(
					(p) =>
						p.startsAt.getTime() > Date.now() && !stillFits(slots, p.day, p.startsAt, p.minutes)
				)
				.map((p) => ({
					...view(p),
					suggestion: moveSuggestion(
						slots,
						p.day,
						p.minutes,
						workDaysOf([p.day], availability).has(p.day)
					)
				}))
		: [];
	const days = weekDays(monday).map((d) => {
		const doneThere = sessions.some((s) => s.day === d);
		const there = planned.filter((p) => p.day === d);
		return {
			day: d,
			state: doneThere
				? 'done'
				: d === today
					? 'today'
					: there.some((p) => p.status === 'planned')
						? 'planned'
						: 'rest'
		};
	});
	const programs = await activePrograms(tx, userId);
	return {
		today,
		days,
		todayPlanned: open.filter((p) => p.day === today).map(view)[0] ?? null,
		next: open.map(view)[0] ?? null,
		minutes: sessions.reduce((a, s) => a + (s.minutes ?? 0), 0),
		minutesGoal: MINUTES_GOAL,
		strengthDays: new Set(sessions.filter((s) => s.kind === 'strength').map((s) => s.day)).size,
		strengthGoal: STRENGTH_GOAL_DAYS,
		needsMove,
		programs: programs.map(programView),
		runningId: running?.id ?? null,
		recent: sessions
			.sort((a, b) => (a.day < b.day ? 1 : -1))
			.slice(0, 7)
			.map((s) => ({
				id: s.id,
				day: s.day,
				title: s.title,
				kind: s.kind,
				minutes: s.minutes,
				byAgent: s.byAgent
			}))
	};
}

export async function getTrain(ctx: Ctx) {
	return run(ctx, (tx, userId) => readTrain(tx, userId, toManilaDate(new Date())));
}

/**
 * Moves the programs on for the week that just ended. Called once a week by the job, in its transaction, so a retry cannot move a program twice. A program started during that
 * week is not moved or marked down: it has not had a whole week yet.
 */
export async function advancePrograms(tx: Tx, userId: string, today: string) {
	const thisMonday = mondayOf(today);
	const lastMonday = addDays(thisMonday, -7);
	const programs = await activePrograms(tx, userId);
	if (!programs.length) return;
	const finished = await tx
		.select({ programId: workoutSession.programId })
		.from(workoutSession)
		.where(
			and(
				eq(workoutSession.userId, userId),
				isNotNull(workoutSession.finishedAt),
				inArray(
					workoutSession.programId,
					programs.map((p) => p.id)
				),
				gte(workoutSession.day, lastMonday),
				lte(workoutSession.day, addDays(lastMonday, 6))
			)
		);
	for (const p of programs) {
		if (p.startedOn > lastMonday) continue;
		const count = finished.filter((f) => f.programId === p.id).length;
		const next =
			p.templateKey === 'walk_to_run'
				? nextRunWeek(p.week, count)
				: nextStrengthWeek(p.week, count);
		if (next.week === p.week) continue;
		await tx
			.update(program)
			.set({ week: next.week, version: sql`${program.version} + 1`, updatedAt: new Date() })
			.where(and(eq(program.userId, userId), eq(program.id, p.id)));
	}
}

/** The time of a planned workout as text, for the reminder engine and the calendar. */
export const clockOf = (minute: number) => timeOf(minute);
