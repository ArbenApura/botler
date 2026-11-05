// PRINTS THE ZONE LIST OF app/lib/core/zone_list.dart FROM THE SERVER'S LIST (yarn tsx scripts/zones-dart.ts). A test checks that the app file still has exactly these lines.

// -- MODULES -- //
import { TIME_ZONES } from '../src/lib/finance/timeZones';

// -- FUNCTIONS -- //

export const dartZoneLines = (): string[] => TIME_ZONES.map((z) => `  '${z}',`);

if (process.argv[1]?.endsWith('zones-dart.ts'))
	process.stdout.write(dartZoneLines().join('\n') + '\n');
