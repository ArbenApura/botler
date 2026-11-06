// A CLOCK TIME AND A DATE AS TEXT FOR A PERSON: 12 OR 24 HOUR, IN THEIR ZONE, IN THEIR DATE ORDER
// The server has no phone to ask, so a clock left on auto is resolved from what a phone last reported (resolveClock); until one has, it reads
// as 12 hour. Date order auto is day, month, year, the same rule as the app (core/clock.dart).

// -- TYPES -- //

type TimeFormat = 'auto' | '12' | '24';
type DateStyle = 'auto' | 'dmy' | 'mdy' | 'ymd';

export type ClockPrefs = { zone: string; timeFormat: TimeFormat; dateStyle?: DateStyle };

// -- CONSTANTS -- //

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// -- FUNCTIONS -- //

/** The clock a person reads: their own choice, else what their phone last reported, else 12 hour. Never auto. */
export function resolveClock(setting: TimeFormat, reported: '12' | '24' | null): '12' | '24' {
	if (setting === '12' || setting === '24') return setting;
	return reported ?? '12';
}

/** 3:42 PM or 15:42 in the person's zone. */
export function clockText(instant: Date, prefs: ClockPrefs): string {
	return new Intl.DateTimeFormat('en-US', {
		hour: prefs.timeFormat === '24' ? '2-digit' : 'numeric',
		minute: '2-digit',
		hourCycle: prefs.timeFormat === '24' ? 'h23' : 'h12',
		timeZone: prefs.zone
	}).format(instant);
}

/** A calendar date (YYYY-MM-DD) in the person's order: 6 Nov 2026, Nov 6, 2026 or 2026 Nov 6. Anything else comes back as it was. */
export function dateText(day: string, style: DateStyle = 'auto'): string {
	const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
	const month = m ? MONTHS[Number(m[2]) - 1] : undefined;
	if (!m || !month) return day;
	const d = String(Number(m[3]));
	if (style === 'mdy') return `${month} ${d}, ${m[1]}`;
	if (style === 'ymd') return `${m[1]} ${month} ${d}`;
	return `${d} ${month} ${m[1]}`;
}
