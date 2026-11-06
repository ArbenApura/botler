// HOW THE ASSISTANT IS TOLD TO WRITE TIMES AND DATES (BTL-20261106-1502)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildMessages, clockLine } from '../../src/lib/server/agent/prompt';

// -- TESTS -- //

describe('clockLine', () => {
	it('names the 24 hour clock and day first by default', () => {
		const line = clockLine('24');
		expect(line).toContain('24 hour clock');
		expect(line).toContain('6 Nov 2026');
	});
	it('names the 12 hour clock and the chosen date order', () => {
		expect(clockLine('12', 'mdy')).toContain('12 hour clock with AM or PM');
		expect(clockLine('12', 'mdy')).toContain('Nov 6, 2026');
		expect(clockLine('12', 'ymd')).toContain('2026 Nov 6');
	});
	it('is in the turn context, after the clock of now and never in the fixed prefix', () => {
		const messages = buildMessages({
			now: new Date('2026-11-06T14:13:00Z'),
			history: [],
			userText: 'hi',
			clock: '24',
			dateStyle: 'mdy'
		});
		const user = messages[messages.length - 1];
		const text = typeof user?.content === 'string' ? user.content : '';
		expect(text).toContain('24 hour clock');
		expect(text).toContain('Nov 6, 2026');
		expect(messages[0]?.content).not.toContain('24 hour clock');
	});
});
