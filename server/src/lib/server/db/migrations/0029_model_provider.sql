ALTER TABLE "user_setting" ADD COLUMN "model_provider" text;--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_model_provider_chk" CHECK ("user_setting"."model_provider" in ('anthropic', 'deepseek'));
--> statement-breakpoint
-- THE AUDIT TRIGGER OF user_setting GAINS THE PROVIDER CHOICE. 0016 STAYS AS IT RAN.
DROP TRIGGER "audit_user_setting" ON "user_setting";
--> statement-breakpoint
CREATE TRIGGER "audit_user_setting" AFTER INSERT OR UPDATE OR DELETE ON "user_setting" FOR EACH ROW EXECUTE FUNCTION audit_row('id,currency,language,reply_language,week_starts_on,model_provider', '', '');
