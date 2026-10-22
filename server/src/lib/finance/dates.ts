// MANILA CALENDAR DATES: A "DAY" IN BOTLER IS A YYYY-MM-DD STRING IN ASIA/MANILA (UTC+8, NO DAYLIGHT SAVING). NEVER A TIMESTAMP.
// All arithmetic runs in UTC on the date parts, so it cannot drift with the machine's own time zone.

// -- TYPES -- //

/** A calendar date in Asia/Manila, written YYYY-MM-DD. */
export type ManilaDate = string;

// -- CONSTANTS -- //

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const DAY_MS = 86_400_000;
const MANILA_OFFSET_MS = 8 * 3_600_000;

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

/** The Manila calendar date of an instant: 2026-10-21T17:00:00Z is already the 22nd in Manila. */
export const toManilaDate = (instant: Date): ManilaDate =>
	fromUtcMs(instant.getTime() + MANILA_OFFSET_MS);

/** The instant a Manila day starts. */
export const manilaStart = (d: ManilaDate): Date => new Date(utcMs(d) - MANILA_OFFSET_MS);

/** Noon in Manila, the instant given to a record that only knows its day. */
export const manilaNoon = (d: ManilaDate): Date =>
	new Date(utcMs(d) - MANILA_OFFSET_MS + 12 * 3_600_000);
