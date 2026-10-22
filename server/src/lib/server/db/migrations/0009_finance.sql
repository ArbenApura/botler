CREATE TABLE "account" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"kind" text DEFAULT 'bank' NOT NULL,
	"min_balance" integer DEFAULT 0 NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"archived_at" timestamp with time zone,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "account_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "account_kind_chk" CHECK ("account"."kind" in ('bank', 'ewallet', 'cash', 'other')),
	CONSTRAINT "account_min_balance_chk" CHECK ("account"."min_balance" >= 0)
);
--> statement-breakpoint
CREATE TABLE "allocation_rule" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"position" integer NOT NULL,
	"mode" text NOT NULL,
	"amount" integer,
	"basis_points" integer,
	"base" text DEFAULT 'pay' NOT NULL,
	"target_account_id" uuid,
	"target_goal_id" uuid,
	"effective_from" date NOT NULL,
	"status" text DEFAULT 'proposed' NOT NULL,
	"source_text" text,
	"approved_at" timestamp with time zone,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "allocation_rule_mode_chk" CHECK ("allocation_rule"."mode" in ('fixed', 'percent', 'rest')),
	CONSTRAINT "allocation_rule_base_chk" CHECK ("allocation_rule"."base" in ('pay', 'remaining')),
	CONSTRAINT "allocation_rule_status_chk" CHECK ("allocation_rule"."status" in ('proposed', 'active', 'retired')),
	CONSTRAINT "allocation_rule_target_chk" CHECK (("allocation_rule"."target_account_id" is not null)::int + ("allocation_rule"."target_goal_id" is not null)::int = 1),
	CONSTRAINT "allocation_rule_value_chk" CHECK (("allocation_rule"."mode" = 'fixed' and "allocation_rule"."amount" > 0 and "allocation_rule"."basis_points" is null)
				or ("allocation_rule"."mode" = 'percent' and "allocation_rule"."basis_points" between 1 and 10000 and "allocation_rule"."amount" is null)
				or ("allocation_rule"."mode" = 'rest' and "allocation_rule"."amount" is null and "allocation_rule"."basis_points" is null))
);
--> statement-breakpoint
CREATE TABLE "balance_snapshot" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid NOT NULL,
	"amount" integer NOT NULL,
	"taken_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expected_amount" integer,
	"source" text DEFAULT 'manual' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "bill" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"category" text DEFAULT 'other' NOT NULL,
	"account_id" uuid NOT NULL,
	"kind" text DEFAULT 'fixed' NOT NULL,
	"amount" integer,
	"schedule" jsonb NOT NULL,
	"weekend_rule" text DEFAULT 'none' NOT NULL,
	"deferrable" boolean DEFAULT false NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "bill_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "bill_kind_chk" CHECK ("bill"."kind" in ('fixed', 'variable')),
	CONSTRAINT "bill_weekend_chk" CHECK ("bill"."weekend_rule" in ('none', 'before', 'after')),
	CONSTRAINT "bill_amount_chk" CHECK ("bill"."amount" is null or "bill"."amount" > 0),
	CONSTRAINT "bill_fixed_amount_chk" CHECK ("bill"."kind" <> 'fixed' or "bill"."amount" is not null)
);
--> statement-breakpoint
CREATE TABLE "bill_payment" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"bill_id" uuid NOT NULL,
	"due_date" date NOT NULL,
	"amount" integer NOT NULL,
	"paid_at" timestamp with time zone DEFAULT now() NOT NULL,
	"txn_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "bill_payment_due_uq" UNIQUE("user_id","bill_id","due_date"),
	CONSTRAINT "bill_payment_amount_chk" CHECK ("bill_payment"."amount" > 0)
);
--> statement-breakpoint
CREATE TABLE "goal" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"account_id" uuid NOT NULL,
	"target_amount" integer,
	"per_payday" integer DEFAULT 0 NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "goal_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "goal_target_chk" CHECK ("goal"."target_amount" is null or "goal"."target_amount" > 0),
	CONSTRAINT "goal_per_payday_chk" CHECK ("goal"."per_payday" >= 0)
);
--> statement-breakpoint
CREATE TABLE "income_schedule" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"label" text NOT NULL,
	"account_id" uuid NOT NULL,
	"expected_amount" integer,
	"schedule" jsonb NOT NULL,
	"weekend_rule" text DEFAULT 'before' NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "income_schedule_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "income_schedule_weekend_chk" CHECK ("income_schedule"."weekend_rule" in ('none', 'before', 'after')),
	CONSTRAINT "income_schedule_amount_chk" CHECK ("income_schedule"."expected_amount" is null or "income_schedule"."expected_amount" > 0)
);
--> statement-breakpoint
CREATE TABLE "ledger_txn" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"type" text NOT NULL,
	"account_id" uuid NOT NULL,
	"to_account_id" uuid,
	"amount" integer NOT NULL,
	"fee" integer DEFAULT 0 NOT NULL,
	"category" text,
	"note" text DEFAULT '' NOT NULL,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	"source" text DEFAULT 'manual' NOT NULL,
	"bill_id" uuid,
	"split_id" uuid,
	"voided_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "ledger_txn_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "ledger_txn_type_chk" CHECK ("ledger_txn"."type" in ('income', 'expense', 'transfer', 'refund', 'adjustment')),
	CONSTRAINT "ledger_txn_source_chk" CHECK ("ledger_txn"."source" in ('manual', 'chat', 'ocr', 'screenshot', 'split', 'bill', 'drift')),
	CONSTRAINT "ledger_txn_amount_chk" CHECK (("ledger_txn"."type" = 'adjustment' and "ledger_txn"."amount" <> 0) or ("ledger_txn"."type" <> 'adjustment' and "ledger_txn"."amount" > 0)),
	CONSTRAINT "ledger_txn_fee_chk" CHECK ("ledger_txn"."fee" >= 0 and ("ledger_txn"."fee" = 0 or "ledger_txn"."type" = 'transfer')),
	CONSTRAINT "ledger_txn_transfer_chk" CHECK (("ledger_txn"."type" = 'transfer' and "ledger_txn"."to_account_id" is not null and "ledger_txn"."to_account_id" <> "ledger_txn"."account_id") or ("ledger_txn"."type" <> 'transfer' and "ledger_txn"."to_account_id" is null))
);
--> statement-breakpoint
CREATE TABLE "split_plan" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"income_schedule_id" uuid,
	"payday" date NOT NULL,
	"pay" integer NOT NULL,
	"status" text DEFAULT 'proposed' NOT NULL,
	"gap" integer DEFAULT 0 NOT NULL,
	"result" jsonb NOT NULL,
	"sent_transfers" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"approved_at" timestamp with time zone,
	"approved_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "split_plan_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "split_plan_status_chk" CHECK ("split_plan"."status" in ('proposed', 'approved', 'shortfall', 'superseded'))
);
--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "allocation_rule" ADD CONSTRAINT "allocation_rule_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "allocation_rule" ADD CONSTRAINT "allocation_rule_account_fk" FOREIGN KEY ("user_id","target_account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "allocation_rule" ADD CONSTRAINT "allocation_rule_goal_fk" FOREIGN KEY ("user_id","target_goal_id") REFERENCES "public"."goal"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "balance_snapshot" ADD CONSTRAINT "balance_snapshot_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "balance_snapshot" ADD CONSTRAINT "balance_snapshot_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill" ADD CONSTRAINT "bill_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill" ADD CONSTRAINT "bill_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill_payment" ADD CONSTRAINT "bill_payment_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill_payment" ADD CONSTRAINT "bill_payment_bill_fk" FOREIGN KEY ("user_id","bill_id") REFERENCES "public"."bill"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bill_payment" ADD CONSTRAINT "bill_payment_txn_fk" FOREIGN KEY ("user_id","txn_id") REFERENCES "public"."ledger_txn"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "goal" ADD CONSTRAINT "goal_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "goal" ADD CONSTRAINT "goal_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "income_schedule" ADD CONSTRAINT "income_schedule_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "income_schedule" ADD CONSTRAINT "income_schedule_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_account_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_to_account_fk" FOREIGN KEY ("user_id","to_account_id") REFERENCES "public"."account"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_bill_fk" FOREIGN KEY ("user_id","bill_id") REFERENCES "public"."bill"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "split_plan" ADD CONSTRAINT "split_plan_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "split_plan" ADD CONSTRAINT "split_plan_income_fk" FOREIGN KEY ("user_id","income_schedule_id") REFERENCES "public"."income_schedule"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "account_user_name_uq" ON "account" USING btree ("user_id",lower("name"));--> statement-breakpoint
CREATE INDEX "allocation_rule_user_status_idx" ON "allocation_rule" USING btree ("user_id","status","position");--> statement-breakpoint
CREATE INDEX "balance_snapshot_account_time_idx" ON "balance_snapshot" USING btree ("user_id","account_id","taken_at");--> statement-breakpoint
CREATE INDEX "bill_payment_bill_paid_idx" ON "bill_payment" USING btree ("user_id","bill_id","paid_at");--> statement-breakpoint
CREATE UNIQUE INDEX "goal_user_name_uq" ON "goal" USING btree ("user_id",lower("name"));--> statement-breakpoint
CREATE INDEX "ledger_txn_account_time_idx" ON "ledger_txn" USING btree ("user_id","account_id","occurred_at");--> statement-breakpoint
CREATE INDEX "ledger_txn_to_account_idx" ON "ledger_txn" USING btree ("user_id","to_account_id");--> statement-breakpoint
CREATE INDEX "split_plan_user_payday_idx" ON "split_plan" USING btree ("user_id","payday");