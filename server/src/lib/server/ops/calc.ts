// THE CALC VERB: THE CALCULATOR OF finance/calc.ts FOR THE ASSISTANT AND THE APP. NO DATABASE: IT NEEDS NO DATA, ONLY THE CALLER'S LIVE IDENTITY.
// Each line comes back as an exact number (or date), the same number rounded for reading, and, when the line names a currency, as money
// through finance/currency.ts (the number is in the currency's own unit unless `unit` says minor). A line that fails says where.

// -- TYPES -- //
import type { Ctx } from './context';
// -- MODULES -- //
import { calculate, CalcError, toMinorUnits } from '../../finance/calc';
import { currencyOf, formatMoney } from '../../finance/currency';
import { calcInput } from '../db/zod';
import { OpsError } from './context';
import { parse } from './shared';

// -- TYPES -- //

export type CalcLineOutput =
	| {
			line: number;
			name: string | null;
			ok: true;
			type: 'number' | 'date';
			/** The whole value as text. Quote this, never a figure you worked out yourself. */
			value: string;
			shown: string;
			/** Only with a currency: the amount in the smallest unit (centavos, cents ...) and as a written amount. */
			minor?: number;
			money?: string;
			note?: string;
	  }
	| { line: number; name: string | null; ok: false; error: string; position: number | null };

// -- CONSTANTS -- //

/** Names of lines that are about food, the body or counts, never pesos. */
const NOT_MONEY_NAME = /(kcal|calor|protein|prot_|carb|gram|steps|weight)/i;

// -- FUNCTIONS -- //

/** Works out the lines. The caller must be signed in; nothing is read or written. */
export async function runCalc(ctx: Ctx, raw: unknown): Promise<{ lines: CalcLineOutput[] }> {
	const input = parse(calcInput, raw);
	// The identity is checked like every verb's, though no row is read: a verb never answers an unknown caller
	if (!ctx.actor.userId) throw new OpsError('FORBIDDEN', 'Sign in first.');
	let results;
	try {
		results = calculate(input.lines.map((l) => ({ name: l.name, expr: l.expr })));
	} catch (e) {
		if (e instanceof CalcError) throw new OpsError('INVALID', e.message);
		throw e;
	}
	return {
		lines: results.map((r, i): CalcLineOutput => {
			if (!r.ok)
				return { line: r.line, name: r.name, ok: false, error: r.error, position: r.position };
			const out: CalcLineOutput = {
				line: r.line,
				name: r.name,
				ok: true,
				type: r.value.type,
				value: r.value.text,
				shown: r.shown
			};
			const asked = input.lines[i];
			if (asked?.currency) {
				if (r.value.type !== 'number') return { ...out, note: 'A date is not an amount of money.' };
				const minor = toMinorUnits(
					r.value.text,
					currencyOf(asked.currency).digits,
					asked.unit ?? 'major'
				);
				return minor === null
					? { ...out, note: 'That amount is too large to write as money.' }
					: {
							...out,
							minor,
							money: formatMoney(minor, asked.currency),
							// A line named like a food or body figure is probably not money (494 kcal came back as a peso amount in the chat of 6 Nov)
							...(NOT_MONEY_NAME.test(asked.name ?? '')
								? {
										note: `Formatted as money only because a currency was given. "${asked.name}" does not look like an amount of money: quote value, not money.`
									}
								: {})
						};
			}
			return out;
		})
	};
}
