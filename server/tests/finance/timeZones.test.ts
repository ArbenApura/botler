// THE ZONE LIST: EVERY NAME IS A REAL ZONE HERE, THE SERVER TAKES ONLY THESE, AND THE APP'S COPY IS THE SAME LIST

// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { dartZoneLines } from '../../scripts/zones-dart';
import { isZone } from '../../src/lib/finance/dates';
import { TIME_ZONES, isListedZone } from '../../src/lib/finance/timeZones';
import { settingsSetInput } from '../../src/lib/server/db/zod';

// -- TESTS -- //

describe('the time zone list', () => {
	it('holds only real zones, sorted, with UTC first and no repeat', () => {
		expect(TIME_ZONES[0]).toBe('UTC');
		expect(TIME_ZONES.filter((z) => !isZone(z))).toEqual([]);
		const rest = TIME_ZONES.slice(1);
		expect(rest).toEqual([...rest].sort());
		expect(new Set(TIME_ZONES).size).toBe(TIME_ZONES.length);
	});

	it('is the list the settings accept, in exactly the listed spelling', () => {
		expect(settingsSetInput.safeParse({ timeZone: 'Asia/Tokyo' }).success).toBe(true);
		expect(settingsSetInput.safeParse({ timeZone: 'asia/tokyo' }).success).toBe(false);
		expect(settingsSetInput.safeParse({ timeZone: '+05:30' }).success).toBe(false);
		expect(settingsSetInput.safeParse({ timeZone: 'Not/AZone' }).success).toBe(false);
		expect(isListedZone('Asia/Manila')).toBe(true);
	});

	it("is the same list the app's picker shows (app/lib/core/zone_list.dart)", () => {
		const dart = readFileSync(
			join(__dirname, '..', '..', '..', 'app', 'lib', 'core', 'zone_list.dart'),
			'utf8'
		).replaceAll('\r\n', '\n');
		for (const line of dartZoneLines()) expect(dart).toContain(`${line}\n`);
		const count = dart.split('\n').filter((l) => /^ {2}'.+',$/.test(l)).length;
		expect(count).toBe(TIME_ZONES.length);
	});
});
