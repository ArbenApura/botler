#!/bin/bash
# NIGHTLY ENCRYPTED DATABASE DUMP, RUN ON THE SERVER (cron: 0 2 * * *  bash ~/botler/deploy/vps/backup.sh).
# The dump is piped straight into `age`, encrypted to BACKUP_AGE_RECIPIENT (a public key). The private key is NOT on this server,
# so a stolen disk or a copied backup is unreadable. Plain dumps are never written to disk. Keeps the last 14 files.
# The dump runs as the postgres superuser inside the container: every user table has FORCE row level security, which hides the rows
# from a non-superuser (pg_dump would fail or dump nothing). A failed dump removes its partial file and exits non-zero.
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a
: "${BACKUP_AGE_RECIPIENT:?Set BACKUP_AGE_RECIPIENT in .env (the public key)}"
command -v age >/dev/null || { echo "age is not installed (sudo apt install age)"; exit 1; }
dir="$HOME/botler/backups"
mkdir -p "$dir" && chmod 700 "$dir"
file="$dir/botler-$(date -u +%Y%m%d-%H%M%S).sql.age"
trap 'rm -f "$file.partial"' ERR EXIT
docker compose exec -T botler-db pg_dump -U postgres -d botler --no-owner --clean --if-exists \
  | age -r "$BACKUP_AGE_RECIPIENT" > "$file.partial"
# An empty or tiny file means the dump failed quietly
size=$(stat -c %s "$file.partial")
if [ "$size" -lt 500 ]; then echo "Backup is only $size bytes: refusing to keep it"; exit 1; fi
mv "$file.partial" "$file"
chmod 600 "$file"
trap - ERR EXIT
# Keep the newest 14
ls -1t "$dir"/botler-*.sql.age | tail -n +15 | xargs -r rm -f
echo "Backup written: $(basename "$file") ($(du -h "$file" | cut -f1))"
