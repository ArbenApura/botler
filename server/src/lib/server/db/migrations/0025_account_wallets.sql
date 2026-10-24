CREATE TABLE "account_wallet" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid NOT NULL,
	"currency" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "account_wallet_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "account_wallet_currency_uq" UNIQUE("user_id","account_id","currency"),
	CONSTRAINT "account_wallet_currency_chk" CHECK ("account_wallet"."currency" ~ '^[A-Z]{3}$')
);
--> statement-breakpoint
ALTER TABLE "ledger_txn" DROP CONSTRAINT "ledger_txn_transfer_chk";--> statement-breakpoint
DROP INDEX "balance_snapshot_account_time_idx";--> statement-breakpoint
ALTER TABLE "account" ADD COLUMN "currency" text DEFAULT 'PHP' NOT NULL;--> statement-breakpoint
ALTER TABLE "balance_snapshot" ADD COLUMN "currency" text DEFAULT 'PHP' NOT NULL;--> statement-breakpoint
ALTER TABLE "bill" ADD COLUMN "currency" text DEFAULT 'PHP' NOT NULL;--> statement-breakpoint
ALTER TABLE "bill_payment" ADD COLUMN "currency" text DEFAULT 'PHP' NOT NULL;--> statement-breakpoint
ALTER TABLE "bill_payment" ADD COLUMN "paid_currency" text;--> statement-breakpoint
ALTER TABLE "bill_payment" ADD COLUMN "paid_amount" bigint;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD COLUMN "currency" text DEFAULT 'PHP' NOT NULL;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD COLUMN "to_currency" text;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD COLUMN "to_amount" bigint;--> statement-breakpoint
-- BACKFILL: EVERY EXISTING AMOUNT WAS IN THE CURRENCY THE PERSON HAD SET (PESOS WHEN NONE), SO THAT IS THE CURRENCY OF EVERY OLD ROW.
-- The owner is bound by forced row level security (it is not a superuser) and has no policy to update or read these tables, so it is lifted
-- for this migration only on the tables read or written below; the security statements put it back when the migrations are done.
ALTER TABLE "user_setting" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "account" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "ledger_txn" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "balance_snapshot" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "bill" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "bill_payment" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
UPDATE "account" a SET "currency" = s."currency" FROM "user_setting" s WHERE s."user_id" = a."user_id" AND a."currency" <> s."currency";--> statement-breakpoint
UPDATE "ledger_txn" t SET "currency" = s."currency" FROM "user_setting" s WHERE s."user_id" = t."user_id" AND t."currency" <> s."currency";--> statement-breakpoint
UPDATE "balance_snapshot" b SET "currency" = s."currency" FROM "user_setting" s WHERE s."user_id" = b."user_id" AND b."currency" <> s."currency";--> statement-breakpoint
UPDATE "bill" b SET "currency" = s."currency" FROM "user_setting" s WHERE s."user_id" = b."user_id" AND b."currency" <> s."currency";--> statement-breakpoint
UPDATE "bill_payment" p SET "currency" = b."currency" FROM "bill" b WHERE b."user_id" = p."user_id" AND b."id" = p."bill_id" AND p."currency" <> b."currency";--> statement-breakpoint
-- A TRANSFER LANDS IN THE SAME CURRENCY IT LEFT IN, WITH NO SEPARATE AMOUNT.
UPDATE "ledger_txn" SET "to_currency" = "currency" WHERE "type" = 'transfer' AND "to_currency" IS NULL;--> statement-breakpoint
-- ONE WALLET FOR EVERY CURRENCY AN ACCOUNT ALREADY HOLDS (ITS OWN, AND ANY OTHER FOUND IN ITS ENTRIES AND COUNTS).
INSERT INTO "account_wallet" ("user_id", "account_id", "currency")
SELECT "user_id", "id", "currency" FROM "account"
UNION SELECT "user_id", "account_id", "currency" FROM "ledger_txn"
UNION SELECT "user_id", "to_account_id", "to_currency" FROM "ledger_txn" WHERE "to_account_id" IS NOT NULL
UNION SELECT "user_id", "account_id", "currency" FROM "balance_snapshot";--> statement-breakpoint
ALTER TABLE "account_wallet" ADD CONSTRAINT "account_wallet_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "account_wallet" ADD CONSTRAINT "account_wallet_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "balance_snapshot_account_time_idx" ON "balance_snapshot" USING btree ("user_id","account_id","currency","taken_at");--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_currency_chk" CHECK ("account"."currency" ~ '^[A-Z]{3}$');--> statement-breakpoint
ALTER TABLE "balance_snapshot" ADD CONSTRAINT "balance_snapshot_currency_chk" CHECK ("balance_snapshot"."currency" ~ '^[A-Z]{3}$');--> statement-breakpoint
ALTER TABLE "bill" ADD CONSTRAINT "bill_currency_chk" CHECK ("bill"."currency" ~ '^[A-Z]{3}$');--> statement-breakpoint
ALTER TABLE "bill_payment" ADD CONSTRAINT "bill_payment_currency_chk" CHECK ("bill_payment"."currency" ~ '^[A-Z]{3}$');--> statement-breakpoint
ALTER TABLE "bill_payment" ADD CONSTRAINT "bill_payment_paid_chk" CHECK (("bill_payment"."paid_currency" is null and "bill_payment"."paid_amount" is null) or ("bill_payment"."paid_currency" ~ '^[A-Z]{3}$' and "bill_payment"."paid_amount" > 0));--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_currency_chk" CHECK ("ledger_txn"."currency" ~ '^[A-Z]{3}$');--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_to_currency_chk" CHECK (("ledger_txn"."type" = 'transfer' and "ledger_txn"."to_currency" is not null and "ledger_txn"."to_currency" ~ '^[A-Z]{3}$'
				and (("ledger_txn"."to_currency" = "ledger_txn"."currency" and "ledger_txn"."to_amount" is null) or ("ledger_txn"."to_currency" <> "ledger_txn"."currency" and "ledger_txn"."to_amount" > 0)))
				or ("ledger_txn"."type" <> 'transfer' and "ledger_txn"."to_currency" is null and "ledger_txn"."to_amount" is null));--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_transfer_chk" CHECK (("ledger_txn"."type" = 'transfer' and "ledger_txn"."to_account_id" is not null and ("ledger_txn"."to_account_id" <> "ledger_txn"."account_id" or "ledger_txn"."to_currency" is distinct from "ledger_txn"."currency")) or ("ledger_txn"."type" <> 'transfer' and "ledger_txn"."to_account_id" is null));
--> statement-breakpoint
-- THE AUDIT TRIGGERS OF THE NEW WALLET TABLE AND OF THE TABLES THAT GAINED A CURRENCY. 0016 AND THE OLDER REPLACEMENTS STAY AS THEY RAN.
CREATE TRIGGER "audit_account_wallet" AFTER INSERT OR UPDATE OR DELETE ON "account_wallet" FOR EACH ROW EXECUTE FUNCTION audit_row('id,account_id,currency', 'account_id', '');
--> statement-breakpoint
DROP TRIGGER "audit_account" ON "account";
--> statement-breakpoint
CREATE TRIGGER "audit_account" AFTER INSERT OR UPDATE OR DELETE ON "account" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,kind,min_balance,sort_order,archived_at,purpose,currency', 'id', '');
--> statement-breakpoint
DROP TRIGGER "audit_ledger_txn" ON "ledger_txn";
--> statement-breakpoint
CREATE TRIGGER "audit_ledger_txn" AFTER INSERT OR UPDATE OR DELETE ON "ledger_txn" FOR EACH ROW EXECUTE FUNCTION audit_row('id,type,account_id,to_account_id,amount,fee,category,note,occurred_at,source,bill_id,split_id,voided_at,currency,to_currency,to_amount', 'account_id', 'txn');
--> statement-breakpoint
DROP TRIGGER "audit_balance_snapshot" ON "balance_snapshot";
--> statement-breakpoint
CREATE TRIGGER "audit_balance_snapshot" AFTER INSERT OR UPDATE OR DELETE ON "balance_snapshot" FOR EACH ROW EXECUTE FUNCTION audit_row('id,account_id,amount,taken_at,expected_amount,source,currency', 'account_id', '');
--> statement-breakpoint
DROP TRIGGER "audit_bill" ON "bill";
--> statement-breakpoint
CREATE TRIGGER "audit_bill" AFTER INSERT OR UPDATE OR DELETE ON "bill" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,category,account_id,kind,amount,schedule,weekend_rule,deferrable,active,starts_on,currency', 'account_id', '');
--> statement-breakpoint
DROP TRIGGER "audit_bill_payment" ON "bill_payment";
--> statement-breakpoint
CREATE TRIGGER "audit_bill_payment" AFTER INSERT OR UPDATE OR DELETE ON "bill_payment" FOR EACH ROW EXECUTE FUNCTION audit_row('id,bill_id,due_date,window_start,window_end,amount,txn_id,currency,paid_currency,paid_amount', '', '');
--> statement-breakpoint
-- THE DATA RESET ERASES THE WALLETS OF AN ACCOUNT BEFORE THE ACCOUNT.
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
		WHEN 'money' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'undo_journal', 'agent_action']
		WHEN 'schedule' THEN ARRAY['reminder', 'task', 'calendar_event', 'routine']
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'chat', 'memory_fact', 'memory_summary']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'chat_turn', 'chat', 'memory_fact', 'memory_summary', 'memory_profile']
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
