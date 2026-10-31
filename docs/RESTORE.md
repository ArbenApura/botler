# Restoring a backup

Backups are nightly, encrypted with `age` to a public key on the server (`deploy/vps/backup.sh`). The private key is kept off the server, so a restore needs that key. A restore always goes into a NEW database. It never overwrites the live one and it never runs `--clean` on the live database.

**The owner must do a restore drill** (below) before trusting the backups: until a dump has been opened and counted once, it is only a file. Repeat it after any change to the database layout, and at least every few months. Nothing here is run by the deploy or by cron.

## What you need

- A backup file `botler-YYYYMMDD-HHMMSS.sql.age`. Newest daily ones are in `~/botler/backups` on the VPS, weekly ones in `~/botler/backups/weekly`; `powershell deploy/vps/pull-backups.ps1` copies both to `Desktop\botler-backups` and warns when `backups/LAST_OK` is older than 36 hours.
- The age private key file (from the password manager). Pass its path as an argument. It is only handed to `age -d -i`; the script never prints or copies it.
- Docker, with a Postgres 17 + pgvector container to restore into.

## Drill on your own PC (safe, touches nothing live)

Use a throwaway container with its own name and its own volume. Never AFB's database and never port 5433 or 5434.

```powershell
# 1. A throwaway Postgres on another port (its own volume, deleted by you only when you are done with it)
docker run -d --name botler-restore-drill -e POSTGRES_PASSWORD=drillpassword -p 127.0.0.1:5439:5432 -v botler_restore_drill:/var/lib/postgresql/data pgvector/pgvector:pg17
# 2. The roles the dump refers to must exist (the dump has GRANTs to them)
docker exec botler-restore-drill psql -U postgres -c "create role app_runtime login; create role botler_owner login;"
# 3. Restore into a new database (Git Bash or WSL; the key path is only passed to age)
RESTORE_DB_EXEC="docker exec -i botler-restore-drill" bash deploy/vps/restore.sh ~/Desktop/botler-backups/botler-YYYYMMDD-HHMMSS.sql.age /path/to/age-key.txt botler_restored
```

The script asks you to type `botler_restored`, creates that database, loads the dump in one transaction, then prints the row count of every table. The "live now" column is empty on the drill container (there is no `botler` database there); that is expected. The drill passes when the tables are listed, the totals are above zero and the numbers look right for the day of the backup (accounts, ledger entries, notebooks, `audit_event`). Then you may remove the drill container and its volume yourself: they are yours and hold only a copy. The repo scripts never remove volumes.

If role creation in step 2 is refused because a role exists, that is fine. If the load stops on a missing role or extension, the error names it; create it and use a new database name.

## Restoring on the server (after a loss)

Only with the owner's yes, because it reaches the VPS. Do not copy the private key onto the server for longer than the restore.

1. Copy the dump and (temporarily) the key into `/dev/shm` (memory, not disk): `scp dump key ubuntu@HOST:/dev/shm/`.
2. On the server: `cd ~/botler/deploy/vps && bash restore.sh /dev/shm/botler-....sql.age /dev/shm/key.txt botler_restored_YYYYMMDD`. Type the database name when asked.
3. Read the row counts. The "live now" column compares with the current `botler` database (read only). Remove the key at once: `shred -u /dev/shm/key.txt` (or `rm`), and the dump from `/dev/shm`.
4. If the numbers are right, continue with "Switch the app" below. If not, the new database can simply be dropped by you later; nothing else changed.

## Switch the app to the restored database (owner)

The live database is only left alone until you choose to replace it. Do this when the live data is lost or damaged, not for a drill.

1. Stop the app only: `cd ~/botler/deploy/vps && docker compose stop botler-app`. Leave `botler-db` running.
2. Make a safety copy first: `bash backup.sh` (it still encrypts to your public key), so the damaged state can be looked at later.
3. Rename, never drop: in `psql -U postgres -d postgres` run `ALTER DATABASE botler RENAME TO botler_old_YYYYMMDD;` (it needs no connections: the app is stopped, and `botler-migrate` has exited), then `ALTER DATABASE botler_restored_YYYYMMDD RENAME TO botler;`. The database is now named what `DATABASE_URL` expects, and the old one stays on disk under its new name.
4. Check the roles can reach it: the app connects as `app_runtime` with `BOTLER_RUNTIME_PASSWORD` from `.env`. `restore.sh` has already handed the new database's tables, functions and types to `botler_owner` (the dump is made with `--no-owner`, so they would otherwise belong to `postgres`, and the migration step and the SECURITY DEFINER functions need `botler_owner`). If `docker compose up` below fails with a permission error, a role from the old cluster is missing: recreate it as `postgres-init.sh` does.
5. Start: `docker compose up -d botler-migrate botler-app` (the migration step brings an older dump up to the current schema), then `bash egress.sh` and check `https://botler.arbenger.com/healthz`.
6. Sign in on the phone and open an account history; run the audit check in Settings.
7. Keep `botler_old_YYYYMMDD` until you are sure; dropping it is a separate, deliberate step, and dropping a volume is never part of this.

Data written after the backup is not in it. The phone's outbox still holds writes it could not send, and they replay with their `requestId`.
