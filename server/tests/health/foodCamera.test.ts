// THE FOOD CAMERA ON THE SERVER (BTL-20261105-0015, P4): CARDS AFTER A PHOTO, APPROVED EDITS, THE SHORTLIST, LABELS, AND BARCODE LOOKUPS THAT STAY ON FIXED ADDRESSES

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import {
	checkBarcode,
	brandQuery,
	cleanName,
	factsFromOff,
	lookupBarcode,
	resetBarcodeState,
	searchBrands
} from '../../src/lib/server/fooddata/barcode';
import { createAction, decideAction } from '../../src/lib/server/ops/actions';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { createMasker } from '../../src/lib/server/proxy/mask';
import { createTestDb } from '../support/testDb';

// -- TYPES -- //

type DayView = {
	totals: { kcal: number };
	entries: { name: string; kcal: number; grams: number }[];
};
type Preview = {
	items: { name: string; grams: number; kcal: number; fits?: boolean; basisGrams?: number }[];
	kcal: number;
	lowKcal: number;
	highKcal: number;
};

// -- CONSTANTS -- //

const ME = 'user_cam_00001';
const OFF_PRODUCT = {
	product: {
		product_name: ' Instant  pancit\n canton ',
		serving_quantity: 60,
		product_quantity: 60,
		nutriments: {
			'energy-kcal_100g': 483,
			proteins_100g: 10,
			carbohydrates_100g: 66,
			fat_100g: 20,
			sodium_100g: 1.7
		}
	}
};

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (): Ctx => ({
	handle: t.handle,
	actor: { userId: ME, kind: 'person' },
	requestId: `req-cam-${String(++counter).padStart(6, '0')}`
});
const agent = (): Ctx => ({
	handle: t.handle,
	actor: { userId: ME, kind: 'agent', tool: 'meal_log' },
	requestId: `req-cam-${String(++counter).padStart(6, '0')}`
});
const fakeFetch = (replies: (url: string, init?: RequestInit) => Response) => {
	const calls: { url: string; init?: RequestInit }[] = [];
	vi.stubGlobal('fetch', async (url: string, init?: RequestInit) => {
		calls.push({ url: String(url), ...(init ? { init } : {}) });
		return replies(String(url), init);
	});
	return calls;
};

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values({ id: ME, name: 'M', email: 'm@example.com' });
});

afterAll(async () => {
	await t.close();
});

afterEach(() => {
	vi.unstubAllGlobals();
	vi.unstubAllEnvs();
	resetBarcodeState();
});

// -- TESTS -- //

describe('a meal card', () => {
	const args = {
		day: '2031-01-01',
		meal: 'lunch',
		items: [
			{ foodId: 'fil:adobo_chicken', grams: 180 },
			{ foodId: 'fil:kanin', grams: 200 }
		]
	};

	it('names every food with its worked-out calories, so nothing is hidden', async () => {
		const card = await createAction(agent(), { verb: 'meal_log', args });
		expect(card.summary).toContain('Chicken adobo 180 g');
		expect(card.summary).toContain('Steamed white rice 200 g');
		expect(card.summary).toMatch(/About \d+ kcal in all \(could be \d+ to \d+\)/);
	});

	it('refuses a made-up food before the person ever sees it', async () => {
		await expect(
			createAction(agent(), {
				verb: 'meal_log',
				args: { items: [{ foodId: 'fil:nothing', grams: 10 }] }
			})
		).rejects.toMatchObject({ message: expect.stringContaining('Search for it first') });
	});

	it('writes nothing until it is approved, then writes the corrected items', async () => {
		const day = '2031-01-02';
		const card = await createAction(agent(), { verb: 'meal_log', args: { ...args, day } });
		expect(((await invokeVerb(person(), 'food_day', { day })) as DayView).entries).toHaveLength(0);
		await decideAction(person(), {
			actionId: card.actionId,
			decision: 'approve',
			editedArgs: { day, meal: 'lunch', items: [{ foodId: 'fil:adobo_chicken', grams: 100 }] }
		});
		const d = (await invokeVerb(person(), 'food_day', { day })) as DayView;
		expect(d.entries.map((e) => [e.name, e.grams])).toEqual([['Chicken adobo', 100]]);
	});

	it('runs the checks again on what was edited', async () => {
		const card = await createAction(agent(), { verb: 'meal_log', args });
		const out = await decideAction(person(), {
			actionId: card.actionId,
			decision: 'approve',
			editedArgs: { items: [{ foodId: 'fil:nothing', grams: 10 }] }
		});
		expect(out).toMatchObject({ status: 'failed' });
	});

	it('takes edits only on a meal card', async () => {
		const card = await createAction(agent(), {
			verb: 'food_day_mark',
			args: { day: '2031-01-03', complete: true }
		});
		await expect(
			decideAction(person(), {
				actionId: card.actionId,
				decision: 'approve',
				editedArgs: { day: '2031-01-03', complete: false }
			})
		).rejects.toMatchObject({ code: 'INVALID', message: 'This card cannot be edited.' });
	});

	it('a rejected card writes nothing', async () => {
		const day = '2031-01-04';
		const card = await createAction(agent(), { verb: 'meal_log', args: { ...args, day } });
		await decideAction(person(), { actionId: card.actionId, decision: 'reject' });
		expect(((await invokeVerb(person(), 'food_day', { day })) as DayView).entries).toHaveLength(0);
	});
});

describe('the preview', () => {
	it('scales to a weighed total', async () => {
		const p = (await invokeVerb(person(), 'meal_preview', {
			totalG: 190,
			items: [
				{ foodId: 'fil:kanin', grams: 200 },
				{ foodId: 'fil:adobo_chicken', grams: 180 }
			]
		})) as Preview;
		expect(p.items.map((i) => i.grams)).toEqual([100, 90]);
	});

	it('is not offered to the assistant', () => {
		expect(verbByName('meal_preview')?.agent).toBe(false);
	});
});

describe('a label', () => {
	const label = {
		name: 'Crackers',
		basisGrams: 30,
		servingG: 30,
		kcal: 150,
		proteinMg: 2000,
		carbsMg: 18_000,
		fatMg: 8000
	};

	it('turns a serving into per 100 g, and logs what was eaten', async () => {
		const p = (await invokeVerb(person(), 'meal_preview', {
			items: [{ label, count: 2 }]
		})) as Preview;
		expect(p.items[0]).toMatchObject({ grams: 60, kcal: 300, basisGrams: 30, fits: true });
	});

	it('converts kJ once, and flags numbers that do not add up', async () => {
		const p = (await invokeVerb(person(), 'meal_preview', {
			items: [{ label: { name: 'Bar', basisGrams: 100, kilojoules: 2000 } }]
		})) as Preview;
		expect(p.items[0]?.kcal).toBe(478);
		const bad = (await invokeVerb(person(), 'meal_preview', {
			items: [{ label: { ...label, kcal: 900 } }]
		})) as Preview;
		expect(bad.items[0]?.fits).toBe(false);
	});

	it('keeps the other printed nutrients of a label, and refuses a made-up one', async () => {
		const r = (await invokeVerb(person(), 'meal_log', {
			day: '2031-02-03',
			items: [
				{ label: { ...label, name: 'Milk drink', extraMg: { calcium: 150, vitamin_b12: 0.0009 } } }
			]
		})) as { entries: { nutrients: Record<string, number> }[] };
		// One serving of 30 g was eaten, so the entry holds what the label printed for it
		expect(r.entries[0]?.nutrients).toEqual({ calcium: 150_000_000, vitamin_b12: 900 });
		const saved = (await invokeVerb(person(), 'food_saved_list', {})) as {
			name: string;
			nutrients: Record<string, number>;
		}[];
		expect(saved.find((s) => s.name === 'Milk drink')?.nutrients).toEqual({
			calcium: 500_000_000,
			vitamin_b12: 3000
		});
		await expect(
			invokeVerb(person(), 'meal_preview', {
				items: [{ label: { ...label, extraMg: { unobtainium: 1 } } }]
			})
		).rejects.toMatchObject({
			message: expect.stringContaining('Unknown nutrient: unobtainium. The codes are: potassium, ')
		});
	});

	it('refuses a label with no energy', async () => {
		await expect(
			invokeVerb(person(), 'meal_preview', {
				items: [{ label: { name: 'Bar', basisGrams: 100 } }]
			})
		).rejects.toMatchObject({ message: 'A label needs its calories or kilojoules.' });
	});

	it('saves the product once approved, so the barcode is found next time', async () => {
		const card = await createAction(agent(), {
			verb: 'meal_log',
			args: {
				day: '2031-02-01',
				items: [{ label: { ...label, barcode: '4801234567890' } }]
			}
		});
		await decideAction(person(), { actionId: card.actionId, decision: 'approve' });
		const again = (await invokeVerb(person(), 'barcode_lookup', {
			barcode: '4801234567890'
		})) as { found: boolean; source: string; name: string };
		expect(again).toMatchObject({ found: true, source: 'saved', name: 'Crackers' });
	});
});

describe('barcode lookups', () => {
	it('accepts digits only, so nothing else can reach an address', () => {
		expect(checkBarcode('4801234567890')).toBe('4801234567890');
		for (const bad of ['../../x', '123', '12345678?y=1', '1234567890123456'])
			expect(() => checkBarcode(bad)).toThrow('A barcode is 8 to 14 digits.');
	});

	it('marks the turn as untrusted', () => {
		expect(verbByName('barcode_lookup')?.taints).toBe(true);
	});

	it('asks a fixed address with no redirects, and cleans the name', async () => {
		const calls = fakeFetch(() => new Response(JSON.stringify(OFF_PRODUCT)));
		const r = await lookupBarcode('4807770270017');
		expect(
			calls[0]?.url.startsWith('https://world.openfoodfacts.org/api/v2/product/4807770270017.json')
		).toBe(true);
		expect(calls[0]?.init?.redirect).toBe('error');
		expect(r).toMatchObject({
			found: true,
			product: {
				id: 'barcode:4807770270017',
				name: 'Instant pancit canton',
				servingG: 60,
				facts: { kcal: 483, proteinMg: 10_000, sodiumMg: 1700, sugarMg: null }
			}
		});
	});

	it('remembers a lookup, so a second scan makes no call', async () => {
		const calls = fakeFetch(() => new Response(JSON.stringify(OFF_PRODUCT)));
		await lookupBarcode('4807770270017');
		await lookupBarcode('4807770270017');
		expect(calls).toHaveLength(1);
	});

	it('treats partial nutrition as missing, and keeps the name for the label flow', async () => {
		fakeFetch(
			() =>
				new Response(
					JSON.stringify({ product: { product_name: 'Mystery', nutriments: { salt_100g: 1 } } })
				)
		);
		expect(await lookupBarcode('4800000000017')).toMatchObject({
			found: false,
			nameHint: 'Mystery',
			reason: 'partial'
		});
	});

	it('reports the USDA source as not configured instead of skipping it silently', async () => {
		vi.stubEnv('USDA_API_KEY', '');
		fakeFetch(() => new Response('{}', { status: 404 }));
		expect(await lookupBarcode('4800000000024')).toMatchObject({
			found: false,
			notConfigured: ['usda_branded']
		});
	});

	it('sends the USDA key in a header only, and never prints it when a call fails', async () => {
		vi.stubEnv('USDA_API_KEY', 'secret-key-value');
		const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
		const calls = fakeFetch((url) => {
			if (url.includes('nal.usda.gov')) throw new Error(`boom ${url}`);
			return new Response('{}', { status: 404 });
		});
		await lookupBarcode('4800000000031');
		const usda = calls.find((c) => c.url.includes('nal.usda.gov'));
		expect(usda?.url).not.toContain('secret-key-value');
		expect((usda?.init?.headers as Record<string, string>)['x-api-key']).toBe('secret-key-value');
		expect(JSON.stringify(errors.mock.calls)).not.toContain('secret-key-value');
		errors.mockRestore();
	});

	it('reads kJ and per-serving figures only with what they need', () => {
		expect(factsFromOff({ nutriments: { 'energy-kj_100g': 418.4, proteins_100g: 1 } })?.kcal).toBe(
			100
		);
		expect(
			factsFromOff({
				serving_quantity: 50,
				nutriments: { 'energy-kcal_serving': 100, fat_serving: 5 }
			})
		).toMatchObject({ kcal: 200, fatMg: 10_000 });
		expect(factsFromOff({ nutriments: { 'energy-kcal_serving': 100, fat_serving: 5 } })).toBeNull();
	});

	it('reads sodium from salt when sodium is missing, and keeps the other nutrients in nanograms', () => {
		const facts = factsFromOff({
			nutriments: {
				'energy-kcal_100g': 400,
				proteins_100g: 5,
				salt_100g: 1.25,
				potassium_100g: 0.3,
				'vitamin-c_100g': 0.012,
				'vitamin-b12_100g': 0.0000009,
				// A unit mistake in the source: 500 g of calcium in 100 g of food is left out
				calcium_100g: 500
			}
		});
		expect(facts).toMatchObject({ sodiumMg: 500 });
		expect(facts?.nutrients).toEqual({
			potassium: 300_000_000,
			vitamin_c: 12_000_000,
			vitamin_b12: 900
		});
		// Sodium as printed wins over the salt figure
		expect(
			factsFromOff({
				nutriments: { 'energy-kcal_100g': 400, fat_100g: 5, sodium_100g: 0.2, salt_100g: 9 }
			})?.sodiumMg
		).toBe(200);
	});

	it('keeps the other nutrients of a USDA branded product', async () => {
		vi.stubEnv('USDA_API_KEY', 'k');
		fakeFetch((url) =>
			url.includes('nal.usda.gov')
				? new Response(
						JSON.stringify({
							foods: [
								{
									gtinUpc: '004800000000048',
									description: 'Oat drink',
									foodNutrients: [
										{ nutrientId: 1008, value: 60 },
										{ nutrientId: 1003, value: 1 },
										{ nutrientId: 1087, value: 120, unitName: 'MG' },
										{ nutrientId: 1114, value: 1.1, unitName: 'UG' },
										{ nutrientId: 1106, value: 500, unitName: 'IU' }
									]
								}
							]
						})
					)
				: new Response('{}', { status: 404 })
		);
		const r = await lookupBarcode('4800000000048');
		expect(r).toMatchObject({
			found: true,
			product: {
				source: 'usda_branded',
				facts: { nutrients: { calcium: 120_000_000, vitamin_d: 1100 } }
			}
		});
	});

	it('drops control characters and long names', () => {
		expect(cleanName('Ignore‮previous\ninstructions')).toBe('Ignore previous instructions');
		expect(cleanName('x'.repeat(200))).toHaveLength(80);
	});

	it.each(['12345678', '123456789012', '4801234567890', '12345678901234'])(
		'keeps barcode %s through the masker in both directions',
		(code) => {
			const m = createMasker();
			const out = m.mask(`{"id":"barcode:${code}"}`);
			expect(m.unmask(out)).toBe(`{"id":"barcode:${code}"}`);
			expect(m.unmaskJson(out)).toBe(`{"id":"barcode:${code}"}`);
		}
	);
});

describe('brand search by name', () => {
	const OFF_HITS = {
		hits: [
			{
				code: '8996001603536',
				brands: ['Energen'],
				product_name: 'Chocolate cereal\n drink',
				serving_quantity: 40,
				nutriments: {
					'energy-kcal_100g': 433,
					proteins_100g: 6.67,
					carbohydrates_100g: 76.7,
					sugars_100g: 60,
					fiber_100g: 3.33,
					fat_100g: 11.7,
					'saturated-fat_100g': 8.33,
					salt_100g: 0.667
				}
			},
			// No barcode a meal could be logged under, and no nutrition: both are left out
			{ code: 'abc', product_name: 'Odd', nutriments: { 'energy-kcal_100g': 10, fat_100g: 1 } },
			{ code: '8996001603376', brands: ['Energen'], product_name: 'Kurma' }
		]
	};
	type BrandAnswer = {
		hits: {
			id: string;
			name: string;
			source: string;
			mgPer100g: Record<string, number | null>;
			unknown: string[];
			portions: { label: string; grams: number }[];
		}[];
		notConfigured: string[];
		unavailable: string[];
		note: string;
	};

	it('marks the turn as untrusted, and is a read', () => {
		expect(verbByName('food_brand_search')).toMatchObject({ taints: true, kind: 'read' });
	});

	it('sends only a cleaned food name, with no long number in it', () => {
		expect(brandQuery('  Energen\nchocolate 09171234567 <script>  ')).toBe(
			'Energen chocolate script'
		);
		expect(brandQuery('x'.repeat(200))).toHaveLength(80);
		// A few digits belong to a name; a number cut into short groups does not get out
		expect(brandQuery('Milo 3 in 1 100 g')).toBe('Milo 3 in 1 100 g');
		expect(brandQuery('1234 5678 9012 3456 milk')).toBe('milk');
	});

	it('asks both fixed addresses, and a hit can be logged with all seven values without a second call', async () => {
		vi.stubEnv('USDA_API_KEY', 'secret-key-value');
		const calls = fakeFetch((url) =>
			url.startsWith('https://search.openfoodfacts.org/search?')
				? new Response(JSON.stringify(OFF_HITS))
				: new Response(JSON.stringify({ foods: [] }))
		);
		const r = (await invokeVerb(person(), 'food_brand_search', {
			name: 'Energen chocolate'
		})) as BrandAnswer;
		expect(calls.map((c) => new URL(c.url).host).sort()).toEqual([
			'api.nal.usda.gov',
			'search.openfoodfacts.org'
		]);
		for (const c of calls) {
			expect(c.init?.redirect).toBe('error');
			expect(c.url).not.toContain('secret-key-value');
		}
		expect(r.hits).toHaveLength(1);
		expect(r.hits[0]).toMatchObject({
			id: 'barcode:8996001603536',
			name: 'Energen Chocolate cereal drink',
			source: 'off',
			unknown: [],
			mgPer100g: { sugarMg: 60_000, fibreMg: 3330, satFatMg: 8330, sodiumMg: 267 },
			portions: [{ label: 'serving', grams: 40 }]
		});
		expect(r.unavailable).toEqual([]);
		const before = calls.length;
		const logged = (await invokeVerb(person(), 'meal_log', {
			day: '2031-03-01',
			items: [{ foodId: 'barcode:8996001603536', portion: 'serving' }]
		})) as { entries: Record<string, unknown>[] };
		expect(logged.entries[0]).toMatchObject({
			grams: 40,
			kcal: 173,
			sugarMg: 24_000,
			fibreMg: 1332,
			satFatMg: 3332,
			sodiumMg: 107,
			sourceKind: 'off'
		});
		expect(calls).toHaveLength(before);
	});

	it('passes over a source that fails and says so, and reports a missing key', async () => {
		vi.stubEnv('USDA_API_KEY', '');
		const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
		fakeFetch(() => {
			throw new Error('boom Energen');
		});
		const r = (await invokeVerb(person(), 'food_brand_search', { name: 'Energen' })) as BrandAnswer;
		expect(r).toMatchObject({ hits: [], notConfigured: ['usda_branded'], unavailable: ['off'] });
		expect(r.note).toContain('could not be asked');
		// The log holds the reason class only, never the name that was searched
		expect(JSON.stringify(errors.mock.calls)).not.toContain('Energen');
		errors.mockRestore();
	});

	it('remembers an answer, and stops asking past the per-minute limit', async () => {
		vi.stubEnv('USDA_API_KEY', '');
		const calls = fakeFetch(() => new Response(JSON.stringify(OFF_HITS)));
		await searchBrands('Energen');
		await searchBrands('energen');
		expect(calls).toHaveLength(1);
		for (let i = 0; i < 12; i += 1) await searchBrands(`Milk drink ${'abcdefghijkl'[i]}`);
		expect(calls).toHaveLength(8);
		expect((await searchBrands('One more')).unavailable).toEqual(['off']);
	});
});
