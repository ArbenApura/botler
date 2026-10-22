CREATE TABLE "bill_override" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"bill_id" uuid NOT NULL,
	"original_due_date" date NOT NULL,
	"new_due_date" date,
	"amount" integer,
	"account_id" uuid,
	"skipped" boolean DEFAULT false NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "bill_override_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "bill_override_occurrence_uq" UNIQUE("user_id","bill_id","original_due_date"),
	CONSTRAINT "bill_override_amount_chk" CHECK ("bill_override"."amount" is null or "bill_override"."amount" > 0),
	CONSTRAINT "bill_override_move_chk" CHECK ("bill_override"."new_due_date" is null or "bill_override"."new_due_date" <> "bill_override"."original_due_date"),
	CONSTRAINT "bill_override_skip_chk" CHECK (not "bill_override"."skipped" or ("bill_override"."new_due_date" is null and "bill_override"."amount" is null and "bill_override"."account_id" is null)),
	CONSTRAINT "bill_override_effect_chk" CHECK ("bill_override"."skipped" or "bill_override"."new_due_date" is not null or "bill_override"."amount" is not null or "bill_override"."account_id" is not null)
);
--> statement-breakpoint
ALTER TABLE "bill_override" ADD CONSTRAINT "bill_override_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill_override" ADD CONSTRAINT "bill_override_bill_fk" FOREIGN KEY ("user_id","bill_id") REFERENCES "public"."bill"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill_override" ADD CONSTRAINT "bill_override_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;
--> statement-breakpoint
CREATE TRIGGER "audit_bill_override" AFTER INSERT OR UPDATE OR DELETE ON "bill_override" FOR EACH ROW EXECUTE FUNCTION audit_row('id,bill_id,original_due_date,new_due_date,amount,account_id,skipped', 'account_id', '');
--> statement-breakpoint
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
		WHEN 'money' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account', 'undo_journal', 'agent_action']
		WHEN 'schedule' THEN ARRAY['reminder', 'task', 'calendar_event', 'routine']
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'memory_fact', 'memory_summary']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'chat_turn', 'memory_fact', 'memory_summary', 'memory_profile']
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
