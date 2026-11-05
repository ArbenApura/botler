// FOOD VERBS (BTL-20261105-0015, P3): THE SERVER WORKS OUT THE NUMBERS, ENTRIES KEEP THEM, UNKNOWN IS NOT ZERO, AND THE SEARCH FINDS COMMON NAMES

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { existsSync, readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { loadNutrition } from '../../src/lib/server/nutrition/load';
import { parseUsdaFile } from '../../src/lib/server/nutrition/usda';
import { mealForHour } from '../../src/lib/server/ops/food';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- TYPES -- //

type Entry = { id: string; kcal: number; lowKcal: number; highKcal: number; name: string };
type DayView = {
	day: string;
	entries: Entry[];
	leftKcal: number | null;
	complete: boolean;
	totals: {
		kcal: number;
		core: Record<string, { mg: number; unknownFoods: number }>;
		nutrients: { code: string; ng: number; knownFoods: number }[];
	};
};
type LogAnswer = { entries: Entry[]; kcal: number; lowKcal: number; today: DayView };
type SearchAnswer = { name: string; hits: { id: string; name: string; source: string }[] }[];

// -- CONSTANTS -- //

const ME = 'user_food_0001';
const DAY = '2030-06-01';
const RICE = {
	fdcId: 100,
	description: 'Rice, white, long-grain, cooked',
	foodNutrients: [
		{ nutrient: { id: 1008, unitName: 'KCAL' }, amount: 130 },
		{ nutrient: { id: 1003, unitName: 'G' }, amount: 2.7 },
		{ nutrient: { id: 1005, unitName: 'G' }, amount: 28 },
		{ nutrient: { id: 1004, unitName: 'G' }, amount: 0.3 },
		{ nutrient: { id: 1178, unitName: 'UG' }, amount: 0.1 }
	],
	foodPortions: [{ gramWeight: 158, amount: 1, modifier: 'cup' }]
};
const EGG = {
	fdcId: 101,
	description: 'Egg, whole, fried',
	foodNutrients: [
		{ nutrient: { id: 1008, unitName: 'KCAL' }, amount: 196 },
		{ nutrient: { id: 1003, unitName: 'G' }, amount: 13.6 },
		{ nutrient: { id: 1093, unitName: 'MG' }, amount: 207 }
	],
	foodPortions: [{ gramWeight: 46, amount: 1, modifier: 'large' }]
};

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const ctx = (kind: 'person' | 'agent' = 'person'): Ctx => ({
	handle: t.handle,
	actor: { userId: ME, kind, ...(kind === 'agent' ? { tool: 'test' } : {}) },
	requestId: `req-food-${String(++counter).padStart(6, '0')}`
});
const ownerQuery = (text: string, params?: unknown[]) =>
	t.handle.owner.query(text, params as never[]);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values({ id: ME, name: 'M', email: 'm@example.com' });
	const { foods, portions } = parseUsdaFile({ SRLegacyFoods: [RICE, EGG] });
	await loadNutrition(ownerQuery, foods, portions);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('search', () => {
	it('finds Filipino dishes by name, and plain food by a Filipino word', async () => {
		const r = (await invokeVerb(ctx(), 'food_search', {
			names: ['adobo', 'kanin', 'itlog']
		})) as SearchAnswer;
		expect(r[0]?.hits[0]).toMatchObject({ id: 'fil:adobo_chicken', source: 'filipino' });
		expect(r[1]?.hits[0]?.id).toBe('fil:kanin');
		expect(r[2]?.hits[0]).toMatchObject({ id: 'usda:101', source: 'usda' });
	});

	it('puts a saved food first', async () => {
		await invokeVerb(ctx(), 'food_save', { name: 'My adobo', kcal: 210, servingG: 180 });
		const r = (await invokeVerb(ctx(), 'food_search', { names: ['adobo'] })) as SearchAnswer;
		expect(r[0]?.hits[0]).toMatchObject({ name: 'My adobo', source: 'saved' });
	});

	it('picks the time of day', () => {
		expect(mealForHour(7)).toBe('breakfast');
		expect(mealForHour(12)).toBe('lunch');
		expect(mealForHour(16)).toBe('merienda');
		expect(mealForHour(20)).toBe('dinner');
	});
});

describe('logging', () => {
	it('works out the numbers from grams, and the model gives none', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day: DAY,
			meal: 'lunch',
			items: [{ foodId: 'usda:100', grams: 200 }]
		})) as LogAnswer;
		expect(r.entries[0]).toMatchObject({ kcal: 260, lowKcal: 221, highKcal: 299 });
		expect(r.today.totals.kcal).toBe(260);
	});

	it('turns a household amount into grams', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day: DAY,
			items: [{ foodId: 'usda:100', portion: 'cup', count: 2 }]
		})) as LogAnswer;
		expect(r.entries[0]?.kcal).toBe(411);
	});

	it('says which amounts a food has when one is unknown', async () => {
		await expect(
			invokeVerb(ctx(), 'meal_log', {
				day: DAY,
				items: [{ foodId: 'usda:100', portion: 'bucket' }]
			})
		).rejects.toMatchObject({
			code: 'INVALID',
			message:
				'"Rice, white, long-grain, cooked" has no "bucket" amount. It has: cup. Give grams instead.'
		});
	});

	it('refuses a made-up food and logs nothing from that call', async () => {
		const before = (await invokeVerb(ctx(), 'food_day', { day: DAY })) as DayView;
		await expect(
			invokeVerb(ctx(), 'meal_log', {
				day: DAY,
				items: [
					{ foodId: 'usda:100', grams: 100 },
					{ foodId: 'usda:999999', grams: 100 }
				]
			})
		).rejects.toMatchObject({
			code: 'INVALID',
			message: expect.stringContaining('Search for it first')
		});
		expect(((await invokeVerb(ctx(), 'food_day', { day: DAY })) as DayView).entries).toHaveLength(
			before.entries.length
		);
	});

	it('works out an estimate from its macronutrients, with a wide range', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day: '2030-06-02',
			items: [{ estimate: { name: 'Sautéed greens', proteinG: 3, carbsG: 5, fatG: 6 }, grams: 100 }]
		})) as LogAnswer;
		expect(r.entries[0]).toMatchObject({ kcal: 86, lowKcal: 60, highKcal: 112 });
	});

	it('takes a rough total for a big day', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day: '2030-06-03',
			items: [{ rough: { name: 'Big party', kcal: 3000 } }]
		})) as LogAnswer;
		expect(r.entries[0]).toMatchObject({ kcal: 3000, lowKcal: 2250, highKcal: 3750 });
	});

	it('returns the first answer for a replay', async () => {
		const c = ctx();
		const args = { day: '2030-06-04', items: [{ foodId: 'usda:100', grams: 100 }] };
		const first = await invokeVerb(c, 'meal_log', args);
		expect(await invokeVerb(c, 'meal_log', args)).toEqual(first);
		expect(
			((await invokeVerb(ctx(), 'food_day', { day: '2030-06-04' })) as DayView).entries
		).toHaveLength(1);
	});
});

describe('the day', () => {
	const day = '2030-07-01';

	it('counts foods that did not know a nutrient instead of calling it zero', async () => {
		await invokeVerb(ctx(), 'meal_log', {
			day,
			items: [
				{ foodId: 'usda:100', grams: 100 },
				{ foodId: 'usda:101', grams: 100 }
			]
		});
		const d = (await invokeVerb(ctx(), 'food_day', { day })) as DayView;
		expect(d.totals.core.sodiumMg).toEqual({ mg: 207, unknownFoods: 1 });
		expect(d.totals.core.carbsMg).toEqual({ mg: 28_000, unknownFoods: 1 });
		expect(d.totals.nutrients).toEqual([
			expect.objectContaining({ code: 'vitamin_b12', ng: 100, knownFoods: 1 })
		]);
	});

	it('marks a day complete', async () => {
		const d = (await invokeVerb(ctx(), 'food_day_mark', { day, complete: true })) as DayView;
		expect(d.complete).toBe(true);
	});
});

describe('entries keep their numbers', () => {
	it('a later import leaves a past day alone', async () => {
		const day = '2030-08-01';
		await invokeVerb(ctx(), 'meal_log', { day, items: [{ foodId: 'usda:100', grams: 100 }] });
		const changed = parseUsdaFile({
			SRLegacyFoods: [
				{
					...RICE,
					foodNutrients: [{ nutrient: { id: 1008, unitName: 'KCAL' }, amount: 500 }]
				}
			]
		});
		await loadNutrition(ownerQuery, changed.foods, changed.portions);
		expect(((await invokeVerb(ctx(), 'food_day', { day })) as DayView).totals.kcal).toBe(130);
		const back = parseUsdaFile({ SRLegacyFoods: [RICE] });
		await loadNutrition(ownerQuery, back.foods, back.portions);
	});

	it('archiving a saved food leaves its entries', async () => {
		const day = '2030-08-02';
		const saved = (await invokeVerb(ctx(), 'food_save', { name: 'Crackers', kcal: 500 })) as {
			id: string;
			food: { id: string };
		};
		await invokeVerb(ctx(), 'meal_log', { day, items: [{ foodId: saved.id, grams: 30 }] });
		await invokeVerb(ctx(), 'food_archive', { foodItemId: saved.food.id });
		expect(((await invokeVerb(ctx(), 'food_day', { day })) as DayView).totals.kcal).toBe(150);
		const list = (await invokeVerb(ctx(), 'food_saved_list', {})) as { name: string }[];
		expect(list.map((f) => f.name)).not.toContain('Crackers');
	});
});

describe('fixing an entry', () => {
	const day = '2030-09-01';

	it('scales its own numbers when the grams change', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day,
			items: [{ foodId: 'usda:100', grams: 200 }]
		})) as LogAnswer;
		const id = r.entries[0]?.id;
		const e = (await invokeVerb(ctx(), 'food_edit', { entryId: id, grams: 100 })) as {
			entry: Entry;
			today: DayView;
		};
		expect(e.entry.kcal).toBe(130);
		expect(e.today.totals.kcal).toBe(130);
	});

	it('refuses new calories on a food from data, and allows them on a rough entry', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day,
			items: [{ foodId: 'usda:100', grams: 100 }]
		})) as LogAnswer;
		await expect(
			invokeVerb(ctx(), 'food_edit', { entryId: r.entries[0]?.id, kcal: 10 })
		).rejects.toMatchObject({
			message: 'The calories of this food come from its data. Change its grams instead.'
		});
		const rough = (await invokeVerb(ctx(), 'meal_log', {
			day,
			items: [{ rough: { name: 'Party', kcal: 900 } }]
		})) as LogAnswer;
		const e = (await invokeVerb(ctx(), 'food_edit', {
			entryId: rough.entries[0]?.id,
			kcal: 1000
		})) as { entry: Entry };
		expect(e.entry).toMatchObject({ kcal: 1000, lowKcal: 750, highKcal: 1250 });
	});

	it('answers what a delete removed', async () => {
		const r = (await invokeVerb(ctx(), 'meal_log', {
			day: '2030-09-02',
			items: [{ foodId: 'usda:101', grams: 50 }]
		})) as LogAnswer;
		const gone = (await invokeVerb(ctx(), 'food_delete', { entryId: r.entries[0]?.id })) as {
			removed: Entry;
			today: DayView;
		};
		expect(gone.removed.name).toBe('Egg, whole, fried');
		expect(gone.today.entries).toHaveLength(0);
	});
});

describe('agent access', () => {
	it('classes every food write as free, marks its entries, and has no user id', async () => {
		for (const v of ['meal_log', 'food_edit', 'food_delete', 'food_day_mark', 'food_save'])
			expect(verbByName(v)?.kind, v).toBe('free');
		const r = (await invokeVerb(ctx('agent'), 'meal_log', {
			day: '2030-10-01',
			items: [{ foodId: 'usda:100', grams: 100 }]
		})) as { entries: { byAgent: boolean }[] };
		expect(r.entries[0]?.byAgent).toBe(true);
		await expect(
			invokeVerb(ctx('agent'), 'meal_log', {
				userId: 'x',
				items: [{ rough: { name: 'A', kcal: 1 } }]
			})
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

// The real data is not in git: this runs only when a seed is named, and records the hit rate for the plan
const SEED = process.env.NUTRITION_SEED;
describe.runIf(SEED && existsSync(SEED))('common names against the real seed', () => {
	it('finds at least 45 of 50 common English and Filipino names', async () => {
		const lines = gunzipSync(readFileSync(SEED ?? ''))
			.toString('utf8')
			.split('\n');
		const foods: unknown[] = [];
		const portions: unknown[] = [];
		for (const line of lines) {
			if (!line) continue;
			const { t: kind, ...row } = JSON.parse(line) as { t: string };
			(kind === 'f' ? foods : portions).push(row);
		}
		await loadNutrition(ownerQuery, foods as never, portions as never);
		const names =
			'rice,white rice,brown rice,egg,fried egg,boiled egg,chicken breast,chicken thigh,pork,beef,tuna,salmon,milk,bread,oatmeal,banana,apple,mango,orange,papaya,coffee,cola,peanut butter,cheese,yogurt,noodles,potato,sweet potato,tomato,cabbage,adobo,sinigang,tinola,kare-kare,menudo,kanin,sinangag,pandesal,tapsilog,longganisa,tocino,lumpia,pancit canton,bihon,lugaw,turon,halo-halo,kangkong,itlog,saging'.split(
				','
			);
		const result = (await invokeVerb(ctx(), 'food_search', {
			names: names.slice(0, 12)
		})) as SearchAnswer;
		const all = [...result];
		for (let i = 12; i < names.length; i += 12)
			all.push(
				...((await invokeVerb(ctx(), 'food_search', {
					names: names.slice(i, i + 12)
				})) as SearchAnswer)
			);
		const found = all.filter((r) => r.hits.length > 0);
		process.stdout.write(
			`hit rate ${found.length} of ${names.length}; missing: ${all
				.filter((r) => r.hits.length === 0)
				.map((r) => r.name)
				.join(', ')}`
		);
		expect(found.length).toBeGreaterThanOrEqual(45);
	}, 300_000);
});
