// THE AGENT KNOWS THE CLOCK TIME IN MANILA, SO "IN 3 MINUTES" BECOMES A FUTURE INSTANT.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildMessages, nowLine } from '../../src/lib/server/agent/prompt';

// -- TESTS -- //

describe('nowLine', () => {
	it('writes the Manila clock time with its offset', () => {
		// 00:26:05 UTC is 08:26:05 in Manila
		expect(nowLine(new Date('2026-10-23T00:26:05Z'))).toContain('Now is 2026-10-23T08:26:05+08:00');
	});

	it('crosses midnight in Manila, not in UTC', () => {
		expect(nowLine(new Date('2026-10-22T17:30:00Z'))).toContain('Now is 2026-10-23T01:30:00+08:00');
	});

	it('is part of the turn context', () => {
		const m = buildMessages({
			now: new Date('2026-10-23T00:26:05Z'),
			history: [],
			userText: 'remind me in 3 minutes'
		});
		expect(JSON.stringify(m)).toContain('Now is 2026-10-23T08:26:05+08:00');
	});
});
