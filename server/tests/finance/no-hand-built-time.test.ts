// NO HAND-BUILT TIMES OR DATES FOR A PERSON IN THE SERVER: A CLOCK TIME OR A DAY THEY READ IS MADE IN finance/clockText.ts AND finance/dates.ts
// (BTL-20261106-1502). The closed list below is what turns an instant into text for a person by the machine's own locale or by hand; the
// wire form (toISOString, UTC) is out of scope. Each allowed file says why.

// -- DEP-MODULES -- //
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

// -- CONSTANTS -- //

const ROOT = join(__dirname, '..', '..', 'src');
const ALLOWED = new Map<string, string>([
	[
		'lib/finance/dates.ts',
		'the one place that reads the zone and turns an instant into a day or a clock'
	],
	['lib/finance/clockText.ts', 'the one place that writes a clock time or a date as text'],
	[
		'lib/server/agent/prompt.ts',
		'the English weekday name of a calendar date, in UTC (no instant, no zone)'
	],
	['lib/server/proxy/limits.ts', 'the monthly model-call cap is billing, not display'],
	['lib/health/rules.ts', 'toLocaleString formats a number with thousands separators, not a time']
]);
const BANNED =
	/\.toLocale(Time|Date)?String\(|\.getHours\(|\.getMinutes\(|\bIntl\.DateTimeFormat\b/;

// -- FUNCTIONS -- //

function files(dir: string): string[] {
	return readdirSync(dir).flatMap((name) => {
		const p = join(dir, name);
		if (statSync(p).isDirectory()) return name === 'migrations' ? [] : files(p);
		return /\.(ts|svelte)$/.test(name) ? [p] : [];
	});
}

// -- TESTS -- //

describe('no hand-built time or date text', () => {
	it('keeps locale and by-hand time formatting out of the server except where it is allowed', () => {
		const found: string[] = [];
		for (const f of files(ROOT)) {
			const rel = f.slice(ROOT.length + 1).replaceAll('\\', '/');
			if (ALLOWED.has(rel)) continue;
			readFileSync(f, 'utf8')
				.split('\n')
				.forEach((line, i) => {
					const code = line.replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '');
					if (BANNED.test(code)) found.push(`${rel}:${i + 1}: ${line.trim()}`);
				});
		}
		expect(found).toEqual([]);
	});
});
