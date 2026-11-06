// INSTANTS AS THE MODEL READS THEM: THE PERSON'S ZONE WITH THE OFFSET, BY FIELD NAME ONLY (BTL-20261106-1502)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { instantInZone, localizeInstants } from '../../src/lib/server/agent/instants';

// -- TESTS -- //

describe('instantInZone', () => {
	it('writes a UTC instant as the zone wall clock with its offset', () => {
		expect(instantInZone('2026-11-06T14:13:39Z', 'Asia/Manila')).toBe('2026-11-06T22:13:39+08:00');
		expect(instantInZone('2026-11-06T14:13:39.291Z', 'Asia/Manila')).toBe(
			'2026-11-06T22:13:39.291+08:00'
		);
		expect(instantInZone('2026-11-06T14:13:39Z', 'America/New_York')).toBe(
			'2026-11-06T09:13:39-05:00'
		);
	});
	it('moves the day near midnight, which the model must never work out itself', () => {
		expect(instantInZone('2026-11-06T17:30:00Z', 'Asia/Manila')).toBe('2026-11-07T01:30:00+08:00');
	});
	it('gives back a text that is not a UTC instant, and an unknown zone', () => {
		expect(instantInZone('2026-11-06', 'Asia/Manila')).toBe('2026-11-06');
		expect(instantInZone('2026-11-06T22:13:39+08:00', 'Asia/Manila')).toBe(
			'2026-11-06T22:13:39+08:00'
		);
		expect(instantInZone('2026-11-06T14:13:39Z', 'Not/AZone')).toBe('2026-11-06T14:13:39Z');
	});
	it('round trips: the text parses to the very same moment', () => {
		const text = instantInZone('2026-11-06T14:13:39Z', 'Asia/Manila');
		expect(Date.parse(text)).toBe(Date.parse('2026-11-06T14:13:39Z'));
	});
});

describe('localizeInstants', () => {
	const result = {
		createdAt: '2026-11-06T13:14:39.291Z',
		title: '2026-11-06T13:14:39Z',
		note: 'paid at 2026-11-06T13:14:39Z',
		events: [{ startsAt: '2026-11-07T00:00:00Z', label: 'x' }],
		at: '2026-11-06T14:13:39Z',
		amount: 200000
	};
	it('changes only the fields named like an instant', () => {
		const out = localizeInstants(result, 'Asia/Manila') as typeof result;
		expect(out.createdAt).toBe('2026-11-06T21:14:39.291+08:00');
		expect(out.events[0]?.startsAt).toBe('2026-11-07T08:00:00+08:00');
		expect(out.at).toBe('2026-11-06T22:13:39+08:00');
		// A title or a note that looks like an instant is the person's text, not a time
		expect(out.title).toBe('2026-11-06T13:14:39Z');
		expect(out.note).toBe('paid at 2026-11-06T13:14:39Z');
		expect(out.amount).toBe(200000);
	});
	it('copies: the original result is left as it was', () => {
		const before = JSON.stringify(result);
		localizeInstants(result, 'Asia/Manila');
		expect(JSON.stringify(result)).toBe(before);
	});
});
