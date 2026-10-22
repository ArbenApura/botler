// HELPERS SHARED BY THE FINANCE VERBS: INPUT PARSING, OWNERSHIP LOOKUPS, DATABASE ERROR MAPPING AND JSON SAFE ROWS

// -- TYPES -- //
import type { z } from 'zod';
import type { Tx } from '../db/client';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { account, bill, goal, incomeSchedule } from '../db/schema';
import { OpsError } from './context';

// -- TYPES -- //

/** A row as the API returns it: dates become ISO text, so a replayed answer equals the first one. */
export type Plain<T> = T extends Date
	? string
	: T extends (infer U)[]
		? Plain<U>[]
		: T extends object
			? { [K in keyof T]: Plain<T[K]> }
			: T;

// -- FUNCTIONS -- //

export const plain = <T>(value: T): Plain<T> =>
	JSON.parse(JSON.stringify(value ?? null)) as Plain<T>;

/** Parses an input, or throws INVALID with the first problem in the schema's own words. */
export function parse<S extends z.ZodType>(schema: S, input: unknown): z.infer<S> {
	const r = schema.safeParse(input);
	if (!r.success) {
		const issue = r.error.issues[0];
		const where = issue?.path.length ? `${issue.path.join('.')}: ` : '';
		throw new OpsError('INVALID', `${where}${issue?.message ?? 'Invalid input'}`);
	}
	return r.data;
}

/** The Postgres error code. Drizzle wraps the driver error, so it can sit on `cause`. */
function pgCode(e: unknown): string | undefined {
	const direct = (e as { code?: unknown } | null)?.code;
	if (typeof direct === 'string' && /^\d{5}$/.test(direct)) return direct;
	const cause = (e as { cause?: { code?: unknown } } | null)?.cause?.code;
	return typeof cause === 'string' && /^\d{5}$/.test(cause) ? cause : undefined;
}

/** Runs a whole verb and turns a constraint violation into the matching OpsError. Wrap the verb outside its transaction. */
export async function mapped<T>(fn: () => Promise<T>): Promise<T> {
	try {
		return await fn();
	} catch (e) {
		if (e instanceof OpsError) throw e;
		switch (pgCode(e)) {
			case '23505':
				throw new OpsError('CONFLICT', 'That already exists.');
			case '23503':
				throw new OpsError('INVALID', 'It points at something that does not exist.');
			case '23514':
				throw new OpsError('INVALID', 'That value is not allowed.');
			case '22003':
				throw new OpsError('INVALID', 'That amount is too large.');
			default:
				throw e;
		}
	}
}

/** The caller's own account, or NOT_FOUND. Row level security means another person's account looks the same as a missing one. */
export async function requireAccount(tx: Tx, userId: string, accountId: string, label = 'account') {
	const [row] = await tx
		.select()
		.from(account)
		.where(and(eq(account.userId, userId), eq(account.id, accountId)));
	if (!row) throw new OpsError('NOT_FOUND', `That ${label} does not exist.`);
	return row;
}

export async function requireActiveAccount(
	tx: Tx,
	userId: string,
	accountId: string,
	label = 'account'
) {
	const row = await requireAccount(tx, userId, accountId, label);
	if (row.archivedAt) throw new OpsError('INVALID', `The ${label} "${row.name}" is archived.`);
	return row;
}

export async function requireGoal(tx: Tx, userId: string, goalId: string) {
	const [row] = await tx
		.select()
		.from(goal)
		.where(and(eq(goal.userId, userId), eq(goal.id, goalId)));
	if (!row) throw new OpsError('NOT_FOUND', 'That goal does not exist.');
	return row;
}

export async function requireBill(tx: Tx, userId: string, billId: string) {
	const [row] = await tx
		.select()
		.from(bill)
		.where(and(eq(bill.userId, userId), eq(bill.id, billId)));
	if (!row) throw new OpsError('NOT_FOUND', 'That bill does not exist.');
	return row;
}

export async function requireIncome(tx: Tx, userId: string, incomeId: string) {
	const [row] = await tx
		.select()
		.from(incomeSchedule)
		.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.id, incomeId)));
	if (!row) throw new OpsError('NOT_FOUND', 'That income does not exist.');
	return row;
}

/** Refuses an update made from a stale read. */
export function checkVersion(current: number, expected: number | undefined, what: string) {
	if (expected !== undefined && expected !== current)
		throw new OpsError(
			'CONFLICT',
			`The ${what} changed since you opened it. Reload and try again.`
		);
}

/** Only a person can change the money plan. The agent proposes, the person approves. */
export function requirePerson(actorKind: 'person' | 'agent', what: string) {
	if (actorKind !== 'person')
		throw new OpsError('FORBIDDEN', `Only you can ${what}, not the assistant.`);
}
