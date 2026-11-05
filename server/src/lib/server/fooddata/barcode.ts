// BARCODE LOOKUPS (BTL-20261105-0015, P4.5): FIXED ADDRESSES ONLY, DIGITS ONLY IN THE PATH, NO REDIRECTS, A TIMEOUT AND A BYTE CAP, LIKE THE EXCHANGE RATE FETCH.
// Everything that comes back was written by other people, so only numbers and a short cleaned name leave this file, and the verb marks the turn as untrusted.
// The USDA key goes in a header, never in an address, and never in an error or a log.

// -- TYPES -- //
import type { CoreKey, FoodFacts } from '../../health/nutrients';
// -- MODULES -- //
import { CORE_KEYS } from '../../health/nutrients';
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

// -- STATES -- //

const cache = new Map<string, { at: number; answer: BarcodeAnswer }>();
let offCalls: number[] = [];

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
	return { kcal: Math.round(kcal), ...core, nutrients: {} };
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
	const unit = String(food.servingSizeUnit ?? '').toLowerCase();
	return {
		found: true,
		notConfigured: [],
		product: {
			id: `barcode:${code}`,
			barcode: code,
			source: 'usda_branded',
			name,
			servingG: unit === 'g' ? num(food.servingSize) : null,
			packG: null,
			facts: { kcal: Math.round(kcal), ...core, nutrients: {} }
		}
	};
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
	offCalls = [];
}
