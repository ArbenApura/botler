-- COMPOSITE REFERENCES FOR TWO COLUMNS THAT WERE PLAIN IDS: ledger_txn.split_id AND memory_fact.superseded_by (BTL: A PLAIN ID BETWEEN A PERSON'S TABLES CAN POINT AT NOTHING).
-- NOT ADDED ON PURPOSE (a reference there would change what they mean): chat.forked_from_chat_id, chat.forked_at_turn_id and chat.summary_through_turn_id are plain ids so the
-- source can be erased without touching a fork or a summary; chat_turn.copied_from_turn_id is a marker ("this turn was copied into a fork") that must survive its source.
-- FIRST A DATA STEP: A VALUE THAT POINTS AT NO ROW IS CLEARED, OR THE KEY WOULD REFUSE TO BE ADDED. The owner is bound by forced row level security with no policy to
-- read or update these tables, so it is lifted for this step only (as 0028 and 0033 did) and put back at the end. The audit trigger only records changes made by
-- app_runtime, so this clean up is not in the audit trail. Safe to run again: it only touches values that still point at nothing.
ALTER TABLE "ledger_txn" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "split_plan" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "memory_fact" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
UPDATE "ledger_txn" AS t SET "split_id" = NULL WHERE t."split_id" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "split_plan" AS s WHERE s."user_id" = t."user_id" AND s."id" = t."split_id");--> statement-breakpoint
UPDATE "memory_fact" AS t SET "superseded_by" = NULL WHERE t."superseded_by" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "memory_fact" AS s WHERE s."user_id" = t."user_id" AND s."id" = t."superseded_by");--> statement-breakpoint
-- HAND-EDITED: DELETING THE TARGET CLEARS ONLY THE ONE COLUMN. A PLAIN ON DELETE SET NULL WOULD ALSO NULL user_id, WHICH IS NOT NULL. A deleted split leaves its ledger entries as
-- plain entries; a deleted fact leaves the fact it replaced as history. The schema keeps no onDelete (drizzle cannot say a column list), so the snapshot and the next db:generate stay empty.
-- NOT VALID first and then VALIDATE: the rows were just cleaned, and the check does not hold the table against writes for long.
ALTER TABLE "ledger_txn" ADD CONSTRAINT "ledger_txn_split_fk" FOREIGN KEY ("user_id","split_id") REFERENCES "public"."split_plan"("user_id","id") ON DELETE SET NULL ("split_id") ON UPDATE no action NOT VALID;--> statement-breakpoint
ALTER TABLE "ledger_txn" VALIDATE CONSTRAINT "ledger_txn_split_fk";--> statement-breakpoint
ALTER TABLE "memory_fact" ADD CONSTRAINT "memory_fact_superseded_fk" FOREIGN KEY ("user_id","superseded_by") REFERENCES "public"."memory_fact"("user_id","id") ON DELETE SET NULL ("superseded_by") ON UPDATE no action NOT VALID;--> statement-breakpoint
ALTER TABLE "memory_fact" VALIDATE CONSTRAINT "memory_fact_superseded_fk";--> statement-breakpoint
ALTER TABLE "memory_fact" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "split_plan" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "ledger_txn" FORCE ROW LEVEL SECURITY;
