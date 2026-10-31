// ACCOUNT VERBS: THE PLACES MONEY SITS (RCBC, GCASH, MAYA, CASH, OR ONE THE PERSON ADDS)

// -- TYPES -- //
import type { Ctx } from './context';
import type {
	AccountCreateInput,
	AccountUpdateInput,
	WalletAddInput,
	WalletRemoveInput
} from '../db/zod';
import type { Plain } from './shared';
// -- DEP-MODULES -- //
import { and, eq, or, sql } from 'drizzle-orm';
// -- MODULES -- //
import {
	account,
	accountWallet,
	allocationRule,
	balanceSnapshot,
	bill,
	billOverride,
	goal,
	incomeSchedule,
	ledgerTxn
} from '../db/schema';
import {
	accountCreateInput,
	accountDeleteInput,
	accountIdInput,
	accountUpdateInput,
	walletAddInput,
	walletRemoveInput
} from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { ensureWallet, walletCurrencies } from './ledger';
import { dropPicture, planMark, splitMark } from './picture';
import { readSettings } from './settings';
import { checkVersion, mapped, parse, plain, requireAccount, requireActiveAccount } from './shared';

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
	const input = parse(accountCreateInput, raw);
	return mapped(() =>
		runWrite(ctx, 'account.create', input, async (tx, userId) => {
			// A new account is in the person's main currency unless it says another
			const currency = input.currency ?? (await readSettings(tx, userId)).currency;
			const { rest, mark } = splitMark(input);
			const plan = await planMark(ctx, tx, userId, null, mark);
			const [row] = await tx
				.insert(account)
				.values({ ...rest, ...plan.set, currency, userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The account could not be saved.');
			await ensureWallet(tx, userId, row.id, row.currency);
			return plain(row);
		})
	);
}

export async function updateAccount(ctx: Ctx, raw: AccountUpdateInput): Promise<AccountView> {
	const { accountId, expectVersion, ...parsed } = parse(accountUpdateInput, raw);
	const { rest: changes, mark } = splitMark(parsed);
	return mapped(() =>
		runWrite(ctx, 'account.update', { accountId, expectVersion, ...parsed }, async (tx, userId) => {
			const current = await requireAccount(tx, userId, accountId);
			checkVersion(current.version, expectVersion, 'account');
			const plan = await planMark(ctx, tx, userId, current.imageId, mark);
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
					.where(and(eq(balanceSnapshot.userId, userId), eq(balanceSnapshot.accountId, accountId)));
				if ((entries?.n ?? 0) + (counts?.n ?? 0) > 0)
					throw new OpsError(
						'INVALID',
						`This account already has entries in ${current.currency}. Add a ${changes.currency} wallet to it instead.`
					);
			}
			const [row] = await tx
				.update(account)
				.set({
					...changes,
					...plan.set,
					version: sql`${account.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(and(eq(account.userId, userId), eq(account.id, accountId)))
				.returning();
			if (!row) throw new OpsError('NOT_FOUND', 'That account does not exist.');
			await dropPicture(tx, userId, plan.dropId);
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
		})
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

/** How many rows a count query found. */
const found = async (query: PromiseLike<{ n: number }[]>): Promise<number> =>
	(await query)[0]?.n ?? 0;

/**
 * Removes an account. One with entries (either side of a transfer) or balance counts keeps everything and is hidden instead; the answer names
 * what holds it. One that a bill, payday, goal, rule or changed bill date still uses is refused until those are moved or removed. A clean account goes, with its empty wallets. The assistant may call it
 * (owner decision 2026-10-28); the removed account is returned whole.
 */
export async function deleteAccount(ctx: Ctx, raw: unknown) {
	const { accountId } = parse(accountDeleteInput, raw);
	return mapped(() =>
		runWrite(ctx, 'account.delete', { accountId }, async (tx, userId) => {
			const current = await requireAccount(tx, userId, accountId);
			// The account is locked first, so an entry cannot land between the checks below and the delete
			await tx
				.select({ id: account.id })
				.from(account)
				.where(and(eq(account.userId, userId), eq(account.id, accountId)))
				.for('update');
			const n = sql<number>`count(*)::int`;
			const holders: [string, number][] = [
				[
					'entries',
					await found(
						tx
							.select({ n })
							.from(ledgerTxn)
							.where(
								and(
									eq(ledgerTxn.userId, userId),
									or(eq(ledgerTxn.accountId, accountId), eq(ledgerTxn.toAccountId, accountId))
								)
							)
					)
				],
				[
					'balance counts',
					await found(
						tx
							.select({ n })
							.from(balanceSnapshot)
							.where(
								and(eq(balanceSnapshot.userId, userId), eq(balanceSnapshot.accountId, accountId))
							)
					)
				],
				[
					'bills',
					await found(
						tx
							.select({ n })
							.from(bill)
							.where(and(eq(bill.userId, userId), eq(bill.accountId, accountId)))
					)
				],
				[
					'changed bill dates',
					await found(
						tx
							.select({ n })
							.from(billOverride)
							.where(and(eq(billOverride.userId, userId), eq(billOverride.accountId, accountId)))
					)
				],
				[
					'paydays',
					await found(
						tx
							.select({ n })
							.from(incomeSchedule)
							.where(
								and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.accountId, accountId))
							)
					)
				],
				[
					'goals',
					await found(
						tx
							.select({ n })
							.from(goal)
							.where(and(eq(goal.userId, userId), eq(goal.accountId, accountId)))
					)
				],
				[
					'payday rules',
					await found(
						tx
							.select({ n })
							.from(allocationRule)
							.where(
								and(
									eq(allocationRule.userId, userId),
									eq(allocationRule.targetAccountId, accountId)
								)
							)
					)
				]
			];
			const holding = holders.filter(([, count]) => count > 0);
			// Things that still use the account would be left pointing at a hidden one (a bill could no longer be paid from it), so they come first
			const using = holding.filter(([what]) =>
				['bills', 'changed bill dates', 'paydays', 'goals', 'payday rules'].includes(what)
			);
			if (using.length > 0)
				throw new OpsError(
					'INVALID',
					`The account is still used by ${using.map(([what, count]) => `${count} ${what}`).join(', ')}. Move or remove those first, then remove the account.`
				);
			if (holding.length > 0) {
				const [row] = await tx
					.update(account)
					.set({
						archivedAt: current.archivedAt ?? sql`now()`,
						version: sql`${account.version} + 1`,
						updatedAt: sql`now()`
					})
					.where(and(eq(account.userId, userId), eq(account.id, accountId)))
					.returning();
				if (!row) throw new OpsError('NOT_FOUND', 'That account does not exist.');
				return {
					deleted: false as const,
					archived: true as const,
					reason: `The account still has ${holding.map(([what, count]) => `${count} ${what}`).join(', ')}, so its history is kept and it is hidden instead.`,
					account: plain(row)
				};
			}
			await tx
				.delete(accountWallet)
				.where(and(eq(accountWallet.userId, userId), eq(accountWallet.accountId, accountId)));
			await tx.delete(account).where(and(eq(account.userId, userId), eq(account.id, accountId)));
			// The picture goes with the account; the removed account is returned without it, so adding it again starts with an icon or a new picture
			await dropPicture(tx, userId, current.imageId);
			return {
				deleted: true as const,
				archived: false as const,
				account: plain({ ...current, imageId: null })
			};
		})
	);
}

/**
 * Takes a currency off an account. Only an empty wallet goes: no entry in or out of it, no balance count in it, and not the account's own
 * currency (that wallet opens again on its next entry). Anything else is refused with the reason.
 */
export async function removeWallet(ctx: Ctx, raw: WalletRemoveInput) {
	const input = parse(walletRemoveInput, raw);
	return mapped(() =>
		runWrite(ctx, 'account.wallet_remove', input, async (tx, userId) => {
			const acc = await requireAccount(tx, userId, input.accountId);
			if (acc.currency === input.currency)
				throw new OpsError(
					'INVALID',
					`${input.currency} is the account's own currency, so its wallet cannot be removed. Hide or delete the account instead.`
				);
			const [wallet] = await tx
				.select({ id: accountWallet.id })
				.from(accountWallet)
				.where(
					and(
						eq(accountWallet.userId, userId),
						eq(accountWallet.accountId, acc.id),
						eq(accountWallet.currency, input.currency)
					)
				);
			if (!wallet) throw new OpsError('NOT_FOUND', `The account has no ${input.currency} wallet.`);
			const n = sql<number>`count(*)::int`;
			const [entries] = await tx
				.select({ n })
				.from(ledgerTxn)
				.where(
					and(
						eq(ledgerTxn.userId, userId),
						or(
							and(eq(ledgerTxn.accountId, acc.id), eq(ledgerTxn.currency, input.currency)),
							and(
								eq(ledgerTxn.toAccountId, acc.id),
								sql`coalesce(${ledgerTxn.toCurrency}, ${ledgerTxn.currency}) = ${input.currency}`
							)
						)
					)
				);
			const [counts] = await tx
				.select({ n })
				.from(balanceSnapshot)
				.where(
					and(
						eq(balanceSnapshot.userId, userId),
						eq(balanceSnapshot.accountId, acc.id),
						eq(balanceSnapshot.currency, input.currency)
					)
				);
			if ((entries?.n ?? 0) + (counts?.n ?? 0) > 0)
				throw new OpsError(
					'INVALID',
					`The ${input.currency} wallet has entries or balance counts, so it is kept. Reset its balance to zero instead.`
				);
			// A bill in this currency paid from this account would have no wallet to be paid from
			const [billsHere] = await tx
				.select({ n })
				.from(bill)
				.where(
					and(
						eq(bill.userId, userId),
						eq(bill.accountId, acc.id),
						eq(bill.currency, input.currency)
					)
				);
			if ((billsHere?.n ?? 0) > 0)
				throw new OpsError(
					'INVALID',
					`${billsHere?.n} bill(s) in ${input.currency} are paid from this account, so the wallet is kept.`
				);
			await tx.delete(accountWallet).where(eq(accountWallet.id, wallet.id));
			return {
				removed: true as const,
				accountId: acc.id,
				currency: input.currency,
				currencies: await walletCurrencies(tx, userId, acc.id, acc.currency)
			};
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
