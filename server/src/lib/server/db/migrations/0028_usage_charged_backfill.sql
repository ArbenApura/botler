-- BACKFILL OF 0027 THAT DID NOT REACH THE PERSON ROWS: THE OWNER IS BOUND BY FORCED ROW LEVEL SECURITY (IT IS NOT A SUPERUSER) AND HAS NO POLICY TO UPDATE
-- model_usage, SO THE UPDATE IN 0027 MATCHED NO ROWS AND EVERY OLD ROW KEPT charged_tokens = 0, WHICH MADE THE MONTH'S USAGE READ AS ZERO AGAINST THE CAP.
-- Every row from before the provider was recorded has provider 'unknown' and counts in full. Safe to run again: it only touches rows still at 0.
-- Lifted for this migration only; the security statements put it back when the migrations are done.
ALTER TABLE "model_usage" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
UPDATE "model_usage" SET "charged_tokens" = "prompt_tokens" + "completion_tokens" WHERE "provider" = 'unknown' AND "charged_tokens" = 0 AND ("prompt_tokens" + "completion_tokens") > 0;--> statement-breakpoint
ALTER TABLE "model_usage" FORCE ROW LEVEL SECURITY;
