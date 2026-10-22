CREATE TABLE "audit_event" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"seq" bigint NOT NULL,
	"at" timestamp with time zone DEFAULT now() NOT NULL,
	"actor_kind" text NOT NULL,
	"on_behalf" text,
	"actor_ref" text,
	"channel" text NOT NULL,
	"verb" text,
	"entity" text NOT NULL,
	"entity_id" text NOT NULL,
	"account_id" uuid,
	"action" text NOT NULL,
	"amount_delta" integer,
	"before" jsonb,
	"after" jsonb,
	"note" text,
	"request_id" text,
	"approval_id" text,
	"turn_id" text,
	"undo_of" text,
	"prev_hash" text,
	"hash" text NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "audit_event_user_seq_uq" UNIQUE("user_id","seq"),
	CONSTRAINT "audit_event_actor_chk" CHECK ("audit_event"."actor_kind" in ('person', 'agent', 'job', 'system')),
	CONSTRAINT "audit_event_channel_chk" CHECK ("audit_event"."channel" in ('app', 'chat', 'widget', 'outbox', 'calendar_sync', 'job', 'system')),
	CONSTRAINT "audit_event_action_chk" CHECK ("audit_event"."action" in ('create', 'update', 'delete', 'undo', 'count', 'reset', 'approve', 'reject', 'expire', 'data_reset'))
);
--> statement-breakpoint
ALTER TABLE "audit_event" ADD CONSTRAINT "audit_event_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "audit_event_account_idx" ON "audit_event" USING btree ("user_id","account_id","seq" DESC NULLS LAST);