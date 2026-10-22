CREATE TABLE "model_spend" (
	"month" text NOT NULL,
	"bucket" text NOT NULL,
	"calls" integer DEFAULT 0 NOT NULL,
	"tokens" bigint DEFAULT 0 NOT NULL,
	CONSTRAINT "model_spend_month_bucket_pk" PRIMARY KEY("month","bucket")
);
--> statement-breakpoint
CREATE TABLE "model_usage" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"bucket" text NOT NULL,
	"month" text NOT NULL,
	"calls" integer DEFAULT 0 NOT NULL,
	"prompt_tokens" bigint DEFAULT 0 NOT NULL,
	"completion_tokens" bigint DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "model_usage_user_bucket_month_uq" UNIQUE("user_id","bucket","month"),
	CONSTRAINT "model_usage_bucket_chk" CHECK ("model_usage"."bucket" in ('chat', 'memory'))
);
--> statement-breakpoint
ALTER TABLE "model_usage" ADD CONSTRAINT "model_usage_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;