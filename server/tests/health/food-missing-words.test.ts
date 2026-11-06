// A BRAND MISS IS SAID, NOT ANSWERED WITH THE PLAIN FOOD (BTL-20261106-1502)
// In the chat of 6 Nov "Greek yogurt Pascual" returned plain nonfat Greek yogurt as the top hit: three times the protein of the product.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { missingWords } from '../../src/lib/server/ops/food';

// -- TESTS -- //

describe('missingWords', () => {
	const usda = ['Yogurt, Greek, plain, nonfat', 'Yogurt, Greek, plain, whole milk'];

	it('names the word no hit holds: a brand search that found the plain food', () => {
		expect(missingWords('Greek yogurt Pascual', 'Greek yogurt Pascual', usda)).toEqual(['pascual']);
	});
	it('says nothing when a hit holds every word, so a generic search still answers', () => {
		expect(missingWords('Greek yogurt', 'Greek yogurt', usda)).toBeNull();
		expect(missingWords('yogurts, greek', 'yogurts, greek', usda)).toBeNull();
	});
	it('ignores how much or how: a cup of plain rice is rice', () => {
		expect(missingWords('1 cup of regular rice', 'rice', ['Rice, white, cooked'])).toBeNull();
	});
	it('accepts the English form of a Filipino name', () => {
		expect(missingWords('sinangag', 'fried rice', ['Rice, fried'])).toBeNull();
	});
	it('names every word when there are no hits at all, and says nothing for an empty name', () => {
		expect(missingWords('pastil', 'pastil', [])).toEqual(['pastil']);
		expect(missingWords('1 cup', '1 cup', [])).toBeNull();
	});
});
