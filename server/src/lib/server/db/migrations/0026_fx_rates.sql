CREATE TABLE "fx_rate" (
	"code" text PRIMARY KEY NOT NULL,
	"rate" text NOT NULL,
	"fetched_at" timestamp with time zone NOT NULL,
	"source" text NOT NULL,
	CONSTRAINT "fx_rate_code_chk" CHECK ("fx_rate"."code" ~ '^[A-Z]{3}$'),
	CONSTRAINT "fx_rate_rate_chk" CHECK ("fx_rate"."rate" ~ '^[0-9]+([.][0-9]{1,18})?$' and "fx_rate"."rate" !~ '^0+([.]0+)?$')
);
--> statement-breakpoint
CREATE TABLE "fx_refresh" (
	"id" text PRIMARY KEY DEFAULT 'main' NOT NULL,
	"attempted_at" timestamp with time zone,
	"succeeded_at" timestamp with time zone,
	"last_error" text,
	CONSTRAINT "fx_refresh_id_chk" CHECK ("fx_refresh"."id" = 'main')
);
--> statement-breakpoint
-- THE ONE ROW THE REFRESH LOCKS AND RECORDS ITSELF IN.
INSERT INTO "fx_refresh" ("id") VALUES ('main') ON CONFLICT DO NOTHING;
