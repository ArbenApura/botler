ALTER TABLE "allocation_rule" ADD COLUMN "funds_bill_id" uuid;--> statement-breakpoint
-- HAND-EDITED (BTL-20261029-0119): DELETING A BILL CLEARS ONLY funds_bill_id. A PLAIN ON DELETE SET NULL WOULD ALSO NULL user_id, WHICH IS NOT NULL.
-- The schema keeps no onDelete for this key (drizzle cannot say a column list), so the snapshot and the next db:generate stay empty.
ALTER TABLE "allocation_rule" ADD CONSTRAINT "allocation_rule_bill_fk" FOREIGN KEY ("user_id","funds_bill_id") REFERENCES "public"."bill"("user_id","id") ON DELETE SET NULL ("funds_bill_id") ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "allocation_rule_funds_bill_uq" ON "allocation_rule" USING btree ("user_id","funds_bill_id") WHERE "allocation_rule"."funds_bill_id" is not null and "allocation_rule"."status" in ('proposed', 'active');--> statement-breakpoint
-- THE AUDIT TRIGGER OF allocation_rule COPIES THE LINKED BILL TOO. 0016 AND 0032 STAY AS THEY RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_allocation_rule" ON "allocation_rule";
--> statement-breakpoint
CREATE TRIGGER "audit_allocation_rule" AFTER INSERT OR UPDATE OR DELETE ON "allocation_rule" FOR EACH ROW EXECUTE FUNCTION audit_row('id,position,mode,amount,basis_points,base,target_account_id,target_goal_id,effective_from,status,approved_at,label,funds_bill_id', 'target_account_id', '');
--> statement-breakpoint
-- TWO RULES OF ONE PERSON COULD SHARE A POSITION (A NEW RULE WAS NUMBERED AFTER THE ACTIVE ONES ONLY), SO WHICH ONE CAME FIRST WAS DECIDED BY
-- ITS RANDOM ID. Every person's rules are numbered again 1, 2, 3 in the order they had (position, then creation, then id). The owner is bound
-- by forced row level security with no update policy, so it is lifted for this statement only (as 0028 did). The audit trigger only records
-- changes made by app_runtime, so this renumbering is not in the audit trail. Safe to run again: it gives the same numbers.
ALTER TABLE "allocation_rule" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
UPDATE "allocation_rule" AS r SET "position" = n.rn FROM (SELECT "id", row_number() OVER (PARTITION BY "user_id" ORDER BY "position", "created_at", "id") AS rn FROM "allocation_rule") AS n WHERE r."id" = n."id" AND r."position" <> n.rn;--> statement-breakpoint
ALTER TABLE "allocation_rule" FORCE ROW LEVEL SECURITY;
