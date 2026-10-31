ALTER TABLE "model_spend" DROP CONSTRAINT "model_spend_provider_chk";--> statement-breakpoint
ALTER TABLE "model_usage" DROP CONSTRAINT "model_usage_provider_chk";--> statement-breakpoint
ALTER TABLE "user_setting" DROP CONSTRAINT "user_setting_model_provider_chk";--> statement-breakpoint
ALTER TABLE "chat_turn" ADD COLUMN "run_no" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
-- AN OLD ROW THAT CHOSE THE REMOVED ANTHROPIC SERVER IS SET BACK TO THE DEFAULT (NULL) FIRST: A NOT VALID CHECK STILL GUARDS EVERY NEW VERSION OF A ROW, SO SAVING ANY SETTING OF SUCH A PERSON WOULD FAIL.
-- The owner is bound by forced row level security with no update policy, so it is lifted for this statement only (as 0028 did). Safe to run again.
ALTER TABLE "user_setting" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
UPDATE "user_setting" SET "model_provider" = NULL WHERE "model_provider" = 'anthropic';--> statement-breakpoint
ALTER TABLE "user_setting" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "model_spend" ADD CONSTRAINT "model_spend_provider_chk" CHECK ("model_spend"."provider" in ('deepseek', 'unknown')) NOT VALID;--> statement-breakpoint
ALTER TABLE "model_usage" ADD CONSTRAINT "model_usage_provider_chk" CHECK ("model_usage"."provider" in ('deepseek', 'unknown')) NOT VALID;--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_model_provider_chk" CHECK ("user_setting"."model_provider" in ('deepseek')) NOT VALID;