#!/bin/bash
# NIGHTLY ENCRYPTED DATABASE DUMP, RUN ON THE SERVER (cron: 0 2 * * *  bash ~/botler/deploy/vps/backup.sh).
# The dump is piped straight into `age`, encrypted to BACKUP_AGE_RECIPIENT (a public key). The private key is NOT on this server,
# so a stolen disk or a copied backup is unreadable. Plain dumps are never written to disk.
# Keeps the newest 14 daily files in ~/botler/backups and, in addition, a weekly set (the Sunday dump, newest 8) in ~/botler/backups/weekly.
# The dump runs as the postgres superuser inside the container: every user table has FORCE row level security, which hides the rows
# from a non-superuser (pg_dump would fail or dump nothing). A failed dump removes its partial file and exits non-zero.
# Only after a verified dump (pg_dump and age both exited 0, an age header, a sane size) the file is kept and ~/botler/backups/LAST_OK is
# rewritten with a UTC timestamp. pull-backups.ps1 and deploy.ps1 warn when LAST_OK is older than 36 hours. To restore: restore.sh, docs/RESTORE.md.
# .env is NOT sourced (a value with $( ) or a backtick would run as code): only BACKUP_AGE_RECIPIENT is read, and it is validated.
set -euo pipefail
cd "$(dirname "$0")"

# -- READ ONE KEY FROM .env SAFELY -- #
# Takes the last KEY=value line, strips one pair of surrounding quotes and rejects anything that is not plain text
env_value() {
  local key="$1" line value
  line="$(grep -E "^${key}=" ./.env | tail -n 1 || true)"
  value="${line#"${key}="}"
  value="${value%$'\r'}"
  if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"; fi
  if [[ "$value" =~ [[:space:]\$\`\\\"\'\;\&\|\<\>\(\)] ]]; then echo "${key} in .env has a space or a shell character: refusing to use it" >&2; return 1; fi
  printf '%s' "$value"
}

[ -f ./.env ] || { echo "No .env next to backup.sh"; exit 1; }
BACKUP_AGE_RECIPIENT="$(env_value BACKUP_AGE_RECIPIENT)"
[ -n "$BACKUP_AGE_RECIPIENT" ] || { echo "Set BACKUP_AGE_RECIPIENT in .env (the public key)"; exit 1; }
[[ "$BACKUP_AGE_RECIPIENT" =~ ^age1[a-z0-9]{50,}$ ]] || { echo "BACKUP_AGE_RECIPIENT is not an age public key (age1...)"; exit 1; }
command -v age >/dev/null || { echo "age is not installed (sudo apt install age)"; exit 1; }

dir="$HOME/botler/backups"
mkdir -p "$dir/weekly" && chmod 700 "$dir" "$dir/weekly"
file="$dir/botler-$(date -u +%Y%m%d-%H%M%S).sql.age"
trap 'rm -f "$file.partial"' ERR EXIT

# -- DUMP -- #
# pipefail makes a failing pg_dump fail the whole pipe
docker compose exec -T botler-db pg_dump -U postgres -d botler --no-owner --clean --if-exists \
  | age -r "$BACKUP_AGE_RECIPIENT" > "$file.partial"

# -- VERIFY -- #
# An empty or tiny file means the dump failed quietly; a real age file starts with its header line
size=$(stat -c %s "$file.partial")
if [ "$size" -lt 500 ]; then echo "Backup is only $size bytes: refusing to keep it"; exit 1; fi
[ "$(head -c 21 "$file.partial")" = "age-encryption.org/v1" ] || { echo "Backup has no age header: refusing to keep it"; exit 1; }
mv "$file.partial" "$file"
chmod 600 "$file"
trap - ERR EXIT

# -- SUCCESS MARKER -- #
# Written only now, and by rename so a reader never sees a half written file
date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/LAST_OK.tmp"
mv "$dir/LAST_OK.tmp" "$dir/LAST_OK"

# -- RETENTION -- #
# Weekly set: the Sunday dump is copied once into weekly/ (newest 8 kept)
if [ "$(date -u +%u)" = "7" ]; then
  cp -p "$file" "$dir/weekly/$(basename "$file")"
fi
# (ls fails when there is no match yet, which pipefail would turn into a failed backup: the || true keeps the retention step quiet)
{ ls -1t "$dir"/weekly/botler-*.sql.age 2>/dev/null || true; } | tail -n +9 | xargs -r rm -f
# Daily set: the newest 14
{ ls -1t "$dir"/botler-*.sql.age 2>/dev/null || true; } | tail -n +15 | xargs -r rm -f
echo "Backup written: $(basename "$file") ($(du -h "$file" | cut -f1))"
