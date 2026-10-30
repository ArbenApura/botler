CREATE TABLE "notebook_page" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"notebook_id" uuid NOT NULL,
	"parent_page_id" uuid,
	"title" text NOT NULL,
	"text" text DEFAULT '' NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"pinned_at" timestamp with time zone,
	"seen_version" integer DEFAULT 0 NOT NULL,
	"updated_by" text DEFAULT 'user' NOT NULL,
	"deleted_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "notebook_page_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "notebook_page_notebook_id_uq" UNIQUE("user_id","notebook_id","id"),
	CONSTRAINT "notebook_page_updated_by_chk" CHECK ("notebook_page"."updated_by" in ('user', 'agent', 'seed')),
	CONSTRAINT "notebook_page_shape_chk" CHECK (length("notebook_page"."title") between 1 and 80 and length("notebook_page"."text") <= 30000 and "notebook_page"."version" >= 1 and "notebook_page"."seen_version" >= 0 and "notebook_page"."position" >= 0)
);
--> statement-breakpoint
CREATE TABLE "notebook_page_revision" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"page_id" uuid NOT NULL,
	"version" integer NOT NULL,
	"text" text NOT NULL,
	"actor" text NOT NULL,
	"ref" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" text NOT NULL,
	CONSTRAINT "notebook_page_revision_user_id_uq" UNIQUE("user_id","id"),
	CONSTRAINT "notebook_page_revision_version_uq" UNIQUE("user_id","page_id","version"),
	CONSTRAINT "notebook_page_revision_actor_chk" CHECK ("notebook_page_revision"."actor" in ('user', 'agent', 'seed')),
	CONSTRAINT "notebook_page_revision_text_chk" CHECK (length("notebook_page_revision"."text") <= 30000)
);
--> statement-breakpoint
ALTER TABLE "notebook" ADD COLUMN "pinned_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "notebook_page" ADD CONSTRAINT "notebook_page_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notebook_page" ADD CONSTRAINT "notebook_page_notebook_fk" FOREIGN KEY ("user_id","notebook_id") REFERENCES "public"."notebook"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notebook_page" ADD CONSTRAINT "notebook_page_parent_fk" FOREIGN KEY ("user_id","notebook_id","parent_page_id") REFERENCES "public"."notebook_page"("user_id","notebook_id","id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notebook_page_revision" ADD CONSTRAINT "notebook_page_revision_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notebook_page_revision" ADD CONSTRAINT "notebook_page_revision_page_fk" FOREIGN KEY ("user_id","page_id") REFERENCES "public"."notebook_page"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "notebook_page_title_uq" ON "notebook_page" USING btree ("user_id","notebook_id",coalesce("parent_page_id", '00000000-0000-0000-0000-000000000000'::uuid),lower("title")) WHERE "notebook_page"."deleted_at" is null;--> statement-breakpoint
CREATE INDEX "notebook_page_tree_idx" ON "notebook_page" USING btree ("user_id","notebook_id","parent_page_id","position");--> statement-breakpoint
CREATE INDEX "notebook_page_updated_idx" ON "notebook_page" USING btree ("user_id","updated_at");--> statement-breakpoint
CREATE INDEX "notebook_page_revision_recent_idx" ON "notebook_page_revision" USING btree ("user_id","page_id","created_at");--> statement-breakpoint
-- HAND-EDITED (BTL NOTEBOOK LIBRARY): THE GENERATED STATEMENTS ABOVE ARE THE PAGE TABLES AND notebook.pinned_at. drizzle-kit also wanted to rewrite three
-- provider checks (the Anthropic removal changed the schema without a migration); that is not part of this change, so those statements are left out and the
-- snapshot keeps the old checks, so the next db:generate still shows that difference.
-- A PAGE SITS AT MOST ONE LEVEL DEEP: A PARENT MUST BE A TOP-LEVEL PAGE, A PAGE WITH LIVE SUB-PAGES CANNOT GET A PARENT, AND A LIVE PAGE CANNOT SIT UNDER A DELETED PARENT. THE PARENT ROW IS LOCKED WHILE THE CHECK RUNS,
-- SO TWO MOVES AT ONCE CANNOT MAKE A CYCLE OR A SECOND LEVEL. The parent is in the same notebook by the composite key of the foreign key.
CREATE OR REPLACE FUNCTION notebook_page_shape() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
	grand uuid;
	parent_deleted timestamptz;
	found_parent boolean;
BEGIN
	IF NEW.parent_page_id IS NULL THEN
		RETURN NEW;
	END IF;
	IF NEW.parent_page_id = NEW.id THEN
		RAISE EXCEPTION 'A page cannot be its own parent' USING ERRCODE = 'check_violation';
	END IF;
	SELECT p.parent_page_id, p.deleted_at, true INTO grand, parent_deleted, found_parent
	FROM notebook_page p
	WHERE p.user_id = NEW.user_id AND p.notebook_id = NEW.notebook_id AND p.id = NEW.parent_page_id
	FOR UPDATE;
	IF found_parent AND grand IS NOT NULL THEN
		RAISE EXCEPTION 'A sub-page cannot have sub-pages: the parent must be a top-level page' USING ERRCODE = 'check_violation';
	END IF;
	IF found_parent AND NEW.deleted_at IS NULL AND parent_deleted IS NOT NULL THEN
		RAISE EXCEPTION 'A live page cannot sit under a deleted page' USING ERRCODE = 'check_violation';
	END IF;
	IF NEW.deleted_at IS NULL AND EXISTS (
		SELECT 1 FROM notebook_page c
		WHERE c.user_id = NEW.user_id AND c.parent_page_id = NEW.id AND c.deleted_at IS NULL
	) THEN
		RAISE EXCEPTION 'A page that has sub-pages cannot become a sub-page' USING ERRCODE = 'check_violation';
	END IF;
	RETURN NEW;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER "notebook_page_shape" BEFORE INSERT OR UPDATE OF "notebook_id", "parent_page_id", "deleted_at" ON "notebook_page" FOR EACH ROW EXECUTE FUNCTION notebook_page_shape();
--> statement-breakpoint
-- EACH EXISTING EXTRA NOTEBOOK (LIVE OR DELETED) BECOMES A NOTEBOOK WITH ONE PAGE TITLED "Overview" HOLDING ITS TEXT, AND ITS REVISIONS MOVE TO THE PAGE.
-- The owner is bound by forced row level security with no read policy for it, so it is lifted on the two old tables for this migration only (as 0033 did),
-- and put back at the end. The page tables have no row level security yet (it is applied after the migrations). The old text column is emptied only after
-- the check below has compared the counts and the total length of the copy with the originals; any difference stops the migration and rolls it all back.
ALTER TABLE "notebook" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "notebook_revision" NO FORCE ROW LEVEL SECURITY;--> statement-breakpoint
INSERT INTO "notebook_page" ("user_id", "notebook_id", "title", "text", "version", "position", "seen_version", "updated_by", "created_at", "updated_at")
SELECT n."user_id", n."id", 'Overview', n."text", n."version", 0, n."version", n."updated_by", n."created_at", n."updated_at"
FROM "notebook" n WHERE n."kind" = 'extra';--> statement-breakpoint
INSERT INTO "notebook_page_revision" ("user_id", "page_id", "version", "text", "actor", "ref", "created_at", "updated_at")
SELECT r."user_id", p."id", r."version", r."text", r."actor", r."ref", r."created_at", r."updated_at"
FROM "notebook_revision" r
JOIN "notebook" n ON n."user_id" = r."user_id" AND n."id" = r."notebook_id" AND n."kind" = 'extra'
JOIN "notebook_page" p ON p."user_id" = n."user_id" AND p."notebook_id" = n."id";--> statement-breakpoint
DO $$
DECLARE
	old_pages bigint; new_pages bigint; old_chars bigint; new_chars bigint;
	old_revs bigint; new_revs bigint; old_rev_chars bigint; new_rev_chars bigint;
BEGIN
	SELECT count(*), coalesce(sum(length("text")), 0) INTO old_pages, old_chars FROM "notebook" WHERE "kind" = 'extra';
	SELECT count(*), coalesce(sum(length("text")), 0) INTO new_pages, new_chars FROM "notebook_page";
	SELECT count(*), coalesce(sum(length(r."text")), 0) INTO old_revs, old_rev_chars
		FROM "notebook_revision" r JOIN "notebook" n ON n."user_id" = r."user_id" AND n."id" = r."notebook_id" AND n."kind" = 'extra';
	SELECT count(*), coalesce(sum(length("text")), 0) INTO new_revs, new_rev_chars FROM "notebook_page_revision";
	IF old_pages <> new_pages OR old_chars <> new_chars OR old_revs <> new_revs OR old_rev_chars <> new_rev_chars THEN
		RAISE EXCEPTION 'The notebook pages copy does not match: % notebooks / % pages, % / % characters, % / % revisions, % / % revision characters',
			old_pages, new_pages, old_chars, new_chars, old_revs, new_revs, old_rev_chars, new_rev_chars;
	END IF;
END $$;
--> statement-breakpoint
UPDATE "notebook" SET "text" = '' WHERE "kind" = 'extra' AND "text" <> '';--> statement-breakpoint
ALTER TABLE "notebook" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "notebook_revision" FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
-- THE DATA RESET ALSO ERASES THE PAGES AND THEIR REVISIONS (THE REVISIONS FIRST, THEN THE PAGES, THEN THE NOTEBOOK). 0031 STAYS AS IT RAN; THE FUNCTION IS REPLACED HERE.
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
		WHEN 'money' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'undo_journal', 'agent_action']
		WHEN 'schedule' THEN ARRAY['reminder', 'task', 'calendar_event', 'routine']
		WHEN 'memory_and_chat' THEN ARRAY['chat_turn', 'chat', 'memory_fact', 'memory_summary', 'notebook_page_revision', 'notebook_page', 'notebook_revision', 'notebook']
		WHEN 'audit' THEN ARRAY[]::text[]
		WHEN 'everything' THEN ARRAY['bill_payment', 'ledger_txn', 'balance_snapshot', 'split_plan', 'allocation_rule', 'goal', 'bill_override', 'bill', 'income_schedule', 'account_wallet', 'account', 'undo_journal', 'agent_action', 'reminder', 'task', 'calendar_event', 'routine', 'chat_turn', 'chat', 'memory_fact', 'memory_summary', 'notebook_page_revision', 'notebook_page', 'notebook_revision', 'notebook', 'memory_profile']
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
