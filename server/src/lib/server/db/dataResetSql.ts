// DATA RESET (BTL-20261022-0218, ADR 6): WHICH TABLES EACH SCOPE ERASES, AND THE SQL OF THE FUNCTION THAT DOES IT.
// The function is SECURITY DEFINER and owned by the migrating owner. It deletes only the rows of the person whose id is set in the session
// (app.user_id), in an order that respects the references between a person's tables, and then writes one tombstone row in the audit trail.
// The app role can run it but cannot delete anything itself. A test checks that every tenant table is erased by 'everything' or is kept on
// purpose, and that the migration file is exactly the SQL built here.

// -- TYPES -- //
export type ResetScope = 'money' | 'schedule' | 'memory_and_chat' | 'audit' | 'everything';

// -- CONSTANTS -- //

export const RESET_SCOPES: readonly ResetScope[] = [
	'money',
	'schedule',
	'memory_and_chat',
	'audit',
	'everything'
];

/**
 * The tables each scope empties, in the order they are deleted. A table that points at another is deleted first. The audit trail is a
 * scope of its own and is emptied last, so the tombstone is the only row left.
 */
export const SCOPE_TABLES: Record<
	Exclude<ResetScope, 'audit' | 'everything'>,
	readonly string[]
> = {
	money: [
		'bill_payment',
		'ledger_txn',
		'balance_snapshot',
		'split_plan',
		'allocation_rule',
		'goal',
		'bill_override',
		'bill',
		'income_schedule',
		'account',
		'undo_journal',
		'agent_action'
	],
	schedule: ['reminder', 'task', 'calendar_event', 'routine'],
	// A chat is deleted after its turns (the turns point at it)
	memory_and_chat: ['chat_turn', 'chat', 'memory_fact', 'memory_summary']
};

/**
 * The money scope as migration 0017 shipped it, kept as it was so the 0017 file stays checkable. Later tables are added to SCOPE_TABLES
 * and reach the database through a newer copy of the function (0018 and on), never by editing an applied migration.
 */
const MONEY_0017: readonly string[] = SCOPE_TABLES.money.filter((t) => t !== 'bill_override');

/** The memory and chat scope as migrations 0017 and 0018 shipped it, before conversations existed (0021 adds the chat table). */
const MEMORY_0017: readonly string[] = SCOPE_TABLES.memory_and_chat.filter((t) => t !== 'chat');

/** What 'everything' empties on top of the three scopes: the persona and what the person told it about themselves. */
export const EVERYTHING_EXTRA: readonly string[] = ['memory_profile'];

/**
 * Tables that a reset keeps, and why. The person stays signed in, keeps the settings they chose, the phone registrations and the counters that guard the model budget. The trail is handled by its own scope.
 */
export const KEPT_ON_RESET: Record<string, string> = {
	user_setting: 'the person keeps their settings',
	device: 'the phones stay registered',
	model_usage: 'the budget counters of the model must not be reset by the person',
	request_log: 'idempotency records, and the single-use reset confirmations',
	audit_event: 'erased by its own scope, which leaves the tombstone'
};

/** Every table 'everything' erases, in order. */
export const EVERYTHING_TABLES: readonly string[] = [
	...SCOPE_TABLES.money,
	...SCOPE_TABLES.schedule,
	...SCOPE_TABLES.memory_and_chat,
	...EVERYTHING_EXTRA
];

// -- FUNCTIONS -- //

const arr = (tables: readonly string[]) =>
	tables.length === 0 ? `ARRAY[]::text[]` : `ARRAY[${tables.map((t) => `'${t}'`).join(', ')}]`;

/** The tables a scope deletes. A scope that touches the trail is run through the same function. */
export function tablesOf(scope: ResetScope): readonly string[] {
	if (scope === 'audit') return [];
	if (scope === 'everything') return EVERYTHING_TABLES;
	return SCOPE_TABLES[scope];
}

/** The function for a given list of tables: the first migration (0017) and the newest one differ only by their lists. */
function resetFunctionSql(
	money: readonly string[],
	memory: readonly string[],
	everything: readonly string[]
): string {
	return `-- ERASE ONE PERSON'S DATA BY SCOPE. SECURITY DEFINER, OWNED BY THE MIGRATING OWNER. IT CAN ONLY ERASE THE PERSON SET IN THE SESSION (app.user_id).
-- The audit triggers stay quiet (this function runs as the owner), the trail's own guard is lifted for this transaction, and one tombstone
-- row says who, when, which scope and how many rows. When the trail itself is erased the chain starts again at 1 with that row.
CREATE OR REPLACE FUNCTION data_reset(p_user text, p_scope text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
	tables text[];
	t text;
	n bigint;
	counts jsonb := '{}'::jsonb;
	erase_trail boolean := p_scope IN ('audit', 'everything');
	last_seq bigint;
	last_hash text;
	new_seq bigint;
	actor text := coalesce(nullif(current_setting('app.actor_kind', true), ''), 'person');
	chan text := coalesce(nullif(current_setting('app.channel', true), ''), 'app');
	req text := nullif(current_setting('app.request_id', true), '');
BEGIN
	IF p_user IS NULL OR p_user IS DISTINCT FROM nullif(current_setting('app.user_id', true), '') THEN
		RAISE EXCEPTION 'A reset can only erase the data of the person who asks';
	END IF;
	tables := CASE p_scope
		WHEN 'money' THEN ${arr(money)}
		WHEN 'schedule' THEN ${arr(SCOPE_TABLES.schedule)}
		WHEN 'memory_and_chat' THEN ${arr(memory)}
		WHEN 'audit' THEN ${arr([])}
		WHEN 'everything' THEN ${arr(everything)}
		ELSE NULL
	END;
	IF tables IS NULL THEN
		RAISE EXCEPTION 'Unknown reset scope';
	END IF;
	PERFORM set_config('app.audit_erase', 'on', true);
	PERFORM pg_advisory_xact_lock(hashtextextended(p_user, 0));
	FOREACH t IN ARRAY tables LOOP
		EXECUTE format('DELETE FROM %I WHERE user_id = $1', t) USING p_user;
		GET DIAGNOSTICS n = ROW_COUNT;
		counts := counts || jsonb_build_object(t, n);
	END LOOP;
	IF p_scope <> 'audit' THEN
		-- Pending jobs would run on data that is gone, whichever part was erased
		DELETE FROM job WHERE user_id = p_user;
		GET DIAGNOSTICS n = ROW_COUNT;
		counts := counts || jsonb_build_object('job', n);
	END IF;
	IF erase_trail THEN
		DELETE FROM audit_event WHERE user_id = p_user;
		GET DIAGNOSTICS n = ROW_COUNT;
		counts := counts || jsonb_build_object('audit_event', n);
	END IF;
	SELECT e.seq, e.hash INTO last_seq, last_hash FROM audit_event e WHERE e.user_id = p_user ORDER BY e.seq DESC LIMIT 1;
	new_seq := coalesce(last_seq, 0) + 1;
	INSERT INTO audit_event (user_id, seq, actor_kind, channel, verb, entity, entity_id, action, after, request_id, prev_hash, hash)
	VALUES (
		p_user, new_seq, actor, chan, 'data.reset', 'data', p_scope, 'data_reset', counts, req, last_hash,
		audit_hash(last_hash, new_seq, 'data', p_scope, 'data_reset', NULL, NULL, counts, req)
	);
	PERFORM set_config('app.audit_erase', 'off', true);
	RETURN counts || jsonb_build_object('tombstone_seq', new_seq);
END;
$$;
`;
}

/** The first migration (0017), exactly as it ran. */
export function dataResetMigrationSql(): string {
	return resetFunctionSql(MONEY_0017, MEMORY_0017, [
		...MONEY_0017,
		...SCOPE_TABLES.schedule,
		...MEMORY_0017,
		...EVERYTHING_EXTRA
	]);
}

/** The function migration 0018 installed (bill overrides, before conversations). */
export function dataResetBillOverrideSql(): string {
	return resetFunctionSql(SCOPE_TABLES.money, MEMORY_0017, [
		...SCOPE_TABLES.money,
		...SCOPE_TABLES.schedule,
		...MEMORY_0017,
		...EVERYTHING_EXTRA
	]);
}

/** The function as it is now: what the newest migration (0021, conversations) installs over the one of 0018. */
export function dataResetLatestSql(): string {
	return resetFunctionSql(SCOPE_TABLES.money, SCOPE_TABLES.memory_and_chat, EVERYTHING_TABLES);
}
