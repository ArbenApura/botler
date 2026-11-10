// FILIPINO FOODS (BTL-20261105-0015, P3): A STARTER LIST OF COMMON DISHES, AND THE WORDS THAT POINT AT PLAIN FOODS.
// These are rough estimates per 100 g of a home-cooked version, written for this list and marked as estimates wherever they show. No national food table is copied.
// The person can correct any of them and save their own version, which then comes first.

// -- TYPES -- //
import type { FoodFacts } from './nutrients';
// -- MODULES -- //
import { kcalFromMacros } from './nutrients';

// -- TYPES -- //

export type FilipinoFood = {
	id: string;
	name: string;
	/** Other names people use, lower case. */
	aliases: readonly string[];
	/** Grams in one usual serving. */
	servingG: number;
	facts: FoodFacts;
};

// -- CONSTANTS -- //

/** [key, name, aliases, serving in grams, protein, carbs, fat in grams per 100 g] */
const RAW: readonly (readonly [
	string,
	string,
	readonly string[],
	number,
	number,
	number,
	number
])[] = [
	['adobo_chicken', 'Chicken adobo', ['adobong manok', 'adobo'], 180, 19, 2, 12],
	['adobo_pork', 'Pork adobo', ['adobong baboy'], 180, 18, 2, 22],
	['sinigang_pork', 'Pork sinigang', ['sinigang na baboy', 'sinigang'], 350, 7, 3, 5],
	['sinigang_fish', 'Fish sinigang', ['sinigang na isda'], 350, 7, 3, 2],
	['tinola', 'Chicken tinola', ['tinolang manok'], 350, 8, 2, 4],
	['nilaga', 'Beef nilaga', ['nilagang baka', 'nilaga'], 350, 8, 4, 5],
	['bulalo', 'Bulalo', [], 400, 9, 3, 8],
	['kare_kare', 'Kare-kare', ['karekare'], 250, 11, 6, 12],
	['menudo', 'Pork menudo', ['menudo'], 200, 11, 7, 9],
	['afritada', 'Chicken afritada', ['afritada'], 200, 11, 6, 7],
	['kaldereta', 'Beef kaldereta', ['caldereta', 'kaldereta'], 200, 13, 6, 10],
	['mechado', 'Beef mechado', ['mechado'], 200, 13, 6, 9],
	['bistek', 'Bistek Tagalog', ['beef steak', 'bistek'], 150, 20, 5, 11],
	['lechon_kawali', 'Lechon kawali', ['lechon'], 120, 19, 1, 40],
	['sisig', 'Pork sisig', ['sisig'], 150, 16, 3, 25],
	['pork_chop', 'Fried pork chop', ['porkchop'], 120, 25, 3, 18],
	['fried_chicken', 'Fried chicken', ['pritong manok', 'chickenjoy'], 150, 22, 8, 15],
	['fried_fish', 'Fried fish', ['pritong isda', 'galunggong', 'tilapia'], 120, 22, 3, 10],
	['tortang_talong', 'Tortang talong', ['eggplant omelette'], 120, 6, 6, 9],
	['ginisang_munggo', 'Ginisang munggo', ['monggo', 'munggo'], 250, 6, 14, 3],
	['pinakbet', 'Pinakbet', ['pakbet'], 200, 4, 7, 4],
	['laing', 'Laing', [], 150, 5, 8, 16],
	['bicol_express', 'Bicol express', [], 180, 11, 5, 24],
	['kangkong_garlic', 'Sautéed kangkong', ['adobong kangkong', 'kangkong'], 100, 3, 5, 6],
	['chopsuey', 'Chop suey', ['chopsuey'], 200, 5, 7, 4],
	['pancit_canton', 'Pancit canton', ['pansit canton'], 200, 7, 25, 5],
	['pancit_bihon', 'Pancit bihon', ['pansit bihon', 'bihon'], 200, 6, 25, 4],
	['spaghetti_pinoy', 'Filipino sweet spaghetti', ['spaghetti'], 250, 7, 25, 5],
	['lumpia_shanghai', 'Lumpia shanghai', ['lumpia'], 80, 12, 20, 18],
	['sinangag', 'Garlic fried rice', ['sinangag'], 180, 3, 32, 4],
	['kanin', 'Steamed white rice', ['kanin', 'puting kanin'], 190, 3, 28, 0.3],
	['tapsilog', 'Tapsilog', ['tapa'], 350, 12, 22, 10],
	['longganisa', 'Longganisa', ['longganisang'], 80, 15, 12, 28],
	['tocino', 'Tocino', [], 100, 16, 14, 16],
	['tuyo', 'Tuyo', ['dried fish'], 30, 45, 0, 8],
	['pandesal', 'Pandesal', ['pan de sal'], 35, 9, 52, 5],
	['ensaymada', 'Ensaymada', [], 70, 8, 45, 18],
	['arroz_caldo', 'Arroz caldo', ['lugaw', 'goto'], 350, 4, 14, 2],
	['turon', 'Turon', [], 90, 2, 45, 8],
	['halo_halo', 'Halo-halo', ['halohalo'], 350, 2, 32, 3],
	['taho', 'Taho', [], 250, 3, 14, 1],
	['banana_cue', 'Banana cue', ['bananacue'], 120, 1, 42, 4],
	['bibingka', 'Bibingka', [], 120, 6, 42, 8],
	['puto', 'Puto', [], 40, 4, 48, 2],
	['balut', 'Balut', [], 70, 14, 2, 10],
	['instant_noodles', 'Instant pancit canton', ['lucky me', 'instant noodles'], 60, 10, 66, 20]
];

/**
 * The other four main nutrients of each dish, per 100 g: [sugar g, fibre g, saturated fat g, sodium mg] (BTL-20261110-1532).
 * Rough estimates like the rest of the list, worked out from the usual ingredients of a home-cooked version (USDA values of the meat, rice,
 * vegetables, oil, soy sauce, fish sauce and sugar a dish holds), so a day's sugar, fibre and sodium are not left unknown for home food.
 * Sugar and fibre never exceed the dish's carbs and saturated fat never exceeds its fat: a test checks every row.
 */
const MORE: Readonly<Record<string, readonly [number, number, number, number]>> = {
	adobo_chicken: [0.5, 0.2, 3.3, 480],
	adobo_pork: [0.5, 0.2, 7.8, 470],
	sinigang_pork: [1, 0.8, 1.8, 330],
	sinigang_fish: [1, 0.8, 0.5, 320],
	tinola: [0.8, 0.5, 1.1, 260],
	nilaga: [1, 0.8, 2, 240],
	bulalo: [0.8, 0.5, 3.3, 230],
	kare_kare: [1.5, 1.5, 4, 180],
	menudo: [2.5, 1, 3, 360],
	afritada: [2.5, 1, 1.9, 330],
	kaldereta: [2, 1, 4, 380],
	mechado: [2.5, 1, 3.5, 370],
	bistek: [1.5, 0.5, 4.2, 560],
	lechon_kawali: [0, 0, 14, 420],
	sisig: [0.8, 0.4, 8.5, 520],
	pork_chop: [0, 0.1, 6.2, 380],
	fried_chicken: [0.1, 0.3, 4, 480],
	fried_fish: [0, 0.1, 2.3, 330],
	tortang_talong: [2.5, 2, 2.2, 260],
	ginisang_munggo: [1.5, 4.5, 0.8, 240],
	pinakbet: [3, 2.2, 1.1, 380],
	laing: [2, 3, 13, 360],
	bicol_express: [1.5, 1, 14, 450],
	kangkong_garlic: [1, 2, 1, 430],
	chopsuey: [2.5, 1.8, 0.9, 340],
	pancit_canton: [1.5, 1.5, 1.2, 480],
	pancit_bihon: [1.2, 1.2, 0.9, 440],
	spaghetti_pinoy: [8, 1.5, 1.8, 360],
	lumpia_shanghai: [1.5, 1.2, 4.5, 480],
	sinangag: [0.1, 0.5, 0.7, 250],
	kanin: [0.1, 0.4, 0.1, 1],
	tapsilog: [2, 0.4, 3, 360],
	longganisa: [9, 0.2, 9.8, 820],
	tocino: [12, 0, 5.6, 750],
	tuyo: [0, 0, 2.4, 4500],
	pandesal: [8, 2, 1.3, 400],
	ensaymada: [14, 1.2, 9, 330],
	arroz_caldo: [0.3, 0.3, 0.6, 280],
	turon: [22, 2, 1.6, 60],
	halo_halo: [22, 1, 2, 45],
	taho: [10, 0.3, 0.2, 10],
	banana_cue: [26, 2.2, 0.7, 5],
	bibingka: [16, 0.8, 5, 300],
	puto: [18, 0.6, 0.8, 220],
	balut: [0.5, 0, 3.3, 120],
	instant_noodles: [4, 2.5, 9, 1900]
};

export const FILIPINO_FOODS: readonly FilipinoFood[] = RAW.map(
	([key, name, aliases, servingG, p, c, f]) => {
		const proteinMg = Math.round(p * 1000);
		const carbsMg = Math.round(c * 1000);
		const fatMg = Math.round(f * 1000);
		const more = MORE[key];
		return {
			id: `fil:${key}`,
			name,
			aliases,
			servingG,
			facts: {
				kcal: kcalFromMacros(proteinMg, carbsMg, fatMg),
				proteinMg,
				carbsMg,
				fatMg,
				sugarMg: more ? Math.round(more[0] * 1000) : null,
				fibreMg: more ? Math.round(more[1] * 1000) : null,
				satFatMg: more ? Math.round(more[2] * 1000) : null,
				sodiumMg: more ? Math.round(more[3]) : null,
				nutrients: {}
			}
		};
	}
);

/** Filipino and everyday words that point at a plain food in the English data. */
export const FOOD_WORDS: Readonly<Record<string, string>> = {
	itlog: 'egg',
	saging: 'banana',
	manok: 'chicken',
	baboy: 'pork',
	baka: 'beef',
	isda: 'fish',
	gatas: 'milk',
	tinapay: 'bread',
	kamote: 'sweet potato',
	mangga: 'mango',
	pakwan: 'watermelon',
	papaya: 'papaya',
	bayabas: 'guava',
	sibuyas: 'onion',
	bawang: 'garlic',
	kamatis: 'tomato',
	talong: 'eggplant',
	repolyo: 'cabbage',
	sitaw: 'beans',
	kape: 'coffee',
	asukal: 'sugar',
	mantika: 'oil',
	hipon: 'shrimp',
	tubig: 'water',
	mais: 'corn',
	gabi: 'taro',
	buko: 'coconut'
};

// -- FUNCTIONS -- //

export const filipinoById = (id: string): FilipinoFood | undefined =>
	FILIPINO_FOODS.find((f) => f.id === id);

/** The Filipino dishes a word matches, best first. */
export function searchFilipino(query: string, limit = 5): readonly FilipinoFood[] {
	const q = query.trim().toLowerCase();
	if (!q) return [];
	const score = (f: FilipinoFood) => {
		const names = [f.name.toLowerCase(), ...f.aliases];
		if (names.includes(q)) return 3;
		if (names.some((n) => n.startsWith(q) || q.startsWith(n))) return 2;
		if (names.some((n) => n.includes(q) || q.includes(n))) return 1;
		return 0;
	};
	return FILIPINO_FOODS.map((f) => [f, score(f)] as const)
		.filter(([, s]) => s > 0)
		.sort((a, b) => b[1] - a[1])
		.slice(0, limit)
		.map(([f]) => f);
}

/** The words to search the English data with: the plain word for a Filipino one, and the words as given. */
export function englishTerm(query: string): string {
	const words = query.trim().toLowerCase().split(/\s+/);
	return words.map((w) => FOOD_WORDS[w] ?? w).join(' ');
}
