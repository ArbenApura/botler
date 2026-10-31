#!/usr/bin/env bash
# EGRESS WALL FOR BOTLER'S APP CONTAINER (BTL P7.6): the fetch tool can only reach the public internet, whatever the code does.
# The in-process fetch guard already refuses private addresses; this is the second wall. It is a firewall inside botler-app's own network namespace
# (nsenter), so it also covers containers on the same Docker network (AFB's app shares one with botler-app for Caddy), which the host firewall cannot see
# without loading br_netfilter for the whole machine. New connections from botler-app to private, link-local (cloud metadata 169.254.169.254) and
# carrier-grade ranges are rejected, and so is the Docker host. The one exception is Postgres: tcp 5432 on botler-db. Replies to connections others opened
# (Caddy) and the container's own DNS (127.0.0.11) still work. Nothing of AFB's, and no host rule, is changed.
# The same wall is built for IPv6 with ip6tables in the same namespace: unique local (fc00::/7), link-local (fe80::/10), site-local (fec0::/10),
# IPv4-mapped (::ffff:0:0/96) and NAT64 (64:ff9b::/96, which would reach private IPv4 hosts) are rejected. ip6tables missing is an error, never skipped.
# THE RULES LIVE ONLY AS LONG AS THE CONTAINER. A container restart or recreate (docker restart, a crash, a host reboot, a deploy) starts with no wall, so this
# script must run again each time. deploy.ps1 runs it after every deploy. For restarts it does not see, put these two lines in the ROOT crontab on the VPS
# (sudo crontab -e; paths are for the ubuntu user, change them if the home differs). The script is safe to repeat:
#   @reboot   sleep 90 && /bin/bash /home/ubuntu/botler/deploy/vps/egress.sh >> /var/log/botler-egress.log 2>&1
#   */5 * * * * /bin/bash /home/ubuntu/botler/deploy/vps/egress.sh >> /var/log/botler-egress.log 2>&1
# The 5 minute line closes the gap after a single container restart to at most 5 minutes. Check with egress-test.sh after any change.
set -euo pipefail

APP="${BOTLER_APP_CONTAINER:-botler-botler-app-1}"
DB="${BOTLER_DB_CONTAINER:-botler-botler-db-1}"
PRIVATE="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10"
PRIVATE6="fc00::/7 fe80::/10 fec0::/10 ::ffff:0:0/96 64:ff9b::/96"

ipof() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" | awk '{print $1}'; }

pid="$(docker inspect -f '{{.State.Pid}}' "$APP")"
db_ip="$(ipof "$DB")"
[ "$pid" -gt 0 ] || { echo "$APP is not running"; exit 1; }
[ -n "$db_ip" ] || { echo "no address for $DB"; exit 1; }
db_ip6="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}} {{end}}' "$DB" | awk '{print $1}')"
sudo nsenter -t "$pid" -n ip6tables -S >/dev/null 2>&1 || { echo "ip6tables does not work inside $APP: the IPv6 wall cannot be set (install the ip6tables / iptables package)"; exit 1; }

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

# -- IPV6 -- #
in_app6() { sudo nsenter -t "$pid" -n ip6tables "$@"; }
in_app6 -N BOTLER-OUT6 2>/dev/null || true
in_app6 -F BOTLER-OUT6
in_app6 -A BOTLER-OUT6 -o lo -j RETURN
in_app6 -A BOTLER-OUT6 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
if [ -n "$db_ip6" ]; then in_app6 -A BOTLER-OUT6 -d "$db_ip6" -p tcp --dport 5432 -j RETURN; fi
for net in $PRIVATE6; do
  in_app6 -A BOTLER-OUT6 -d "$net" -j REJECT --reject-with icmp6-port-unreachable
done
in_app6 -C OUTPUT -j BOTLER-OUT6 2>/dev/null || in_app6 -I OUTPUT 1 -j BOTLER-OUT6
echo "egress wall set inside $APP (pid $pid); database $db_ip:5432 allowed (IPv4 and IPv6 walls)"
