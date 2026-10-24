// PRINTS THE CURRENCY LIST OF app/lib/core/money.dart FROM THE SERVER'S CATALOGUE (yarn tsx scripts/currencies-dart.ts). A test checks that the app file still has exactly these lines.

// -- MODULES -- //
import { CURRENCIES } from '../src/lib/finance/currency';

// -- FUNCTIONS -- //

/** A Dart string literal: raw when it holds a dollar sign, so it is never read as interpolation. */
const lit = (s: string) => {
	if (s.includes("'")) throw new Error(`A Dart literal cannot hold an apostrophe: ${s}`);
	return s.includes('$') ? `r'${s}'` : `'${s}'`;
};

export const dartCurrencyLines = (): string[] =>
	CURRENCIES.map((c) => `  Currency('${c.code}', ${lit(c.symbol)}, ${c.digits}, ${lit(c.name)}),`);

if (process.argv[1]?.endsWith('currencies-dart.ts'))
	process.stdout.write(dartCurrencyLines().join('\n') + '\n');
