// BARCODE LOOKUPS (BTL-20261105-0015, P4.5): FIXED ADDRESSES ONLY, DIGITS ONLY IN THE PATH, NO REDIRECTS, A TIMEOUT AND A BYTE CAP, LIKE THE EXCHANGE RATE FETCH.
// Everything that comes back was written by other people, so only numbers and a short cleaned name leave this file, and the verb marks the turn as untrusted.
// The USDA key goes in a header, never in an address, and never in an error or a log.

// -- TYPES -- //
import type { CoreKey, FoodFacts } from '../../health/nutrients';
// -- MODULES -- //
import { CORE_KEYS, NUTRIENTS, toNanograms } from '../../health/nutrients';
import { OpsError } from '../ops/context';

// -- TYPES -- //

export type BarcodeSource = 'off' | 'usda_branded';

export type BarcodeProduct = {
	id: string;
	barcode: string;
	source: BarcodeSource;
	name: string;
	servingG: number | null;
	packG: number | null;
	facts: FoodFacts;
};

export type BarcodeAnswer =
	| { found: true; product: BarcodeProduct; notConfigured: string[] }
	| {
			found: false;
			/** A product name with no usable nutrition, to start the label flow with. */
			nameHint: string | null;
			reason: 'not_found' | 'partial' | 'unavailable';
			notConfigured: string[];
	  };

type Json = Record<string, unknown>;

// -- CONSTANTS -- //

const OFF_URL = 'https://world.openfoodfacts.org/api/v2/product/';
const OFF_FIELDS = 'product_name,brands,serving_quantity,product_quantity,nutriments';
const USDA_URL = 'https://api.nal.usda.gov/fdc/v1/foods/search';
const UPC_URL = 'https://api.upcitemdb.com/prod/trial/lookup';
const TIMEOUT_MS = 6000;
const MAX_BYTES = 512 * 1024;
const OFF_PER_MINUTE = 15;
const CACHE_MS = 3_600_000;
const CACHE_MAX = 500;
const NAME_MAX = 80;
/**
 * The name search of Open Food Facts (its search service; the older cgi/search.pl answered in 9 s or with a 503 when tried on 2026-11-10,
 * this one in about a second). Its limit is lower than the product address, so this server stays well under it.
 */
const OFF_SEARCH_URL = 'https://search.openfoodfacts.org/search';
const OFF_SEARCH_PER_MINUTE = 8;
const BRAND_QUERY_MAX = 80;
const BRAND_QUERY_DIGITS = 6;
const BRAND_HITS = 5;

const USDA_NUTRIENT_IDS: Record<CoreKey, number> = {
	proteinMg: 1003,
	carbsMg: 1005,
	sugarMg: 2000,
	fibreMg: 1079,
	fatMg: 1004,
	satFatMg: 1258,
	sodiumMg: 1093
};

/** Open Food Facts field names, grams per 100 g. */
const OFF_FIELD_OF: Record<CoreKey, string> = {
	proteinMg: 'proteins',
	carbsMg: 'carbohydrates',
	sugarMg: 'sugars',
	fibreMg: 'fiber',
	fatMg: 'fat',
	satFatMg: 'saturated-fat',
	sodiumMg: 'sodium'
};

/** Open Food Facts field names of the other nutrients, by the code of health/nutrients.ts. Its values are grams per 100 g, whatever the nutrient (BTL-20261110-1532). */
const OFF_EXTRA_FIELD_OF: Readonly<Record<string, string>> = {
	potassium: 'potassium',
	calcium: 'calcium',
	iron: 'iron',
	magnesium: 'magnesium',
	phosphorus: 'phosphorus',
	zinc: 'zinc',
	copper: 'copper',
	selenium: 'selenium',
	cholesterol: 'cholesterol',
	vitamin_a: 'vitamin-a',
	vitamin_c: 'vitamin-c',
	vitamin_d: 'vitamin-d',
	vitamin_e: 'vitamin-e',
	vitamin_k: 'vitamin-k',
	thiamin: 'vitamin-b1',
	riboflavin: 'vitamin-b2',
	niacin: 'vitamin-pp',
	vitamin_b6: 'vitamin-b6',
	folate: 'vitamin-b9',
	vitamin_b12: 'vitamin-b12'
};

/** Sodium is this part of salt by weight. */
const SODIUM_IN_SALT = 0.4;
/** No food holds more of one of the other nutrients than this in 100 g: a larger figure is a unit mistake in the source and is left out. */
const MAX_EXTRA_NG = 20e9;

// -- STATES -- //

const cache = new Map<string, { at: number; answer: BarcodeAnswer }>();
const brandCache = new Map<string, { at: number; answer: BrandSearchAnswer }>();
let offCalls: number[] = [];
let offSearches: number[] = [];

// -- FUNCTIONS -- //

/** A barcode as the verbs accept it. Anything else never gets near an address. */
export function checkBarcode(code: string): string {
	if (!/^\d{8,14}$/.test(code)) throw new OpsError('INVALID', 'A barcode is 8 to 14 digits.');
	return code;
}

/** A product name for the card: control characters out, spaces tidied, cut short. It is shown, never followed. */
export function cleanName(v: unknown): string {
	if (typeof v !== 'string') return '';
	return v
		.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, ' ')
		.replace(/\s+/g, ' ')
		.trim()
		.slice(0, NAME_MAX);
}

const num = (v: unknown): number | null => {
	const n = typeof v === 'string' ? Number(v) : v;
	return typeof n === 'number' && Number.isFinite(n) && n >= 0 ? n : null;
};

async function getJson(url: string, headers: Record<string, string>): Promise<Json | null> {
	const res = await fetch(url, {
		headers: { accept: 'application/json', ...headers },
		redirect: 'error',
		signal: AbortSignal.timeout(TIMEOUT_MS)
	});
	if (res.status === 404) return null;
	if (!res.ok) throw new Error(`status ${res.status}`);
	const text = await res.text();
	if (text.length > MAX_BYTES) throw new Error('too large');
	return JSON.parse(text) as Json;
}

/** What one Open Food Facts product holds per 100 g, or null when calories or every macronutrient is missing. A per-serving figure is used only when the serving's grams are known. */
export function factsFromOff(product: Json): FoodFacts | null {
	const n = (product.nutriments ?? {}) as Json;
	const serving = num(product.serving_quantity);
	const per100 = (field: string): number | null => {
		const direct = num(n[`${field}_100g`]);
		if (direct !== null) return direct;
		const s = num(n[`${field}_serving`]);
		return s !== null && serving ? (s * 100) / serving : null;
	};
	const kj = per100('energy-kj');
	const kcal = per100('energy-kcal') ?? (kj === null ? null : kj / 4.184);
	if (kcal === null || kcal > 900) return null;
	const core = Object.fromEntries(
		CORE_KEYS.map((k) => {
			const g = per100(OFF_FIELD_OF[k]);
			return [k, g === null ? null : Math.round(g * 1000)];
		})
	) as Record<CoreKey, number | null>;
	if (core.proteinMg === null && core.carbsMg === null && core.fatMg === null) return null;
	// Many products list salt and no sodium
	if (core.sodiumMg === null) {
		const salt = per100('salt');
		if (salt !== null) core.sodiumMg = Math.round(salt * SODIUM_IN_SALT * 1000);
	}
	const nutrients: Record<string, number> = {};
	for (const [code, field] of Object.entries(OFF_EXTRA_FIELD_OF)) {
		const g = per100(field);
		if (g === null) continue;
		const ng = Math.round(g * 1e9);
		if (ng <= MAX_EXTRA_NG) nutrients[code] = ng;
	}
	return { kcal: Math.round(kcal), ...core, nutrients };
}

async function fromOff(code: string): Promise<BarcodeAnswer | null> {
	// One server address is shared by every scan, so the limit is held here
	const now = Date.now();
	offCalls = offCalls.filter((t) => now - t < 60_000);
	if (offCalls.length >= OFF_PER_MINUTE) return null;
	offCalls.push(now);
	const json = await getJson(`${OFF_URL}${code}.json?fields=${OFF_FIELDS}`, {
		'user-agent': process.env.FOOD_USER_AGENT || 'Botler/1.0'
	});
	const product = json?.product as Json | undefined;
	if (!product) return null;
	const name = cleanName(product.product_name);
	const facts = factsFromOff(product);
	if (!facts || !name)
		return { found: false, nameHint: name || null, reason: 'partial', notConfigured: [] };
	return {
		found: true,
		notConfigured: [],
		product: {
			id: `barcode:${code}`,
			barcode: code,
			source: 'off',
			name,
			servingG: num(product.serving_quantity),
			packG: num(product.product_quantity),
			facts
		}
	};
}

async function fromUsda(code: string, key: string): Promise<BarcodeAnswer | null> {
	const json = await getJson(`${USDA_URL}?dataType=Branded&pageSize=5&query=${code}`, {
		'x-api-key': key
	});
	const foods = Array.isArray(json?.foods) ? (json.foods as Json[]) : [];
	const want = code.replace(/^0+/, '');
	const food = foods.find((f) => String(f.gtinUpc ?? '').replace(/^0+/, '') === want);
	if (!food) return null;
	const product = usdaProduct(food, code);
	return product ? { found: true, notConfigured: [], product } : null;
}

/** One USDA Branded food as a product under a barcode, or null when it has no usable energy or name. */
function usdaProduct(food: Json, code: string): BarcodeProduct | null {
	const list = Array.isArray(food.foodNutrients) ? (food.foodNutrients as Json[]) : [];
	const value = (id: number): number | null => num(list.find((x) => x.nutrientId === id)?.value);
	const kcal = value(1008);
	if (kcal === null || kcal > 900) return null;
	const core = Object.fromEntries(
		CORE_KEYS.map((k) => {
			const v = value(USDA_NUTRIENT_IDS[k]);
			return [k, v === null ? null : k === 'sodiumMg' ? Math.round(v) : Math.round(v * 1000)];
		})
	) as Record<CoreKey, number | null>;
	const name = cleanName(food.description);
	if (!name) return null;
	const nutrients: Record<string, number> = {};
	for (const def of NUTRIENTS) {
		const row = list.find((x) => x.nutrientId === def.usda);
		const amount = num(row?.value);
		if (amount === null) continue;
		const ng = toNanograms(amount, typeof row?.unitName === 'string' ? row.unitName : '');
		if (ng !== null && ng <= MAX_EXTRA_NG) nutrients[def.code] = ng;
	}
	const unit = String(food.servingSizeUnit ?? '').toLowerCase();
	return {
		id: `barcode:${code}`,
		barcode: code,
		source: 'usda_branded',
		name,
		servingG: unit === 'g' ? num(food.servingSize) : null,
		packG: null,
		facts: { kcal: Math.round(kcal), ...core, nutrients }
	};
}

// -- BRAND SEARCH BY NAME (BTL-20261110-1532) -- //
// The same two sources as a barcode, asked by a product name the person typed. Fixed addresses, the name cleaned and cut, both asked at the
// same time under the one timeout, and only products that carry a barcode come back, under that barcode: a later meal_log finds them through
// the barcode path, and the lookup is remembered so it makes no second call.

export type BrandSearchAnswer = {
	products: BarcodeProduct[];
	/** Sources with no key on this server. */
	notConfigured: string[];
	/** Sources that could not be asked now (the per-minute limit, an error or a timeout). */
	unavailable: string[];
};

/** A product name as it is sent out: cleaned, no long runs of digits (nothing but a food name leaves), cut short. Empty when nothing is left. */
export function brandQuery(name: string): string {
	const cleaned = cleanName(name).replace(/\d{5,}/g, ' ');
	// A product name holds a few digits at most ("7 Up", "3 in 1", "100 Plus"). More than six in all is not a name: every digit is dropped,
	// so a number cannot be sent out in pieces
	const few = (cleaned.match(/\d/g) ?? []).length <= BRAND_QUERY_DIGITS;
	return (few ? cleaned : cleaned.replace(/\d/g, ' '))
		.replace(/[^\p{L}\p{N} '&.-]/gu, ' ')
		.replace(/\s+/g, ' ')
		.trim()
		.slice(0, BRAND_QUERY_MAX);
}

const withBrand = (name: string, brand: unknown): string => {
	// One source gives a list of brands, the other a text with commas
	const first = cleanName(String((Array.isArray(brand) ? brand[0] : brand) ?? '').split(',')[0]);
	return first && !name.toLowerCase().includes(first.toLowerCase())
		? cleanName(`${first} ${name}`)
		: name;
};

async function brandsFromOff(query: string): Promise<BarcodeProduct[] | null> {
	const now = Date.now();
	offSearches = offSearches.filter((t) => now - t < 60_000);
	if (offSearches.length >= OFF_SEARCH_PER_MINUTE) return null;
	offSearches.push(now);
	const json = await getJson(
		`${OFF_SEARCH_URL}?q=${encodeURIComponent(query)}&page_size=${BRAND_HITS}&fields=code,${OFF_FIELDS}`,
		{ 'user-agent': process.env.FOOD_USER_AGENT || 'Botler/1.0' }
	);
	const list = Array.isArray(json?.hits) ? (json.hits as Json[]) : [];
	const out: BarcodeProduct[] = [];
	for (const product of list) {
		const code = String(product.code ?? '');
		const name = cleanName(product.product_name);
		const facts = factsFromOff(product);
		if (!/^\d{8,14}$/.test(code) || !name || !facts) continue;
		out.push({
			id: `barcode:${code}`,
			barcode: code,
			source: 'off',
			name: withBrand(name, product.brands),
			servingG: num(product.serving_quantity),
			packG: num(product.product_quantity),
			facts
		});
	}
	return out;
}

async function brandsFromUsda(query: string, key: string): Promise<BarcodeProduct[]> {
	const json = await getJson(
		`${USDA_URL}?dataType=Branded&pageSize=${BRAND_HITS}&query=${encodeURIComponent(query)}`,
		{ 'x-api-key': key }
	);
	const foods = Array.isArray(json?.foods) ? (json.foods as Json[]) : [];
	const out: BarcodeProduct[] = [];
	for (const food of foods) {
		const code = String(food.gtinUpc ?? '').replace(/^0+(?=\d{8})/, '');
		if (!/^\d{8,14}$/.test(code)) continue;
		const product = usdaProduct(food, code);
		if (product) out.push({ ...product, name: withBrand(product.name, food.brandName) });
	}
	return out;
}

/** Products by name from both sources at once. A source that fails is named and passed over; found products are remembered under their barcodes. */
export async function searchBrands(rawName: string): Promise<BrandSearchAnswer> {
	const query = brandQuery(rawName);
	if (query.length < 2) throw new OpsError('INVALID', 'Give the product name to look for.');
	const held = brandCache.get(query.toLowerCase());
	if (held && Date.now() - held.at < CACHE_MS) return held.answer;
	const usdaKey = process.env.USDA_API_KEY;
	const notConfigured = usdaKey ? [] : ['usda_branded'];
	const unavailable: string[] = [];
	const attempt = async (
		source: string,
		fn: () => Promise<BarcodeProduct[] | null>
	): Promise<BarcodeProduct[]> => {
		try {
			const found = await fn();
			if (found === null) unavailable.push(source);
			return found ?? [];
		} catch (e) {
			unavailable.push(source);
			// The reason class only: an error of a fetch can hold the address, and the address holds the name
			console.error(
				JSON.stringify({
					event: 'brand_source_error',
					error: e instanceof Error ? e.name : 'Error'
				})
			);
			return [];
		}
	};
	const [off, usda] = await Promise.all([
		attempt('off', () => brandsFromOff(query)),
		usdaKey ? attempt('usda_branded', () => brandsFromUsda(query, usdaKey)) : Promise.resolve([])
	]);
	const byCode = new Map<string, BarcodeProduct>();
	for (const p of [...off, ...usda]) if (!byCode.has(p.barcode)) byCode.set(p.barcode, p);
	const products = [...byCode.values()].slice(0, BRAND_HITS);
	const at = Date.now();
	if (cache.size + products.length >= CACHE_MAX) cache.clear();
	for (const product of products)
		cache.set(product.barcode, { at, answer: { found: true, product, notConfigured } });
	const answer: BrandSearchAnswer = { products, notConfigured, unavailable };
	// An answer with a source missing is not remembered, so the next try asks again
	if (unavailable.length === 0) {
		if (brandCache.size >= CACHE_MAX) brandCache.clear();
		brandCache.set(query.toLowerCase(), { at, answer });
	}
	return answer;
}

async function nameFromUpc(code: string): Promise<string | null> {
	const json = await getJson(`${UPC_URL}?upc=${code}`, {});
	const items = Array.isArray(json?.items) ? (json.items as Json[]) : [];
	return cleanName(items[0]?.title) || null;
}

/** Looks a barcode up across the sources in order. A source that fails is passed over, and an answer says when nothing could be asked at all. */
export async function lookupBarcode(rawCode: string): Promise<BarcodeAnswer> {
	const code = checkBarcode(rawCode);
	const held = cache.get(code);
	if (held && Date.now() - held.at < CACHE_MS) return held.answer;
	const usdaKey = process.env.USDA_API_KEY;
	const notConfigured = usdaKey ? [] : ['usda_branded'];
	let nameHint: string | null = null;
	let failures = 0;
	let answer: BarcodeAnswer | null = null;
	const attempt = async <T>(fn: () => Promise<T | null>): Promise<T | null> => {
		try {
			return await fn();
		} catch (e) {
			failures += 1;
			// The reason class only: an error of a fetch can hold the address
			console.error(
				JSON.stringify({
					event: 'barcode_source_error',
					error: e instanceof Error ? e.name : 'Error'
				})
			);
			return null;
		}
	};
	const off = await attempt(() => fromOff(code));
	if (off?.found) answer = off;
	else if (off) nameHint = off.nameHint;
	if (!answer && usdaKey) {
		const usda = await attempt(() => fromUsda(code, usdaKey));
		if (usda?.found) answer = usda;
	}
	if (!answer && !nameHint) nameHint = await attempt(() => nameFromUpc(code));
	const final: BarcodeAnswer = answer
		? { ...answer, notConfigured }
		: {
				found: false,
				nameHint,
				reason: nameHint ? 'partial' : failures >= 2 ? 'unavailable' : 'not_found',
				notConfigured
			};
	if (final.found || final.reason !== 'unavailable') {
		if (cache.size >= CACHE_MAX) cache.clear();
		cache.set(code, { at: Date.now(), answer: final });
	}
	return final;
}

/** For tests: starts with no remembered lookups and no counted calls. */
export function resetBarcodeState(): void {
	cache.clear();
	brandCache.clear();
	offCalls = [];
	offSearches = [];
}
