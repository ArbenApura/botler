// LOADS THE NUTRITION SEED AS THE OWNER ROLE. THE ADDRESS COMES ONLY FROM DATABASE_OWNER_URL IN THE ENVIRONMENT, NEVER FROM THE COMMAND LINE, AND IS NEVER PRINTED.
// On the VPS this runs only on the owner's word (check M8 of BTL-20261105-0015). Usage: nutrition-load <seed .jsonl.gz>

// -- TYPES -- //
import type { NutritionFoodRow, NutritionPortionRow } from '../src/lib/server/nutrition/usda';
// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import pg from 'pg';
// -- MODULES -- //
import { loadNutrition } from '../src/lib/server/nutrition/load';

// -- FUNCTIONS -- //

const url = process.env.DATABASE_OWNER_URL;
if (!url) throw new Error('DATABASE_OWNER_URL is not set.');
const file = process.argv[2];
if (!file) throw new Error('Usage: nutrition-load <seed .jsonl.gz>');
const foods: NutritionFoodRow[] = [];
const portions: NutritionPortionRow[] = [];
for (const line of gunzipSync(readFileSync(file)).toString('utf8').split('\n')) {
	if (!line) continue;
	const { t, ...row } = JSON.parse(line) as { t: string } & Record<string, unknown>;
	if (t === 'f') foods.push(row as unknown as NutritionFoodRow);
	else portions.push(row as unknown as NutritionPortionRow);
}
const client = new pg.Client({ connectionString: url });
await client.connect();
const started = Date.now();
try {
	const done = await loadNutrition(
		(text, params) => client.query(text, params as never[]),
		foods,
		portions
	);
	console.log(`${done.foods} foods, ${done.portions} portions, ${Date.now() - started} ms`);
} finally {
	await client.end();
}
