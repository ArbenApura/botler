CREATE TABLE "picture" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"mime" text NOT NULL,
	"data" text NOT NULL,
	"bytes" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "picture_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "picture_mime_chk" CHECK ("picture"."mime" in ('image/jpeg', 'image/png', 'image/webp')),
	CONSTRAINT "picture_bytes_chk" CHECK ("picture"."bytes" between 1 and 24576)
);
--> statement-breakpoint
ALTER TABLE "account" ADD COLUMN "icon" text;--> statement-breakpoint
ALTER TABLE "account" ADD COLUMN "image_id" uuid;--> statement-breakpoint
ALTER TABLE "bill" ADD COLUMN "icon" text;--> statement-breakpoint
ALTER TABLE "bill" ADD COLUMN "image_id" uuid;--> statement-breakpoint
ALTER TABLE "picture" ADD CONSTRAINT "picture_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_image_fk" FOREIGN KEY ("user_id","image_id") REFERENCES "public"."picture"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill" ADD CONSTRAINT "bill_image_fk" FOREIGN KEY ("user_id","image_id") REFERENCES "public"."picture"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "account_image_uq" ON "account" USING btree ("user_id","image_id");--> statement-breakpoint
CREATE UNIQUE INDEX "bill_image_uq" ON "bill" USING btree ("user_id","image_id");--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_icon_chk" CHECK ("account"."icon" is null or "account"."icon" ~ '^[a-z0-9_]{1,24}$');--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_mark_chk" CHECK ("account"."icon" is null or "account"."image_id" is null);--> statement-breakpoint
ALTER TABLE "bill" ADD CONSTRAINT "bill_icon_chk" CHECK ("bill"."icon" is null or "bill"."icon" ~ '^[a-z0-9_]{1,24}$');--> statement-breakpoint
ALTER TABLE "bill" ADD CONSTRAINT "bill_mark_chk" CHECK ("bill"."icon" is null or "bill"."image_id" is null);
--> statement-breakpoint
-- THE AUDIT TRIGGERS OF account AND bill ALSO COPY THE ICON KEY AND THE PICTURE ID (NEVER THE PICTURE BYTES). 0022, 0023 AND 0025 STAY AS THEY RAN; THE TRIGGERS ARE REPLACED HERE.
DROP TRIGGER "audit_account" ON "account";
--> statement-breakpoint
CREATE TRIGGER "audit_account" AFTER INSERT OR UPDATE OR DELETE ON "account" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,kind,min_balance,sort_order,archived_at,purpose,currency,icon,image_id', 'id', '');
--> statement-breakpoint
DROP TRIGGER "audit_bill" ON "bill";
--> statement-breakpoint
CREATE TRIGGER "audit_bill" AFTER INSERT OR UPDATE OR DELETE ON "bill" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,category,account_id,kind,amount,schedule,weekend_rule,deferrable,active,starts_on,currency,icon,image_id', 'account_id', '');
--> statement-breakpoint
-- THE DATA RESET ALSO ERASES THE PICTURES, AFTER THE ACCOUNTS AND BILLS THAT POINT AT THEM. 0037 STAYS AS IT RAN; THE FUNCTION IS REPLACED HERE.
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
		WHEN 'money' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'picture', 'undo_journal', 'agent_action']
		WHEN 'schedule' THEN ARRAY['reminder', 'task', 'calendar_event', 'routine']
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'chat', 'memory_fact', 'memory_summary', 'notebook_page_revision', 'notebook_page', 'notebook_revision', 'notebook']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'picture', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'chat_turn', 'chat', 'memory_fact', 'memory_summary', 'notebook_page_revision', 'notebook_page', 'notebook_revision', 'notebook', 'memory_profile']
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
