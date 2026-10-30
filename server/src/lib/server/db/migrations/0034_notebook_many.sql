ALTER TABLE "notebook" DROP CONSTRAINT "notebook_user_uq";--> statement-breakpoint
ALTER TABLE "notebook" ADD COLUMN "kind" text DEFAULT 'main' NOT NULL;--> statement-breakpoint
ALTER TABLE "notebook" ADD COLUMN "title" text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE "notebook" ADD COLUMN "summary" text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE "notebook" ADD COLUMN "deleted_at" timestamp with time zone;--> statement-breakpoint
CREATE UNIQUE INDEX "notebook_main_uq" ON "notebook" USING btree ("user_id") WHERE "notebook"."kind" = 'main';--> statement-breakpoint
CREATE UNIQUE INDEX "notebook_title_uq" ON "notebook" USING btree ("user_id",lower("title")) WHERE "notebook"."kind" = 'extra' and "notebook"."deleted_at" is null;--> statement-breakpoint
ALTER TABLE "notebook" ADD CONSTRAINT "notebook_kind_chk" CHECK ("notebook"."kind" in ('main', 'extra'));--> statement-breakpoint
ALTER TABLE "notebook" ADD CONSTRAINT "notebook_shape_chk" CHECK (length("notebook"."title") <= 80 and length("notebook"."summary") <= 200 and ("notebook"."kind" = 'extra' or ("notebook"."title" = '' and "notebook"."deleted_at" is null)));