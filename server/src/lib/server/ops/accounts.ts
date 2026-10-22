// ACCOUNT VERBS: THE PLACES MONEY SITS (RCBC, GCASH, MAYA, CASH, OR ONE THE PERSON ADDS)

// -- TYPES -- //
import type { Ctx } from './context';
import type { AccountCreateInput, AccountUpdateInput } from '../db/zod';
import type { Plain } from './shared';
// -- DEP-MODULES -- //
import { and, eq, sql } from 'drizzle-orm';
// -- MODULES -- //
import { account } from '../db/schema';
import { accountCreateInput, accountIdInput, accountUpdateInput } from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { checkVersion, mapped, parse, plain, requireAccount, requirePerson } from './shared';

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
			const [row] = await tx
				.insert(account)
				.values({ ...input, userId })
				.returning();
			if (!row) throw new OpsError('CONFLICT', 'The account could not be saved.');
			return plain(row);
		})
	);
}

export async function updateAccount(ctx: Ctx, raw: AccountUpdateInput): Promise<AccountView> {
	requirePerson(ctx.actor.kind, 'change an account');
	const { accountId, expectVersion, ...changes } = parse(accountUpdateInput, raw);
	return mapped(() =>
		runWrite(
			ctx,
			'account.update',
			{ accountId, expectVersion, ...changes },
			async (tx, userId) => {
				const current = await requireAccount(tx, userId, accountId);
				checkVersion(current.version, expectVersion, 'account');
				const [row] = await tx
					.update(account)
					.set({ ...changes, version: sql`${account.version} + 1`, updatedAt: sql`now()` })
					.where(and(eq(account.userId, userId), eq(account.id, accountId)))
					.returning();
				if (!row) throw new OpsError('NOT_FOUND', 'That account does not exist.');
				return plain(row);
			}
		)
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
