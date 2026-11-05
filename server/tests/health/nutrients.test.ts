// NUTRIENTS (BTL-20261105-0015, P3): WHOLE-NUMBER SUMS, UNKNOWN IS NEVER ZERO, USDA FILES ARE READ IN THE RIGHT UNITS, A REPEAT LOAD DELETES NOTHING, AND THE STARTER LIST ADDS UP

// -- TYPES -- //
import type { FoodFacts } from '../../src/lib/health/nutrients';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { englishTerm, FILIPINO_FOODS, searchFilipino } from '../../src/lib/health/filipino';
import {
	addUp,
	kcalFits,
	kcalFromMacros,
	rangeOf,
	scaleFood,
	toMilligrams,
	toNanograms
} from '../../src/lib/health/nutrients';
import { loadNutrition } from '../../src/lib/server/nutrition/load';
import { parseUsdaFile, parseUsdaFood } from '../../src/lib/server/nutrition/usda';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const FACTS: FoodFacts = {
	kcal: 130,
	proteinMg: 2700,
	carbsMg: 28_000,
	fatMg: 300,
	sugarMg: null,
	fibreMg: 400,
	satFatMg: null,
	sodiumMg: 1000,
	nutrients: { vitamin_b12: 2400, iron: 200_000 }
};

const RICE = {
	fdcId: 168878,
	description: 'Rice, white, cooked',
	foodNutrients: [
		{ nutrient: { id: 1008, unitName: 'KCAL' }, amount: 130 },
		{ nutrient: { id: 1062, unitName: 'kJ' }, amount: 544 },
		{ nutrient: { id: 1003, unitName: 'G' }, amount: 2.69 },
		{ nutrient: { id: 1005, unitName: 'G' }, amount: 28.2 },
		{ nutrient: { id: 1004, unitName: 'G' }, amount: 0.28 },
		{ nutrient: { id: 1178, unitName: 'UG' }, amount: 0.04 },
		{ nutrient: { id: 1093, unitName: 'MG' }, amount: 1 },
		{ nutrient: { id: 1110, unitName: 'IU' }, amount: 4 }
	],
	foodPortions: [
		{ gramWeight: 158, amount: 1, modifier: 'cup' },
		{ gramWeight: 79, amount: 0.5, modifier: 'half' },
		{ gramWeight: 0, amount: 1, modifier: 'none' }
	]
};

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('whole number units', () => {
	it('converts grams, milligrams and micrograms, and leaves IU out', () => {
		expect(toNanograms(0.04, 'UG')).toBe(40);
		expect(toNanograms(2, 'MG')).toBe(2_000_000);
		expect(toMilligrams(2.7, 'G')).toBe(2700);
		expect(toNanograms(4, 'IU')).toBeNull();
	});

	it('keeps vitamin B12 through scaling instead of rounding it to nothing', () => {
		const portion = scaleFood(FACTS, 150);
		expect(portion.nutrients.vitamin_b12).toBe(3600);
		expect(portion.kcal).toBe(195);
		expect(scaleFood({ ...FACTS, nutrients: { vitamin_b12: 40 } }, 100).nutrients.vitamin_b12).toBe(
			40
		);
	});

	it('leaves an unknown nutrient unknown when scaling', () => {
		const p = scaleFood(FACTS, 200);
		expect(p.sugarMg).toBeNull();
		expect(p.fibreMg).toBe(800);
	});
});

describe('totals', () => {
	const entry = (over: Partial<FoodFacts>) => ({
		...FACTS,
		lowKcal: 100,
		highKcal: 160,
		...over
	});

	it('adds known values and counts the foods that did not know', () => {
		const d = addUp([entry({}), entry({ sugarMg: 5000, nutrients: { vitamin_b12: 100 } })]);
		expect(d.kcal).toBe(260);
		expect(d.lowKcal).toBe(200);
		expect(d.core.sugarMg).toEqual({ mg: 5000, unknownFoods: 1 });
		expect(d.nutrients.find((n) => n.code === 'vitamin_b12')).toMatchObject({
			ng: 2500,
			knownFoods: 2
		});
		expect(d.nutrients.find((n) => n.code === 'iron')).toMatchObject({ knownFoods: 1 });
	});

	it('never lists a nutrient no food knows', () => {
		expect(addUp([entry({ nutrients: {} })]).nutrients).toEqual([]);
	});

	it('gives a range', () => {
		expect(rangeOf(1000, 15)).toEqual({ lowKcal: 850, highKcal: 1150 });
	});

	it('checks calories against protein, carbs and fat', () => {
		expect(kcalFromMacros(2000, 18_000, 8000)).toBe(152);
		expect(kcalFits(150, 2000, 18_000, 8000)).toBe(true);
		expect(kcalFits(620, 2000, 18_000, 8000)).toBe(false);
	});
});

describe('USDA files', () => {
	it('reads per 100 g values and portions in the right units', () => {
		const p = parseUsdaFood(RICE, 'sr_legacy');
		expect(p?.food).toMatchObject({
			id: 'usda:168878',
			kcal: 130,
			proteinMg: 2690,
			carbsMg: 28_200,
			fatMg: 280,
			sodiumMg: 1,
			sugarMg: null,
			fibreMg: null
		});
		expect(p?.food.nutrients).toEqual({ vitamin_b12: 40 });
		expect(p?.portions.map((x) => [x.label, x.gramsTenths])).toEqual([
			['cup', 1580],
			['half', 1580]
		]);
	});

	it('falls back through the energy numbers and never reads kJ as kcal', () => {
		const atwater = parseUsdaFood(
			{
				fdcId: 1,
				description: 'A',
				foodNutrients: [{ nutrient: { id: 2047, unitName: 'KCAL' }, amount: 90 }]
			},
			'foundation'
		);
		expect(atwater?.food.kcal).toBe(90);
		const kj = parseUsdaFood(
			{
				fdcId: 2,
				description: 'B',
				foodNutrients: [
					{ nutrient: { id: 1008, unitName: 'kJ' }, amount: 544 },
					{ nutrient: { id: 1003, unitName: 'G' }, amount: 10 },
					{ nutrient: { id: 1005, unitName: 'G' }, amount: 10 },
					{ nutrient: { id: 1004, unitName: 'G' }, amount: 5 }
				]
			},
			'foundation'
		);
		expect(kj?.food.kcal).toBe(125);
	});

	it('skips a food with no energy and no macronutrients', () => {
		expect(parseUsdaFood({ fdcId: 3, description: 'C', foodNutrients: [] }, 'survey')).toBeNull();
	});

	it('reads whichever of the three lists a file holds', () => {
		const r = parseUsdaFile({ SurveyFoods: [RICE] });
		expect(r.foods[0]?.dataType).toBe('survey');
		expect(r.portions).toHaveLength(2);
	});
});

describe('the loader', () => {
	it('updates the same rows on a repeat and deletes nothing', async () => {
		const q = (text: string, params?: unknown[]) => t.handle.owner.query(text, params as never[]);
		const first = parseUsdaFile({ SRLegacyFoods: [RICE] });
		await loadNutrition(q, first.foods, first.portions);
		await t.handle.owner.query(
			`insert into nutrition_food (id, source, data_type, name, kcal) values ('usda:9', 'usda', 'sr_legacy', 'Other', 10)`
		);
		const changed = first.foods.map((f) => ({ ...f, kcal: 131 }));
		await loadNutrition(q, changed, first.portions);
		const rows = await t.handle.owner.query<{ id: string; kcal: number }>(
			`select id, kcal from nutrition_food order by id`
		);
		expect(rows).toEqual([
			{ id: 'usda:168878', kcal: 131 },
			{ id: 'usda:9', kcal: 10 }
		]);
		const [p] = await t.handle.owner.query<{ n: number }>(
			`select count(*)::int as n from nutrition_portion`
		);
		expect(p?.n).toBe(2);
	});
});

describe('the Filipino list', () => {
	it('has sensible entries, each marked with a real serving', () => {
		expect(FILIPINO_FOODS.length).toBeGreaterThanOrEqual(40);
		expect(new Set(FILIPINO_FOODS.map((f) => f.id)).size).toBe(FILIPINO_FOODS.length);
		for (const f of FILIPINO_FOODS) {
			expect(f.servingG, f.name).toBeGreaterThan(0);
			expect(f.facts.kcal, f.name).toBeGreaterThan(5);
			expect(f.facts.kcal, f.name).toBeLessThan(900);
			expect(
				kcalFits(f.facts.kcal, f.facts.proteinMg ?? 0, f.facts.carbsMg ?? 0, f.facts.fatMg ?? 0),
				f.name
			).toBe(true);
		}
	});

	it('finds dishes by their common names', () => {
		for (const [word, id] of [
			['adobo', 'fil:adobo_chicken'],
			['sinigang', 'fil:sinigang_pork'],
			['tinola', 'fil:tinola'],
			['kanin', 'fil:kanin'],
			['lugaw', 'fil:arroz_caldo'],
			['kare-kare', 'fil:kare_kare']
		] as const)
			expect(searchFilipino(word)[0]?.id, word).toBe(id);
	});

	it('turns Filipino words into plain English search words', () => {
		expect(englishTerm('itlog')).toBe('egg');
		expect(englishTerm('saging')).toBe('banana');
		expect(englishTerm('brown rice')).toBe('brown rice');
	});
});
