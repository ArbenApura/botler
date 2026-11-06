// THE CLOCK AND DATE TEXT A PERSON READS: 12 OR 24 HOUR, IN THEIR ZONE, IN THEIR DATE ORDER (BTL-20261106-1502)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { clockText, dateText, resolveClock } from '../../src/lib/finance/clockText';

// -- TESTS -- //

describe('resolveClock', () => {
	it('keeps a clock the person chose', () => {
		expect(resolveClock('24', '12')).toBe('24');
		expect(resolveClock('12', '24')).toBe('12');
	});
	it('follows the phone on auto, and reads 12 hour until a phone has reported', () => {
		expect(resolveClock('auto', '24')).toBe('24');
		expect(resolveClock('auto', '12')).toBe('12');
		expect(resolveClock('auto', null)).toBe('12');
	});
});

describe('clockText', () => {
	const at = new Date('2026-11-06T14:13:00Z');
	it('writes the same instant in the zone, 12 or 24 hour', () => {
		expect(clockText(at, { zone: 'Asia/Manila', timeFormat: '12' })).toBe('10:13 PM');
		expect(clockText(at, { zone: 'Asia/Manila', timeFormat: '24' })).toBe('22:13');
		expect(clockText(at, { zone: 'America/New_York', timeFormat: '24' })).toBe('09:13');
	});
});

describe('dateText', () => {
	it('writes a day in the person order, day first on auto', () => {
		expect(dateText('2026-11-06')).toBe('6 Nov 2026');
		expect(dateText('2026-11-06', 'dmy')).toBe('6 Nov 2026');
		expect(dateText('2026-11-06', 'mdy')).toBe('Nov 6, 2026');
		expect(dateText('2026-11-06', 'ymd')).toBe('2026 Nov 6');
	});
	it('leaves a text that is not a day as it was', () => {
		expect(dateText('soon')).toBe('soon');
		expect(dateText('2026-13-40')).toBe('2026-13-40');
	});
});
