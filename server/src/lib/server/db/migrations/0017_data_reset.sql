-- ERASE ONE PERSON'S DATA BY SCOPE. SECURITY DEFINER, OWNED BY THE MIGRATING OWNER. IT CAN ONLY ERASE THE PERSON SET IN THE SESSION (app.user_id).
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
		WHEN 'money' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill', 'income_schedule', 'account', 'undo_journal', 'agent_action']
		WHEN 'schedule' THEN ARRAY['reminder', 'task', 'calendar_event', 'routine']
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'memory_fact', 'memory_summary']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill', 'income_schedule', 'account', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'chat_turn', 'memory_fact', 'memory_summary', 'memory_profile']
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
