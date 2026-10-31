# DEPLOY THE WORKING TREE TO THE VPS: yarn deploy:vps (from server/) or powershell deploy/vps/deploy.ps1
# Builds the image on this PC (never on the VPS), sends it with the TRACKED files only (git ls-files; an untracked file never reaches the server), keeps the server's .env, takes an encrypted backup first, rebuilds, migrates, re-applies the egress wall and checks that the container now running is the image that was just built.
# This reaches the live server: the user confirms immediately before every run (VPS.md). Botler's compose project only; AFB is never touched.
param(
	[string]$Server = '',
	[string]$Url = 'https://botler.arbenger.com'
)
$ErrorActionPreference = 'Stop'
# The server login lives in one file
. "$PSScriptRoot\host.ps1"
if (-not $Server) { $Server = $BotlerServer }
Set-Location (Resolve-Path "$PSScriptRoot\..\..")
$tmp = Join-Path $env:TEMP 'botler-deploy'
# The build id names this deploy. It is baked into the image (label botler.build and env BOTLER_BUILD) and compared on the server after the start
$build = (Get-Date -Format 'yyyyMMddHHmmss')

# A native command's exit code is not an exception, so every step checks it
function Check([string]$what) {
	if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE). Nothing was reported as live." }
}

try {
	New-Item -ItemType Directory -Force $tmp | Out-Null

	# -- PACK -- #
	# Tracked files only: a stray untracked file (a scratch script, a local key) must never be copied to the server
	$untracked = @(git ls-files -o --exclude-standard)
	Check 'git ls-files (untracked)'
	if ($untracked.Count -gt 0) {
		Write-Warning ("{0} untracked file(s) are NOT sent (git add them first if they belong in the deploy): {1}" -f $untracked.Count, (($untracked | Select-Object -First 5) -join ', '))
	}
	git ls-files | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Set-Content "$tmp\files.txt" -Encoding ascii
	Check 'git ls-files'
	tar -czf "$tmp\botler.tgz" -T "$tmp\files.txt"
	Check 'tar'
	Write-Host ("Packed {0:N1} MB" -f ((Get-Item "$tmp\botler.tgz").Length / 1MB))

	# -- BUILD THE IMAGE HERE -- #
	# The VPS (3.7 GB shared with AFB) must never compile the app: a build there exhausted its memory and took the whole host down.
	# The image is built on this PC, sent as a tar and loaded on the server, which only runs it.
	docker build --build-arg "BUILD_ID=$build" -t botler-server:local server
	Check 'docker build'
	docker save -o "$tmp\image.tar" botler-server:local
	Check 'docker save'
	Write-Host ("Image {0:N0} MB, build $build" -f ((Get-Item "$tmp\image.tar").Length / 1MB))

	# -- REMOTE SCRIPT (no BOM, LF only) -- #
	# BUILD arrives as an environment variable (digits only)
	$remote = @'
set -euo pipefail
: "${BUILD:?BUILD is not set}"
rm -rf ~/botler-incoming && mkdir ~/botler-incoming && tar -xzf /tmp/botler.tgz -C ~/botler-incoming && rm /tmp/botler.tgz
mkdir -p ~/botler/deploy/vps
cd ~/botler/deploy/vps
# An update must start from a backup when the database already holds data. A failed backup stops the deploy
if [ -f docker-compose.yml ] && [ -n "$(docker compose ps -q botler-db 2>/dev/null)" ]; then
  echo "Backing up before the update"
  bash ~/botler/deploy/vps/backup.sh
fi
rsync -a --delete --exclude 'deploy/vps/.env' --exclude 'backups' ~/botler-incoming/ ~/botler/
rm -rf ~/botler-incoming
cd ~/botler/deploy/vps
# The image was built on the deploy PC and arrives as a tar. Nothing is built on this host
docker load -i /tmp/botler-image.tar
rm -f /tmp/botler-image.tar
loaded="$(docker image inspect -f '{{index .Config.Labels "botler.build"}}' botler-server:local)"
if [ "$loaded" != "$BUILD" ]; then echo "DEPLOY FAILED: the loaded image has build '$loaded', expected '$BUILD'"; exit 1; fi
docker compose up -d --no-build
# The container that runs now must be the image just loaded (same image id, same build label). An old container that survived fails here
cid="$(docker compose ps -q botler-app)"
[ -n "$cid" ] || { echo "DEPLOY FAILED: botler-app is not running"; exit 1; }
want_id="$(docker image inspect -f '{{.Id}}' botler-server:local)"
have_id="$(docker inspect -f '{{.Image}}' "$cid")"
have_build="$(docker inspect -f '{{index .Config.Labels "botler.build"}}' "$cid")"
if [ "$have_id" != "$want_id" ] || [ "$have_build" != "$BUILD" ]; then
  echo "DEPLOY FAILED: botler-app runs build '$have_build' (image $have_id), expected '$BUILD' (image $want_id). The old container is still up."
  exit 1
fi
echo "botler-app runs build $have_build"
# The egress wall lives inside the app container, so it is set again after every start (see egress.sh). A failure stops the deploy
bash ~/botler/deploy/vps/egress.sh
docker image prune -f >/dev/null
docker compose ps --format '{{.Service}} {{.Status}}'
# The newest backup must be recent (backup.sh writes backups/LAST_OK only after a verified dump)
ok=~/botler/backups/LAST_OK
if [ -f "$ok" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$ok") ))
  if [ "$age" -gt 129600 ]; then echo "WARNING: the last good backup is $(( age / 3600 )) hours old (nightly cron may have stopped)"; fi
else
  echo "WARNING: backups/LAST_OK is missing: no verified backup has been recorded yet"
fi
'@
	[IO.File]::WriteAllText("$tmp\remote.sh", ($remote -replace "`r", ''), (New-Object Text.UTF8Encoding $false))

	# -- SEND AND RUN -- #
	scp "$tmp\botler.tgz" "${Server}:/tmp/botler.tgz"
	Check 'scp of the code'
	scp -C "$tmp\image.tar" "${Server}:/tmp/botler-image.tar"
	Check 'scp of the image'
	scp "$tmp\remote.sh" "${Server}:/tmp/botler-remote.sh"
	Check 'scp of the script'
	ssh $Server "BUILD=$build bash /tmp/botler-remote.sh; code=`$?; rm -f /tmp/botler-remote.sh; exit `$code"
	Check 'the remote deploy'
}
finally {
	# The temp folder holds the packed code and the image: always removed, failure or not
	if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# -- WAIT FOR HEALTH -- #
# The remote script already proved the running container is this build. If /healthz also reports a build (needs the server to expose BOTLER_BUILD), it must match
for ($i = 0; $i -lt 40; $i++) {
	$r = curl.exe -s -m 5 "$Url/healthz"
	if ($r -match '"service":"botler"') {
		if ($r -match '"build":"([^"]*)"') {
			if ($Matches[1] -ne $build) { throw "DEPLOY FAILED: $Url/healthz reports build $($Matches[1]) but $build was deployed. An old instance still answers." }
		}
		else { Write-Warning '/healthz does not report a build id yet: only the container label was compared.' }
		Write-Host "Live: $Url (build $build)"
		exit 0
	}
	Start-Sleep 3
}
throw "Botler did not answer $Url/healthz in time. On the server: cd ~/botler/deploy/vps; docker compose logs botler-app"
