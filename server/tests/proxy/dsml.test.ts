// THE MODEL'S TOOL CALL WRITTEN AS TEXT (DSML): READ INTO REAL CALLS, NEVER SHOWN, NEVER HALF RUN

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createDsmlGuard, splitDsml } from '../../src/lib/server/proxy/dsml';

// -- CONSTANTS -- //

const BAR = '｜';
const tag = (name: string, attrs = '') => `<${BAR}DSML${BAR}${name}${attrs}>`;
const end = (name: string) => `</${BAR}DSML${BAR}${name}>`;
const param = (name: string, value: string, isString = true) =>
	`${tag('parameter', ` name="${name}" string="${isString}"`)}${value}${end('parameter')}`;
const invoke = (name: string, params: string) =>
	`${tag('invoke', ` name="${name}"`)}${params}${end('invoke')}`;

// The block the phone showed: two skips of a bill date
const SCREEN =
	tag('function_calls') +
	invoke(
		'bill_occurrence_update',
		param('billId', '47eaef59-e891-4004-8833-e061317c064f') +
			param('dueDate', '2026-09-02') +
			param('skipped', 'true', false)
	) +
	invoke(
		'bill_occurrence_update',
		param('billId', '72835839-3588-4112-a885-5964d68d1f4a') +
			param('dueDate', '2026-09-16') +
			param('skipped', 'true', false)
	) +
	end('function_calls');

// -- FUNCTIONS -- //

/** Feeds the guard in small pieces, like a stream, and returns everything it let through. */
function shown(text: string, size: number): string {
	const guard = createDsmlGuard();
	let out = '';
	for (let i = 0; i < text.length; i += size) out += guard.push(text.slice(i, i + size));
	return out + guard.flush();
}

describe('splitDsml', () => {
	it('reads the block from the phone into two calls with typed values', () => {
		const { text, calls } = splitDsml(SCREEN);
		expect(text).toBe('');
		expect(calls.map((c) => c.function.name)).toEqual([
			'bill_occurrence_update',
			'bill_occurrence_update'
		]);
		expect(JSON.parse(calls[0]!.function.arguments)).toEqual({
			billId: '47eaef59-e891-4004-8833-e061317c064f',
			dueDate: '2026-09-02',
			skipped: true
		});
		expect(JSON.parse(calls[1]!.function.arguments).dueDate).toBe('2026-09-16');
		expect(new Set(calls.map((c) => c.id)).size).toBe(2);
		expect(calls.every((c) => c.type === 'function')).toBe(true);
	});

	it('keeps the words before and after the block and drops only the markup', () => {
		const { text, calls } = splitDsml(`Let me skip them.\n${SCREEN}\nDone soon.`);
		expect(text).toBe('Let me skip them.\n\nDone soon.');
		expect(calls).toHaveLength(2);
	});

	it('reads plain bars and spaced bars the same way', () => {
		const plain =
			'<||DSML||function_calls><||DSML||invoke name="goals_list"></||DSML||invoke></||DSML||function_calls>';
		const spaced =
			'< | | DSML | | function_calls>< | | DSML | | invoke name="goals_list">< / | | DSML | | invoke>< / | | DSML | | function_calls>';
		expect(splitDsml(plain).calls.map((c) => c.function.name)).toEqual(['goals_list']);
		expect(splitDsml(plain).calls[0]!.function.arguments).toBe('{}');
		expect(splitDsml(spaced).calls.map((c) => c.function.name)).toEqual(['goals_list']);
	});

	it('reads a list or a number from a non-string parameter and keeps text as text', () => {
		const text =
			tag('function_calls') +
			invoke(
				'x',
				param('n', ' 42 ', false) + param('ids', '["a","b"]', false) + param('note', ' hi ')
			) +
			end('function_calls');
		expect(JSON.parse(splitDsml(text).calls[0]!.function.arguments)).toEqual({
			n: 42,
			ids: ['a', 'b'],
			note: ' hi '
		});
	});

	it('never runs a cut-off call and never shows its markup', () => {
		const whole = invoke('bill_occurrence_update', param('billId', 'a'));
		const cut =
			tag('function_calls') +
			whole +
			tag('invoke', ' name="second"') +
			param('billId', 'b').slice(0, 40);
		const { text, calls } = splitDsml(`Ok. ${cut}`);
		expect(calls.map((c) => c.function.name)).toEqual(['bill_occurrence_update']);
		expect(text).toBe('Ok. ');
		expect(text).not.toMatch(/DSML/);
	});

	it('leaves text without markup untouched, even with angle brackets', () => {
		const plain = 'Use <b>bold</b> if 3 < 5 and a | b.';
		expect(splitDsml(plain)).toEqual({ text: plain, calls: [] });
	});
});

describe('createDsmlGuard', () => {
	it('lets plain words through at once', () => {
		const guard = createDsmlGuard();
		expect(guard.push('Hello there')).toBe('Hello there');
		expect(guard.flush()).toBe('');
	});

	it('never lets any piece of the markup through, however the stream is cut', () => {
		const text = `I will do it. ${SCREEN}`;
		for (const size of [1, 2, 3, 5, 7, 16, 1000]) {
			const out = shown(text, size);
			expect(out, `piece size ${size}`).toBe('I will do it. ');
			expect(out).not.toMatch(/DSML|invoke|billId/);
		}
	});

	it('lets a "<" that is not markup go once that is clear, with nothing lost', () => {
		for (const size of [1, 2, 4, 100]) {
			expect(shown('a <b>bold</b> and 3 < 5', size)).toBe('a <b>bold</b> and 3 < 5');
		}
		const guard = createDsmlGuard();
		expect(guard.push('ends with <')).toBe('ends with ');
		expect(guard.flush()).toBe('<');
	});

	it('keeps the words after a block for the end of the answer', () => {
		expect(shown(`${SCREEN} All set.`, 4)).toBe(' All set.');
	});
});

describe('odd answers stay fast', () => {
	it('a "<" followed by a huge run of spaces or bars is read in a blink', () => {
		const odd = [
			`<${' '.repeat(200_000)}x`,
			`<${'｜'.repeat(100_000)}x`,
			`<${'| '.repeat(50_000)}DSM`,
			`${'<｜DSML｜'.repeat(20_000)}`
		];
		for (const text of odd) {
			const started = performance.now();
			splitDsml(text);
			shown(text, 5_000);
			expect(performance.now() - started).toBeLessThan(1500);
		}
	});
});
