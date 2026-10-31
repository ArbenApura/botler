#!/bin/bash
# RESTORE AN AGE ENCRYPTED BACKUP INTO A NEW, SEPARATE DATABASE (never over a live one). See docs/RESTORE.md for the whole procedure.
#   bash restore.sh <backup.sql.age> <age-private-key-file> <new-database-name>
# What it does, in order:
#   1. refuses a database name that already exists or that is botler / postgres / template0 / template1 (the live database is never a target)
#   2. asks you to TYPE the new database name
#   3. creates the new database, decrypts the dump with `age -d -i <key>` (the key file is only passed to age, never printed or copied) and loads it
#      into the new database in ONE transaction with ON_ERROR_STOP. The dump carries DROP ... IF EXISTS lines (it was made with --clean): they run
#      only inside the new, empty database, never on the live one
#   4. gives the new database's objects to botler_owner (as in the live database), when that role exists
#   5. counts the rows of every table in the new database (next to the live database's counts, read only) and fails if the restore is empty
# It never drops or truncates anything and never runs against the live database. It does not switch the app: that is the owner's step (docs/RESTORE.md).
# Where to run it: the private key is kept OFF the server, so the safe drill is on your own PC against a throwaway Postgres container (own name, own volume):
#   RESTORE_DB_EXEC="docker exec -i botler-restore-drill" bash restore.sh dump.sql.age key.txt botler_restored
# On the server, with no RESTORE_DB_EXEC, it talks to the botler-db service of this compose project. Do not run it without the owner's yes.
set -euo pipefail
cd "$(dirname "$0")"

[ "$#" -eq 3 ] || { echo "Usage: bash restore.sh <backup.sql.age> <age-private-key-file> <new-database-name>"; exit 2; }
dump="$1"; key="$2"; newdb="$3"

# -- CHECK THE ARGUMENTS -- #
[ -f "$dump" ] || { echo "No such backup file: $dump"; exit 2; }
[ -f "$key" ] || { echo "No such key file (the path is not printed back): check the second argument"; exit 2; }
command -v age >/dev/null || { echo "age is not installed (sudo apt install age)"; exit 1; }
[[ "$newdb" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "The new database name must be lowercase letters, digits and _, 3 to 41 characters, starting with a letter"; exit 2; }
case "$newdb" in
  botler|postgres|template0|template1) echo "Refusing: '$newdb' is a live or system database. Pick a new name such as botler_restored_$(date -u +%Y%m%d)"; exit 2 ;;
esac

# -- HOW TO REACH POSTGRES -- #
# RESTORE_DB_EXEC is a command prefix that runs a command inside the Postgres container (default: this compose project's botler-db)
if [ -n "${RESTORE_DB_EXEC:-}" ]; then read -r -a runner <<< "$RESTORE_DB_EXEC"; else runner=(docker compose exec -T botler-db); fi
psql_in() { "${runner[@]}" psql -U postgres -v ON_ERROR_STOP=1 "$@"; }

exists="$(psql_in -d postgres -tAc "select 1 from pg_database where datname = '$newdb'")"
[ -z "$exists" ] || { echo "Database '$newdb' already exists. Refusing to load into it. Pick another name."; exit 1; }

# -- TYPED CONFIRMATION -- #
echo "This will create a NEW database '$newdb' and load $(basename "$dump") into it. The live database is not touched."
read -r -p "Type the new database name to continue: " typed
[ "$typed" = "$newdb" ] || { echo "Not the same name. Nothing was done."; exit 1; }

# -- RESTORE -- #
psql_in -d postgres -c "create database \"$newdb\""
echo "Loading (this can take a while)..."
if ! age -d -i "$key" "$dump" | psql_in -d "$newdb" --single-transaction -q -o /dev/null; then
  echo "RESTORE FAILED. The empty database '$newdb' is left in place for inspection; drop it yourself when done: psql -U postgres -d postgres -c 'drop database $newdb'"
  exit 1
fi

# -- OWNERSHIP -- #
# The dump was made with --no-owner, so everything now belongs to postgres. The live database is owned by botler_owner (it runs the migrations, and the
# SECURITY DEFINER functions and forced row level security depend on that), so hand the new database's own objects to botler_owner when that role exists.
# Only the NEW database is touched; extension members and identity sequences are skipped.
psql_in -d "$newdb" -q -o /dev/null <<'SQL'
DO $do$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'botler_owner') THEN
    RAISE NOTICE 'role botler_owner does not exist here: ownership left as restored';
    RETURN;
  END IF;
  EXECUTE format('ALTER DATABASE %I OWNER TO botler_owner', current_database());
  ALTER SCHEMA public OWNER TO botler_owner;
  FOR r IN
    SELECT c.oid, c.relkind, quote_ident(n.nspname) || '.' || quote_ident(c.relname) AS name
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('e', 'i', 'a'))
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO botler_owner',
      CASE r.relkind WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END, r.name);
  END LOOP;
  FOR r IN
    SELECT p.oid::regprocedure::text AS name, p.prokind
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e')
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO botler_owner', CASE r.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, r.name);
  END LOOP;
  FOR r IN
    SELECT quote_ident(n.nspname) || '.' || quote_ident(t.typname) AS name
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype IN ('e', 'd')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = t.oid AND d.classid = 'pg_type'::regclass AND d.deptype = 'e')
  LOOP
    EXECUTE format('ALTER TYPE %s OWNER TO botler_owner', r.name);
  END LOOP;
END
$do$;
SQL

# -- ROW COUNT CHECK -- #
# Exact counts for every ordinary table in public, restored database on the left, live database ('botler') on the right (for comparison only)
counts() {
  printf '%s\n' "select format('select %L, count(*) from %I.%I', c.relname, n.nspname, c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'r' and n.nspname = 'public' order by c.relname \\gexec" \
    | psql_in -d "$1" -tA -F '|' 2>/dev/null | sort -t'|' -k1,1
}
restored="$(counts "$newdb")"
live="$(counts botler || true)"
[ -n "$restored" ] || { echo "CHECK FAILED: the restored database has no tables"; exit 1; }
printf '%-40s %12s %12s\n' "table" "restored" "live now"
total=0
while IFS='|' read -r tbl n; do
  l="$(printf '%s\n' "$live" | awk -F'|' -v t="$tbl" '$1==t{print $2}')"
  printf '%-40s %12s %12s\n' "$tbl" "$n" "${l:--}"
  total=$(( total + n ))
done <<< "$restored"
[ "$total" -gt 0 ] || { echo "CHECK FAILED: every table in '$newdb' is empty"; exit 1; }
echo
echo "Restored $(printf '%s\n' "$restored" | wc -l) tables, $total rows into '$newdb'. The live database was not changed."
echo "The restored numbers can be lower than the live ones (the backup is older). Switching the app to it: docs/RESTORE.md, step 'Switch the app'."
