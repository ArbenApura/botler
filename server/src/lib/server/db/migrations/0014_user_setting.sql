CREATE TABLE "user_setting" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"currency" text DEFAULT 'PHP' NOT NULL,
	"language" text DEFAULT 'en' NOT NULL,
	"reply_language" text DEFAULT 'auto' NOT NULL,
	"week_starts_on" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "user_setting_user_uq" UNIQUE("user_id"),
	CONSTRAINT "user_setting_currency_chk" CHECK ("user_setting"."currency" in ('PHP', 'USD', 'EUR', 'GBP', 'JPY', 'KRW', 'CNY', 'HKD', 'SGD', 'AUD', 'NZD', 'CAD', 'CHF', 'INR', 'IDR', 'MYR', 'THB', 'VND', 'TWD', 'AED', 'SAR')),
	CONSTRAINT "user_setting_language_chk" CHECK ("user_setting"."language" in ('en', 'fil')),
	CONSTRAINT "user_setting_reply_language_chk" CHECK ("user_setting"."reply_language" in ('auto', 'en', 'fil', 'taglish')),
	CONSTRAINT "user_setting_week_chk" CHECK ("user_setting"."week_starts_on" in (0, 1))
);
--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;