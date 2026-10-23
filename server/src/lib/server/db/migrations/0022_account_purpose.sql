ALTER TABLE "account" ADD COLUMN "purpose" text;--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_purpose_chk" CHECK ("account"."purpose" is null or (char_length("account"."purpose") between 1 and 24 and "account"."purpose" = btrim("account"."purpose")));--> statement-breakpoint
-- THE AUDIT TRIGGER OF account COPIES THE NEW LABEL TOO. 0016 STAYS AS IT RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_account" ON "account";
--> statement-breakpoint
CREATE TRIGGER "audit_account" AFTER INSERT OR UPDATE OR DELETE ON "account" FOR EACH ROW EXECUTE FUNCTION audit_row('id,name,kind,min_balance,sort_order,archived_at,purpose', 'id', '');
