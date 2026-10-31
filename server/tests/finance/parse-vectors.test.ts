// SHARED PARSE VECTORS: THE SAME JSON FILE IS READ BY THE DART SIDE, SO BOTH PARSERS AGREE ON WHAT A TYPED AMOUNT MEANS

// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { parseMoney } from '../../src/lib/finance/currency';
import { parseExpenseText, parseRuleText } from '../../src/lib/finance/text';

// -- TYPES -- //

type Vector = { code: string; text: string; minor: number | null };

// -- CONSTANTS -- //

const VECTORS = JSON.parse(readFileSync(join(__dirname, 'parse-vectors.json'), 'utf8')) as Vector[];

// -- TESTS -- //

describe('shared parse vectors', () => {
	it('has vectors', () => expect(VECTORS.length).toBeGreaterThan(30));
	for (const v of VECTORS)
		it(`${v.code} ${JSON.stringify(v.text)} -> ${v.minor}`, () => {
			expect(parseMoney(v.text, v.code)).toBe(v.minor);
		});
});

describe('amounts inside a sentence follow the same rule', () => {
	it('reads a comma decimal and refuses extra decimals instead of cutting them', () => {
		expect(parseExpenseText('lunch 12,50 gcash', ['gcash']).amount).toBe(1250);
		expect(parseExpenseText('lunch 1,250 gcash', ['gcash']).amount).toBe(125_000);
		expect(parseExpenseText('lunch 1,250.50', []).amount).toBe(125_050);
		expect(parseExpenseText('lunch 12.345', []).amount).toBeNull();
		expect(parseExpenseText('lunch 1,250', [], 'KWD').amount).toBeNull();
		expect(parseExpenseText('lunch 99999999999999999', []).amount).toBeNull();
	});
});

describe('a name that contains the word rest is not the rest rule', () => {
	const targets = [
		{ kind: 'goal' as const, id: 'g1', name: 'Rest and travel' },
		{ kind: 'account' as const, id: 'a1', name: 'Gcash' }
	];
	it('reads 500 to Rest and travel as a fixed amount', () => {
		const r = parseRuleText('500 to Rest and travel', targets);
		expect(r).toMatchObject({ ok: true, mode: 'fixed', amount: 50_000, target: { id: 'g1' } });
	});
	it('reads 20% to Rest and travel as a share', () => {
		expect(parseRuleText('20% to Rest and travel', targets)).toMatchObject({
			ok: true,
			mode: 'percent',
			basisPoints: 2000
		});
	});
	it('still reads the real keyword forms', () => {
		expect(parseRuleText('the rest to Gcash', targets)).toMatchObject({ ok: true, mode: 'rest' });
		expect(parseRuleText('the rest to Rest and travel', targets)).toMatchObject({
			ok: true,
			mode: 'rest',
			target: { id: 'g1' }
		});
		expect(parseRuleText('everything else to gcash', targets)).toMatchObject({ mode: 'rest' });
	});
	it('refuses an amount with extra decimals', () => {
		expect(parseRuleText('12.345 to gcash', targets)).toMatchObject({ ok: false });
	});
});
