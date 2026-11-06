// THE ZONE AND CLOCK OF THE PERSON WHOSE VERB OR JOB IS RUNNING
// A day is a date in the person's zone (Asia/Manila until they choose another). Every verb body runs inside withZone, so the date helpers in
// finance/dates.ts answer for that person without the zone being passed through every function. Outside a verb they answer for Manila.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { ClockPrefs } from '../../finance/clockText';
// -- DEP-MODULES -- //
import { AsyncLocalStorage } from 'node:async_hooks';
import { and, desc, eq, isNotNull } from 'drizzle-orm';
// -- MODULES -- //
import { clockText, dateText, resolveClock } from '../../finance/clockText';
import { DEFAULT_ZONE, isZone, setZoneProvider } from '../../finance/dates';
import { device, userSetting } from '../db/schema';

// -- CONSTANTS -- //

const DEFAULT_PREFS: ClockPrefs = { zone: DEFAULT_ZONE, timeFormat: '12', dateStyle: 'auto' };

const store = new AsyncLocalStorage<ClockPrefs>();

setZoneProvider(() => (store.getStore() ?? DEFAULT_PREFS).zone);

// -- FUNCTIONS -- //

/** The clock the person's newest reporting phone reads, or null when no phone has reported one. */
export async function reportedClock(tx: Tx, userId: string): Promise<'12' | '24' | null> {
	const [row] = await tx
		.select({ clock: device.clock })
		.from(device)
		.where(and(eq(device.userId, userId), isNotNull(device.clock)))
		.orderBy(desc(device.lastSeenAt))
		.limit(1);
	return row?.clock === '12' || row?.clock === '24' ? row.clock : null;
}

/**
 * The zone and clock a person chose. The clock is always 12 or 24, never auto: a clock left on auto follows the newest phone that reported
 * one, else 12 hour. Manila and day-first when they have no settings row or the stored zone is not a real one.
 */
export async function readClockPrefs(tx: Tx, userId: string): Promise<ClockPrefs> {
	const [row] = await tx
		.select({
			timeZone: userSetting.timeZone,
			timeFormat: userSetting.timeFormat,
			dateStyle: userSetting.dateStyle
		})
		.from(userSetting)
		.where(eq(userSetting.userId, userId));
	const setting = row?.timeFormat ?? 'auto';
	const timeFormat = resolveClock(
		setting,
		setting === 'auto' ? await reportedClock(tx, userId) : null
	);
	return {
		zone: row && isZone(row.timeZone) ? row.timeZone : DEFAULT_ZONE,
		timeFormat,
		dateStyle: row?.dateStyle ?? 'auto'
	};
}

/** Runs fn with the date helpers answering for these prefs. */
export const withClock = <T>(prefs: ClockPrefs, fn: () => Promise<T>): Promise<T> =>
	store.run(prefs, fn);

/** Reads the person's zone and clock inside their transaction, then runs fn in them. */
export async function inPersonZone<T>(tx: Tx, userId: string, fn: () => Promise<T>): Promise<T> {
	return withClock(await readClockPrefs(tx, userId), fn);
}

/** The prefs of the verb or job running now. */
export const currentClock = (): ClockPrefs => store.getStore() ?? DEFAULT_PREFS;

/** A calendar date (YYYY-MM-DD) as text in the running person's date order. */
export const dateNow = (day: string): string => dateText(day, currentClock().dateStyle);

/** A clock time as text, in the running person's zone and 12 or 24 hour choice. */
export const clockNow = (instant: Date): string => clockText(instant, currentClock());
