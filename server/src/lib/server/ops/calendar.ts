// CALENDAR SYNC VERBS: TURN IT ON OR OFF, AND SAY HOW IT IS DOING. Only a person can turn it on or off (it moves their events to and from Google).
// The Google consent itself happens in the browser (see routes/api/v1/calendar/connect); `calendar_enable` is called after the person came back.

// -- TYPES -- //
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { eq, sql } from 'drizzle-orm';
import { z } from 'zod';
// -- MODULES -- //
import { calendarSync } from '../db/schema';
import { run, runWrite } from './context';
import { mapped, parse, requirePerson } from './shared';

// -- CONSTANTS -- //

const emptyInput = z.object({});

// -- FUNCTIONS -- //

export async function calendarStatus(ctx: Ctx) {
	return run(ctx, async (tx, userId) => {
		const [s] = await tx.select().from(calendarSync).where(eq(calendarSync.userId, userId));
		return {
			status: s?.status ?? 'off',
			errorCode: s?.errorCode ?? null,
			lastSyncAt: s?.lastSyncAt?.toISOString() ?? null
		};
	});
}

/** Starts syncing. The first pass lists everything again. Also clears an earlier error after the person reconnected. */
export async function enableCalendar(ctx: Ctx, raw: unknown = {}) {
	requirePerson(ctx.actor.kind, 'turn calendar sync on');
	parse(emptyInput, raw);
	return mapped(() =>
		runWrite(ctx, 'calendar.enable', {}, async (tx, userId) => {
			await tx
				.insert(calendarSync)
				.values({ userId, status: 'ok' })
				.onConflictDoUpdate({
					target: calendarSync.userId,
					set: { status: 'ok', errorCode: null, syncToken: null, updatedAt: sql`now()` }
				});
			return { status: 'ok' as const };
		})
	);
}

/** Stops syncing. Events already in Botler and in Google stay where they are. */
export async function disableCalendar(ctx: Ctx, raw: unknown = {}) {
	requirePerson(ctx.actor.kind, 'turn calendar sync off');
	parse(emptyInput, raw);
	return mapped(() =>
		runWrite(ctx, 'calendar.disable', {}, async (tx, userId) => {
			await tx
				.insert(calendarSync)
				.values({ userId, status: 'off' })
				.onConflictDoUpdate({
					target: calendarSync.userId,
					set: { status: 'off', syncToken: null, updatedAt: sql`now()` }
				});
			return { status: 'off' as const };
		})
	);
}
