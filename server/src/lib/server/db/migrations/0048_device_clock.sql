ALTER TABLE "device" ADD COLUMN "clock" text;--> statement-breakpoint
ALTER TABLE "device" ADD CONSTRAINT "device_clock_chk" CHECK ("device"."clock" in ('12', '24'));