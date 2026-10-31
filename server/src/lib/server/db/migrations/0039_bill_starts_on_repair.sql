-- REPAIR OF 0023: ITS UPDATE NEVER REACHED A ROW. THE OWNER IS BOUND BY FORCED ROW LEVEL SECURITY (IT IS NOT A SUPERUSER) AND HAS NO POLICY TO READ OR UPDATE bill,
-- SO EVERY BILL ADDED BEFORE THE COLUMN KEPT starts_on = NULL AND ITS PAST DUE DATES SHOWED AS OVERDUE.
-- A bill with no start counts from the Manila day it was added, as 0023 meant, or from its earliest recorded payment when that is earlier (a payment is never before the start).
-- Safe to run again: it only touches rows still at NULL. Row level security is lifted for this migration only (as 0028 and 0033 did) and put back at the end.
-- The audit trigger only records changes made by app_runtime, so this repair is not in the audit trail.
ALTER TABLE "bill" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "bill_payment" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
UPDATE "bill" AS b SET "starts_on" = LEAST(
	(b."created_at" AT TIME ZONE 'Asia/Manila')::date,
	COALESCE((SELECT MIN(p."due_date") FROM "bill_payment" AS p WHERE p."user_id" = b."user_id" AND p."bill_id" = b."id"), (b."created_at" AT TIME ZONE 'Asia/Manila')::date)
) WHERE b."starts_on" IS NULL;--> statement-breakpoint
ALTER TABLE "bill_payment" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "bill" FORCE ROW LEVEL SECURITY;
