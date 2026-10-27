# DEPLOY THE WORKING TREE TO THE VPS: yarn deploy:vps (from server/) or powershell deploy/vps/deploy.ps1
# Builds the image on this PC (never on the VPS), sends it with the tracked and untracked (not ignored) files, keeps the server's .env, takes an encrypted backup first, rebuilds, migrates and waits for /healthz.
# This reaches the live server: the user confirms immediately before every run (VPS.md). Botler's compose project only; AFB is never touched.
param(
	[string]$Server = 'ubuntu@15.235.241.169',
	[string]$Url = 'https://botler.arbenger.com'
)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..\..")
$tmp = Join-Path $env:TEMP 'botler-deploy'
New-Item -ItemType Directory -Force $tmp | Out-Null

# A native command's exit code is not an exception, so every step checks it
function Check([string]$what) {
	if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE). Nothing was reported as live." }
}

# -- PACK -- #
git ls-files -co --exclude-standard | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Set-Content "$tmp\files.txt" -Encoding ascii
Check 'git ls-files'
tar -czf "$tmp\botler.tgz" -T "$tmp\files.txt"
Check 'tar'
Write-Host ("Packed {0:N1} MB" -f ((Get-Item "$tmp\botler.tgz").Length / 1MB))

# -- BUILD THE IMAGE HERE -- #
# The VPS (3.7 GB shared with AFB) must never compile the app: a build there exhausted its memory and took the whole host down.
# The image is built on this PC, sent as a tar and loaded on the server, which only runs it.
docker build -t botler-server:local server
Check 'docker build'
docker save -o "$tmp\image.tar" botler-server:local
Check 'docker save'
Write-Host ("Image {0:N0} MB" -f ((Get-Item "$tmp\image.tar").Length / 1MB))

# -- REMOTE SCRIPT (no BOM, LF only) -- #
# The build id is written next to the code so /healthz can be compared with it after the deploy
$build = (Get-Date -Format 'yyyyMMddHHmmss')
$remote = @'
set -euo pipefail
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
docker compose up -d --no-build
# The egress wall lives inside the app container, so it is set again after every start (see egress.sh)
bash ~/botler/deploy/vps/egress.sh
docker image prune -f >/dev/null
docker compose ps --format '{{.Service}} {{.Status}}'
'@
[IO.File]::WriteAllText("$tmp\remote.sh", ($remote -replace "`r", ''), (New-Object Text.UTF8Encoding $false))

# -- SEND AND RUN -- #
scp "$tmp\botler.tgz" "${Server}:/tmp/botler.tgz"
Check 'scp of the code'
scp -C "$tmp\image.tar" "${Server}:/tmp/botler-image.tar"
Check 'scp of the image'
scp "$tmp\remote.sh" "${Server}:/tmp/botler-remote.sh"
Check 'scp of the script'
ssh $Server 'bash /tmp/botler-remote.sh; code=$?; rm -f /tmp/botler-remote.sh; exit $code'
Check 'the remote deploy'
Remove-Item $tmp -Recurse -Force

# -- WAIT FOR HEALTH -- #
for ($i = 0; $i -lt 40; $i++) {
	$r = curl.exe -s -m 5 "$Url/healthz"
	if ($r -match '"service":"botler"') { Write-Host "Live: $Url"; exit 0 }
	Start-Sleep 3
}
throw "Botler did not answer $Url/healthz in time. On the server: cd ~/botler/deploy/vps; docker compose logs botler-app"
