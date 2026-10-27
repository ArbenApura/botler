// THE CHAT ENVIRONMENT SETTINGS: DEFAULTS, GOOD VALUES AND A LOUD FAILURE ON A BAD ONE

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	DEFAULT_CHAT_MAX_TOKENS,
	DEFAULT_TURN_TOKEN_BUDGET,
	deepseekEffort,
	parseChatEffort,
	positiveInt
} from '../../src/lib/server/proxy/chatEnv';

// -- TESTS -- //

describe('chat environment settings', () => {
	it('defaults to a 64000 ceiling, effort high and a 300000 budget', () => {
		expect(positiveInt(undefined, DEFAULT_CHAT_MAX_TOKENS, 'CHAT_MAX_TOKENS')).toBe(64000);
		expect(positiveInt('  ', DEFAULT_TURN_TOKEN_BUDGET, 'TURN_TOKEN_BUDGET')).toBe(300000);
		expect(parseChatEffort(undefined)).toBe('high');
		expect(parseChatEffort('')).toBe('high');
	});

	it('reads good values, ignoring case and spaces', () => {
		expect(positiveInt('12000', 1, 'X')).toBe(12000);
		for (const e of ['low', 'medium', 'high', 'max'] as const) {
			expect(parseChatEffort(` ${e.toUpperCase()} `)).toBe(e);
		}
	});

	it('stops the server on a bad value instead of choosing for the person', () => {
		expect(() => parseChatEffort('xhigh')).toThrow(/CHAT_EFFORT/);
		expect(() => parseChatEffort('hihg')).toThrow(/low, medium, high or max/);
		for (const bad of ['0', '-5', '1.5', 'many', '1e3x']) {
			expect(() => positiveInt(bad, 1, 'TURN_TOKEN_BUDGET')).toThrow(/TURN_TOKEN_BUDGET/);
		}
	});

	it('maps the effort DeepSeek understands', () => {
		expect(deepseekEffort('low')).toBe('high');
		expect(deepseekEffort('medium')).toBe('high');
		expect(deepseekEffort('high')).toBe('high');
		expect(deepseekEffort('max')).toBe('max');
	});
});
