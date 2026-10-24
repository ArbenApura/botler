// WHEN A FREE VERB MUST BECOME A CARD FOR THE ASSISTANT (BTL-20261023-1407, M4): ADDING A CURRENCY TO THE MONEY PICTURE
// The assistant records freely, but a new currency wallet adds to what the accounts screen and the total show, so an entry that would
// open one is a card the person approves. An entry in a currency the account already holds is as free as ever. The verbs themselves are
// not changed: the person opens a wallet by entering something in a new currency, as before.

// -- TYPES -- //
import type { Ctx } from './context';
// -- DEP-MODULES -- //
import { and, eq, isNotNull } from 'drizzle-orm';
// -- MODULES -- //
import { parseExpenseText } from '../../finance/text';
import { account, accountWallet, bill, billOverride } from '../db/schema';
import { run } from './context';
import { readSettings } from './settings';

// -- FUNCTIONS -- //

/** Whether an entry in this currency would open a wallet the account does not have. No currency named means the account's own, which it has. */
export async function opensWallet(
	ctx: Ctx,
	accountId: string | undefined,
	currency: string | undefined
): Promise<boolean> {
	if (!accountId || !currency) return false;
	return run(ctx, async (tx, userId) => {
		const [acc] = await tx
			.select({ currency: account.currency })
			.from(account)
			.where(and(eq(account.userId, userId), eq(account.id, accountId)));
		// An account that does not exist is answered by the verb itself
		if (!acc || acc.currency === currency) return false;
		const [wallet] = await tx
			.select({ id: accountWallet.id })
			.from(accountWallet)
			.where(
				and(
					eq(accountWallet.userId, userId),
					eq(accountWallet.accountId, accountId),
					eq(accountWallet.currency, currency)
				)
			);
		return !wallet;
	});
}

/** A sentence like "coffee usd 5 paypal": whether it would open a wallet. A sentence that names no currency, or no account, opens none. */
export async function textOpensWallet(
	ctx: Ctx,
	text: string,
	accountId: string | undefined
): Promise<boolean> {
	const { names, main } = await run(ctx, async (tx, userId) => ({
		names: await tx
			.select({ id: account.id, name: account.name })
			.from(account)
			.where(eq(account.userId, userId)),
		main: (await readSettings(tx, userId)).currency
	}));
	const parsed = parseExpenseText(
		text,
		names.map((n) => n.name),
		main
	);
	if (!parsed.currency) return false;
	const named = parsed.accountName
		? names.find((n) => n.name.toLowerCase() === parsed.accountName?.toLowerCase())
		: undefined;
	const id = named?.id ?? accountId ?? (names.length === 1 ? names[0]?.id : undefined);
	return opensWallet(ctx, id, parsed.currency);
}

/** Whether paying a bill would take money out of a wallet that is not there yet: the one in the currency it is paid in, on the account it is paid from. */
export async function billPayOpensWallet(
	ctx: Ctx,
	billId: string,
	accountId: string | undefined,
	paidCurrency: string | undefined
): Promise<boolean> {
	const b = await run(ctx, async (tx, userId) => {
		const [row] = await tx
			.select({ currency: bill.currency, accountId: bill.accountId })
			.from(bill)
			.where(and(eq(bill.userId, userId), eq(bill.id, billId)));
		return row;
	});
	// A bill that does not exist is answered by the verb itself
	if (!b) return false;
	// Without an account named, the money leaves the account the bill is paid from, or the one a changed date names
	const override = accountId
		? undefined
		: await run(ctx, async (tx, userId) => {
				const [row] = await tx
					.select({ accountId: billOverride.accountId })
					.from(billOverride)
					.where(
						and(
							eq(billOverride.userId, userId),
							eq(billOverride.billId, billId),
							isNotNull(billOverride.accountId)
						)
					);
				return row?.accountId ?? undefined;
			});
	const accounts = [accountId ?? b.accountId, ...(override ? [override] : [])];
	for (const id of accounts)
		if (await opensWallet(ctx, id, paidCurrency ?? b.currency)) return true;
	return false;
}
