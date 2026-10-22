CREATE TABLE "memory_fact" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"text" text NOT NULL,
	"text_hash" text NOT NULL,
	"subject" text,
	"kind" text DEFAULT 'fact' NOT NULL,
	"importance" smallint DEFAULT 3 NOT NULL,
	"source" text DEFAULT 'extracted' NOT NULL,
	"confidence" smallint DEFAULT 80 NOT NULL,
	"valid_from" timestamp with time zone DEFAULT now() NOT NULL,
	"valid_to" timestamp with time zone,
	"superseded_by" uuid,
	"suppressed" boolean DEFAULT false NOT NULL,
	"pending" boolean DEFAULT false NOT NULL,
	"fade_weight" real DEFAULT 1 NOT NULL,
	"last_used_at" timestamp with time zone,
	"turn_id" text,
	"search_text" "tsvector" GENERATED ALWAYS AS (to_tsvector('simple', text)) STORED,
	"embedding" vector(384),
	"embedding_model" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "memory_fact_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "memory_fact_kind_chk" CHECK ("memory_fact"."kind" in ('fact', 'preference', 'event', 'person', 'money')),
	CONSTRAINT "memory_fact_source_chk" CHECK ("memory_fact"."source" in ('user', 'extracted', 'web')),
	CONSTRAINT "memory_fact_text_chk" CHECK (length("memory_fact"."text") between 1 and 400),
	CONSTRAINT "memory_fact_scores_chk" CHECK ("memory_fact"."importance" between 1 and 5 and "memory_fact"."confidence" between 0 and 100 and "memory_fact"."fade_weight" between 0.1 and 1)
);
--> statement-breakpoint
CREATE TABLE "memory_profile" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"persona" text DEFAULT '' NOT NULL,
	"about" text DEFAULT '' NOT NULL,
	"people" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"mood" integer DEFAULT 0 NOT NULL,
	"familiarity" integer DEFAULT 0 NOT NULL,
	"mood_updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "memory_profile_user_uq" UNIQUE("user_id"),
	CONSTRAINT "memory_profile_mood_chk" CHECK ("memory_profile"."mood" between -100 and 100),
	CONSTRAINT "memory_profile_familiarity_chk" CHECK ("memory_profile"."familiarity" >= 0),
	CONSTRAINT "memory_profile_persona_chk" CHECK (length("memory_profile"."persona") <= 2000 and length("memory_profile"."about") <= 2000)
);
--> statement-breakpoint
CREATE TABLE "memory_summary" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"period" text NOT NULL,
	"period_start" date NOT NULL,
	"text" text NOT NULL,
	"fact_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "memory_summary_period_uq" UNIQUE("user_id","period","period_start"),
	CONSTRAINT "memory_summary_period_chk" CHECK ("memory_summary"."period" in ('day', 'week', 'month')),
	CONSTRAINT "memory_summary_text_chk" CHECK (length("memory_summary"."text") <= 4000)
);
--> statement-breakpoint
ALTER TABLE "memory_fact" ADD CONSTRAINT "memory_fact_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "memory_profile" ADD CONSTRAINT "memory_profile_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "memory_summary" ADD CONSTRAINT "memory_summary_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "memory_fact_user_state_idx" ON "memory_fact" USING btree ("user_id","suppressed","valid_to");--> statement-breakpoint
CREATE INDEX "memory_fact_user_hash_idx" ON "memory_fact" USING btree ("user_id","text_hash");--> statement-breakpoint
CREATE INDEX "memory_fact_user_subject_idx" ON "memory_fact" USING btree ("user_id","subject");--> statement-breakpoint
CREATE INDEX "memory_fact_search_idx" ON "memory_fact" USING gin ("search_text");--> statement-breakpoint
CREATE INDEX "memory_fact_embedding_idx" ON "memory_fact" USING hnsw ("embedding" vector_cosine_ops);