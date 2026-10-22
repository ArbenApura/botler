ALTER TABLE "device" DROP CONSTRAINT "device_push_token_uq";--> statement-breakpoint
ALTER TABLE "device" ADD CONSTRAINT "device_user_push_token_uq" UNIQUE("user_id","push_token");