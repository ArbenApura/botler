// THE WORDS OF A REFUSED INPUT: THEY MUST SAY WHAT TO CHANGE, BECAUSE THE ASSISTANT READS THEM AND TRIES AGAIN.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { schedulePreviewInput } from '../../src/lib/server/db/zod';
import { parse } from '../../src/lib/server/ops/shared';

describe('refused input', () => {
	it('tells the assistant where the anchor of a every other week rule goes', () => {
		expect(() =>
			parse(schedulePreviewInput, { schedule: { kind: 'weekly', days: [3], everyWeeks: 2 } })
		).toThrow(/Add "anchor" inside the schedule/);
	});

	it('names the fields that exist when a field is beside the schedule', () => {
		const strict = schedulePreviewInput.strict();
		expect(() =>
			parse(strict, {
				schedule: { kind: 'weekly', days: [3], everyWeeks: 2, anchor: '2026-10-28' },
				anchor: '2026-10-28'
			})
		).toThrow(/Unknown field "anchor"\. The fields here are: schedule, weekend, from, count/);
	});

	it('accepts the every other Wednesday rule with its anchor inside', () => {
		const ok = parse(schedulePreviewInput, {
			schedule: { kind: 'weekly', days: [3], everyWeeks: 2, anchor: '2026-10-28' }
		});
		expect(ok.schedule.kind).toBe('weekly');
	});
});
