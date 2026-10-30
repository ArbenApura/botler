ALTER TABLE "user_setting" ADD COLUMN "photo_mode" text DEFAULT 'image' NOT NULL;--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_photo_mode_chk" CHECK ("user_setting"."photo_mode" in ('image', 'text'));--> statement-breakpoint
-- THE AUDIT TRIGGER OF user_setting COPIES THE PHOTO CHOICE TOO. 0016, 0029 AND 0035 STAY AS THEY RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_user_setting" ON "user_setting";
--> statement-breakpoint
CREATE TRIGGER "audit_user_setting" AFTER INSERT OR UPDATE OR DELETE ON "user_setting" FOR EACH ROW EXECUTE FUNCTION audit_row('id,currency,language,reply_language,week_starts_on,model_provider,show_net_balance,photo_mode', '', '');
