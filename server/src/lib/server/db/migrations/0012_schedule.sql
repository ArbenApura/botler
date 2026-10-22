CREATE TABLE "calendar_event" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"title" text NOT NULL,
	"starts_at" timestamp with time zone NOT NULL,
	"ends_at" timestamp with time zone NOT NULL,
	"all_day" boolean DEFAULT false NOT NULL,
	"location" text DEFAULT '' NOT NULL,
	"notes" text DEFAULT '' NOT NULL,
	"source" text DEFAULT 'botler' NOT NULL,
	"ref_key" text,
	"google_event_id" text,
	"google_etag" text,
	"google_updated_at" timestamp with time zone,
	"synced_version" integer DEFAULT 0 NOT NULL,
	"recurring_event_id" text,
	"deleted_at" timestamp with time zone,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "calendar_event_google_uq" UNIQUE("user_id","google_event_id"),
	CONSTRAINT "calendar_event_ref_uq" UNIQUE("user_id","ref_key"),
	CONSTRAINT "calendar_event_source_chk" CHECK ("calendar_event"."source" in ('botler', 'google', 'bill', 'payday')),
	CONSTRAINT "calendar_event_time_chk" CHECK ("calendar_event"."ends_at" >= "calendar_event"."starts_at"),
	CONSTRAINT "calendar_event_text_chk" CHECK (length("calendar_event"."title") between 1 and 300 and length("calendar_event"."notes") <= 4000 and length("calendar_event"."location") <= 300)
);
--> statement-breakpoint
CREATE TABLE "calendar_sync" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"status" text DEFAULT 'off' NOT NULL,
	"calendar_id" text DEFAULT 'primary' NOT NULL,
	"sync_token" text,
	"error_code" text,
	"last_sync_at" timestamp with time zone,
	"last_full_sync_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "calendar_sync_user_uq" UNIQUE("user_id"),
	CONSTRAINT "calendar_sync_status_chk" CHECK ("calendar_sync"."status" in ('off', 'ok', 'error'))
);
--> statement-breakpoint
CREATE TABLE "push_token_owner" (
	"token_hash" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "reminder" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"kind" text NOT NULL,
	"ref_key" text NOT NULL,
	"title" text NOT NULL,
	"remind_at" timestamp with time zone NOT NULL,
	"status" text DEFAULT 'scheduled' NOT NULL,
	"origin" text DEFAULT 'system' NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "reminder_user_ref_uq" UNIQUE("user_id","ref_key"),
	CONSTRAINT "reminder_kind_chk" CHECK ("reminder"."kind" in ('task', 'event', 'bill', 'payday', 'routine', 'custom', 'alarm', 'timer')),
	CONSTRAINT "reminder_status_chk" CHECK ("reminder"."status" in ('scheduled', 'sent', 'dismissed', 'cancelled')),
	CONSTRAINT "reminder_origin_chk" CHECK ("reminder"."origin" in ('user', 'agent', 'system')),
	CONSTRAINT "reminder_title_chk" CHECK (length("reminder"."title") between 1 and 200)
);
--> statement-breakpoint
CREATE TABLE "routine" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"title" text NOT NULL,
	"recurrence" jsonb NOT NULL,
	"lead_minutes" integer DEFAULT 0 NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "routine_title_chk" CHECK (length("routine"."title") between 1 and 200),
	CONSTRAINT "routine_lead_chk" CHECK ("routine"."lead_minutes" between 0 and 1440)
);
--> statement-breakpoint
CREATE TABLE "task" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"title" text NOT NULL,
	"notes" text DEFAULT '' NOT NULL,
	"due_at" timestamp with time zone,
	"follow_up_at" timestamp with time zone,
	"status" text DEFAULT 'open' NOT NULL,
	"priority" integer DEFAULT 2 NOT NULL,
	"source" text DEFAULT 'user' NOT NULL,
	"done_at" timestamp with time zone,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "task_status_chk" CHECK ("task"."status" in ('open', 'done', 'dropped')),
	CONSTRAINT "task_source_chk" CHECK ("task"."source" in ('user', 'chat', 'calendar')),
	CONSTRAINT "task_title_chk" CHECK (length("task"."title") between 1 and 200 and length("task"."notes") <= 2000),
	CONSTRAINT "task_priority_chk" CHECK ("task"."priority" between 1 and 3)
);
--> statement-breakpoint
ALTER TABLE "calendar_event" ADD CONSTRAINT "calendar_event_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "calendar_sync" ADD CONSTRAINT "calendar_sync_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "push_token_owner" ADD CONSTRAINT "push_token_owner_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reminder" ADD CONSTRAINT "reminder_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine" ADD CONSTRAINT "routine_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "task" ADD CONSTRAINT "task_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "calendar_event_user_time_idx" ON "calendar_event" USING btree ("user_id","starts_at");--> statement-breakpoint
CREATE INDEX "push_token_owner_user_idx" ON "push_token_owner" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "reminder_user_status_time_idx" ON "reminder" USING btree ("user_id","status","remind_at");--> statement-breakpoint
CREATE INDEX "task_user_status_idx" ON "task" USING btree ("user_id","status","due_at");