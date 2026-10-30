ALTER TABLE "user_setting" ADD COLUMN "show_net_balance" boolean DEFAULT false NOT NULL;--> statement-breakpoint
-- THE AUDIT TRIGGER OF user_setting COPIES THE NET BALANCE CHOICE TOO. 0016 AND 0029 STAY AS THEY RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_user_setting" ON "user_setting";
--> statement-breakpoint
CREATE TRIGGER "audit_user_setting" AFTER INSERT OR UPDATE OR DELETE ON "user_setting" FOR EACH ROW EXECUTE FUNCTION audit_row('id,currency,language,reply_language,week_starts_on,model_provider,show_net_balance', '', '');
