ALTER TABLE "model_spend" ADD COLUMN "provider" text DEFAULT 'unknown' NOT NULL;--> statement-breakpoint
ALTER TABLE "model_spend" ADD COLUMN "charged_tokens" bigint DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "model_usage" ADD COLUMN "provider" text DEFAULT 'unknown' NOT NULL;--> statement-breakpoint
ALTER TABLE "model_usage" ADD COLUMN "cache_read_tokens" bigint DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "model_usage" ADD COLUMN "cache_write_tokens" bigint DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "model_usage" ADD COLUMN "charged_tokens" bigint DEFAULT 0 NOT NULL;--> statement-breakpoint
-- BACKFILL: EVERY OLD ROW COUNTS IN FULL (NO CACHE EXISTED), SO THE CAP READS THE SAME NUMBER AS BEFORE.
UPDATE "model_usage" SET "charged_tokens" = "prompt_tokens" + "completion_tokens";--> statement-breakpoint
UPDATE "model_spend" SET "charged_tokens" = "tokens";--> statement-breakpoint
ALTER TABLE "model_usage" DROP CONSTRAINT "model_usage_user_bucket_month_uq";--> statement-breakpoint
ALTER TABLE "model_spend" DROP CONSTRAINT "model_spend_month_bucket_pk";--> statement-breakpoint
ALTER TABLE "model_spend" ADD CONSTRAINT "model_spend_month_bucket_provider_pk" PRIMARY KEY("month","bucket","provider");--> statement-breakpoint
ALTER TABLE "model_usage" ADD CONSTRAINT "model_usage_user_bucket_month_provider_uq" UNIQUE("user_id","bucket","month","provider");--> statement-breakpoint
ALTER TABLE "model_spend" ADD CONSTRAINT "model_spend_provider_chk" CHECK ("model_spend"."provider" in ('anthropic', 'deepseek', 'unknown'));--> statement-breakpoint
ALTER TABLE "model_usage" ADD CONSTRAINT "model_usage_provider_chk" CHECK ("model_usage"."provider" in ('anthropic', 'deepseek', 'unknown'));
