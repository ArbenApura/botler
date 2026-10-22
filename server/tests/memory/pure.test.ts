// THE PURE PARTS OF MEMORY: HASHING, REDACTION, MOOD LIMITS, FADING, THE TOKEN BUDGET AND SCORING

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import {
	MOOD_MAX_STEP,
	cosine,
	decayMood,
	estimateTokens,
	fadeStep,
	fitBudget,
	hashFact,
	nextMood,
	normalizeFact,
	redactSecrets,
	restoreStep,
	scoreFact,
	toneHint
} from '../../src/lib/server/memory/pure';

// -- TESTS -- //

describe('hashing', () => {
	it('gives the same hash to the same words written differently', () => {
		expect(hashFact('My sister lives in Cebu.')).toBe(hashFact('  my SISTER lives, in cebu '));
		expect(hashFact('My sister lives in Cebu')).not.toBe(hashFact('My sister lives in Manila'));
		expect(normalizeFact('Hello,   World!!')).toBe('hello world');
	});
});

describe('redaction before a fact is stored', () => {
	it('removes account, card and phone numbers and keeps the rest', () => {
		expect(redactSecrets('My RCBC account number is 1234567890123')).toBe(
			'My RCBC account number is (details removed)'
		);
		expect(redactSecrets('Call me on 0917 123 4567 after work')).toContain('(details removed)');
		expect(redactSecrets('Card 4111 1111 1111 1111 is for travel')).not.toMatch(/4111/);
		expect(redactSecrets('I like green tea')).toBe('I like green tea');
		expect(redactSecrets('   ')).toBeNull();
	});
});

describe('mood', () => {
	it('moves at most ten a turn and stays inside the limits', () => {
		expect(nextMood(0, 50)).toBe(MOOD_MAX_STEP);
		expect(nextMood(0, -50)).toBe(-MOOD_MAX_STEP);
		expect(nextMood(95, 10)).toBe(100);
		expect(nextMood(-95, -10)).toBe(-100);
		expect(nextMood(20, Number.NaN)).toBe(20);
		let m = 0;
		for (let i = 0; i < 30; i++) m = nextMood(m, 10);
		expect(m).toBe(100);
	});

	it('drifts back to zero and never past it', () => {
		expect(decayMood(100, 1)).toBe(90);
		expect(decayMood(-100, 2)).toBe(-81);
		expect(decayMood(5, 30)).toBe(0);
		expect(decayMood(-5, 30)).toBe(0);
		expect(decayMood(50, 0)).toBe(50);
	});

	it('only ever speaks about tone', () => {
		for (const m of [-100, -40, -15, 0, 15, 40, 100])
			expect(toneHint(m)).not.toMatch(/₱|peso|bill|split|approve|money/i);
		expect(toneHint(0)).toBe('');
		expect(toneHint(-60)).toMatch(/gentle/);
	});
});

describe('fading', () => {
	it('halves down to a floor and is undone by use', () => {
		expect(fadeStep(1)).toBe(0.5);
		expect(fadeStep(0.15)).toBe(0.1);
		expect(fadeStep(0.1)).toBe(0.1);
		expect(restoreStep(0.25)).toBe(0.5);
		expect(restoreStep(0.8)).toBe(1);
	});
});

describe('the token budget', () => {
	it('keeps lines in order while they fit and skips one that does not', () => {
		const lines = ['a'.repeat(40), 'b'.repeat(400), 'c'.repeat(40)];
		expect(estimateTokens('a'.repeat(40))).toBe(10);
		const kept = fitBudget(lines, 30);
		expect(kept).toEqual([lines[0], lines[2]]);
		expect(kept.reduce((n, l) => n + estimateTokens(l) + 1, 0)).toBeLessThanOrEqual(30);
		expect(fitBudget(lines, 0)).toEqual([]);
	});
});

describe('scoring', () => {
	const base = { similarity: 0.5, keyword: 0.5, ageDays: 10, importance: 3, fadeWeight: 1 };

	it('prefers similar, recent and important facts, and a faded fact counts for less', () => {
		expect(scoreFact({ ...base, similarity: 0.9 })).toBeGreaterThan(scoreFact(base));
		expect(scoreFact({ ...base, ageDays: 400 })).toBeLessThan(scoreFact(base));
		expect(scoreFact({ ...base, importance: 5 })).toBeGreaterThan(
			scoreFact({ ...base, importance: 1 })
		);
		expect(scoreFact({ ...base, fadeWeight: 0.1 })).toBeCloseTo(scoreFact(base) / 10, 5);
	});

	it('works from keywords alone when there is no vector', () => {
		expect(scoreFact({ ...base, similarity: null, keyword: 1 })).toBeGreaterThan(
			scoreFact({ ...base, similarity: null, keyword: 0 })
		);
	});

	it('measures the angle between vectors', () => {
		expect(cosine([1, 0], [1, 0])).toBeCloseTo(1);
		expect(cosine([1, 0], [0, 1])).toBeCloseTo(0);
		expect(cosine([0, 0], [1, 1])).toBe(0);
	});
});
