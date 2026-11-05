CREATE TABLE "availability_override" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"day" date NOT NULL,
	"off" boolean DEFAULT false NOT NULL,
	"blocks" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "availability_override_user_day_uq" UNIQUE("user_id","day")
);
--> statement-breakpoint
CREATE TABLE "availability_setting" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"wake_start_minute" integer DEFAULT 360 NOT NULL,
	"wake_end_minute" integer DEFAULT 1320 NOT NULL,
	"travel_minutes" integer DEFAULT 30 NOT NULL,
	"wind_down" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "availability_setting_user_uq" UNIQUE("user_id"),
	CONSTRAINT "availability_setting_wake_chk" CHECK ("availability_setting"."wake_start_minute" < "availability_setting"."wake_end_minute"),
	CONSTRAINT "availability_setting_travel_chk" CHECK ("availability_setting"."travel_minutes" between 0 and 240)
);
--> statement-breakpoint
CREATE TABLE "day_status" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"day" date NOT NULL,
	"complete" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "day_status_user_day_uq" UNIQUE("user_id","day")
);
--> statement-breakpoint
CREATE TABLE "energy_estimate" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"week_key" text NOT NULL,
	"trend_g" integer NOT NULL,
	"burn_kcal" integer NOT NULL,
	"intake_kcal" integer NOT NULL,
	"complete_days" integer NOT NULL,
	"weigh_ins" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "energy_estimate_user_week_uq" UNIQUE("user_id","week_key")
);
--> statement-breakpoint
CREATE TABLE "food_entry" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"day" date NOT NULL,
	"meal" text NOT NULL,
	"meal_group" uuid NOT NULL,
	"name" text NOT NULL,
	"grams" integer,
	"kcal" integer NOT NULL,
	"low_kcal" integer NOT NULL,
	"high_kcal" integer NOT NULL,
	"protein_mg" integer,
	"carbs_mg" integer,
	"sugar_mg" integer,
	"fibre_mg" integer,
	"fat_mg" integer,
	"sat_fat_mg" integer,
	"sodium_mg" integer,
	"nutrients" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"source_kind" text NOT NULL,
	"source_ref" text,
	"food_item_id" uuid,
	"by_agent" boolean DEFAULT false NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "food_entry_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "food_entry_meal_chk" CHECK ("food_entry"."meal" in ('breakfast', 'lunch', 'merienda', 'dinner', 'snack')),
	CONSTRAINT "food_entry_source_chk" CHECK ("food_entry"."source_kind" in ('usda', 'filipino', 'saved', 'off', 'usda_branded', 'label', 'estimate', 'manual', 'rough')),
	CONSTRAINT "food_entry_name_chk" CHECK (length("food_entry"."name") between 1 and 120),
	CONSTRAINT "food_entry_grams_chk" CHECK ("food_entry"."grams" is null or "food_entry"."grams" between 1 and 10000),
	CONSTRAINT "food_entry_kcal_chk" CHECK ("food_entry"."kcal" between 0 and 20000),
	CONSTRAINT "food_entry_range_chk" CHECK ("food_entry"."low_kcal" <= "food_entry"."kcal" and "food_entry"."kcal" <= "food_entry"."high_kcal")
);
--> statement-breakpoint
CREATE TABLE "food_item" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"barcode" text,
	"source" text DEFAULT 'manual' NOT NULL,
	"kcal" integer NOT NULL,
	"protein_mg" integer,
	"carbs_mg" integer,
	"sugar_mg" integer,
	"fibre_mg" integer,
	"fat_mg" integer,
	"sat_fat_mg" integer,
	"sodium_mg" integer,
	"nutrients" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"serving_g" integer,
	"archived_at" timestamp with time zone,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "food_item_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "food_item_source_chk" CHECK ("food_item"."source" in ('label', 'barcode', 'manual', 'chat')),
	CONSTRAINT "food_item_name_chk" CHECK (length("food_item"."name") between 1 and 120),
	CONSTRAINT "food_item_barcode_chk" CHECK ("food_item"."barcode" is null or "food_item"."barcode" ~ '^[0-9]{8,14}$'),
	CONSTRAINT "food_item_kcal_chk" CHECK ("food_item"."kcal" between 0 and 900),
	CONSTRAINT "food_item_serving_chk" CHECK ("food_item"."serving_g" is null or "food_item"."serving_g" > 0)
);
--> statement-breakpoint
CREATE TABLE "health_goal" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"kind" text DEFAULT 'track' NOT NULL,
	"goal_weight_g" integer,
	"pace_bp" integer DEFAULT 50 NOT NULL,
	"target_kcal" integer,
	"protein_tenths" integer DEFAULT 16 NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "health_goal_user_uq" UNIQUE("user_id"),
	CONSTRAINT "health_goal_kind_chk" CHECK ("health_goal"."kind" in ('lose', 'maintain', 'gain', 'track')),
	CONSTRAINT "health_goal_weight_chk" CHECK ("health_goal"."goal_weight_g" is null or "health_goal"."goal_weight_g" > 0),
	CONSTRAINT "health_goal_pace_chk" CHECK ("health_goal"."pace_bp" between 25 and 100),
	CONSTRAINT "health_goal_target_chk" CHECK ("health_goal"."target_kcal" is null or "health_goal"."target_kcal" > 0),
	CONSTRAINT "health_goal_protein_chk" CHECK ("health_goal"."protein_tenths" between 14 and 20)
);
--> statement-breakpoint
CREATE TABLE "health_profile" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"height_mm" integer,
	"birth_year" integer,
	"sex" text DEFAULT 'skip' NOT NULL,
	"activity" text DEFAULT 'sitting' NOT NULL,
	"setup_done_at" timestamp with time zone,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "health_profile_user_uq" UNIQUE("user_id"),
	CONSTRAINT "health_profile_sex_chk" CHECK ("health_profile"."sex" in ('female', 'male', 'skip')),
	CONSTRAINT "health_profile_activity_chk" CHECK ("health_profile"."activity" in ('sitting', 'some_walking', 'on_feet', 'very_active')),
	CONSTRAINT "health_profile_height_chk" CHECK ("health_profile"."height_mm" is null or "health_profile"."height_mm" between 1000 and 2500),
	CONSTRAINT "health_profile_birth_chk" CHECK ("health_profile"."birth_year" is null or "health_profile"."birth_year" between 1900 and 2100)
);
--> statement-breakpoint
CREATE TABLE "health_proposal" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"kind" text NOT NULL,
	"week_key" text NOT NULL,
	"status" text DEFAULT 'open' NOT NULL,
	"payload" jsonb NOT NULL,
	"basis_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"answered_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "health_proposal_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "health_proposal_kind_chk" CHECK ("health_proposal"."kind" in ('target', 'week', 'review')),
	CONSTRAINT "health_proposal_status_chk" CHECK ("health_proposal"."status" in ('open', 'accepted', 'kept', 'superseded', 'expired'))
);
--> statement-breakpoint
CREATE TABLE "nutrition_food" (
	"id" text PRIMARY KEY NOT NULL,
	"source" text NOT NULL,
	"data_type" text NOT NULL,
	"name" text NOT NULL,
	"kcal" integer NOT NULL,
	"protein_mg" integer,
	"carbs_mg" integer,
	"sugar_mg" integer,
	"fibre_mg" integer,
	"fat_mg" integer,
	"sat_fat_mg" integer,
	"sodium_mg" integer,
	"nutrients" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"loaded_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "nutrition_food_kcal_chk" CHECK ("nutrition_food"."kcal" between 0 and 900)
);
--> statement-breakpoint
CREATE TABLE "nutrition_portion" (
	"id" text PRIMARY KEY NOT NULL,
	"food_id" text NOT NULL,
	"label" text NOT NULL,
	"grams_tenths" integer NOT NULL,
	CONSTRAINT "nutrition_portion_grams_chk" CHECK ("nutrition_portion"."grams_tenths" > 0)
);
--> statement-breakpoint
CREATE TABLE "planned_workout" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"program_id" uuid,
	"day" date NOT NULL,
	"starts_at" timestamp with time zone NOT NULL,
	"minutes" integer NOT NULL,
	"kind" text NOT NULL,
	"session_key" text NOT NULL,
	"status" text DEFAULT 'planned' NOT NULL,
	"week_key" text NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "planned_workout_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "planned_workout_kind_chk" CHECK ("planned_workout"."kind" in ('strength', 'walk', 'run', 'other')),
	CONSTRAINT "planned_workout_status_chk" CHECK ("planned_workout"."status" in ('planned', 'done', 'skipped')),
	CONSTRAINT "planned_workout_minutes_chk" CHECK ("planned_workout"."minutes" between 1 and 600)
);
--> statement-breakpoint
CREATE TABLE "program" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"template_key" text NOT NULL,
	"started_on" date NOT NULL,
	"stopped_at" timestamp with time zone,
	"week" integer DEFAULT 1 NOT NULL,
	"levels" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "program_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "program_week_chk" CHECK ("program"."week" >= 1)
);
--> statement-breakpoint
CREATE TABLE "sleep_entry" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"day" date NOT NULL,
	"starts_at" timestamp with time zone NOT NULL,
	"ends_at" timestamp with time zone NOT NULL,
	"nap" boolean DEFAULT false NOT NULL,
	"by_agent" boolean DEFAULT false NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "sleep_entry_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "sleep_entry_time_chk" CHECK ("sleep_entry"."ends_at" > "sleep_entry"."starts_at")
);
--> statement-breakpoint
CREATE TABLE "weekly_block" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"weekday" integer NOT NULL,
	"start_minute" integer NOT NULL,
	"end_minute" integer NOT NULL,
	"kind" text NOT NULL,
	"label" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "weekly_block_kind_chk" CHECK ("weekly_block"."kind" in ('work', 'busy', 'free')),
	CONSTRAINT "weekly_block_weekday_chk" CHECK ("weekly_block"."weekday" between 0 and 6),
	CONSTRAINT "weekly_block_start_chk" CHECK ("weekly_block"."start_minute" between 0 and 1439),
	CONSTRAINT "weekly_block_end_chk" CHECK ("weekly_block"."end_minute" between 0 and 1440),
	CONSTRAINT "weekly_block_length_chk" CHECK ("weekly_block"."start_minute" <> "weekly_block"."end_minute"),
	CONSTRAINT "weekly_block_label_chk" CHECK ("weekly_block"."label" is null or length("weekly_block"."label") <= 60)
);
--> statement-breakpoint
CREATE TABLE "weight_entry" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"day" date NOT NULL,
	"grams" integer NOT NULL,
	"by_agent" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "weight_entry_user_day_uq" UNIQUE("user_id","day"),
	CONSTRAINT "weight_entry_grams_chk" CHECK ("weight_entry"."grams" between 20000 and 400000)
);
--> statement-breakpoint
CREATE TABLE "workout_session" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"planned_id" uuid,
	"program_id" uuid,
	"day" date NOT NULL,
	"kind" text NOT NULL,
	"title" text NOT NULL,
	"minutes" integer,
	"distance_m" integer,
	"started_at" timestamp with time zone,
	"finished_at" timestamp with time zone,
	"by_agent" boolean DEFAULT false NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "workout_session_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "workout_session_kind_chk" CHECK ("workout_session"."kind" in ('strength', 'walk', 'run', 'other')),
	CONSTRAINT "workout_session_title_chk" CHECK (length("workout_session"."title") between 1 and 120),
	CONSTRAINT "workout_session_minutes_chk" CHECK ("workout_session"."minutes" is null or "workout_session"."minutes" between 0 and 1440),
	CONSTRAINT "workout_session_distance_chk" CHECK ("workout_session"."distance_m" is null or "workout_session"."distance_m" >= 0)
);
--> statement-breakpoint
CREATE TABLE "workout_set" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"session_id" uuid NOT NULL,
	"exercise_key" text NOT NULL,
	"position" integer NOT NULL,
	"reps" integer,
	"seconds" integer,
	"done" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "workout_set_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "workout_set_position_uq" UNIQUE("user_id","session_id","exercise_key","position"),
	CONSTRAINT "workout_set_reps_chk" CHECK ("workout_set"."reps" is null or "workout_set"."reps" between 0 and 1000),
	CONSTRAINT "workout_set_seconds_chk" CHECK ("workout_set"."seconds" is null or "workout_set"."seconds" between 0 and 36000)
);
--> statement-breakpoint
ALTER TABLE "reminder" DROP CONSTRAINT "reminder_kind_chk";--> statement-breakpoint
ALTER TABLE "availability_override" ADD CONSTRAINT "availability_override_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "availability_setting" ADD CONSTRAINT "availability_setting_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "day_status" ADD CONSTRAINT "day_status_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "energy_estimate" ADD CONSTRAINT "energy_estimate_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_entry" ADD CONSTRAINT "food_entry_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_entry" ADD CONSTRAINT "food_entry_item_fk" FOREIGN KEY ("user_id","food_item_id") REFERENCES "public"."food_item"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_item" ADD CONSTRAINT "food_item_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "health_goal" ADD CONSTRAINT "health_goal_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "health_profile" ADD CONSTRAINT "health_profile_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "health_proposal" ADD CONSTRAINT "health_proposal_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "nutrition_portion" ADD CONSTRAINT "nutrition_portion_food_id_nutrition_food_id_fk" FOREIGN KEY ("food_id") REFERENCES "public"."nutrition_food"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "planned_workout" ADD CONSTRAINT "planned_workout_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "planned_workout" ADD CONSTRAINT "planned_workout_program_fk" FOREIGN KEY ("user_id","program_id") REFERENCES "public"."program"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "program" ADD CONSTRAINT "program_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sleep_entry" ADD CONSTRAINT "sleep_entry_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "weekly_block" ADD CONSTRAINT "weekly_block_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "weight_entry" ADD CONSTRAINT "weight_entry_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_session" ADD CONSTRAINT "workout_session_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_session" ADD CONSTRAINT "workout_session_planned_fk" FOREIGN KEY ("user_id","planned_id") REFERENCES "public"."planned_workout"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_session" ADD CONSTRAINT "workout_session_program_fk" FOREIGN KEY ("user_id","program_id") REFERENCES "public"."program"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_set" ADD CONSTRAINT "workout_set_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_set" ADD CONSTRAINT "workout_set_session_fk" FOREIGN KEY ("user_id","session_id") REFERENCES "public"."workout_session"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "food_entry_user_day_idx" ON "food_entry" USING btree ("user_id","day");--> statement-breakpoint
CREATE INDEX "food_item_user_barcode_idx" ON "food_item" USING btree ("user_id","barcode");--> statement-breakpoint
CREATE UNIQUE INDEX "health_proposal_open_uq" ON "health_proposal" USING btree ("user_id","kind") WHERE "health_proposal"."status" = 'open';--> statement-breakpoint
CREATE INDEX "nutrition_food_name_trgm_idx" ON "nutrition_food" USING gin ("name" gin_trgm_ops);--> statement-breakpoint
CREATE INDEX "nutrition_portion_food_idx" ON "nutrition_portion" USING btree ("food_id");--> statement-breakpoint
CREATE INDEX "planned_workout_user_day_idx" ON "planned_workout" USING btree ("user_id","day");--> statement-breakpoint
CREATE INDEX "sleep_entry_user_day_idx" ON "sleep_entry" USING btree ("user_id","day");--> statement-breakpoint
CREATE INDEX "weekly_block_user_day_idx" ON "weekly_block" USING btree ("user_id","weekday");--> statement-breakpoint
CREATE INDEX "workout_session_user_day_idx" ON "workout_session" USING btree ("user_id","day");--> statement-breakpoint
ALTER TABLE "reminder" ADD CONSTRAINT "reminder_kind_chk" CHECK ("reminder"."kind" in ('task', 'event', 'bill', 'payday', 'routine', 'custom', 'alarm', 'timer', 'workout', 'winddown'));
--> statement-breakpoint
CREATE TRIGGER "audit_health_profile" AFTER INSERT OR UPDATE OR DELETE ON "health_profile" FOR EACH ROW EXECUTE FUNCTION audit_row('id,height_mm,birth_year,sex,activity,setup_done_at', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_health_goal" AFTER INSERT OR UPDATE OR DELETE ON "health_goal" FOR EACH ROW EXECUTE FUNCTION audit_row('id,kind,goal_weight_g,pace_bp,target_kcal,protein_tenths', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_food_item" AFTER INSERT OR UPDATE OR DELETE ON "food_item" FOR EACH ROW EXECUTE FUNCTION audit_row('id,source,kcal,serving_g,archived_at', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_food_entry" AFTER INSERT OR UPDATE OR DELETE ON "food_entry" FOR EACH ROW EXECUTE FUNCTION audit_row('id,day,meal,grams,kcal,low_kcal,high_kcal,source_kind,food_item_id', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_day_status" AFTER INSERT OR UPDATE OR DELETE ON "day_status" FOR EACH ROW EXECUTE FUNCTION audit_row('id,day,complete', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_weight_entry" AFTER INSERT OR UPDATE OR DELETE ON "weight_entry" FOR EACH ROW EXECUTE FUNCTION audit_row('id,day,grams', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_energy_estimate" AFTER INSERT OR UPDATE OR DELETE ON "energy_estimate" FOR EACH ROW EXECUTE FUNCTION audit_row('id,week_key,trend_g,burn_kcal,intake_kcal,complete_days,weigh_ins', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_health_proposal" AFTER INSERT OR UPDATE OR DELETE ON "health_proposal" FOR EACH ROW EXECUTE FUNCTION audit_row('id,kind,week_key,status,answered_at', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_program" AFTER INSERT OR UPDATE OR DELETE ON "program" FOR EACH ROW EXECUTE FUNCTION audit_row('id,template_key,started_on,stopped_at,week', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_planned_workout" AFTER INSERT OR UPDATE OR DELETE ON "planned_workout" FOR EACH ROW EXECUTE FUNCTION audit_row('id,program_id,day,starts_at,minutes,kind,session_key,status,week_key', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_workout_session" AFTER INSERT OR UPDATE OR DELETE ON "workout_session" FOR EACH ROW EXECUTE FUNCTION audit_row('id,planned_id,program_id,day,kind,minutes,distance_m,finished_at', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_workout_set" AFTER INSERT OR UPDATE OR DELETE ON "workout_set" FOR EACH ROW EXECUTE FUNCTION audit_row('id,session_id,exercise_key,position,reps,seconds,done', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_sleep_entry" AFTER INSERT OR UPDATE OR DELETE ON "sleep_entry" FOR EACH ROW EXECUTE FUNCTION audit_row('id,day,starts_at,ends_at,nap', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_weekly_block" AFTER INSERT OR UPDATE OR DELETE ON "weekly_block" FOR EACH ROW EXECUTE FUNCTION audit_row('id,weekday,start_minute,end_minute,kind', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_availability_override" AFTER INSERT OR UPDATE OR DELETE ON "availability_override" FOR EACH ROW EXECUTE FUNCTION audit_row('id,day,off', '', '');
--> statement-breakpoint
CREATE TRIGGER "audit_availability_setting" AFTER INSERT OR UPDATE OR DELETE ON "availability_setting" FOR EACH ROW EXECUTE FUNCTION audit_row('id,wake_start_minute,wake_end_minute,travel_minutes,wind_down', '', '');
--> statement-breakpoint
-- ERASE ONE PERSON'S DATA BY SCOPE. SECURITY DEFINER, OWNED BY THE MIGRATING OWNER. IT CAN ONLY ERASE THE PERSON SET IN THE SESSION (app.user_id).
-- The audit triggers stay quiet (this function runs as the owner), the trail's own guard is lifted for this transaction, and one tombstone
-- row says who, when, which scope and how many rows. When the trail itself is erased the chain starts again at 1 with that row.
CREATE OR REPLACE FUNCTION data_reset(p_user text, p_scope text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
	tables text[];
	t text;
	n bigint;
	counts jsonb := '{}'::jsonb;
	erase_trail boolean := p_scope IN ('audit', 'everything');
	last_seq bigint;
	last_hash text;
	new_seq bigint;
	actor text := coalesce(nullif(current_setting('app.actor_kind', true), ''), 'person');
	chan text := coalesce(nullif(current_setting('app.channel', true), ''), 'app');
	req text := nullif(current_setting('app.request_id', true), '');
BEGIN
	IF p_user IS NULL OR p_user IS DISTINCT FROM nullif(current_setting('app.user_id', true), '') THEN
		RAISE EXCEPTION 'A reset can only erase the data of the person who asks';
	END IF;
	tables := CASE p_scope
		WHEN 'money' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'picture', 'undo_journal', 'agent_action']
		WHEN 'schedule' THEN ARRAY['reminder', 'task', 'calendar_event', 'routine', 'availability_override', 'weekly_block', 'availability_setting']
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'chat', 'memory_fact', 'memory_summary', 'notebook_page_revision', 'notebook_page', 'notebook_revision', 'notebook']
		WHEN 'health' THEN ARRAY['workout_set', 'workout_session', 'planned_workout', 'program', 'health_proposal', 'energy_estimate', 'weight_entry', 'sleep_entry', 'food_entry', 'food_item', 'day_status', 'health_goal', 'health_profile']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'picture', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'availability_override', 'weekly_block', 'availability_setting', 'chat_turn', 'chat', 'memory_fact', 'memory_summary', 'notebook_page_revision', 'notebook_page', 'notebook_revision', 'notebook', 'workout_set', 'workout_session', 'planned_workout', 'program', 'health_proposal', 'energy_estimate', 'weight_entry', 'sleep_entry', 'food_entry', 'food_item', 'day_status', 'health_goal', 'health_profile', 'memory_profile']
		ELSE NULL
	END;
	IF tables IS NULL THEN
		RAISE EXCEPTION 'Unknown reset scope';
	END IF;
	PERFORM set_config('app.audit_erase', 'on', true);
	PERFORM pg_advisory_xact_lock(hashtextextended(p_user, 0));
	FOREACH t IN ARRAY tables LOOP
		EXECUTE format('DELETE FROM %I WHERE user_id = $1', t) USING p_user;
		GET DIAGNOSTICS n = ROW_COUNT;
		counts := counts || jsonb_build_object(t, n);
	END LOOP;
	IF p_scope <> 'audit' THEN
		-- Pending jobs would run on data that is gone, whichever part was erased
		DELETE FROM job WHERE user_id = p_user;
		GET DIAGNOSTICS n = ROW_COUNT;
		counts := counts || jsonb_build_object('job', n);
	END IF;
	IF erase_trail THEN
		DELETE FROM audit_event WHERE user_id = p_user;
		GET DIAGNOSTICS n = ROW_COUNT;
		counts := counts || jsonb_build_object('audit_event', n);
	END IF;
	SELECT e.seq, e.hash INTO last_seq, last_hash FROM audit_event e WHERE e.user_id = p_user ORDER BY e.seq DESC LIMIT 1;
	new_seq := coalesce(last_seq, 0) + 1;
	INSERT INTO audit_event (user_id, seq, actor_kind, channel, verb, entity, entity_id, action, after, request_id, prev_hash, hash)
	VALUES (
		p_user, new_seq, actor, chan, 'data.reset', 'data', p_scope, 'data_reset', counts, req, last_hash,
		audit_hash(last_hash, new_seq, 'data', p_scope, 'data_reset', NULL, NULL, counts, req)
	);
	PERFORM set_config('app.audit_erase', 'off', true);
	RETURN counts || jsonb_build_object('tombstone_seq', new_seq);
END;
$$;
