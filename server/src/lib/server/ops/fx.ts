// EXCHANGE RATE VERBS: READ THE STORED RATES AND ASK FOR A FRESH SET (BTL-20261023-1407, M3)
// The rates are the same for everyone and are fetched by the server from one fixed address (see server/fx/). Reading never waits for the
// network: when the rates are stale a refresh starts in the background and the answer carries the rates that are stored, with their date.

// -- TYPES -- //
import type { Ctx } from './context';
import type { FxConvertInput } from '../db/zod';
import type { RatesStatus, RefreshOutcome } from '../fx/store';
// -- MODULES -- //
import { canConvert, convert, showRate } from '../../finance/fx';
import { fxConvertInput } from '../db/zod';
import { fxConfig } from '../fx/config';
import { loadRates, refreshInBackground, refreshRates } from '../fx/store';
import { OpsError, run } from './context';
import { parse } from './shared';

// -- TYPES -- //

export type FxView = RatesStatus & {
	/** Whether the server has a rates source at all. Without one nothing is ever fetched. */
	configured: boolean;
};

// -- FUNCTIONS -- //

/** The stored rates for the caller, and a background refresh when they are stale. Checks the caller's identity like every verb. */
export async function fxRates(ctx: Ctx): Promise<FxView> {
	const status = await run(ctx, (tx) => loadRates(tx));
	refreshInBackground(ctx.handle, status);
	return { ...status, configured: fxConfig() !== null };
}

/**
 * Fetches a fresh set now, when asked. Tried within the last ten minutes it fetches nothing and says so; a source that fails keeps the
 * stored rates. Returns what the refresh did and the rates as they are afterwards.
 */
export async function fxRatesRefresh(ctx: Ctx): Promise<{ outcome: RefreshOutcome; view: FxView }> {
	// The caller must be a live person of this server before anything is fetched
	await run(ctx, async () => undefined);
	if (!fxConfig())
		throw new OpsError(
			'UNAVAILABLE',
			'Exchange rates are not set up on this server (FX_RATES_URL is missing).'
		);
	const outcome = await refreshRates(ctx.handle);
	return { outcome, view: await fxRates(ctx) };
}

export type FxConversion =
	| {
			status: 'ok';
			amount: number;
			from: string;
			to: string;
			/** The amount in the smallest unit of the target currency. */
			converted: number;
			/** One unit of the source currency in the target currency, for showing. */
			rate: string;
			asOf: string | null;
			stale: boolean;
	  }
	| { status: 'missing_rate'; amount: number; from: string; to: string; missing: string[] };

/**
 * An amount converted from one currency to another at the stored rates, for an answer the assistant gives ("about how much is 50 dollars in
 * pesos"). Rounded to the nearest smallest unit. A currency without a rate is answered as missing, never as zero.
 */
export async function fxConvert(ctx: Ctx, raw: FxConvertInput): Promise<FxConversion> {
	const input = parse(fxConvertInput, raw);
	const status = await run(ctx, (tx) => loadRates(tx));
	refreshInBackground(ctx.handle, status);
	if (!canConvert(input.from, input.to, status.rates)) {
		const missing = [input.from, input.to].filter(
			(c) => c !== 'USD' && !canConvert(c, 'USD', status.rates)
		);
		return { status: 'missing_rate', ...input, missing: [...new Set(missing)] };
	}
	let converted: number;
	try {
		converted = convert(input.amount, input.from, input.to, status.rates);
	} catch (e) {
		if (e instanceof RangeError)
			throw new OpsError('INVALID', 'That amount is too large to convert.');
		throw e;
	}
	return {
		status: 'ok',
		...input,
		converted,
		rate: input.from === input.to ? '1' : showRate(input.from, input.to, status.rates),
		asOf: status.asOf,
		stale: status.stale
	};
}
