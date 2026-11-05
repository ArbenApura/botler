// WRITES THE SHARED NUTRITION TABLES, AS THE OWNER ROLE ONLY. A REPEAT LOAD UPDATES THE SAME ROWS BY THE SOURCE'S OWN ID AND NEVER DELETES A FOOD,
// AND FOOD ENTRIES KEEP THEIR OWN NUMBERS, SO A NEW LOAD CANNOT CHANGE A PAST DAY.

// -- TYPES -- //
import type { NutritionFoodRow, NutritionPortionRow } from './usda';

export type OwnerQuery = (text: string, params?: unknown[]) => Promise<unknown>;

// -- CONSTANTS -- //

const BATCH = 500;

// -- FUNCTIONS -- //

const FOOD_COLUMNS = [
	'id',
	'source',
	'data_type',
	'name',
	'kcal',
	'protein_mg',
	'carbs_mg',
	'sugar_mg',
	'fibre_mg',
	'fat_mg',
	'sat_fat_mg',
	'sodium_mg',
	'nutrients'
];

function placeholders(rows: number, columns: number): string {
	const groups: string[] = [];
	for (let r = 0; r < rows; r++) {
		const cells: string[] = [];
		for (let c = 0; c < columns; c++) cells.push(`$${r * columns + c + 1}`);
		groups.push(`(${cells.join(', ')})`);
	}
	return groups.join(', ');
}

/** Upserts foods, then replaces only the portions of the foods in this load. Returns how many went in. */
export async function loadNutrition(
	query: OwnerQuery,
	foods: readonly NutritionFoodRow[],
	portions: readonly NutritionPortionRow[]
): Promise<{ foods: number; portions: number }> {
	for (let i = 0; i < foods.length; i += BATCH) {
		const part = foods.slice(i, i + BATCH);
		const params = part.flatMap((f) => [
			f.id,
			f.source,
			f.dataType,
			f.name,
			f.kcal,
			f.proteinMg,
			f.carbsMg,
			f.sugarMg,
			f.fibreMg,
			f.fatMg,
			f.satFatMg,
			f.sodiumMg,
			JSON.stringify(f.nutrients)
		]);
		await query(
			`insert into nutrition_food (${FOOD_COLUMNS.join(', ')}) values ${placeholders(part.length, FOOD_COLUMNS.length)}
			on conflict (id) do update set ${FOOD_COLUMNS.slice(1)
				.map((c) => `${c} = excluded.${c}`)
				.join(', ')}, loaded_at = now()`,
			params
		);
	}
	for (let i = 0; i < portions.length; i += BATCH) {
		const part = portions.slice(i, i + BATCH);
		await query(
			`insert into nutrition_portion (id, food_id, label, grams_tenths) values ${placeholders(part.length, 4)}
			on conflict (id) do update set label = excluded.label, grams_tenths = excluded.grams_tenths`,
			part.flatMap((p) => [p.id, p.foodId, p.label, p.gramsTenths])
		);
	}
	return { foods: foods.length, portions: portions.length };
}
