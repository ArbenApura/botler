// A TOOL RESULT THAT IS CUT SAYS WHERE AND WHAT TO ASK FOR (BTL-20261106-1502)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { capJson } from '../../src/lib/server/agent/turn';

// -- TESTS -- //

describe('capJson', () => {
	it('leaves a result that fits exactly as it is', () => {
		expect(capJson({ a: 1 }, 1000)).toBe('{"a":1}');
	});
	it('cuts a long result with a marker that says where, never longer than the limit', () => {
		const big = {
			rows: Array.from({ length: 400 }, (_, i) => ({
				day: `2026-11-${i}`,
				label: 'a "quoted" word'
			}))
		};
		const text = capJson(big, 2000);
		expect(text.length).toBeLessThanOrEqual(2000);
		const out = JSON.parse(text) as {
			truncated: boolean;
			cutAfter: number;
			ofCharacters: number;
			note: string;
			preview: string;
		};
		expect(out.truncated).toBe(true);
		expect(out.ofCharacters).toBe(JSON.stringify(big).length);
		expect(out.cutAfter).toBe(out.preview.length);
		expect(out.note).toContain(`cut after ${out.cutAfter} of ${out.ofCharacters}`);
		expect(out.note).toMatch(/shorter range|coarser grouping/);
	});
});
