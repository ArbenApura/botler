// FOOD VERBS (BTL-20261105-0015, P3): FIND A FOOD, LOG A MEAL, FIX IT, SAVE A FOOD, AND THE DAY'S TOTALS.
// The server works out every number from grams and the food's values, and each entry keeps its numbers, so a later import or a changed saved food never moves a past day.
// Food is not part of the money plan: a delete here sits outside the three-delete cap, and it answers the removed row.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { BarcodeProduct } from '../fooddata/barcode';
import type {
	BarcodeLookupInput,
	DayMarkInput,
	FoodArchiveInput,
	FoodDayInput,
	FoodDeleteInput,
	FoodEditInput,
	FoodSaveInput,
	FoodSearchInput,
	MealItemInput,
	MealLogInput
} from '../db/zod';
import type { FoodSource, MealKind } from '../db/schema';
import type { FoodFacts, FoodNumbers } from '../../health/nutrients';
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { randomUUID } from 'node:crypto';
import { and, desc, eq, inArray, isNull, sql } from 'drizzle-orm';
// -- MODULES -- //
import { toLocalDate } from '../../finance/dates';
import { englishTerm, filipinoById, searchFilipino } from '../../health/filipino';
import {
	addUp,
	CORE_KEYS,
	isNutrientCode,
	kcalFits,
	kcalFromMacros,
	RANGE_PERCENT,
	rangeOf,
	scaleFood
} from '../../health/nutrients';
import {
	dayStatus,
	foodEntry,
	foodItem,
	healthGoal,
	nutritionFood,
	nutritionPortion
} from '../db/schema';
import {
	barcodeLookupInput,
	dayMarkInput,
	foodArchiveInput,
	foodDayInput,
	foodDeleteInput,
	foodEditInput,
	foodSaveInput,
	foodSearchInput,
	mealLogInput
} from '../db/zod';
import { checkBarcode, lookupBarcode } from '../fooddata/barcode';
import { DATA_TYPE_ORDER } from '../nutrition/usda';
import { OpsError, run, runWrite } from './context';
import { mapped, parse, plain } from './shared';

// -- TYPES -- //

export type FoodHit = {
	id: string;
	name: string;
	source: 'saved' | 'filipino' | 'usda';
	kcalPer100g: number;
	proteinMgPer100g: number | null;
	portions: { label: string; grams: number }[];
	/** An estimate written for the starter list rather than a measured value. */
	estimate: boolean;
};

type ResolvedFood = {
	name: string;
	facts: FoodFacts;
	source: FoodSource;
	sourceRef: string | null;
	foodItemId: string | null;
	rangePercent: number;
	portions: { label: string; grams: number }[];
	servingG: number | null;
};

// -- CONSTANTS -- //

const MAX_HITS = 5;
const ENTRY_COLUMNS = {
	id: foodEntry.id,
	day: foodEntry.day,
	meal: foodEntry.meal,
	mealGroup: foodEntry.mealGroup,
	name: foodEntry.name,
	grams: foodEntry.grams,
	kcal: foodEntry.kcal,
	lowKcal: foodEntry.lowKcal,
	highKcal: foodEntry.highKcal,
	proteinMg: foodEntry.proteinMg,
	carbsMg: foodEntry.carbsMg,
	sugarMg: foodEntry.sugarMg,
	fibreMg: foodEntry.fibreMg,
	fatMg: foodEntry.fatMg,
	satFatMg: foodEntry.satFatMg,
	sodiumMg: foodEntry.sodiumMg,
	nutrients: foodEntry.nutrients,
	sourceKind: foodEntry.sourceKind,
	foodItemId: foodEntry.foodItemId,
	byAgent: foodEntry.byAgent,
	version: foodEntry.version
};

// -- FUNCTIONS -- //

/** Rows that are per 100 g, as facts. */
const factsOf = (r: FoodFacts): FoodFacts => ({
	kcal: r.kcal,
	proteinMg: r.proteinMg,
	carbsMg: r.carbsMg,
	sugarMg: r.sugarMg,
	fibreMg: r.fibreMg,
	fatMg: r.fatMg,
	satFatMg: r.satFatMg,
	sodiumMg: r.sodiumMg,
	nutrients: r.nutrients
});

/** Nearly identical rows ("Rice, white, cooked" three times over) become one line in a shortlist. */
const collapseKey = (name: string) => name.toLowerCase().split(',').slice(0, 2).join(',').trim();

async function usdaHits(tx: Tx, query: string): Promise<FoodHit[]> {
	const term = englishTerm(query);
	const rows = await tx
		.select({
			id: nutritionFood.id,
			name: nutritionFood.name,
			kcal: nutritionFood.kcal,
			proteinMg: nutritionFood.proteinMg,
			dataType: nutritionFood.dataType,
			score: sql<number>`word_similarity(${term}, ${nutritionFood.name})`
		})
		.from(nutritionFood)
		.where(sql`${term} <% ${nutritionFood.name}`)
		.orderBy(
			desc(sql`word_similarity(${term}, ${nutritionFood.name})`),
			sql`length(${nutritionFood.name})`
		)
		.limit(40);
	const best = new Map<string, (typeof rows)[number]>();
	for (const r of rows) {
		const key = collapseKey(r.name);
		const seen = best.get(key);
		if (!seen || DATA_TYPE_ORDER.indexOf(r.dataType) < DATA_TYPE_ORDER.indexOf(seen.dataType))
			best.set(key, r);
	}
	const hits = [...best.values()].slice(0, MAX_HITS);
	const portions = hits.length
		? await tx
				.select()
				.from(nutritionPortion)
				.where(
					inArray(
						nutritionPortion.foodId,
						hits.map((h) => h.id)
					)
				)
		: [];
	return hits.map((h) => ({
		id: h.id,
		name: h.name,
		source: 'usda' as const,
		kcalPer100g: h.kcal,
		proteinMgPer100g: h.proteinMg,
		estimate: false,
		portions: portions
			.filter((p) => p.foodId === h.id)
			.slice(0, 6)
			.map((p) => ({ label: p.label, grams: Math.round(p.gramsTenths / 10) }))
	}));
}

/** Words that say how much or how, not which food. */
const FILLER_WORDS = new Set([
	'and',
	'the',
	'with',
	'for',
	'cup',
	'cups',
	'glass',
	'piece',
	'pieces',
	'small',
	'large',
	'medium',
	'regular',
	'plain',
	'serving',
	'bowl',
	'plate',
	'some',
	'one',
	'two'
]);

/** The words of a food name that say which food it is, lower case, with a trailing s taken off. */
const foodWords = (text: string): string[] =>
	(text.toLowerCase().match(/\p{L}{3,}/gu) ?? [])
		.filter((w) => !FILLER_WORDS.has(w))
		.map((w) => w.replace(/s$/, ''));

/**
 * The words of the searched name that no listed hit holds, or null when some hit holds all of them (in the name as typed or in its English
 * form). "Greek yogurt Pascual" against "Yogurt, Greek, plain, nonfat" is missing pascual: a brand miss. Pure.
 */
export function missingWords(
	query: string,
	english: string,
	hitNames: readonly string[]
): string[] | null {
	const asked = foodWords(query);
	if (asked.length === 0) return null;
	const inEnglish = foodWords(english);
	let closest: string[] = asked;
	for (const hit of hitNames) {
		const have = foodWords(hit).join(' ');
		const lack = (words: string[]) => words.filter((w) => !have.includes(w));
		const a = lack(asked);
		const e = lack(inEnglish);
		if (a.length === 0 || (inEnglish.length > 0 && e.length === 0)) return null;
		if (a.length < closest.length) closest = a;
	}
	return closest;
}

/** The person's own saved foods, then the Filipino list, then the public data, at most five for each name. */
export async function searchFoods(ctx: Ctx, raw: FoodSearchInput) {
	const { names } = parse(foodSearchInput, raw);
	return run(ctx, async (tx, userId) => {
		const results = [];
		for (const name of names) {
			const saved = await tx
				.select()
				.from(foodItem)
				.where(
					and(
						eq(foodItem.userId, userId),
						isNull(foodItem.archivedAt),
						sql`${foodItem.name} ilike ${`%${name.replace(/[%_\\]/g, '')}%`}`
					)
				)
				.limit(MAX_HITS);
			const hits: FoodHit[] = saved.map((s) => ({
				id: `saved:${s.id}`,
				name: s.name,
				source: 'saved',
				kcalPer100g: s.kcal,
				proteinMgPer100g: s.proteinMg,
				estimate: false,
				portions: s.servingG ? [{ label: 'serving', grams: s.servingG }] : []
			}));
			for (const f of searchFilipino(name, MAX_HITS))
				hits.push({
					id: f.id,
					name: f.name,
					source: 'filipino',
					kcalPer100g: f.facts.kcal,
					proteinMgPer100g: f.facts.proteinMg,
					estimate: true,
					portions: [{ label: 'serving', grams: f.servingG }]
				});
			if (hits.length < MAX_HITS) hits.push(...(await usdaHits(tx, name)));
			const shown = hits.slice(0, MAX_HITS);
			const missing = missingWords(
				name,
				englishTerm(name),
				shown.map((h) => h.name)
			);
			results.push({
				name,
				hits: shown,
				// No hit holds every word of the name: they are the closest names only, perhaps a different product (a brand search that
				// returned the plain food). The assistant is told so and goes to the web
				...(missing
					? {
							matched: 'partial' as const,
							note: `No food in the database matches every word of "${name}" (missing: ${missing.join(', ')}). ${shown.length > 0 ? 'The hits are only the closest names and may be a different product: do not present one as the exact food. ' : ''}Search the web for the exact product (web_search), or ask the person for its label.`
						}
					: {})
			});
		}
		return results;
	});
}

/** Products scanned for this call, looked up before the transaction so an outside service never holds the person's lock. */
type Scanned = ReadonlyMap<string, BarcodeProduct>;

async function scannedFor(items: readonly MealItemInput[]): Promise<Scanned> {
	const out = new Map<string, BarcodeProduct>();
	for (const item of items) {
		if (!item.foodId?.startsWith('barcode:')) continue;
		const answer = await lookupBarcode(checkBarcode(item.foodId.slice('barcode:'.length)));
		if (answer.found) out.set(item.foodId, answer.product);
	}
	return out;
}

/** Finds a food by the id a search gave. An id that is not a real food is refused, so a made-up one cannot be logged. */
async function resolveFood(
	tx: Tx,
	userId: string,
	id: string,
	scanned: Scanned
): Promise<ResolvedFood> {
	const unknown = () =>
		new OpsError(
			'INVALID',
			`There is no food with the id "${id.slice(0, 60)}". Search for it first.`
		);
	if (id.startsWith('saved:')) {
		const itemId = id.slice('saved:'.length);
		if (!/^[0-9a-f-]{36}$/i.test(itemId)) throw unknown();
		const [s] = await tx
			.select()
			.from(foodItem)
			.where(and(eq(foodItem.userId, userId), eq(foodItem.id, itemId)));
		if (!s) throw unknown();
		return {
			name: s.name,
			facts: factsOf(s),
			source: 'saved',
			sourceRef: null,
			foodItemId: s.id,
			rangePercent: RANGE_PERCENT.printed,
			portions: s.servingG ? [{ label: 'serving', grams: s.servingG }] : [],
			servingG: s.servingG
		};
	}
	if (id.startsWith('barcode:')) {
		const p = scanned.get(id);
		if (!p) throw unknown();
		return {
			name: p.name,
			facts: p.facts,
			source: p.source,
			sourceRef: p.barcode,
			foodItemId: null,
			rangePercent: RANGE_PERCENT.printed,
			portions: [
				...(p.servingG ? [{ label: 'serving', grams: p.servingG }] : []),
				...(p.packG ? [{ label: 'pack', grams: p.packG }] : [])
			],
			servingG: p.servingG
		};
	}
	if (id.startsWith('fil:')) {
		const f = filipinoById(id);
		if (!f) throw unknown();
		return {
			name: f.name,
			facts: f.facts,
			source: 'filipino',
			sourceRef: id,
			foodItemId: null,
			rangePercent: RANGE_PERCENT.estimate,
			portions: [{ label: 'serving', grams: f.servingG }],
			servingG: f.servingG
		};
	}
	if (id.startsWith('usda:')) {
		const [n] = await tx.select().from(nutritionFood).where(eq(nutritionFood.id, id));
		if (!n) throw unknown();
		const portions = await tx
			.select()
			.from(nutritionPortion)
			.where(eq(nutritionPortion.foodId, id));
		return {
			name: n.name,
			facts: factsOf(n),
			source: 'usda',
			sourceRef: id,
			foodItemId: null,
			rangePercent: RANGE_PERCENT.database,
			portions: portions.map((p) => ({ label: p.label, grams: Math.round(p.gramsTenths / 10) })),
			servingG: null
		};
	}
	throw unknown();
}

/** Grams from what was said: grams, or a count of a household amount the food has. Otherwise the caller says what is missing. */
function gramsFor(item: MealItemInput, food: ResolvedFood): number {
	if (item.grams !== undefined) return item.grams;
	if (item.portion) {
		const want = item.portion.toLowerCase();
		const p =
			food.portions.find((x) => x.label === want) ??
			food.portions.find((x) => x.label.includes(want));
		if (!p)
			throw new OpsError(
				'INVALID',
				`"${food.name}" has no "${item.portion}" amount${food.portions.length ? `. It has: ${food.portions.map((x) => x.label).join(', ')}` : ''}. Give grams instead.`
			);
		return Math.max(1, Math.round(p.grams * (item.count ?? 1)));
	}
	if (food.servingG) return Math.max(1, Math.round(food.servingG * (item.count ?? 1)));
	throw new OpsError('INVALID', `Say how much "${food.name}" there was, in grams.`);
}

/** The row of one item. Every number comes from here. */
type EntryNumbers = {
	name: string;
	grams: number | null;
	numbers: FoodNumbers;
	lowKcal: number;
	highKcal: number;
	sourceKind: FoodSource;
	sourceRef: string | null;
	foodItemId: string | null;
	/** Label values: the basis they were read on and whether calories fit the macronutrients. */
	label?: { basisGrams: number; fits: boolean; per100: FoodFacts };
};

/** What a label says, turned to per 100 g. kJ becomes kcal once. The person checks all of it on the card. */
function labelFacts(l: NonNullable<MealItemInput['label']>): FoodFacts {
	const kcal = l.kcal ?? (l.kilojoules === undefined ? null : Math.round(l.kilojoules / 4.184));
	if (kcal === null) throw new OpsError('INVALID', 'A label needs its calories or kilojoules.');
	const per100 = (v: number | undefined) =>
		v === undefined ? null : Math.round((v * 100) / l.basisGrams);
	return {
		kcal: per100(kcal) ?? 0,
		proteinMg: per100(l.proteinMg),
		carbsMg: per100(l.carbsMg),
		sugarMg: per100(l.sugarMg),
		fibreMg: per100(l.fibreMg),
		fatMg: per100(l.fatMg),
		satFatMg: per100(l.satFatMg),
		sodiumMg: per100(l.sodiumMg),
		nutrients: {}
	};
}

async function entryFor(
	tx: Tx,
	userId: string,
	item: MealItemInput,
	scanned: Scanned
): Promise<EntryNumbers> {
	if (item.label) {
		const l = item.label;
		const per100 = labelFacts(l);
		const grams =
			item.grams ?? Math.max(1, Math.round((l.servingG ?? l.basisGrams) * (item.count ?? 1)));
		const numbers = scaleFood(per100, grams);
		return {
			name: l.name,
			grams,
			numbers,
			...rangeOf(numbers.kcal, RANGE_PERCENT.printed),
			sourceKind: 'label',
			sourceRef: l.barcode ?? null,
			foodItemId: null,
			label: {
				basisGrams: l.basisGrams,
				per100,
				fits:
					per100.proteinMg === null || per100.carbsMg === null || per100.fatMg === null
						? true
						: kcalFits(per100.kcal, per100.proteinMg, per100.carbsMg, per100.fatMg)
			}
		};
	}
	if (item.foodId) {
		const food = await resolveFood(tx, userId, item.foodId, scanned);
		const grams = gramsFor(item, food);
		const numbers = scaleFood(food.facts, grams);
		const range = rangeOf(numbers.kcal, food.rangePercent);
		return {
			name: food.name,
			grams,
			numbers,
			lowKcal: item.lowGrams
				? Math.min(numbers.kcal, Math.round((food.facts.kcal * item.lowGrams) / 100))
				: range.lowKcal,
			highKcal: item.highGrams
				? Math.max(numbers.kcal, Math.round((food.facts.kcal * item.highGrams) / 100))
				: range.highKcal,
			sourceKind: food.source,
			sourceRef: food.sourceRef,
			foodItemId: food.foodItemId
		};
	}
	const empty: Omit<FoodNumbers, 'kcal'> = {
		proteinMg: null,
		carbsMg: null,
		sugarMg: null,
		fibreMg: null,
		fatMg: null,
		satFatMg: null,
		sodiumMg: null,
		nutrients: {}
	};
	if (item.estimate) {
		// The assistant's guess of the three macronutrients. The calories are worked out here, the range is wide and nothing else is claimed
		const proteinMg = Math.round(item.estimate.proteinG * 1000);
		const carbsMg = Math.round(item.estimate.carbsG * 1000);
		const fatMg = Math.round(item.estimate.fatG * 1000);
		const kcal = kcalFromMacros(proteinMg, carbsMg, fatMg);
		return {
			name: item.estimate.name,
			grams: item.grams ?? null,
			numbers: { ...empty, kcal, proteinMg, carbsMg, fatMg },
			...rangeOf(kcal, RANGE_PERCENT.estimate),
			sourceKind: 'estimate',
			sourceRef: null,
			foodItemId: null
		};
	}
	if (item.rough) {
		return {
			name: item.rough.name,
			grams: null,
			numbers: { ...empty, kcal: item.rough.kcal },
			...rangeOf(item.rough.kcal, RANGE_PERCENT.rough),
			sourceKind: 'rough',
			sourceRef: null,
			foodItemId: null
		};
	}
	if (item.manual) {
		const m = item.manual;
		return {
			name: m.name,
			grams: item.grams ?? null,
			numbers: {
				...empty,
				kcal: m.kcal,
				proteinMg: m.proteinMg ?? null,
				carbsMg: m.carbsMg ?? null,
				fatMg: m.fatMg ?? null
			},
			...rangeOf(m.kcal, RANGE_PERCENT.printed),
			sourceKind: 'manual',
			sourceRef: null,
			foodItemId: null
		};
	}
	throw new OpsError('INVALID', 'Name a food from a search, or give a rough total.');
}

/** Every item's numbers. A total weight from a kitchen scale scales the foods that have grams, so they add up to it. */
async function entriesFor(
	tx: Tx,
	userId: string,
	input: MealLogInput,
	scanned: Scanned
): Promise<EntryNumbers[]> {
	const first = [];
	for (const item of input.items) first.push(await entryFor(tx, userId, item, scanned));
	if (input.totalG === undefined) return first;
	const sum = first.reduce((a, e) => a + (e.grams ?? 0), 0);
	if (sum <= 0) return first;
	const out = [];
	for (const [i, item] of input.items.entries()) {
		const grams = first[i]?.grams;
		if (!grams) {
			const same = first[i];
			if (same) out.push(same);
			continue;
		}
		const {
			lowGrams: _low,
			highGrams: _high,
			portion: _portion,
			count: _count,
			...plainItem
		} = item;
		out.push(
			await entryFor(
				tx,
				userId,
				{ ...plainItem, grams: Math.max(1, Math.round((grams * input.totalG) / sum)) },
				scanned
			)
		);
	}
	return out;
}

/** What a meal would log, with every number, writing nothing. The review screen and the card read this. */
export async function previewMeal(ctx: Ctx, raw: MealLogInput) {
	const input = parse(mealLogInput, raw);
	const scanned = await scannedFor(input.items);
	return run(ctx, async (tx, userId) => {
		const entries = await entriesFor(tx, userId, input, scanned);
		const add = (f: (e: EntryNumbers) => number | null) =>
			entries.reduce((a, e) => a + (f(e) ?? 0), 0);
		return {
			items: entries.map((e) => ({
				name: e.name,
				grams: e.grams,
				kcal: e.numbers.kcal,
				lowKcal: e.lowKcal,
				highKcal: e.highKcal,
				proteinMg: e.numbers.proteinMg,
				carbsMg: e.numbers.carbsMg,
				fatMg: e.numbers.fatMg,
				sourceKind: e.sourceKind,
				...(e.label ? { basisGrams: e.label.basisGrams, fits: e.label.fits } : {})
			})),
			kcal: add((e) => e.numbers.kcal),
			lowKcal: add((e) => e.lowKcal),
			highKcal: add((e) => e.highKcal),
			proteinMg: add((e) => e.numbers.proteinMg),
			carbsMg: add((e) => e.numbers.carbsMg),
			fatMg: add((e) => e.numbers.fatMg)
		};
	});
}

/** The words of a meal card: each food with its amount and calories, so the person sees what approving writes. */
export async function mealCardSummary(ctx: Ctx, args: MealLogInput): Promise<string> {
	const p = await previewMeal(ctx, args);
	const parts = p.items.map(
		(i) =>
			`${i.name}${i.grams ? ` ${i.grams} g` : ''}, about ${i.kcal} kcal${i.sourceKind === 'estimate' ? ' (an AI estimate)' : ''}`
	);
	return `Log this food: ${parts.join('; ')}. About ${p.kcal} kcal in all (could be ${p.lowKcal} to ${p.highKcal}), ${mealSourceWords(p.items.map((i) => i.sourceKind))}, so check the amounts.`;
}

/** Where a meal's numbers came from, in words for its card: not "from a photo" for a meal the assistant only worked out from the person's words. */
export function mealSourceWords(kinds: readonly string[]): string {
	if (kinds.length > 0 && kinds.every((k) => k === 'estimate'))
		return 'an AI estimate from what you said';
	if (kinds.some((k) => k === 'estimate'))
		return 'partly an AI estimate, partly from a photo, a label or the food list';
	return 'from a photo, a label or the food list';
}

/** A barcode: the person's saved food first, then the outside sources. Numbers and a short clean name only. */
export async function barcodeLookup(ctx: Ctx, raw: BarcodeLookupInput) {
	const { barcode } = parse(barcodeLookupInput, raw);
	const [saved] = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(foodItem)
			.where(
				and(eq(foodItem.userId, userId), eq(foodItem.barcode, barcode), isNull(foodItem.archivedAt))
			)
			.limit(1)
	);
	if (saved)
		return {
			found: true,
			id: `saved:${saved.id}`,
			source: 'saved',
			name: saved.name,
			kcalPer100g: saved.kcal,
			servingG: saved.servingG,
			packG: null,
			facts: factsOf(saved),
			notConfigured: []
		};
	const answer = await lookupBarcode(barcode);
	if (!answer.found) return answer;
	const p = answer.product;
	return {
		found: true,
		id: p.id,
		source: p.source,
		name: p.name,
		kcalPer100g: p.facts.kcal,
		servingG: p.servingG,
		packG: p.packG,
		facts: p.facts,
		notConfigured: answer.notConfigured
	};
}

/** The meal for a time of day, when the caller does not say. */
export function mealForHour(hour: number): MealKind {
	if (hour < 10) return 'breakfast';
	if (hour < 15) return 'lunch';
	if (hour < 18) return 'merienda';
	return 'dinner';
}

const manilaHour = (d: Date) => (d.getUTCHours() + 8) % 24;

async function saveLabelFood(tx: Tx, userId: string, e: EntryNumbers): Promise<string | null> {
	const per100 = e.label?.per100;
	if (!per100) return null;
	const values = {
		name: e.name,
		barcode: e.sourceRef,
		source: 'label' as const,
		kcal: Math.min(per100.kcal, 900),
		proteinMg: per100.proteinMg,
		carbsMg: per100.carbsMg,
		sugarMg: per100.sugarMg,
		fibreMg: per100.fibreMg,
		fatMg: per100.fatMg,
		satFatMg: per100.satFatMg,
		sodiumMg: per100.sodiumMg,
		servingG: e.grams
	};
	const [same] = await tx
		.select({ id: foodItem.id })
		.from(foodItem)
		.where(
			and(
				eq(foodItem.userId, userId),
				isNull(foodItem.archivedAt),
				e.sourceRef ? eq(foodItem.barcode, e.sourceRef) : eq(foodItem.name, e.name)
			)
		);
	if (same) {
		await tx
			.update(foodItem)
			.set({ ...values, version: sql`${foodItem.version} + 1`, updatedAt: new Date() })
			.where(and(eq(foodItem.userId, userId), eq(foodItem.id, same.id)));
		return same.id;
	}
	const [made] = await tx
		.insert(foodItem)
		.values({ userId, ...values })
		.returning({ id: foodItem.id });
	return made?.id ?? null;
}

/** One meal of one or more foods, on a Manila date (today when none is given). */
export async function logMeal(ctx: Ctx, raw: MealLogInput) {
	const input = parse(mealLogInput, raw);
	const scanned = await scannedFor(input.items);
	return mapped(() =>
		runWrite(ctx, 'food.meal_log', input, async (tx, userId) => {
			const now = new Date();
			const day = input.day ?? toLocalDate(now);
			const meal = input.meal ?? mealForHour(manilaHour(now));
			const mealGroup = randomUUID();
			const made = [];
			for (const e of await entriesFor(tx, userId, input, scanned)) {
				// A product read from its label is saved for next time, under the name the person saw on the card
				const savedId = e.label ? await saveLabelFood(tx, userId, e) : e.foodItemId;
				const [row] = await tx
					.insert(foodEntry)
					.values({
						userId,
						day,
						meal,
						mealGroup,
						name: e.name,
						grams: e.grams,
						kcal: e.numbers.kcal,
						lowKcal: e.lowKcal,
						highKcal: e.highKcal,
						proteinMg: e.numbers.proteinMg,
						carbsMg: e.numbers.carbsMg,
						sugarMg: e.numbers.sugarMg,
						fibreMg: e.numbers.fibreMg,
						fatMg: e.numbers.fatMg,
						satFatMg: e.numbers.satFatMg,
						sodiumMg: e.numbers.sodiumMg,
						nutrients: e.numbers.nutrients,
						sourceKind: e.sourceKind,
						sourceRef: e.sourceRef,
						foodItemId: savedId,
						byAgent: ctx.actor.kind === 'agent' || ctx.onBehalfOf === 'agent'
					})
					.returning(ENTRY_COLUMNS);
				if (row) made.push(row);
			}
			return {
				day,
				meal,
				entries: plain(made),
				kcal: made.reduce((a, e) => a + e.kcal, 0),
				lowKcal: made.reduce((a, e) => a + e.lowKcal, 0),
				highKcal: made.reduce((a, e) => a + e.highKcal, 0),
				today: await readDay(tx, userId, day)
			};
		})
	);
}

/** A day's food with its totals, the target and what is left. */
export async function readDay(tx: Tx, userId: string, day: string) {
	const rows = await tx
		.select(ENTRY_COLUMNS)
		.from(foodEntry)
		.where(and(eq(foodEntry.userId, userId), eq(foodEntry.day, day)))
		.orderBy(foodEntry.createdAt);
	const [status] = await tx
		.select({ complete: dayStatus.complete })
		.from(dayStatus)
		.where(and(eq(dayStatus.userId, userId), eq(dayStatus.day, day)));
	const [goal] = await tx
		.select({ targetKcal: healthGoal.targetKcal })
		.from(healthGoal)
		.where(eq(healthGoal.userId, userId));
	const totals = addUp(rows);
	const targetKcal = goal?.targetKcal ?? null;
	return {
		day,
		complete: status?.complete ?? false,
		targetKcal,
		leftKcal: targetKcal === null ? null : targetKcal - totals.kcal,
		totals,
		entries: plain(rows)
	};
}

export async function getFoodDay(ctx: Ctx, raw: FoodDayInput) {
	const { day } = parse(foodDayInput, raw);
	return run(ctx, (tx, userId) => readDay(tx, userId, day ?? toLocalDate(new Date())));
}

/** Changes an entry. New grams scale its own stored numbers; a manual or rough entry may have its calories set. */
export async function editFood(ctx: Ctx, raw: FoodEditInput) {
	const input = parse(foodEditInput, raw);
	return mapped(() =>
		runWrite(ctx, 'food.edit', input, async (tx, userId) => {
			const [e] = await tx
				.select()
				.from(foodEntry)
				.where(and(eq(foodEntry.userId, userId), eq(foodEntry.id, input.entryId)));
			if (!e) throw new OpsError('NOT_FOUND', 'That food entry is not there any more.');
			const set: Partial<typeof foodEntry.$inferInsert> = {};
			if (input.name !== undefined) set.name = input.name;
			if (input.meal !== undefined) set.meal = input.meal;
			if (input.day !== undefined) set.day = input.day;
			if (input.grams !== undefined) {
				if (!e.grams)
					throw new OpsError('INVALID', 'This entry has no weight to change. Give its calories.');
				const ratio = (v: number) => Math.round((v * input.grams!) / e.grams!); // A guard above makes both present
				set.grams = input.grams;
				set.kcal = ratio(e.kcal);
				set.lowKcal = ratio(e.lowKcal);
				set.highKcal = ratio(e.highKcal);
				for (const k of CORE_KEYS) {
					const v = e[k];
					set[k] = v === null ? null : ratio(v);
				}
				set.nutrients = Object.fromEntries(
					Object.entries(e.nutrients).map(([code, ng]) => [code, ratio(ng)])
				);
			}
			if (input.kcal !== undefined) {
				if (e.sourceKind !== 'manual' && e.sourceKind !== 'rough')
					throw new OpsError(
						'INVALID',
						'The calories of this food come from its data. Change its grams instead.'
					);
				const percent = e.sourceKind === 'rough' ? RANGE_PERCENT.rough : RANGE_PERCENT.printed;
				set.kcal = input.kcal;
				Object.assign(set, rangeOf(input.kcal, percent));
			}
			const [row] = await tx
				.update(foodEntry)
				.set({ ...set, version: sql`${foodEntry.version} + 1`, updatedAt: new Date() })
				.where(and(eq(foodEntry.userId, userId), eq(foodEntry.id, input.entryId)))
				.returning(ENTRY_COLUMNS);
			return { entry: plain(row), today: await readDay(tx, userId, row?.day ?? e.day) };
		})
	);
}

/** Removes an entry and answers what was removed, so it can be logged again. */
export async function deleteFood(ctx: Ctx, raw: FoodDeleteInput) {
	const input = parse(foodDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'food.delete', input, async (tx, userId) => {
			const [row] = await tx
				.delete(foodEntry)
				.where(and(eq(foodEntry.userId, userId), eq(foodEntry.id, input.entryId)))
				.returning(ENTRY_COLUMNS);
			if (!row) throw new OpsError('NOT_FOUND', 'That food entry is not there any more.');
			return { removed: plain(row), today: await readDay(tx, userId, row.day) };
		})
	);
}

/** Says whether everything eaten that day is logged. Only complete days feed the burn estimate. */
export async function markDay(ctx: Ctx, raw: DayMarkInput) {
	const input = parse(dayMarkInput, raw);
	return mapped(() =>
		runWrite(ctx, 'food.day_mark', input, async (tx, userId) => {
			const day = input.day ?? toLocalDate(new Date());
			await tx
				.insert(dayStatus)
				.values({ userId, day, complete: input.complete })
				.onConflictDoUpdate({
					target: [dayStatus.userId, dayStatus.day],
					set: { complete: input.complete, updatedAt: new Date() }
				});
			return readDay(tx, userId, day);
		})
	);
}

/** A saved food: values per 100 g. A barcode that is already saved is replaced, so a scan stays current. */
export async function saveFood(ctx: Ctx, raw: FoodSaveInput) {
	const input = parse(foodSaveInput, raw);
	for (const code of Object.keys(input.nutrients ?? {}))
		if (!isNutrientCode(code))
			throw new OpsError('INVALID', `Unknown nutrient: ${code.slice(0, 40)}`);
	return mapped(() =>
		runWrite(ctx, 'food.save', input, async (tx, userId) => {
			const values = {
				name: input.name,
				barcode: input.barcode ?? null,
				source: input.source ?? ('manual' as const),
				kcal: input.kcal,
				proteinMg: input.proteinMg ?? null,
				carbsMg: input.carbsMg ?? null,
				sugarMg: input.sugarMg ?? null,
				fibreMg: input.fibreMg ?? null,
				fatMg: input.fatMg ?? null,
				satFatMg: input.satFatMg ?? null,
				sodiumMg: input.sodiumMg ?? null,
				nutrients: input.nutrients ?? {},
				servingG: input.servingG ?? null
			};
			const [existing] = input.barcode
				? await tx
						.select({ id: foodItem.id })
						.from(foodItem)
						.where(
							and(
								eq(foodItem.userId, userId),
								eq(foodItem.barcode, input.barcode),
								isNull(foodItem.archivedAt)
							)
						)
				: [];
			if (existing) {
				const [row] = await tx
					.update(foodItem)
					.set({ ...values, version: sql`${foodItem.version} + 1`, updatedAt: new Date() })
					.where(and(eq(foodItem.userId, userId), eq(foodItem.id, existing.id)))
					.returning();
				return { food: plain(row), id: `saved:${existing.id}` };
			}
			const [row] = await tx
				.insert(foodItem)
				.values({ userId, ...values })
				.returning();
			return { food: plain(row), id: `saved:${row?.id}` };
		})
	);
}

export async function listSavedFoods(ctx: Ctx) {
	return run(ctx, async (tx, userId) =>
		plain(
			await tx
				.select()
				.from(foodItem)
				.where(and(eq(foodItem.userId, userId), isNull(foodItem.archivedAt)))
				.orderBy(foodItem.name)
		)
	);
}

/** Hides a saved food. Entries that named it keep their numbers. */
export async function archiveFood(ctx: Ctx, raw: FoodArchiveInput) {
	const input = parse(foodArchiveInput, raw);
	return mapped(() =>
		runWrite(ctx, 'food.archive', input, async (tx, userId) => {
			const [row] = await tx
				.update(foodItem)
				.set({ archivedAt: new Date(), updatedAt: new Date() })
				.where(and(eq(foodItem.userId, userId), eq(foodItem.id, input.foodItemId)))
				.returning({ id: foodItem.id, name: foodItem.name });
			if (!row) throw new OpsError('NOT_FOUND', 'That saved food is not there any more.');
			return { archived: plain(row) };
		})
	);
}
