// THE ZONE-AWARE DATE HELPERS: A DAY STARTS WHERE THE PERSON'S CLOCK SAYS, DAYLIGHT SAVING AND ODD OFFSETS INCLUDED

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	addDays,
	atLocalTime,
	dayNoon,
	dayStart,
	isZone,
	toLocalDate,
	zoneOffsetMinutes
} from '../../src/lib/finance/dates';

// -- TESTS -- //

describe('zone-aware dates', () => {
	it('keeps Manila as the default zone', () => {
		expect(toLocalDate(new Date('2026-10-21T17:00:00Z'))).toBe('2026-10-22');
		expect(dayStart('2026-10-22').toISOString()).toBe('2026-10-21T16:00:00.000Z');
		expect(dayNoon('2026-10-22').toISOString()).toBe('2026-10-22T04:00:00.000Z');
		expect(atLocalTime('2026-10-22', '08:30').toISOString()).toBe('2026-10-22T00:30:00.000Z');
	});

	it('moves the day with the zone', () => {
		const t = new Date('2026-11-05T20:00:00Z');
		expect(toLocalDate(t, 'Asia/Manila')).toBe('2026-11-06');
		expect(toLocalDate(t, 'Asia/Tokyo')).toBe('2026-11-06');
		expect(toLocalDate(t, 'America/New_York')).toBe('2026-11-05');
		expect(toLocalDate(t, 'Pacific/Kiritimati')).toBe('2026-11-06');
		expect(zoneOffsetMinutes(t.getTime(), 'Pacific/Kiritimati')).toBe(840);
	});

	it('gets a spring forward day right: 23 hours long, the missing time lands after the gap', () => {
		const z = 'America/New_York';
		const len = dayStart('2026-03-09', z).getTime() - dayStart('2026-03-08', z).getTime();
		expect(len).toBe(23 * 3_600_000);
		expect(atLocalTime('2026-03-08', '02:30', z).toISOString()).toBe('2026-03-08T07:30:00.000Z');
	});

	it('gets a fall back day right: 25 hours long, the repeated time is the first one', () => {
		const z = 'America/New_York';
		const len = dayStart('2026-11-02', z).getTime() - dayStart('2026-11-01', z).getTime();
		expect(len).toBe(25 * 3_600_000);
		expect(atLocalTime('2026-11-01', '01:30', z).toISOString()).toBe('2026-11-01T05:30:00.000Z');
	});

	it('handles a half hour daylight saving shift', () => {
		const z = 'Australia/Lord_Howe';
		const a = zoneOffsetMinutes(Date.parse('2026-07-01T00:00:00Z'), z);
		const b = zoneOffsetMinutes(Date.parse('2026-12-01T00:00:00Z'), z);
		expect(a).toBe(630);
		expect(b).toBe(660);
		expect(toLocalDate(dayStart('2026-10-10', z), z)).toBe('2026-10-10');
	});

	it('round trips a day start for many zones', () => {
		for (const z of [
			'Asia/Manila',
			'Asia/Kolkata',
			'Asia/Kathmandu',
			'Europe/London',
			'America/Sao_Paulo'
		]) {
			for (const d of ['2026-01-01', '2026-03-29', '2026-10-25', '2026-12-31']) {
				expect(toLocalDate(dayStart(d, z), z)).toBe(d);
				expect(toLocalDate(new Date(dayStart(addDays(d, 1), z).getTime() - 1), z)).toBe(d);
			}
		}
	});

	it('falls back to Manila for a name that is not a zone', () => {
		expect(isZone('Not/AZone')).toBe(false);
		expect(toLocalDate(new Date('2026-10-21T17:00:00Z'), 'Not/AZone')).toBe('2026-10-22');
	});
});
