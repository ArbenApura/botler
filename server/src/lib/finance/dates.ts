// CALENDAR DATES: A "DAY" IN BOTLER IS A YYYY-MM-DD STRING, NEVER A TIMESTAMP. WHICH DAY AN INSTANT FALLS ON DEPENDS ON THE PERSON'S ZONE (ASIA/MANILA UNTIL THEY CHOOSE ANOTHER).
// Arithmetic on date text runs in UTC on the date parts, so it cannot drift with the machine's own time zone. Only turning an instant into a day, or a day into an instant, uses the zone.

// -- TYPES -- //

/** A calendar date in the person's zone (Asia/Manila by default), written YYYY-MM-DD. The name is kept; it is only text. */
export type ManilaDate = string;

// -- CONSTANTS -- //

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const DAY_MS = 86_400_000;
const MINUTE_MS = 60_000;
/** The zone of a person who has not chosen one. */
export const DEFAULT_ZONE = 'Asia/Manila';

// -- FUNCTIONS -- //

const pad = (n: number, width: number) => String(n).padStart(width, '0');

export function daysInMonth(year: number, month: number): number {
	return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** The parts of a date, or null when the text is not a real calendar date (2026-02-30 is not). */
export function parseDate(d: string): { year: number; month: number; day: number } | null {
	const m = DATE_RE.exec(d);
	if (!m) return null;
	const year = Number(m[1]);
	const month = Number(m[2]);
	const day = Number(m[3]);
	if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
	return { year, month, day };
}

export const isDate = (d: string): boolean => parseDate(d) !== null;

export function formatDate(year: number, month: number, day: number): ManilaDate {
	return `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}`;
}

function utcMs(d: ManilaDate): number {
	const p = parseDate(d);
	if (!p) throw new RangeError(`Not a calendar date: ${d}`);
	return Date.UTC(p.year, p.month - 1, p.day);
}

function fromUtcMs(ms: number): ManilaDate {
	const x = new Date(ms);
	return formatDate(x.getUTCFullYear(), x.getUTCMonth() + 1, x.getUTCDate());
}

export const addDays = (d: ManilaDate, n: number): ManilaDate => fromUtcMs(utcMs(d) + n * DAY_MS);

/** Whole days from b to a (positive when a is later). */
export const diffDays = (a: ManilaDate, b: ManilaDate): number =>
	Math.round((utcMs(a) - utcMs(b)) / DAY_MS);

/** 0 is Sunday, 6 is Saturday. */
export const weekday = (d: ManilaDate): number => new Date(utcMs(d)).getUTCDay();

export const isWeekend = (d: ManilaDate): boolean => {
	const w = weekday(d);
	return w === 0 || w === 6;
};

// -- ZONES -- //

let zoneProvider: () => string = () => DEFAULT_ZONE;

/** The server sets this once: it answers the zone of the person whose verb or job is running. Unset, every day is a Manila day. */
export function setZoneProvider(fn: () => string): void {
	zoneProvider = fn;
}

const formatters = new Map<string, Intl.DateTimeFormat | null>();

function formatterFor(zone: string): Intl.DateTimeFormat | null {
	if (formatters.has(zone)) return formatters.get(zone) ?? null;
	let f: Intl.DateTimeFormat | null;
	try {
		f = new Intl.DateTimeFormat('en-US', {
			timeZone: zone,
			hourCycle: 'h23',
			year: 'numeric',
			month: 'numeric',
			day: 'numeric',
			hour: 'numeric',
			minute: 'numeric',
			second: 'numeric'
		});
	} catch {
		f = null;
	}
	formatters.set(zone, f);
	return f;
}

/** True for a real IANA zone name this server knows. */
export const isZone = (zone: string): boolean => formatterFor(zone) !== null;

/** The zone to use now: the person's, or Manila when none is set or the name is not a real zone (never throws). */
export function currentZone(): string {
	const z = zoneProvider();
	return isZone(z) ? z : DEFAULT_ZONE;
}

const safeZone = (zone: string | undefined): string =>
	zone !== undefined && isZone(zone) ? zone : currentZone();

/** Minutes the zone's clock is ahead of UTC at an instant (Manila is 480, New York is -300 or -240). */
export function zoneOffsetMinutes(instantMs: number, zone?: string): number {
	// Manila has had no clock change since 1978, so the common case needs no formatter
	if (zone === undefined ? currentZone() === DEFAULT_ZONE : zone === DEFAULT_ZONE) return 480;
	const f = formatterFor(safeZone(zone));
	if (!f) return 480;
	const parts: Record<string, number> = {};
	for (const p of f.formatToParts(new Date(instantMs))) {
		if (p.type !== 'literal') parts[p.type] = Number(p.value);
	}
	const wall = Date.UTC(
		parts.year ?? 1970,
		(parts.month ?? 1) - 1,
		parts.day ?? 1,
		parts.hour ?? 0,
		parts.minute ?? 0,
		parts.second ?? 0
	);
	return Math.round((wall - Math.floor(instantMs / 1000) * 1000) / MINUTE_MS);
}

/** The instant at which the zone's clock reads minutesIntoDay on a date. A time that does not exist (spring forward) lands after the gap; one that happens twice (fall back) is the first one. */
function wallToInstant(d: ManilaDate, minutesIntoDay: number, zone?: string): Date {
	const z = safeZone(zone);
	const guess = utcMs(d) + minutesIntoDay * MINUTE_MS;
	const before = zoneOffsetMinutes(guess - DAY_MS, z);
	const after = zoneOffsetMinutes(guess + DAY_MS, z);
	const valid = [...new Set([before, after])]
		.map((o) => guess - o * MINUTE_MS)
		.filter((t) => zoneOffsetMinutes(t, z) === (guess - t) / MINUTE_MS);
	if (valid.length > 0) return new Date(Math.min(...valid));
	return new Date(guess - before * MINUTE_MS);
}

/** The calendar date of an instant in the zone: 2026-10-21T17:00:00Z is already the 22nd in Manila. */
export function toLocalDate(instant: Date, zone?: string): ManilaDate {
	return fromUtcMs(instant.getTime() + zoneOffsetMinutes(instant.getTime(), zone) * MINUTE_MS);
}

/** The clock reading of an instant in the zone as HH:mm (24 hour), the form the app and the verbs exchange. */
export function localHm(instant: Date, zone?: string): string {
	const wall = new Date(instant.getTime() + zoneOffsetMinutes(instant.getTime(), zone) * MINUTE_MS);
	return `${pad(wall.getUTCHours(), 2)}:${pad(wall.getUTCMinutes(), 2)}`;
}

/** The instant the zone's clock reads a number of minutes after midnight on a date. On a 23 or 25 hour day this is the clock's minute, not elapsed time. */
export const atLocalMinute = (d: ManilaDate, minutes: number, zone?: string): Date =>
	wallToInstant(d, minutes, zone);

/** The clock's minutes after midnight of a date at an instant in the zone: negative before it, 1440 or more after it. */
export function localMinuteOf(instant: Date, d: ManilaDate, zone?: string): number {
	const wallMs = instant.getTime() + zoneOffsetMinutes(instant.getTime(), zone) * MINUTE_MS;
	return Math.floor((wallMs - utcMs(d)) / MINUTE_MS);
}

/** The instant a day starts in the zone. */
export const dayStart = (d: ManilaDate, zone?: string): Date => wallToInstant(d, 0, zone);

/** Noon in the zone, the instant given to a record that only knows its day. */
export const dayNoon = (d: ManilaDate, zone?: string): Date => wallToInstant(d, 720, zone);

/** The instant the zone's clock reads HH:mm on a date. */
export function atLocalTime(d: ManilaDate, hhmm: string, zone?: string): Date {
	const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(hhmm);
	if (!m) throw new RangeError(`Not a time: ${hhmm}`);
	return wallToInstant(d, Number(m[1]) * 60 + Number(m[2]), zone);
}
