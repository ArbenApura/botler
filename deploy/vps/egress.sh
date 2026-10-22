#!/usr/bin/env bash
# EGRESS WALL FOR BOTLER'S APP CONTAINER (BTL P7.6): the fetch tool can only reach the public internet, whatever the code does.
# The in-process fetch guard already refuses private addresses; this is the second wall. It is a firewall inside botler-app's own network namespace
# (nsenter), so it also covers containers on the same Docker network (AFB's app shares one with botler-app for Caddy), which the host firewall cannot see
# without loading br_netfilter for the whole machine. New connections from botler-app to private, link-local (cloud metadata 169.254.169.254) and
# carrier-grade ranges are rejected, and so is the Docker host. The one exception is Postgres: tcp 5432 on botler-db. Replies to connections others opened
# (Caddy) and the container's own DNS (127.0.0.11) still work. Nothing of AFB's, and no host rule, is changed.
# The rules live as long as the container, so run this after every deploy or restart (deploy.ps1 does, and a @reboot cron line).
set -euo pipefail

APP="${BOTLER_APP_CONTAINER:-botler-botler-app-1}"
DB="${BOTLER_DB_CONTAINER:-botler-botler-db-1}"
PRIVATE="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10"

ipof() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" | awk '{print $1}'; }

pid="$(docker inspect -f '{{.State.Pid}}' "$APP")"
db_ip="$(ipof "$DB")"
[ "$pid" -gt 0 ] || { echo "$APP is not running"; exit 1; }
[ -n "$db_ip" ] || { echo "no address for $DB"; exit 1; }

# The first version of this wall used host chains; take them out if they are still there
if sudo iptables -L BOTLER-EGRESS -n >/dev/null 2>&1; then
  sudo iptables -D DOCKER-USER -j BOTLER-EGRESS 2>/dev/null || true
  sudo iptables -F BOTLER-EGRESS && sudo iptables -X BOTLER-EGRESS
fi
if sudo iptables -L BOTLER-INPUT -n >/dev/null 2>&1; then
  sudo iptables -D INPUT -j BOTLER-INPUT 2>/dev/null || true
  sudo iptables -F BOTLER-INPUT && sudo iptables -X BOTLER-INPUT
fi

in_app() { sudo nsenter -t "$pid" -n iptables "$@"; }

in_app -N BOTLER-OUT 2>/dev/null || true
in_app -F BOTLER-OUT
in_app -A BOTLER-OUT -o lo -j RETURN
in_app -A BOTLER-OUT -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
in_app -A BOTLER-OUT -d "$db_ip" -p tcp --dport 5432 -j RETURN
for net in $PRIVATE; do
  in_app -A BOTLER-OUT -d "$net" -j REJECT --reject-with icmp-port-unreachable
done
in_app -C OUTPUT -j BOTLER-OUT 2>/dev/null || in_app -I OUTPUT 1 -j BOTLER-OUT
echo "egress wall set inside $APP (pid $pid); database $db_ip:5432 allowed"
