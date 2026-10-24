ALTER TABLE "user_setting" DROP CONSTRAINT "user_setting_currency_chk";--> statement-breakpoint
ALTER TABLE "account" ALTER COLUMN "min_balance" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "allocation_rule" ALTER COLUMN "amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "balance_snapshot" ALTER COLUMN "amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "balance_snapshot" ALTER COLUMN "expected_amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "bill" ALTER COLUMN "amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "bill_override" ALTER COLUMN "amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "bill_payment" ALTER COLUMN "amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "goal" ALTER COLUMN "target_amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "goal" ALTER COLUMN "per_payday" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "income_schedule" ALTER COLUMN "expected_amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "ledger_txn" ALTER COLUMN "amount" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "ledger_txn" ALTER COLUMN "fee" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "split_plan" ALTER COLUMN "pay" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "split_plan" ALTER COLUMN "gap" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "audit_event" ALTER COLUMN "amount_delta" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_currency_chk" CHECK ("user_setting"."currency" in ('PHP', 'USD', 'EUR', 'GBP', 'JPY', 'KRW', 'CNY', 'HKD', 'SGD', 'AUD', 'NZD', 'CAD', 'CHF', 'INR', 'IDR', 'MYR', 'THB', 'VND', 'TWD', 'AED', 'SAR', 'AFN', 'ALL', 'AMD', 'ANG', 'AOA', 'ARS', 'AWG', 'AZN', 'BAM', 'BBD', 'BDT', 'BGN', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL', 'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CDF', 'CLP', 'COP', 'CRC', 'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP', 'ERN', 'ETB', 'FJD', 'FKP', 'GEL', 'GHS', 'GIP', 'GMD', 'GNF', 'GTQ', 'GYD', 'HNL', 'HTG', 'HUF', 'ILS', 'IQD', 'IRR', 'ISK', 'JMD', 'JOD', 'KES', 'KGS', 'KHR', 'KMF', 'KPW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP', 'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR', 'MVR', 'MWK', 'MXN', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR', 'OMR', 'PAB', 'PEN', 'PGK', 'PKR', 'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB', 'RWF', 'SBD', 'SCR', 'SDG', 'SEK', 'SHP', 'SLE', 'SOS', 'SRD', 'SSP', 'STN', 'SVC', 'SYP', 'SZL', 'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TZS', 'UAH', 'UGX', 'UYU', 'UZS', 'VES', 'VUV', 'WST', 'XAF', 'XCD', 'XOF', 'XPF', 'YER', 'ZAR', 'ZMW', 'ZWG'));
--> statement-breakpoint
-- AMOUNTS ARE 64 BIT NOW: THE AUDIT FUNCTIONS THAT WERE TYPED integer ARE REPLACED. 0016 STAYS AS IT RAN.
--> statement-breakpoint
DROP FUNCTION audit_hash(text, bigint, text, text, text, integer, jsonb, jsonb, text);
--> statement-breakpoint
DROP FUNCTION audit_txn_effect(jsonb);
--> statement-breakpoint
-- THE HASH OF ONE AUDIT ROW: THE PREVIOUS HASH AND THE FIELDS THAT SAY WHAT HAPPENED. audit_verify RECOMPUTES IT WITH THIS SAME FUNCTION.
CREATE OR REPLACE FUNCTION audit_hash(prev text, seq bigint, entity text, entity_id text, action text, amount_delta bigint, before jsonb, after jsonb, request_id text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
	SELECT encode(sha256(convert_to(concat_ws('|', coalesce(prev, ''), seq::text, entity, entity_id, action, coalesce(amount_delta::text, ''), coalesce(before::text, ''), coalesce(after::text, ''), coalesce(request_id, '')), 'UTF8')), 'hex')
$$;
--> statement-breakpoint
-- HOW ONE LEDGER ROW CHANGES THE BALANCE OF THE ACCOUNT IT IS FILED UNDER. A VOIDED ROW CHANGES NOTHING.
CREATE OR REPLACE FUNCTION audit_txn_effect(j jsonb)
RETURNS bigint LANGUAGE sql IMMUTABLE AS $$
	SELECT CASE
		WHEN j IS NULL OR (j ->> 'voided_at') IS NOT NULL THEN 0
		WHEN j ->> 'type' IN ('income', 'refund', 'adjustment') THEN (j ->> 'amount')::bigint
		WHEN j ->> 'type' = 'expense' THEN -(j ->> 'amount')::bigint
		WHEN j ->> 'type' = 'transfer' THEN -((j ->> 'amount')::bigint + coalesce((j ->> 'fee')::bigint, 0))
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
	delta bigint;
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
