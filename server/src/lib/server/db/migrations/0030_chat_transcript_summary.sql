ALTER TABLE "chat" ADD COLUMN "summary" text;--> statement-breakpoint
ALTER TABLE "chat" ADD COLUMN "summary_through_turn_id" uuid;--> statement-breakpoint
ALTER TABLE "chat" ADD COLUMN "summary_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "chat_turn" ADD COLUMN "transcript" jsonb;