// INSTANTS AS THE MODEL READS THEM: IN THE PERSON'S ZONE, WITH THE OFFSET
// A verb answers every instant in UTC (2026-11-06T14:13:39Z) and the app depends on that. The model must never convert in its head (near
// midnight a day slips), so the copy of a result it is given has each instant written as the person's wall clock with its offset
// (2026-11-06T22:13:39+08:00). That text is still a full ISO instant, so the model can pass it back to reminder_create or event_create unchanged.
// Only by field NAME: a value that merely looks like an instant (a title, a note) is never touched, and the stored transcript and the
// app's own events never pass through here.

// -- MODULES -- //
import { isZone, zoneOffsetMinutes } from '../../finance/dates';

// -- CONSTANTS -- //

const MINUTE_MS = 60_000;

/** An instant as verbs write it: UTC with a Z, seconds always there, milliseconds optional. */
const UTC_INSTANT = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(\.\d+)?Z$/;

/** The field names that hold an instant: every camelCase name that ends in At (createdAt, occurredAt, startsAt, dueAt), and plain at. */
const isInstantKey = (key: string): boolean => key === 'at' || /[a-z]At$/.test(key);

// -- FUNCTIONS -- //

/** One UTC instant text as the zone's wall clock with its offset; any other text comes back as it was. */
export function instantInZone(text: string, zone: string): string {
	const m = UTC_INSTANT.exec(text);
	if (!m || !isZone(zone)) return text;
	const ms = Date.parse(text);
	if (Number.isNaN(ms)) return text;
	const offset = zoneOffsetMinutes(ms, zone);
	const wall = new Date(ms + offset * MINUTE_MS).toISOString().slice(0, 19);
	const abs = Math.abs(offset);
	const sign = offset < 0 ? '-' : '+';
	const hh = String(Math.floor(abs / 60)).padStart(2, '0');
	const mm = String(abs % 60).padStart(2, '0');
	return `${wall}${m[3] ?? ''}${sign}${hh}:${mm}`;
}

/** A result with every instant field written in the zone. Objects and arrays are copied; nothing is changed in place. */
export function localizeInstants(value: unknown, zone: string): unknown {
	if (Array.isArray(value)) return value.map((v) => localizeInstants(v, zone));
	if (!value || typeof value !== 'object') return value;
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(value as Record<string, unknown>))
		out[k] =
			typeof v === 'string' && isInstantKey(k) ? instantInZone(v, zone) : localizeInstants(v, zone);
	return out;
}
