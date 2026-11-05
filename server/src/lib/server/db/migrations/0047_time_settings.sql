ALTER TABLE "user_setting" ADD COLUMN "time_zone" text DEFAULT 'Asia/Manila' NOT NULL;--> statement-breakpoint
ALTER TABLE "user_setting" ADD COLUMN "time_format" text DEFAULT 'auto' NOT NULL;--> statement-breakpoint
ALTER TABLE "user_setting" ADD COLUMN "date_style" text DEFAULT 'auto' NOT NULL;--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_time_format_chk" CHECK ("user_setting"."time_format" in ('auto', '12', '24'));--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_date_style_chk" CHECK ("user_setting"."date_style" in ('auto', 'dmy', 'mdy', 'ymd'));--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_time_zone_chk" CHECK (char_length("user_setting"."time_zone") between 1 and 64);--> statement-breakpoint
-- THE AUDIT TRIGGER OF user_setting COPIES THE ZONE AND THE TWO CLOCK CHOICES TOO. 0016, 0029, 0035 AND 0036 STAY AS THEY RAN; THE TRIGGER IS REPLACED HERE.
DROP TRIGGER "audit_user_setting" ON "user_setting";
--> statement-breakpoint
CREATE TRIGGER "audit_user_setting" AFTER INSERT OR UPDATE OR DELETE ON "user_setting" FOR EACH ROW EXECUTE FUNCTION audit_row('id,currency,language,reply_language,week_starts_on,model_provider,show_net_balance,photo_mode,time_zone,time_format,date_style', '', '');
