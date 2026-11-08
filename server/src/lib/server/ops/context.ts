// THE OPERATIONS CONTEXT: WHO IS ACTING AND HOW A VERB RUNS
// Every verb of the operations layer takes a Ctx. The user id comes from the session, never from a request body or a model,
// and every verb runs inside withUser, so row level security applies to everything it reads and writes.
// A write verb runs through runWrite: it needs a client request id, and a repeat of the same id returns the first result.

// -- TYPES -- //
import type { DbHandle, Tx } from '../db/client';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { requestLog, undoJournal } from '../db/schema';
import { assertUserId, lockPerson, setAuditContext, withUser } from '../db/tenant';
import { inPersonZone } from './zone';
import type { AuditContext } from '../db/tenant';

// -- TYPES -- //

export type Actor = {
	userId: string;
	/** A person at the app, or the agent acting for that person. The agent never gets more rights than the person. */
	kind: 'person' | 'agent';
	/** The agent tool that called, for the activity record. */
	tool?: string;
};

/** Where a change came from, for the audit trail. */
export type Channel = 'app' | 'chat' | 'widget' | 'outbox' | 'calendar_sync' | 'job' | 'system';

export type Ctx = {
	handle: DbHandle;
	actor: Actor;
	/** Chosen by the client for each write (8 to 80 characters). Repeating a write with the same id returns the stored result and writes nothing twice. */
	requestId?: string;
	/** The way in: set by the HTTP edge from a checked header, by the assistant's loop, by a job or by sync. Left out it follows the actor. */
	channel?: Channel;
	/** The chat turn an assistant action belongs to, and the approval card a person answered. Short ids, never text. */
	turnId?: string;
	approvalId?: string;
	/** 'agent' when a person approved something the assistant proposed: the assistant asked, the person did it. */
	onBehalfOf?: 'agent';
	/** A background job or sync acts as itself, not as a person or a tool call. */
	via?: 'job' | 'system';
};

/** What a write changed, for the undo journal. `before` is null for a create, `after` is null for a delete. */
export type UndoEntry = {
	verb: string;
	entity: string;
	entityId: string;
	before: unknown;
	after: unknown;
};

export class OpsError extends Error {
	constructor(
		readonly code:
			| 'INVALID'
			| 'NOT_FOUND'
			| 'FORBIDDEN'
			| 'CONFLICT'
			/** Another message of the same chat is still being answered. Retryable: the caller asks again shortly. */
			| 'BUSY_CHAT'
			/** A rate limit or a monthly cap was reached. The caller should wait or use the manual path. */
			| 'LIMIT'
			/** The model or another outside service is down. Non-model actions still work. */
			| 'UNAVAILABLE',
		message: string
	) {
		super(message);
		this.name = 'OpsError';
	}
}

// -- FUNCTIONS -- //

/** Runs a verb body in the actor's user context. A body can only see and change the actor's own rows. */
export function run<T>(ctx: Ctx, fn: (tx: Tx, userId: string) => Promise<T>): Promise<T> {
	const userId = assertUserId(ctx.actor.userId);
	return withUser(ctx.handle, userId, async (tx) => {
		await setAuditContext(tx, auditOf(ctx));
		// The body's dates are the person's days, in the zone they chose
		return inPersonZone(tx, userId, () => fn(tx, userId));
	});
}

/** The audit context of a caller: who acted, on whose behalf, through which way in. */
export function auditOf(ctx: Ctx): AuditContext {
	const actorKind = ctx.via ?? ctx.actor.kind;
	return {
		actorKind,
		onBehalf: ctx.onBehalfOf ?? '',
		actorRef: ctx.actor.tool ?? '',
		channel: ctx.channel ?? ctx.via ?? (ctx.actor.kind === 'agent' ? 'chat' : 'app'),
		turnId: ctx.turnId ?? '',
		approvalId: ctx.approvalId ?? '',
		requestId: ctx.requestId ?? ''
	};
}

/** JSON with sorted keys, so the same input always gives the same fingerprint. */
function stable(value: unknown): string {
	return JSON.stringify(value, (_k, v: unknown) =>
		v && typeof v === 'object' && !Array.isArray(v)
			? Object.fromEntries(
					Object.entries(v as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : 1))
				)
			: v
	);
}

/** A result as it is stored and replayed: plain JSON, so a first answer and a replay are identical. */
const plain = <T>(value: T): T => JSON.parse(JSON.stringify(value ?? null)) as T;

/**
 * Runs a write verb exactly once per request id. The id is claimed in the same transaction as the write: a write that fails
 * rolls the claim back and can be retried, a finished write is replayed from the log, and the same id with a different
 * request is refused. The result must be JSON (dates as strings).
 */
export async function runWrite<T>(
	ctx: Ctx,
	verb: string,
	input: unknown,
	fn: (tx: Tx, userId: string) => Promise<T>
): Promise<T> {
	const requestId = ctx.requestId;
	if (!requestId || requestId.length < 8 || requestId.length > 80)
		throw new OpsError(
			'INVALID',
			'A write needs a request id of 8 to 80 characters (Idempotency-Key).'
		);
	const fingerprint = createHash('sha256')
		.update(`${verb}\n${stable(input)}`)
		.digest('hex');
	return run(ctx, async (tx, userId) => {
		// Line up with this person's other writes before touching any row, so the audit trigger never deadlocks them
		await lockPerson(tx, userId);
		// The verb's name, for the audit rows this write causes
		await setAuditContext(tx, { verb });
		const claimed = await tx
			.insert(requestLog)
			.values({ userId, requestId, verb, fingerprint })
			.onConflictDoNothing()
			.returning({ id: requestLog.id });
		if (claimed.length === 0) {
			const [prev] = await tx
				.select({ fingerprint: requestLog.fingerprint, result: requestLog.result })
				.from(requestLog)
				.where(and(eq(requestLog.userId, userId), eq(requestLog.requestId, requestId)));
			if (!prev || prev.fingerprint !== fingerprint)
				throw new OpsError('CONFLICT', 'This request id was already used for a different request.');
			return prev.result as T;
		}
		const result = plain(await fn(tx, userId));
		await tx
			.update(requestLog)
			.set({ result })
			.where(and(eq(requestLog.userId, userId), eq(requestLog.requestId, requestId)));
		return result;
	}) as Promise<T>;
}

/** Writes what a verb changed into the undo journal, in the verb's own transaction. */
export async function recordUndo(
	tx: Tx,
	userId: string,
	requestId: string | undefined,
	e: UndoEntry
) {
	const [entry] = await tx
		.insert(undoJournal)
		.values({
			userId,
			verb: e.verb,
			requestId: requestId ?? null,
			entity: e.entity,
			entityId: e.entityId,
			before: e.before === undefined ? null : plain(e.before),
			after: e.after === undefined ? null : plain(e.after)
		})
		.returning({ id: undoJournal.id });
	// The id undo takes, so a write can hand it back (a row's own id is not it)
	return entry?.id ?? null;
}
