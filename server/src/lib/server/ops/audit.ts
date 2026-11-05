// AUDIT VERBS: VERIFY THE TRAIL, READ THE HISTORY OF ONE ACCOUNT WITH A RUNNING BALANCE, EXPORT IT
// The rows themselves are written by triggers (db/auditSql.ts). These verbs only read. The history is replayed from the trail, so a change that
// was undone, voided or reset reads correctly. Free text is never returned from here: the trail holds only the allow-listed columns.

// -- TYPES -- //
import type { Ctx } from './context';
import type { AccountHistoryInput, AuditExportInput } from '../db/zod';
import type { Snapshot, Txn } from '../../finance/ledger';
// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, dayStart } from '../../finance/dates';
import { balanceOf } from '../../finance/ledger';
import { accountHistoryInput, auditExportInput } from '../db/zod';
import { run } from './context';
import { balanceFor } from './ledger';
import { parse, requireAccount } from './shared';

// -- TYPES -- //

type Row = {
	seq: number;
	at: string;
	actor_kind: string;
	on_behalf: string | null;
	actor_ref: string | null;
	channel: string;
	verb: string | null;
	entity: string;
	entity_id: string;
	account_id: string | null;
	action: string;
	amount_delta: number | null;
	before: Record<string, unknown> | null;
	after: Record<string, unknown> | null;
	request_id: string | null;
	approval_id: string | null;
	turn_id: string | null;
	undo_of: string | null;
};

export type HistoryEntry = {
	/** The currency of a ledger entry or a count; null for the rest (an account or a bill changing). */
	currency: string | null;
	seq: number;
	at: string;
	/** Who did it: the person, the assistant, a job or sync. */
	actor: 'person' | 'agent' | 'job' | 'system';
	/** 'agent' when the person approved what the assistant proposed. */
	onBehalf: string | null;
	channel: string;
	verb: string | null;
	entity: string;
	entityId: string;
	action: string;
	/** What this entry did to the account's balance (negative takes money out). Zero for an entry that does not touch it. */
	delta: number;
	/** The balance of the account right after this entry. */
	balanceAfter: number;
	note: string | null;
	approvalId: string | null;
	turnId: string | null;
	requestId: string | null;
	undoOf: string | null;
	before: Record<string, unknown> | null;
	after: Record<string, unknown> | null;
};

export type VerifyResult = {
	ok: boolean;
	checked: number;
	/** The first row that does not fit: a gap in the numbering, a broken link or a changed row. */
	problem: { seq: number; kind: 'gap' | 'chain' | 'hash' } | null;
	verifiedAt: string;
};

// -- CONSTANTS -- //

/** The rows replayed for one account's running balance. A longer history is read from its newest part. */
const REPLAY_LIMIT = 20_000;
const EXPORT_LIMIT = 5_000;
const LEDGER_ENTITIES = ['ledger_txn', 'balance_snapshot'];
const COLUMNS = `seq, at, actor_kind, on_behalf, actor_ref, channel, verb, entity, entity_id, account_id, action, amount_delta,
	before, after, request_id, approval_id, turn_id, undo_of`;

// -- FUNCTIONS -- //

// A 64 bit column comes back from a raw query as text, so the amount is turned into a number here (it is a safe integer by the amount cap)
const rowsOf = (r: unknown): Row[] =>
	(r as { rows: Row[] }).rows.map((row) =>
		typeof row.amount_delta === 'string' ? { ...row, amount_delta: Number(row.amount_delta) } : row
	);

/** Walks the whole trail of the person and recomputes every number and hash with the database's own function. */
export async function verifyAudit(ctx: Ctx): Promise<VerifyResult> {
	return run(ctx, async (tx, userId) => {
		const counted = (await tx.execute(
			sql`select count(*)::int as n from audit_event where user_id = ${userId}`
		)) as unknown as { rows: { n: number }[] };
		const found = (await tx.execute(sql`
			with ordered as (
				select seq, prev_hash, hash, entity, entity_id, action, amount_delta, before, after, request_id,
					lag(hash) over (order by seq) as prev_row_hash,
					row_number() over (order by seq) as n
				from audit_event where user_id = ${userId}
			)
			select seq, case
				when seq <> n then 'gap'
				when prev_hash is distinct from prev_row_hash then 'chain'
				when hash <> audit_hash(prev_hash, seq, entity, entity_id, action, amount_delta, before, after, request_id) then 'hash'
			end as kind
			from ordered
			where seq <> n
				or prev_hash is distinct from prev_row_hash
				or hash <> audit_hash(prev_hash, seq, entity, entity_id, action, amount_delta, before, after, request_id)
			order by seq limit 1
		`)) as unknown as { rows: { seq: string | number; kind: 'gap' | 'chain' | 'hash' }[] };
		const first = found.rows[0];
		return {
			ok: !first,
			checked: counted.rows[0]?.n ?? 0,
			problem: first ? { seq: Number(first.seq), kind: first.kind } : null,
			verifiedAt: new Date().toISOString()
		};
	});
}

const asDate = (v: unknown): Date => new Date(typeof v === 'string' ? v : 0);
const asNum = (v: unknown): number => (typeof v === 'number' ? v : Number(v ?? 0));

/**
 * A ledger row of the trail as the engine's Txn. A row written before wallets existed has no currency: it was in the currency of its
 * account (the migration gave every old row its person's currency), so the account's own currency stands in.
 */
function toTxn(j: Record<string, unknown>, own: string): Txn {
	const currency = typeof j.currency === 'string' ? j.currency : own;
	return {
		type: j.type as Txn['type'],
		accountId: String(j.account_id ?? ''),
		toAccountId: (j.to_account_id as string | null | undefined) ?? null,
		amount: asNum(j.amount),
		currency,
		toCurrency: typeof j.to_currency === 'string' ? j.to_currency : currency,
		toAmount: j.to_amount == null ? null : asNum(j.to_amount),
		fee: asNum(j.fee),
		occurredAt: asDate(j.occurred_at),
		voided: j.voided_at != null
	};
}

/**
 * Replays the trail of one wallet of an account (the account in one currency) in order and gives each entry the balance right after it.
 * An entry of the account in another currency is left out, and so is a transfer that does not touch this wallet.
 */
function replay(accountId: string, currency: string, own: string, rows: Row[]): HistoryEntry[] {
	const txns = new Map<string, Txn>();
	const snaps = new Map<string, Snapshot>();
	const balance = () => {
		let latest: Snapshot | null = null;
		for (const s of snaps.values())
			if (s.currency === currency && (!latest || s.takenAt.getTime() > latest.takenAt.getTime()))
				latest = s;
		return balanceOf(accountId, currency, latest, [...txns.values()]);
	};
	const snapCurrency = (j: Record<string, unknown>) =>
		typeof j.currency === 'string' ? j.currency : own;
	const kept: HistoryEntry[] = [];
	let previous = 0;
	for (const r of rows) {
		const after = r.after;
		const side = after ?? r.before;
		// Whether the entry is about this wallet: a ledger row in its currency (or landing in it), or a count of it
		const about =
			r.entity === 'ledger_txn' && side
				? toTxn(side, own).currency === currency ||
					(toTxn(side, own).toCurrency === currency && side.to_account_id === accountId)
				: r.entity === 'balance_snapshot' && side
					? snapCurrency(side) === currency
					: true;
		if (r.entity === 'ledger_txn') {
			if (after) txns.set(r.entity_id, toTxn(after, own));
			else txns.delete(r.entity_id);
		} else if (r.entity === 'balance_snapshot') {
			if (after)
				snaps.set(r.entity_id, {
					amount: asNum(after.amount),
					takenAt: asDate(after.taken_at),
					currency: snapCurrency(after)
				});
			else snaps.delete(r.entity_id);
		}
		const now = balance();
		const delta = LEDGER_ENTITIES.includes(r.entity) ? now - previous : 0;
		previous = now;
		const note = (after?.note ?? r.before?.note ?? null) as string | null;
		if (!about) continue;
		kept.push({
			currency: LEDGER_ENTITIES.includes(r.entity) && side ? toTxn(side, own).currency : null,
			seq: Number(r.seq),
			at: new Date(r.at).toISOString(),
			actor: r.actor_kind as HistoryEntry['actor'],
			onBehalf: r.on_behalf,
			channel: r.channel,
			verb: r.verb,
			entity: r.entity,
			entityId: r.entity_id,
			action: r.action,
			delta,
			balanceAfter: now,
			note,
			approvalId: r.approval_id,
			turnId: r.turn_id,
			requestId: r.request_id,
			undoOf: r.undo_of,
			before: r.before,
			after: r.after
		});
	}
	return kept;
}

/**
 * Everything that happened to one account, newest first, with who did it and the balance after each entry. A transfer shows on both of its
 * accounts. The filters cut the list after the replay, so the running balance is always the real one.
 */
export async function accountHistory(ctx: Ctx, raw: AccountHistoryInput) {
	const input = parse(accountHistoryInput, raw);
	return run(ctx, async (tx, userId) => {
		const acc = await requireAccount(tx, userId, input.accountId);
		const currency = input.currency ?? acc.currency;
		const found = await tx.execute(sql`
			select ${sql.raw(COLUMNS)}
			from audit_event
			where user_id = ${userId}
				and (account_id = ${input.accountId}
					or before ->> 'to_account_id' = ${input.accountId}
					or after ->> 'to_account_id' = ${input.accountId})
			order by seq desc
			limit ${REPLAY_LIMIT}
		`);
		const replayed = replay(input.accountId, currency, acc.currency, rowsOf(found).reverse());
		// The trail may not hold everything: money from before the trail began, or a very long history cut at the replay limit. The real balance
		// is the anchor, so every running balance is moved by the same gap and the answer says it is partial.
		const real = (await balanceFor(tx, userId, input.accountId, currency)).balance;
		const gap = replayed.length > 0 ? real - (replayed.at(-1)?.balanceAfter ?? 0) : 0;
		const all = replayed.map((e) => ({ ...e, balanceAfter: e.balanceAfter + gap }));
		const partial = gap !== 0 || rowsOf(found).length >= REPLAY_LIMIT;
		const needle = input.search?.toLowerCase();
		const fromMs = input.from ? dayStart(input.from).getTime() : null;
		// The end day is inclusive: the range ends before the first instant of the day after it
		const toMs = input.to ? dayStart(addDays(input.to, 1)).getTime() : null;
		const kept = all
			.filter((e) => (input.by ? e.actor === input.by || e.onBehalf === input.by : true))
			.filter((e) => (input.action ? e.action === input.action : true))
			.filter((e) => (fromMs === null ? true : new Date(e.at).getTime() >= fromMs))
			.filter((e) => (toMs === null ? true : new Date(e.at).getTime() < toMs))
			.filter((e) =>
				needle ? `${e.note ?? ''} ${e.verb ?? ''} ${e.entity}`.toLowerCase().includes(needle) : true
			)
			.filter((e) => (input.cursor ? e.seq < input.cursor : true))
			.reverse();
		const limit = input.limit ?? 50;
		const page = kept.slice(0, limit);
		return {
			entries: page,
			nextCursor: kept.length > limit ? (page.at(-1)?.seq ?? null) : null,
			balance: real,
			currency,
			/** True when the trail does not explain the whole balance, so the running balances are anchored on today's real one. */
			partial
		};
	});
}

const csvCell = (v: unknown): string => {
	const text = v === null || v === undefined ? '' : String(v);
	// A cell that starts like a formula is made inert for a spreadsheet
	const safe = /^[=+@\t\r-]/.test(text) && !/^-?\d+(\.\d+)?$/.test(text) ? `'${text}` : text;
	return /[",\n\r]/.test(safe) ? `"${safe.replaceAll('"', '""')}"` : safe;
};

/** The trail as a CSV or JSON text, the newest 5,000 rows of a date range or an account. Only the allow-listed columns, never a secret. */
export async function exportAudit(ctx: Ctx, raw: AuditExportInput) {
	const input = parse(auditExportInput, raw);
	return run(ctx, async (tx, userId) => {
		if (input.accountId) await requireAccount(tx, userId, input.accountId);
		const account = input.accountId
			? sql`and (account_id = ${input.accountId} or before ->> 'to_account_id' = ${input.accountId} or after ->> 'to_account_id' = ${input.accountId})`
			: sql``;
		const from = input.from
			? sql`and at >= ${dayStart(input.from).toISOString()}::timestamptz`
			: sql``;
		const to = input.to
			? sql`and at < ${dayStart(addDays(input.to, 1)).toISOString()}::timestamptz`
			: sql``;
		const found = await tx.execute(sql`
			select ${sql.raw(COLUMNS)}
			from audit_event
			where user_id = ${userId} ${account} ${from} ${to}
			order by seq desc
			limit ${EXPORT_LIMIT + 1}
		`);
		const all = rowsOf(found);
		const truncated = all.length > EXPORT_LIMIT;
		const rows = all.slice(0, EXPORT_LIMIT).reverse();
		const cols = [
			'seq',
			'at',
			'actor',
			'on_behalf',
			'channel',
			'verb',
			'entity',
			'entity_id',
			'account_id',
			'action',
			'amount_delta',
			'request_id',
			'approval_id'
		];
		const body =
			input.format === 'json'
				? JSON.stringify(
						rows.map((r) => ({
							seq: Number(r.seq),
							at: new Date(r.at).toISOString(),
							actor: r.actor_kind,
							onBehalf: r.on_behalf,
							channel: r.channel,
							verb: r.verb,
							entity: r.entity,
							entityId: r.entity_id,
							accountId: r.account_id,
							action: r.action,
							amountDelta: r.amount_delta,
							requestId: r.request_id,
							approvalId: r.approval_id,
							before: r.before,
							after: r.after
						})),
						null,
						2
					)
				: [
						cols.join(','),
						...rows.map((r) =>
							[
								r.seq,
								new Date(r.at).toISOString(),
								r.actor_kind,
								r.on_behalf,
								r.channel,
								r.verb,
								r.entity,
								r.entity_id,
								r.account_id,
								r.action,
								r.amount_delta,
								r.request_id,
								r.approval_id
							]
								.map(csvCell)
								.join(',')
						)
					].join('\n');
		return {
			format: input.format,
			rows: rows.length,
			truncated,
			notice: truncated
				? `Only the newest ${EXPORT_LIMIT} rows are included. Narrow the dates for the rest.`
				: null,
			body
		};
	});
}
