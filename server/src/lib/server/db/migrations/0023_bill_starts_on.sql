ALTER TABLE "bill" ADD COLUMN "starts_on" date;--> statement-breakpoint
-- A BILL ADDED BEFORE THIS COLUMN COUNTS FROM THE MANILA DAY IT WAS ADDED, SO ITS PAST DATES STOP SHOWING AS OVERDUE.
UPDATE "bill" SET "starts_on" = ("created_at" AT TIME ZONE 'Asia/Manila')::date WHERE "starts_on" IS NULL;--> statement-breakpoint
-- THE AUDIT TRIGGER OF bill COPIES THE NEW DATE TOO. 0016 STAYS AS IT RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_bill" ON "bill";
--> statement-breakpoint
CREATE TRIGGER "audit_bill" AFTER INSERT OR UPDATE OR DELETE ON "bill" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,category,account_id,kind,amount,schedule,weekend_rule,deferrable,active,starts_on', 'account_id', '');
