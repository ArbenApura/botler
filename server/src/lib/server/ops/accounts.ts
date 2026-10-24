// ACCOUNT VERBS: THE PLACES MONEY SITS (RCBC, GCASH, MAYA, CASH, OR ONE THE PERSON ADDS)

// -- TYPES -- //
import type { Ctx } from './context';
import type { AccountCreateInput, AccountUpdateInput, WalletAddInput } from '../db/zod';
import type { Plain } from './shared';
// -- DEP-MODULES -- //
import { and, eq, or, sql } from 'drizzle-orm';
// -- MODULES -- //
import { account, accountWallet, balanceSnapshot, ledgerTxn } from '../db/schema';
import { accountCreateInput, accountIdInput, accountUpdateInput, walletAddInput } from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { ensureWallet, walletCurrencies } from './ledger';
import { readSettings } from './settings';
import {
	checkVersion,
	mapped,
	parse,
	plain,
	requireAccount,
	requireActiveAccount,
	requirePerson
} from './shared';

// -- TYPES -- //

export type AccountView = Plain<typeof account.$inferSelect>;

// -- CONSTANTS -- //

/** The accounts a new person starts with, so "lunch 180 gcash" works on day one. Added by the app on first sign in, if the person wants. */
export const STARTER_ACCOUNTS = [
	{ name: 'RCBC', kind: 'bank' },
	{ name: 'GCash', kind: 'ewallet' },
	{ name: 'Maya', kind: 'ewallet' },
	{ name: 'Cash', kind: 'cash' }
] as const;

// -- FUNCTIONS -- //

export async function createAccount(ctx: Ctx, raw: AccountCreateInput): Promise<AccountView> {
	requirePerson(ctx.actor.kind, 'add an account');
	const input = parse(accountCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'account.create', input, async (tx, userId) => {
			// A new account is in the person's main currency unless it says another
			const currency = input.currency ?? (await readSettings(tx, userId)).currency;
			const [row] = await tx
				.insert(account)
				.values({ ...input, currency, userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The account could not be saved.');
			await ensureWallet(tx, userId, row.id, row.currency);
			return plain(row);
		})
	);
}

export async function updateAccount(ctx: Ctx, raw: AccountUpdateInput): Promise<AccountView> {
	const { accountId, expectVersion, ...changes } = parse(accountUpdateInput, raw);
	return mapped(() =>
		runWrite(
			ctx,
			'account.update',
			{ accountId, expectVersion, ...changes },
			async (tx, userId) => {
				const current = await requireAccount(tx, userId, accountId);
				checkVersion(current.version, expectVersion, 'account');
				const retag = changes.currency !== undefined && changes.currency !== current.currency;
				if (retag) {
					// The account is locked first, so an entry cannot land between the check below and the change
					await tx
						.select({ id: account.id })
						.from(account)
						.where(and(eq(account.userId, userId), eq(account.id, accountId)))
						.for('update');
					// The currency of an account with history cannot change under its entries: it holds a wallet in the other currency instead
					const [entries] = await tx
						.select({ n: sql<number>`count(*)::int` })
						.from(ledgerTxn)
						.where(
							and(
								eq(ledgerTxn.userId, userId),
								or(eq(ledgerTxn.accountId, accountId), eq(ledgerTxn.toAccountId, accountId))
							)
						);
					const [counts] = await tx
						.select({ n: sql<number>`count(*)::int` })
						.from(balanceSnapshot)
						.where(
							and(eq(balanceSnapshot.userId, userId), eq(balanceSnapshot.accountId, accountId))
						);
					if ((entries?.n ?? 0) + (counts?.n ?? 0) > 0)
						throw new OpsError(
							'INVALID',
							`This account already has entries in ${current.currency}. Add a ${changes.currency} wallet to it instead.`
						);
				}
				const [row] = await tx
					.update(account)
					.set({ ...changes, version: sql`${account.version} + 1`, updatedAt: sql`now()` })
					.where(and(eq(account.userId, userId), eq(account.id, accountId)))
					.returning();
				if (!row) throw new OpsError('NOT_FOUND', 'That account does not exist.');
				if (retag) {
					// Nothing was entered in the old currency, so its empty wallet goes and the new one opens
					await tx
						.delete(accountWallet)
						.where(
							and(
								eq(accountWallet.userId, userId),
								eq(accountWallet.accountId, accountId),
								eq(accountWallet.currency, current.currency)
							)
						);
					await ensureWallet(tx, userId, accountId, row.currency);
				}
				return plain(row);
			}
		)
	);
}

/** Adds a currency to an account: a Wise or PayPal account that holds pesos, dollars and euros has a wallet for each. Safe to repeat. */
export async function addWallet(ctx: Ctx, raw: WalletAddInput) {
	const input = parse(walletAddInput, raw);
	return mapped(() =>
		runWrite(ctx, 'account.wallet_add', input, async (tx, userId) => {
			const acc = await requireActiveAccount(tx, userId, input.accountId);
			await ensureWallet(tx, userId, acc.id, input.currency);
			return {
				accountId: acc.id,
				currencies: await walletCurrencies(tx, userId, acc.id, acc.currency)
			};
		})
	);
}

/** Hides an account from lists and new entries. Its history stays. */
export async function archiveAccount(ctx: Ctx, raw: { accountId: string }): Promise<AccountView> {
	requirePerson(ctx.actor.kind, 'archive an account');
	const { accountId } = parse(accountIdInput, raw);
	return mapped(() =>
		runWrite(ctx, 'account.archive', { accountId }, async (tx, userId) => {
			await requireAccount(tx, userId, accountId);
			const [row] = await tx
				.update(account)
				.set({
					archivedAt: sql`now()`,
					version: sql`${account.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(and(eq(account.userId, userId), eq(account.id, accountId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That account does not exist.');
			return plain(row);
		})
	);
}

export async function listAccounts(
	ctx: Ctx,
	opts: { includeArchived?: boolean } = {}
): Promise<AccountView[]> {
	const rows = await run(ctx, (tx, userId) =>
		tx
			.select()
			.from(account)
			.where(and(eq(account.userId, userId)))
			.orderBy(account.sortOrder, account.name)
	);
	return plain(opts.includeArchived ? rows : rows.filter((r) => !r.archivedAt));
}
