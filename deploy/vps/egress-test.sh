#!/usr/bin/env bash
# TESTS THE EGRESS WALL FROM INSIDE botler-app (run egress.sh first): private, metadata, AFB and host addresses must fail, the public internet and the database must work.
set -uo pipefail
APP="${BOTLER_APP_CONTAINER:-botler-botler-app-1}"
DB="${BOTLER_DB_CONTAINER:-botler-botler-db-1}"
AFB="${AFB_APP_CONTAINER:-agent-flow-board-app-1}"
ipof() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" | awk '{print $1}'; }
afb_ip="$(ipof "$AFB")"
host_ip="$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}')"

# connects to host:port from inside the app container and prints open or blocked
try() {
  docker exec "$APP" node -e "
    const s = require('net').connect({ host: '$1', port: $2, timeout: 4000 });
    s.on('connect', () => { console.log('open'); s.destroy(); });
    s.on('timeout', () => { console.log('blocked'); s.destroy(); });
    s.on('error', () => console.log('blocked'));
  " 2>/dev/null | tail -1
}
fail=0
expect() { # name, want, got
  if [ "$2" = "$3" ]; then echo "ok    $1 -> $3"; else echo "FAIL  $1 -> $3 (wanted $2)"; fail=1; fi
}
expect "metadata 169.254.169.254:80"     blocked "$(try 169.254.169.254 80)"
expect "AFB app $afb_ip:3000"            blocked "$(try "$afb_ip" 3000)"
expect "AFB app $afb_ip:80"              blocked "$(try "$afb_ip" 80)"
expect "Docker host $host_ip:22"         blocked "$(try "$host_ip" 22)"
expect "private 10.0.0.1:80"             blocked "$(try 10.0.0.1 80)"
expect "private 192.168.1.1:80"          blocked "$(try 192.168.1.1 80)"
expect "botler-db port 80 (not 5432)"    blocked "$(try "$(ipof "$DB")" 80)"
expect "botler-db 5432"                  open    "$(try "$(ipof "$DB")" 5432)"
expect "public internet 1.1.1.1:443"     open    "$(try 1.1.1.1 443)"

# -- IPV6 -- #
# A connect to these can fail only because the host has no IPv6 route, so the connect result alone proves little. The rules themselves are checked
# inside the app's namespace (the wall must exist and reject each range), and the connects are kept as a second line
pid="$(docker inspect -f '{{.State.Pid}}' "$APP")"
rules6="$(sudo nsenter -t "$pid" -n ip6tables -S 2>/dev/null || true)"
has6() { # name, pattern
  if printf '%s\n' "$rules6" | grep -q -- "$2"; then echo "ok    ip6tables $1"; else echo "FAIL  ip6tables $1 missing"; fail=1; fi
}
has6 "OUTPUT jumps to BOTLER-OUT6" "-A OUTPUT -j BOTLER-OUT6"
has6 "rejects fc00::/7"            "-A BOTLER-OUT6 -d fc00::/7 .*-j REJECT"
has6 "rejects fe80::/10"           "-A BOTLER-OUT6 -d fe80::/10 .*-j REJECT"
has6 "rejects 64:ff9b::/96"        "-A BOTLER-OUT6 -d 64:ff9b::/96 .*-j REJECT"
expect "IPv6 unique local fc00::1:80"    blocked "$(try fc00::1 80)"
expect "IPv6 AWS metadata fd00:ec2::254" blocked "$(try fd00:ec2::254 80)"
expect "IPv6 NAT64 of 10.0.0.1"          blocked "$(try 64:ff9b::a00:1 80)"
exit $fail
