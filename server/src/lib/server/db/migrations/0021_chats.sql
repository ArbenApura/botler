CREATE TABLE "chat" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"title" text,
	"pinned_at" timestamp with time zone,
	"archived_at" timestamp with time zone,
	"forked_from_chat_id" uuid,
	"forked_at_turn_id" uuid,
	"last_active_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "chat_user_id_uq" UNIQUE("user_id","id")
);
--> statement-breakpoint
-- THE CHAT_ID COLUMN STARTS EMPTY AND IS MADE REQUIRED ONLY AFTER EVERY EXISTING TURN HAS A CHAT (BELOW)
ALTER TABLE "chat_turn" ADD COLUMN "chat_id" uuid;--> statement-breakpoint
ALTER TABLE "chat_turn" ADD COLUMN "copied_from_turn_id" uuid;--> statement-breakpoint
ALTER TABLE "chat" ADD CONSTRAINT "chat_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "chat_user_active_idx" ON "chat" USING btree ("user_id","last_active_at");--> statement-breakpoint
-- BACKFILL: ONE CHAT PER PERSON AND PER EARLIER "NEW CHAT" BATCH (THE TURNS SET ASIDE TOGETHER SHARE ONE cleared_at), PLUS THE LIVE ONE.
-- A turn left running when a batch was set aside still has no cleared_at: it belongs to the first batch cleared after it was made.
-- The owner is bound by forced row level security on the turns, so it is lifted for this migration only; the security statements put it back.
ALTER TABLE "chat_turn" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TEMP TABLE "chat_backfill" ON COMMIT DROP AS
SELECT t.id AS turn_id, t.user_id, t.created_at,
	coalesce(t.cleared_at, (SELECT min(x.cleared_at) FROM "chat_turn" x WHERE x.user_id = t.user_id AND x.cleared_at > t.created_at)) AS batch
FROM "chat_turn" t;--> statement-breakpoint
CREATE TEMP TABLE "chat_backfill_chat" ON COMMIT DROP AS
SELECT user_id, batch, gen_random_uuid() AS chat_id, max(created_at) AS last_at FROM "chat_backfill" GROUP BY user_id, batch;--> statement-breakpoint
INSERT INTO "chat" ("id", "user_id", "last_active_at", "created_at", "updated_at")
SELECT chat_id, user_id, last_at, last_at, last_at FROM "chat_backfill_chat";--> statement-breakpoint
UPDATE "chat_turn" t SET "chat_id" = c.chat_id
FROM "chat_backfill" b JOIN "chat_backfill_chat" c ON c.user_id = b.user_id AND c.batch IS NOT DISTINCT FROM b.batch
WHERE t.id = b.turn_id;--> statement-breakpoint
-- A person whose last act was "new chat" opens on an empty chat, as before
INSERT INTO "chat" ("user_id")
SELECT DISTINCT user_id FROM "chat_backfill_chat" u
WHERE NOT EXISTS (SELECT 1 FROM "chat_backfill_chat" l WHERE l.user_id = u.user_id AND l.batch IS NULL);--> statement-breakpoint
ALTER TABLE "chat_turn" ALTER COLUMN "chat_id" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "chat_turn" ADD CONSTRAINT "chat_turn_chat_fk" FOREIGN KEY ("user_id","chat_id") REFERENCES "public"."chat"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "chat_turn_chat_created_idx" ON "chat_turn" USING btree ("user_id","chat_id","created_at");--> statement-breakpoint
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
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'chat', 'memory_fact', 'memory_summary']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'chat_turn', 'chat', 'memory_fact', 'memory_summary', 'memory_profile']
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
