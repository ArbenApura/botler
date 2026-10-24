// TOTAL ASSETS IN THE MAIN CURRENCY (BTL-20261023-1407, M4): EVERY WALLET OF EVERY ACTIVE ACCOUNT, CONVERTED WITH THE STORED RATES
// A wallet in a currency with no known rate is listed as "missing rate" and left out of the total; it is never counted as zero, so the
// total is never quietly wrong. A negative balance (an overdraft, a credit card) counts as negative: this is what the person owns less what they owe.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { RatesStatus } from '../fx/store';
import type { Rates } from '../../finance/fx';
// -- DEP-MODULES -- //
import { and, eq, isNull } from 'drizzle-orm';
// -- MODULES -- //
import { canConvert, convert, showRate } from '../../finance/fx';
import { account } from '../db/schema';
import { fxConfig } from '../fx/config';
import { loadRates, refreshInBackground } from '../fx/store';
import { run } from './context';
import { balanceFor, walletCurrencies } from './ledger';
import { readSettings } from './settings';

// -- TYPES -- //

export type AssetWallet = {
	accountId: string;
	accountName: string;
	currency: string;
	/** In minor units of currency. */
	balance: number;
	/** The balance in the main currency, or null when the rate is missing. */
	value: number | null;
	/** What one unit of this currency is worth in the main currency, for showing ("1 USD = 56 PHP"), or null for the main currency itself or a missing rate. */
	rate: string | null;
	missingRate: boolean;
};

export type AssetAccount = {
	accountId: string;
	name: string;
	kind: string;
	/** The converted wallets of the account, in the main currency. Wallets with a missing rate are not in it. */
	subtotal: number;
	wallets: number;
	hasMissing: boolean;
};

export type AssetsView = {
	/** The main currency: the one every value and the total are in. */
	currency: string;
	total: number;
	wallets: AssetWallet[];
	accounts: AssetAccount[];
	/** Currencies held but without a rate, left out of the total. */
	missing: string[];
	rates: Pick<RatesStatus, 'asOf' | 'oldestAt' | 'stale' | 'source' | 'lastError'> & {
		configured: boolean;
	};
};

// -- FUNCTIONS -- //

/** An amount in the main currency, or null when a rate is missing. The same currency needs no rate. */
export function valueInMain(
	amount: number,
	currency: string,
	main: string,
	rates: Rates
): number | null {
	if (currency === main) return amount;
	return canConvert(currency, main, rates) ? convert(amount, currency, main, rates) : null;
}

/** The assets inside a transaction. Reads only. */
export async function computeAssets(
	tx: Tx,
	userId: string,
	now: Date = new Date()
): Promise<{ view: AssetsView; status: RatesStatus }> {
	const main = (await readSettings(tx, userId)).currency;
	const status = await loadRates(tx, now);
	const accounts = await tx
		.select()
		.from(account)
		.where(and(eq(account.userId, userId), isNull(account.archivedAt)))
		.orderBy(account.sortOrder, account.name);
	const wallets: AssetWallet[] = [];
	const perAccount: AssetAccount[] = [];
	let total = 0;
	const missing = new Set<string>();
	for (const a of accounts) {
		let subtotal = 0;
		let hasMissing = false;
		const currencies = await walletCurrencies(tx, userId, a.id, a.currency);
		for (const currency of currencies) {
			const { balance } = await balanceFor(tx, userId, a.id, currency, now);
			const value = valueInMain(balance, currency, main, status.rates);
			if (value === null) {
				hasMissing = true;
				missing.add(currency);
			} else {
				subtotal += value;
				total += value;
			}
			wallets.push({
				accountId: a.id,
				accountName: a.name,
				currency,
				balance,
				value,
				rate: currency === main || value === null ? null : showRate(currency, main, status.rates),
				missingRate: value === null
			});
		}
		perAccount.push({
			accountId: a.id,
			name: a.name,
			kind: a.kind,
			subtotal,
			wallets: currencies.length,
			hasMissing
		});
	}
	return {
		status,
		view: {
			currency: main,
			total,
			wallets,
			accounts: perAccount,
			missing: [...missing].sort(),
			rates: {
				asOf: status.asOf,
				oldestAt: status.oldestAt,
				stale: status.stale,
				source: status.source,
				lastError: status.lastError,
				configured: fxConfig() !== null
			}
		}
	};
}

/**
 * Every wallet of every active account with its value in the main currency, the total, and the rates used with their date. Reading it
 * never waits for the network: stale rates start a refresh in the background and the answer carries the stored ones with their date.
 */
export async function assetsSummary(ctx: Ctx): Promise<AssetsView> {
	const { view, status } = await run(ctx, (tx, userId) => computeAssets(tx, userId));
	refreshInBackground(ctx.handle, status);
	return view;
}
