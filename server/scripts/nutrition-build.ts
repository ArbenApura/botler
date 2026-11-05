// BUILDS THE NUTRITION SEED ON THIS LAPTOP FROM THE USDA JSON DOWNLOADS. NOTHING HERE TOUCHES A DATABASE. THE RESULT STAYS OUT OF GIT.
// Usage: yarn nutrition:build <folder with the unzipped USDA .json files> <output .jsonl.gz>

// -- DEP-MODULES -- //
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';
// -- MODULES -- //
import { parseUsdaFile } from '../src/lib/server/nutrition/usda';

// -- FUNCTIONS -- //

const [folder, output] = process.argv.slice(2);
if (!folder || !output) throw new Error('Usage: nutrition-build <folder> <output .jsonl.gz>');
const started = Date.now();
const lines: string[] = [];
for (const name of readdirSync(folder).filter((f) => f.endsWith('.json'))) {
	const { foods, portions } = parseUsdaFile(JSON.parse(readFileSync(join(folder, name), 'utf8')));
	for (const food of foods) lines.push(JSON.stringify({ t: 'f', ...food }));
	for (const portion of portions) lines.push(JSON.stringify({ t: 'p', ...portion }));
	console.log(`${name}: ${foods.length} foods, ${portions.length} portions`);
}
writeFileSync(output, gzipSync(lines.join('\n')));
console.log(
	`${lines.length} rows, ${Math.round(statSync(output).size / 1024)} KB, ${Date.now() - started} ms`
);
