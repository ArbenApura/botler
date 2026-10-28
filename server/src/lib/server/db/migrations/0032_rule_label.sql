ALTER TABLE "allocation_rule" ADD COLUMN "label" text;--> statement-breakpoint
ALTER TABLE "allocation_rule" ADD CONSTRAINT "allocation_rule_label_chk" CHECK ("allocation_rule"."label" is null or length("allocation_rule"."label") between 1 and 60);
--> statement-breakpoint
-- THE AUDIT TRIGGER OF allocation_rule COPIES THE LABEL TOO. 0016 STAYS AS IT RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_allocation_rule" ON "allocation_rule";
--> statement-breakpoint
CREATE TRIGGER "audit_allocation_rule" AFTER INSERT OR UPDATE OR DELETE ON "allocation_rule" FOR EACH ROW EXECUTE FUNCTION audit_row('id,position,mode,amount,basis_points,base,target_account_id,target_goal_id,effective_from,status,approved_at,label', 'target_account_id', '');
