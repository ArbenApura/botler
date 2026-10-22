-- THE HASH OF ONE AUDIT ROW: THE PREVIOUS HASH AND THE FIELDS THAT SAY WHAT HAPPENED. audit_verify RECOMPUTES IT WITH THIS SAME FUNCTION.
CREATE OR REPLACE FUNCTION audit_hash(prev text, seq bigint, entity text, entity_id text, action text, amount_delta integer, before jsonb, after jsonb, request_id text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
	SELECT encode(sha256(convert_to(concat_ws('|', coalesce(prev, ''), seq::text, entity, entity_id, action, coalesce(amount_delta::text, ''), coalesce(before::text, ''), coalesce(after::text, ''), coalesce(request_id, '')), 'UTF8')), 'hex')
$$;
--> statement-breakpoint
-- ONLY THE COLUMNS OF THE ALLOW-LIST ARE COPIED. A NOTE FROM AN OUTSIDE SOURCE (A PICTURE, THE WEB, GOOGLE) IS NEVER COPIED.
CREATE OR REPLACE FUNCTION audit_pick(j jsonb, cols text[])
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
	SELECT CASE WHEN j IS NULL THEN NULL ELSE (
		SELECT coalesce(jsonb_object_agg(key, CASE WHEN key = 'note' AND (j ->> 'source') IN ('ocr', 'screenshot', 'web', 'google', 'calendar') THEN 'null'::jsonb ELSE value END), '{}'::jsonb)
		FROM jsonb_each(j) WHERE key = ANY (cols)
	) END
$$;
--> statement-breakpoint
-- HOW ONE LEDGER ROW CHANGES THE BALANCE OF THE ACCOUNT IT IS FILED UNDER. A VOIDED ROW CHANGES NOTHING.
CREATE OR REPLACE FUNCTION audit_txn_effect(j jsonb)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
	SELECT CASE
		WHEN j IS NULL OR (j ->> 'voided_at') IS NOT NULL THEN 0
		WHEN j ->> 'type' IN ('income', 'refund', 'adjustment') THEN (j ->> 'amount')::integer
		WHEN j ->> 'type' = 'expense' THEN -(j ->> 'amount')::integer
		WHEN j ->> 'type' = 'transfer' THEN -((j ->> 'amount')::integer + coalesce((j ->> 'fee')::integer, 0))
		ELSE 0
	END
$$;
--> statement-breakpoint
-- THE TRIGGER BODY. ARGUMENTS: THE COLUMNS TO COPY (COMMA SEPARATED), THE COLUMN THAT NAMES THE ACCOUNT ('' FOR NONE), 'txn' FOR A LEDGER ROW.
-- Only the app's own role is audited: migrations, restores and maintenance run as another role and write nothing here.
-- The person's lock serialises the chain: two writes by one person take turns, so the sequence has no gap and the chain no fork.
CREATE OR REPLACE FUNCTION audit_row() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
	cols text[] := string_to_array(TG_ARGV[0], ',');
	rec jsonb;
	old_rec jsonb;
	uid text;
	ent_id text;
	acct uuid;
	act text;
	delta integer;
	last_seq bigint;
	last_hash text;
	new_seq bigint;
	new_before jsonb;
	new_after jsonb;
	req text := nullif(current_setting('app.request_id', true), '');
BEGIN
	IF current_user <> 'app_runtime' OR current_setting('app.audit_off', true) = 'on' THEN
		RETURN NULL;
	END IF;
	IF TG_OP = 'DELETE' THEN
		old_rec := to_jsonb(OLD); rec := NULL; uid := OLD.user_id;
	ELSIF TG_OP = 'INSERT' THEN
		rec := to_jsonb(NEW); old_rec := NULL; uid := NEW.user_id;
	ELSE
		rec := to_jsonb(NEW); old_rec := to_jsonb(OLD); uid := NEW.user_id;
	END IF;
	ent_id := coalesce(rec, old_rec) ->> 'id';
	IF TG_ARGV[1] <> '' THEN
		acct := nullif(coalesce(rec, old_rec) ->> TG_ARGV[1], '')::uuid;
	END IF;
	act := CASE TG_OP WHEN 'INSERT' THEN 'create' WHEN 'DELETE' THEN 'delete' ELSE 'update' END;
	IF current_setting('app.verb', true) = 'undo' THEN
		act := 'undo';
	ELSIF TG_TABLE_NAME = 'balance_snapshot' AND TG_OP = 'INSERT' THEN
		act := 'count';
	ELSIF TG_TABLE_NAME = 'ledger_txn' AND TG_OP = 'INSERT' AND rec ->> 'type' = 'adjustment' AND rec ->> 'category' = 'reset' THEN
		act := 'reset';
	ELSIF TG_TABLE_NAME = 'agent_action' AND TG_OP = 'UPDATE' THEN
		act := CASE rec ->> 'status' WHEN 'applied' THEN 'approve' WHEN 'rejected' THEN 'reject' WHEN 'expired' THEN 'expire' ELSE 'update' END;
	END IF;
	IF TG_ARGV[2] = 'txn' THEN
		delta := audit_txn_effect(rec) - audit_txn_effect(old_rec);
	END IF;
	new_before := audit_pick(old_rec, cols);
	new_after := audit_pick(rec, cols);
	PERFORM pg_advisory_xact_lock(hashtextextended(uid, 0));
	SELECT e.seq, e.hash INTO last_seq, last_hash FROM audit_event e WHERE e.user_id = uid ORDER BY e.seq DESC LIMIT 1;
	new_seq := coalesce(last_seq, 0) + 1;
	INSERT INTO audit_event (user_id, seq, actor_kind, on_behalf, actor_ref, channel, verb, entity, entity_id, account_id, action, amount_delta, before, after, request_id, approval_id, turn_id, undo_of, prev_hash, hash)
	VALUES (
		uid,
		new_seq,
		coalesce(nullif(current_setting('app.actor_kind', true), ''), 'system'),
		nullif(current_setting('app.on_behalf', true), ''),
		nullif(current_setting('app.actor_ref', true), ''),
		coalesce(nullif(current_setting('app.channel', true), ''), 'system'),
		nullif(current_setting('app.verb', true), ''),
		TG_TABLE_NAME,
		coalesce(ent_id, ''),
		acct,
		act,
		delta,
		new_before,
		new_after,
		req,
		nullif(current_setting('app.approval_id', true), ''),
		nullif(current_setting('app.turn_id', true), ''),
		nullif(current_setting('app.undo_of', true), ''),
		last_hash,
		audit_hash(last_hash, new_seq, TG_TABLE_NAME, coalesce(ent_id, ''), act, delta, new_before, new_after, req)
	);
	RETURN NULL;
END;
$$;
--> statement-breakpoint
-- THE TRAIL CANNOT BE EDITED OR SHORTENED. ONLY THE PERSON'S OWN DATA RESET (A FUNCTION OF THE OWNER) TURNS app.audit_erase ON FOR ITS TRANSACTION.
CREATE OR REPLACE FUNCTION audit_block() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
	IF current_setting('app.audit_erase', true) = 'on' THEN
		RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
	END IF;
	RAISE EXCEPTION 'audit_event is append-only';
END;
$$;
--> statement-breakpoint
CREATE TRIGGER audit_event_block BEFORE UPDATE OR DELETE ON "audit_event" FOR EACH ROW EXECUTE FUNCTION audit_block();
--> statement-breakpoint
CREATE TRIGGER "audit_account" AFTER INSERT OR UPDATE OR DELETE ON "account" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,kind,min_balance,sort_order,archived_at', 'id', '');
--> statement-breakpoint
CREATE TRIGGER "audit_ledger_txn" AFTER INSERT OR UPDATE OR DELETE ON "ledger_txn" FOR EACH ROW EXECUTE FUNCTION audit_row('id,type,account_id,to_account_id,amount,fee,category,note,occurred_at,source,bill_id,split_id,voided_at', 'account_id', 'txn');
--> statement-breakpoint
CREATE TRIGGER "audit_balance_snapshot" AFTER INSERT OR UPDATE OR DELETE ON "balance_snapshot" FOR EACH ROW EXECUTE FUNCTION audit_row('id,account_id,amount,taken_at,expected_amount,source', 'account_id', '');
--> statement-breakpoint
CREATE TRIGGER "audit_bill" AFTER INSERT OR UPDATE OR DELETE ON "bill" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,category,account_id,kind,amount,schedule,weekend_rule,deferrable,active', 'account_id', '');
--> statement-breakpoint
CREATE TRIGGER "audit_bill_payment" AFTER INSERT OR UPDATE OR DELETE ON "bill_payment" FOR EACH ROW EXECUTE FUNCTION audit_row('id,bill_id,due_date,window_start,window_end,amount,txn_id', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_goal" AFTER INSERT OR UPDATE OR DELETE ON "goal" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,account_id,target_amount,per_payday,active', 'account_id', '');
--> statement-breakpoint
CREATE TRIGGER "audit_allocation_rule" AFTER INSERT OR UPDATE OR DELETE ON "allocation_rule" FOR EACH ROW EXECUTE FUNCTION audit_row('id,position,mode,amount,basis_points,base,target_account_id,target_goal_id,effective_from,status,approved_at', 'target_account_id', '');
--> statement-breakpoint
CREATE TRIGGER "audit_income_schedule" AFTER INSERT OR UPDATE OR DELETE ON "income_schedule" FOR EACH ROW EXECUTE FUNCTION audit_row('id,label,account_id,expected_amount,schedule,weekend_rule,active', 'account_id', '');
--> statement-breakpoint
CREATE TRIGGER "audit_split_plan" AFTER INSERT OR UPDATE OR DELETE ON "split_plan" FOR EACH ROW EXECUTE FUNCTION audit_row('id,income_schedule_id,payday,pay,status,gap,approved_at,approved_by', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_task" AFTER INSERT OR UPDATE OR DELETE ON "task" FOR EACH ROW EXECUTE FUNCTION audit_row('id,status,priority,due_at,follow_up_at,source,done_at', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_calendar_event" AFTER INSERT OR UPDATE OR DELETE ON "calendar_event" FOR EACH ROW EXECUTE FUNCTION audit_row('id,starts_at,ends_at,all_day,source,ref_key,deleted_at', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_routine" AFTER INSERT OR UPDATE OR DELETE ON "routine" FOR EACH ROW EXECUTE FUNCTION audit_row('id,recurrence,lead_minutes,active', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_reminder" AFTER INSERT OR UPDATE OR DELETE ON "reminder" FOR EACH ROW EXECUTE FUNCTION audit_row('id,kind,ref_key,remind_at,status,origin', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_user_setting" AFTER INSERT OR UPDATE OR DELETE ON "user_setting" FOR EACH ROW EXECUTE FUNCTION audit_row('id,currency,language,reply_language,week_starts_on', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_agent_action" AFTER INSERT OR UPDATE OR DELETE ON "agent_action" FOR EACH ROW EXECUTE FUNCTION audit_row('id,verb,status,turn_id,expires_at,decided_at', '', '');
