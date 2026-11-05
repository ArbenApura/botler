// NUTRIENTS (BTL-20261105-0015, P3): THE ONE LIST OF WHAT IS TRACKED AND IN WHICH UNIT, AND THE WHOLE-NUMBER SUMS. PURE: NO DATABASE.
// The main nutrients are milligrams in their own columns. Everything else is a map from a fixed code to whole nanograms, so vitamin B12 at 0.04 micrograms survives,
// and units can never be mixed: one code always means one scale. Unknown is left out or null, and is never counted as zero.

// -- TYPES -- //

export type DisplayUnit = 'mg' | 'µg';

export type NutrientDef = { code: string; label: string; unit: DisplayUnit; usda: number };

export type CoreKey =
	'proteinMg' | 'carbsMg' | 'sugarMg' | 'fibreMg' | 'fatMg' | 'satFatMg' | 'sodiumMg';

/** What a food holds per 100 g. */
export type FoodFacts = { kcal: number; nutrients: Record<string, number> } & Record<
	CoreKey,
	number | null
>;

/** What an amount of a food holds, or a whole entry. */
export type FoodNumbers = FoodFacts;

export type DayTotals = {
	kcal: number;
	lowKcal: number;
	highKcal: number;
	foods: number;
	core: Record<CoreKey, { mg: number; unknownFoods: number }>;
	/** Only codes at least one food knows. */
	nutrients: { code: string; label: string; unit: DisplayUnit; ng: number; knownFoods: number }[];
};

// -- CONSTANTS -- //

export const CORE_KEYS: readonly CoreKey[] = [
	'proteinMg',
	'carbsMg',
	'sugarMg',
	'fibreMg',
	'fatMg',
	'satFatMg',
	'sodiumMg'
];

/** Energy, in the order to trust it: kcal as listed, then the two Atwater figures Foundation Foods gives. */
export const USDA_ENERGY_IDS: readonly number[] = [1008, 2047, 2048];

/** The USDA nutrient number behind each main nutrient. Sugars have two numbers across its data types. */
export const USDA_CORE_IDS: Record<CoreKey, readonly number[]> = {
	proteinMg: [1003],
	carbsMg: [1005, 1050],
	sugarMg: [2000, 1063],
	fibreMg: [1079],
	fatMg: [1004, 1085],
	satFatMg: [1258],
	sodiumMg: [1093]
};

export const NUTRIENTS: readonly NutrientDef[] = [
	{ code: 'potassium', label: 'Potassium', unit: 'mg', usda: 1092 },
	{ code: 'calcium', label: 'Calcium', unit: 'mg', usda: 1087 },
	{ code: 'iron', label: 'Iron', unit: 'mg', usda: 1089 },
	{ code: 'magnesium', label: 'Magnesium', unit: 'mg', usda: 1090 },
	{ code: 'phosphorus', label: 'Phosphorus', unit: 'mg', usda: 1091 },
	{ code: 'zinc', label: 'Zinc', unit: 'mg', usda: 1095 },
	{ code: 'copper', label: 'Copper', unit: 'mg', usda: 1098 },
	{ code: 'selenium', label: 'Selenium', unit: 'µg', usda: 1103 },
	{ code: 'cholesterol', label: 'Cholesterol', unit: 'mg', usda: 1253 },
	{ code: 'vitamin_a', label: 'Vitamin A', unit: 'µg', usda: 1106 },
	{ code: 'vitamin_c', label: 'Vitamin C', unit: 'mg', usda: 1162 },
	{ code: 'vitamin_d', label: 'Vitamin D', unit: 'µg', usda: 1114 },
	{ code: 'vitamin_e', label: 'Vitamin E', unit: 'mg', usda: 1109 },
	{ code: 'vitamin_k', label: 'Vitamin K', unit: 'µg', usda: 1185 },
	{ code: 'thiamin', label: 'Thiamin', unit: 'mg', usda: 1165 },
	{ code: 'riboflavin', label: 'Riboflavin', unit: 'mg', usda: 1166 },
	{ code: 'niacin', label: 'Niacin', unit: 'mg', usda: 1167 },
	{ code: 'vitamin_b6', label: 'Vitamin B6', unit: 'mg', usda: 1175 },
	{ code: 'folate', label: 'Folate', unit: 'µg', usda: 1177 },
	{ code: 'vitamin_b12', label: 'Vitamin B12', unit: 'µg', usda: 1178 }
];

const BY_CODE = new Map(NUTRIENTS.map((n) => [n.code, n]));

const UNIT_TO_NG: Record<string, number> = { G: 1e9, MG: 1e6, UG: 1e3 };

/** How wide a calorie estimate is, in percent either way, by where it came from. */
export const RANGE_PERCENT = { database: 15, printed: 5, estimate: 30, rough: 25 } as const;

// -- FUNCTIONS -- //

export const isNutrientCode = (code: string): boolean => BY_CODE.has(code);

/** A source's amount in nanograms, or null for a unit that has no sure conversion (IU is left out on purpose). */
export function toNanograms(amount: number, unit: string): number | null {
	const factor = UNIT_TO_NG[unit.toUpperCase()];
	return factor === undefined ? null : Math.round(amount * factor);
}

/** A source's amount in milligrams, or null. */
export function toMilligrams(amount: number, unit: string): number | null {
	const ng = toNanograms(amount, unit);
	return ng === null ? null : Math.round(ng / 1e6);
}

const scale = (per100: number, grams: number) => Math.round((per100 * grams) / 100);

/** What an amount of a food holds. Rounded once, here. Unknown stays unknown. */
export function scaleFood(per100: FoodFacts, grams: number): FoodNumbers {
	const core = Object.fromEntries(
		CORE_KEYS.map((k) => {
			const v = per100[k];
			return [k, v === null ? null : scale(v, grams)];
		})
	) as Record<CoreKey, number | null>;
	return {
		kcal: scale(per100.kcal, grams),
		...core,
		nutrients: Object.fromEntries(
			Object.entries(per100.nutrients).map(([code, ng]) => [code, scale(ng, grams)])
		)
	};
}

/** Calories worked out from the three macronutrients, in milligrams. */
export const kcalFromMacros = (proteinMg: number, carbsMg: number, fatMg: number): number =>
	Math.round((proteinMg * 4 + carbsMg * 4 + fatMg * 9) / 1000);

/** Whether stated calories fit the protein, carbs and fat: within 20%, and never fussy about small numbers. */
export function kcalFits(kcal: number, proteinMg: number, carbsMg: number, fatMg: number): boolean {
	const worked = kcalFromMacros(proteinMg, carbsMg, fatMg);
	return Math.abs(kcal - worked) <= Math.max(30, worked * 0.2);
}

/** The low and high of a calorie estimate. */
export function rangeOf(kcal: number, percent: number): { lowKcal: number; highKcal: number } {
	return {
		lowKcal: Math.round((kcal * (100 - percent)) / 100),
		highKcal: Math.round((kcal * (100 + percent)) / 100)
	};
}

/** The totals of a day. Each nutrient says how many foods did not know it, so a low number can be read for what it is. */
export function addUp(
	entries: readonly (FoodNumbers & { lowKcal: number; highKcal: number })[]
): DayTotals {
	const core = Object.fromEntries(
		CORE_KEYS.map((k) => [k, { mg: 0, unknownFoods: 0 }])
	) as DayTotals['core'];
	const map = new Map<string, { ng: number; knownFoods: number }>();
	let kcal = 0;
	let lowKcal = 0;
	let highKcal = 0;
	for (const e of entries) {
		kcal += e.kcal;
		lowKcal += e.lowKcal;
		highKcal += e.highKcal;
		for (const k of CORE_KEYS) {
			const v = e[k];
			if (v === null) core[k].unknownFoods += 1;
			else core[k].mg += v;
		}
		for (const [code, ng] of Object.entries(e.nutrients)) {
			const seen = map.get(code) ?? { ng: 0, knownFoods: 0 };
			map.set(code, { ng: seen.ng + ng, knownFoods: seen.knownFoods + 1 });
		}
	}
	const nutrients = NUTRIENTS.flatMap((n) => {
		const seen = map.get(n.code);
		return seen ? [{ code: n.code, label: n.label, unit: n.unit, ...seen }] : [];
	});
	return { kcal, lowKcal, highKcal, foods: entries.length, core, nutrients };
}
