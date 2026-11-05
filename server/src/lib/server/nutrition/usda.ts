// READS THE USDA FOODDATA CENTRAL DOWNLOADS (CC0, CREDITED IN THE APP) INTO THE ROWS OF THE SHARED NUTRITION TABLES. NO DATABASE: THE LOADER WRITES THEM.
// Per 100 g, whole numbers, in the units of lib/health/nutrients.ts. A nutrient a food does not list stays unknown. A food with no energy and no macronutrients is skipped.

// -- TYPES -- //
import type { CoreKey } from '../../health/nutrients';
// -- MODULES -- //
import {
	CORE_KEYS,
	kcalFromMacros,
	NUTRIENTS,
	toMilligrams,
	toNanograms,
	USDA_CORE_IDS,
	USDA_ENERGY_IDS
} from '../../health/nutrients';

// -- TYPES -- //

export type NutritionFoodRow = {
	id: string;
	source: 'usda';
	dataType: string;
	name: string;
	kcal: number;
	nutrients: Record<string, number>;
} & Record<CoreKey, number | null>;

export type NutritionPortionRow = {
	id: string;
	foodId: string;
	label: string;
	gramsTenths: number;
};

type RawNutrient = { nutrient?: { id?: number; unitName?: string }; amount?: number };
type RawPortion = {
	gramWeight?: number;
	amount?: number;
	modifier?: string;
	portionDescription?: string;
	measureUnit?: { name?: string; abbreviation?: string };
};
type RawFood = {
	fdcId?: number;
	description?: string;
	foodNutrients?: RawNutrient[];
	foodPortions?: RawPortion[];
};

// -- CONSTANTS -- //

const MAX_KCAL_PER_100G = 900;

// -- FUNCTIONS -- //

/** The kcal of a USDA row, in the order to trust it. A kJ figure is never read as kcal. */
function energyOf(found: ReadonlyMap<number, RawNutrient>): number | null {
	for (const id of USDA_ENERGY_IDS) {
		const n = found.get(id);
		if (n?.amount !== undefined && n.nutrient?.unitName?.toUpperCase() === 'KCAL')
			return Math.round(n.amount);
	}
	return null;
}

function portionsOf(foodId: string, raw: readonly RawPortion[]): NutritionPortionRow[] {
	const out: NutritionPortionRow[] = [];
	raw.forEach((p, i) => {
		if (!p.gramWeight || p.gramWeight <= 0) return;
		const amount = p.amount && p.amount > 0 ? p.amount : 1;
		const unit =
			p.measureUnit?.name && p.measureUnit.name !== 'undetermined' ? p.measureUnit.name : '';
		const label = (p.portionDescription || p.modifier || unit || '').trim().slice(0, 80);
		if (!label || label.toLowerCase().includes('not specified')) return;
		out.push({
			id: `${foodId}:${i}`,
			foodId,
			label: label.toLowerCase(),
			gramsTenths: Math.max(1, Math.round((p.gramWeight / amount) * 10))
		});
	});
	return out;
}

/** One food of a download, or null when it cannot be used. */
export function parseUsdaFood(
	raw: RawFood,
	dataType: string
): { food: NutritionFoodRow; portions: NutritionPortionRow[] } | null {
	if (typeof raw.fdcId !== 'number' || !raw.description) return null;
	const found = new Map<number, RawNutrient>();
	for (const n of raw.foodNutrients ?? [])
		if (typeof n.nutrient?.id === 'number' && typeof n.amount === 'number')
			found.set(n.nutrient.id, n);
	const core = Object.fromEntries(
		CORE_KEYS.map((k) => {
			for (const id of USDA_CORE_IDS[k]) {
				const n = found.get(id);
				if (n?.amount !== undefined) {
					const mg = toMilligrams(n.amount, n.nutrient?.unitName ?? '');
					if (mg !== null) return [k, mg];
				}
			}
			return [k, null];
		})
	) as Record<CoreKey, number | null>;
	const nutrients: Record<string, number> = {};
	for (const def of NUTRIENTS) {
		const n = found.get(def.usda);
		if (n?.amount === undefined) continue;
		const ng = toNanograms(n.amount, n.nutrient?.unitName ?? '');
		if (ng !== null) nutrients[def.code] = ng;
	}
	let kcal = energyOf(found);
	if (kcal === null && core.proteinMg !== null && core.carbsMg !== null && core.fatMg !== null)
		kcal = kcalFromMacros(core.proteinMg, core.carbsMg, core.fatMg);
	if (kcal === null || kcal < 0 || kcal > MAX_KCAL_PER_100G) return null;
	const id = `usda:${raw.fdcId}`;
	return {
		food: {
			id,
			source: 'usda',
			dataType,
			name: raw.description.trim().slice(0, 200),
			kcal,
			...core,
			nutrients
		},
		portions: portionsOf(id, raw.foodPortions ?? [])
	};
}

/** All the foods of one downloaded file, whichever of the three it is. */
export function parseUsdaFile(json: unknown): {
	foods: NutritionFoodRow[];
	portions: NutritionPortionRow[];
} {
	const lists: [string, string][] = [
		['FoundationFoods', 'foundation'],
		['SRLegacyFoods', 'sr_legacy'],
		['SurveyFoods', 'survey']
	];
	const foods: NutritionFoodRow[] = [];
	const portions: NutritionPortionRow[] = [];
	for (const [key, dataType] of lists) {
		const list = (json as Record<string, unknown>)[key];
		if (!Array.isArray(list)) continue;
		for (const raw of list as RawFood[]) {
			const parsed = parseUsdaFood(raw, dataType);
			if (!parsed) continue;
			foods.push(parsed.food);
			portions.push(...parsed.portions);
		}
	}
	return { foods, portions };
}

/** The order the data types are preferred in a shortlist. */
export const DATA_TYPE_ORDER: readonly string[] = ['foundation', 'sr_legacy', 'survey'];
