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
exit $fail
