CREATE TABLE "agent_action" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"verb" text NOT NULL,
	"args" jsonb NOT NULL,
	"summary" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"result" jsonb,
	"turn_id" text,
	"expires_at" timestamp with time zone NOT NULL,
	"decided_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "agent_action_status_chk" CHECK ("agent_action"."status" in ('pending', 'applied', 'rejected', 'failed', 'expired'))
);
--> statement-breakpoint
CREATE TABLE "chat_turn" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"client_message_id" text NOT NULL,
	"user_text" text NOT NULL,
	"status" text DEFAULT 'running' NOT NULL,
	"reply" text DEFAULT '' NOT NULL,
	"events" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"finished_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "chat_turn_user_message_uq" UNIQUE("user_id","client_message_id"),
	CONSTRAINT "chat_turn_status_chk" CHECK ("chat_turn"."status" in ('running', 'done', 'failed'))
);
--> statement-breakpoint
ALTER TABLE "agent_action" ADD CONSTRAINT "agent_action_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chat_turn" ADD CONSTRAINT "chat_turn_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "agent_action_user_status_idx" ON "agent_action" USING btree ("user_id","status","created_at");--> statement-breakpoint
CREATE INDEX "chat_turn_user_created_idx" ON "chat_turn" USING btree ("user_id","created_at");