// DATA RESET VERBS: SEE WHAT A SCOPE WOULD ERASE, THEN ERASE IT WITH A CONFIRMATION THAT WORKS ONCE (BTL-20261022-0218, ADR 6)
// Both verbs are the person's alone: the assistant has no way to reach them, and an approval card cannot run them. The erase is one database
// function (db/dataResetSql.ts) inside one transaction, so a failure halfway leaves everything as it was. What stays: the sign-in, the
// settings, the phones and the model budget counters. Backups taken before a reset keep the old data until they rotate.

// -- TYPES -- //
import type { Ctx } from './context';
import type { DataResetInput, DataResetPreviewInput } from '../db/zod';
import type { ResetScope } from '../db/dataResetSql';
// -- DEP-MODULES -- //
import { randomBytes } from 'node:crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
// -- MODULES -- //
import { EVERYTHING_TABLES, tablesOf } from '../db/dataResetSql';
import { requestLog } from '../db/schema';
import { dataResetInput, dataResetPreviewInput } from '../db/zod';
import { OpsError, run, runWrite } from './context';
import { mapped, parse, requirePerson } from './shared';

// -- CONSTANTS -- //

/** What the person types to confirm. */
export const RESET_WORD = 'RESET';
const TOKEN_MINUTES = 5;
const NOTE = 'Backups made before the reset keep the old data until they are replaced.';

// -- FUNCTIONS -- //

const tokenKey = (token: string) => `reset-${token}`;

/** The rows of a scope, counted for this person. Reading through the person's own context, so only their rows are seen. */
async function countsOf(tx: Parameters<Parameters<typeof run>[1]>[0], scope: ResetScope) {
	const counts: Record<string, number> = {};
	const tables = [
		...tablesOf(scope),
		...(scope === 'audit' || scope === 'everything' ? ['audit_event'] : [])
	];
	for (const t of tables) {
		// The names come from the constant lists above, never from input
		const res = (await tx.execute(sql.raw(`select count(*)::int as n from "${t}"`))) as unknown as {
			rows: { n: number }[];
		};
		counts[t] = res.rows[0]?.n ?? 0;
	}
	return counts;
}

/** What a scope would erase, and a confirmation that works once for five minutes. Nothing is changed. */
export async function previewDataReset(ctx: Ctx, raw: DataResetPreviewInput) {
	requirePerson(ctx.actor.kind, 'reset data');
	const { scope } = parse(dataResetPreviewInput, raw);
	return run(ctx, async (tx, userId) => {
		const counts = await countsOf(tx, scope);
		const token = randomBytes(16).toString('hex');
		await tx.insert(requestLog).values({
			userId,
			requestId: tokenKey(token),
			verb: 'data_reset_preview',
			fingerprint: scope,
			result: { used: false }
		});
		const total = Object.values(counts).reduce((a, b) => a + b, 0);
		return {
			scope,
			counts,
			total,
			token,
			expiresInMinutes: TOKEN_MINUTES,
			word: RESET_WORD,
			note: NOTE,
			// A reset can only be started on this word, so a tap by mistake never reaches the database
			keeps: ['sign-in', 'settings', 'phones']
		};
	});
}

/** Erases a scope of the person's own data. Needs the confirmation from the preview and the typed word. */
export async function resetData(ctx: Ctx, raw: DataResetInput) {
	requirePerson(ctx.actor.kind, 'reset data');
	const input = parse(dataResetInput, raw);
	if (input.typed !== RESET_WORD) throw new OpsError('INVALID', `Type ${RESET_WORD} to confirm.`);
	return mapped(() =>
		runWrite(ctx, 'data.reset', { scope: input.scope, token: input.token }, async (tx, userId) => {
			// The confirmation is for this scope, this person and these five minutes, and works once: using it marks it used
			const [row] = await tx
				.select()
				.from(requestLog)
				.where(
					and(
						eq(requestLog.userId, userId),
						eq(requestLog.requestId, tokenKey(input.token)),
						eq(requestLog.fingerprint, input.scope),
						gt(
							requestLog.createdAt,
							sql`now() - interval '${sql.raw(String(TOKEN_MINUTES))} minutes'`
						)
					)
				)
				.for('update');
			if (!row)
				throw new OpsError('INVALID', 'That confirmation is not valid any more. Start again.');
			if ((row.result as { used?: boolean } | null)?.used)
				throw new OpsError('CONFLICT', 'That confirmation was already used.');
			await tx
				.update(requestLog)
				.set({ result: { used: true } })
				.where(and(eq(requestLog.userId, userId), eq(requestLog.requestId, tokenKey(input.token))));
			const done = (await tx.execute(
				sql`select data_reset(${userId}, ${input.scope}) as result`
			)) as unknown as { rows: { result: Record<string, number> }[] };
			const result = done.rows[0]?.result ?? {};
			const { tombstone_seq: tombstone, ...deleted } = result;
			return { scope: input.scope, deleted, tombstoneSeq: tombstone ?? null };
		})
	);
}

/** Every table 'everything' erases, for the registry test. */
export const ERASED_BY_EVERYTHING = EVERYTHING_TABLES;
