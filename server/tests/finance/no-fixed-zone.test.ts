// NO FIXED ZONE IN THE SERVER: DAYS AND CLOCK TIMES COME FROM finance/dates.ts, WHICH FOLLOWS THE PERSON'S ZONE (BTL-20261105-0529)

// -- DEP-MODULES -- //
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

// -- CONSTANTS -- //

const ROOT = join(__dirname, '..', '..', 'src');
// Where a fixed Manila is correct, and why
const ALLOWED = new Map<string, string>([
	['lib/finance/dates.ts', 'the one place that knows the default zone'],
	['lib/finance/timeZones.ts', 'the list of zones a person can choose from'],
	['lib/server/db/schema/settings.ts', 'the column default'],
	['lib/server/db/schema/auth.ts', 'an unused column, kept as it is'],
	['lib/server/db/schema/usage.ts', 'the monthly model-call cap is billing, not display'],
	['lib/server/proxy/limits.ts', 'the monthly model-call cap is billing, not display']
]);
const BANNED =
	/\b(toManilaDate|manilaStart|manilaNoon|atManilaTime)\b|['"`]Asia\/Manila['"`]|\+08:00|\b8 \* 3_600_000\b/;

// -- FUNCTIONS -- //

function files(dir: string): string[] {
	return readdirSync(dir).flatMap((name) => {
		const p = join(dir, name);
		if (statSync(p).isDirectory()) return name === 'migrations' ? [] : files(p);
		return /\.(ts|svelte)$/.test(name) ? [p] : [];
	});
}

// -- TESTS -- //

describe('no fixed zone', () => {
	it('keeps Manila out of the server except where it is the default or billing', () => {
		const found: string[] = [];
		for (const f of files(ROOT)) {
			const rel = f.slice(ROOT.length + 1).replaceAll('\\', '/');
			if (ALLOWED.has(rel)) continue;
			readFileSync(f, 'utf8')
				.split('\n')
				.forEach((line, i) => {
					// Prose in a comment may still say Manila; code may not hold the zone
					const code = line.replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '');
					if (BANNED.test(code)) found.push(`${rel}:${i + 1}: ${line.trim()}`);
				});
		}
		expect(found).toEqual([]);
	});
});
