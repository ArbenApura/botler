-- EVENTS COPIED FROM GOOGLE ARE REMOVED: BOTLER NO LONGER READS OR WRITES GOOGLE CALENDAR, AND THE COPIES WOULD BE STALE
-- Forced row level security binds the migrating owner too, so each person's rows are reached with that person set in the session.
DO $$
DECLARE u text;
BEGIN
	FOR u IN SELECT "id" FROM "user" LOOP
		PERFORM set_config('app.user_id', u, true);
		DELETE FROM "reminder" WHERE "user_id" = u AND "ref_key" IN (SELECT 'event:' || "id" FROM "calendar_event" WHERE "user_id" = u AND "source" = 'google');
		DELETE FROM "calendar_event" WHERE "user_id" = u AND "source" = 'google';
	END LOOP;
	PERFORM set_config('app.user_id', '', true);
END $$;--> statement-breakpoint
ALTER TABLE "calendar_sync" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
DROP TABLE "calendar_sync" CASCADE;--> statement-breakpoint
ALTER TABLE "calendar_event" DROP CONSTRAINT "calendar_event_google_uq";--> statement-breakpoint
ALTER TABLE "calendar_event" DROP CONSTRAINT "calendar_event_source_chk";--> statement-breakpoint
ALTER TABLE "calendar_event" DROP COLUMN "google_event_id";--> statement-breakpoint
ALTER TABLE "calendar_event" DROP COLUMN "google_etag";--> statement-breakpoint
ALTER TABLE "calendar_event" DROP COLUMN "google_updated_at";--> statement-breakpoint
ALTER TABLE "calendar_event" DROP COLUMN "synced_version";--> statement-breakpoint
ALTER TABLE "calendar_event" DROP COLUMN "recurring_event_id";--> statement-breakpoint
ALTER TABLE "calendar_event" ADD CONSTRAINT "calendar_event_source_chk" CHECK ("calendar_event"."source" in ('botler', 'bill', 'payday'));