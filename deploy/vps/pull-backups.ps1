# COPY THE ENCRYPTED BACKUPS FROM THE VPS TO THIS PC (the off-host copy): powershell deploy/vps/pull-backups.ps1
# Only encrypted files travel. They are readable only with the private age key, which is kept off the server and off the repo.
# Warns when the server's backups/LAST_OK marker (written by backup.sh only after a verified dump) is older than 36 hours or missing.
param(
	[string]$Server = '',
	[string]$Dest = "$HOME\Desktop\botler-backups"
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\host.ps1"
if (-not $Server) { $Server = $BotlerServer }
New-Item -ItemType Directory -Force $Dest | Out-Null

# -- LAST GOOD BACKUP -- #
# LAST_OK holds a UTC timestamp (yyyy-MM-ddTHH:mm:ssZ) on its first line
$ok = (& ssh $Server 'cat ~/botler/backups/LAST_OK 2>/dev/null || true') | Select-Object -First 1
if ($LASTEXITCODE -ne 0) { throw 'ssh (reading backups/LAST_OK) failed' }
if (-not $ok) {
	Write-Warning 'The server has no backups/LAST_OK: no verified backup is recorded. Check the nightly cron and run backup.sh.'
}
else {
	$when = [DateTime]::MinValue
	$styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
	if ([DateTime]::TryParse("$ok".Trim(), [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$when)) {
		$hours = ([DateTime]::UtcNow - $when).TotalHours
		if ($hours -gt 36) { Write-Warning ("The last good backup is {0:N0} hours old ({1}). The nightly backup may have stopped." -f $hours, $ok) }
		else { Write-Host ("Last good backup: {0} ({1:N1} h ago)" -f $ok, $hours) }
	}
	else { Write-Warning "backups/LAST_OK is not a timestamp: $ok" }
}

# -- COPY -- #
scp "${Server}:botler/backups/botler-*.sql.age" $Dest
if ($LASTEXITCODE -ne 0) { throw "scp of the backups failed (exit $LASTEXITCODE)" }
# The weekly set (backup.sh keeps the newest 8 Sunday dumps); it may not exist yet, which is only a warning
New-Item -ItemType Directory -Force "$Dest\weekly" | Out-Null
scp "${Server}:botler/backups/weekly/botler-*.sql.age" "$Dest\weekly"
if ($LASTEXITCODE -ne 0) { Write-Warning 'No weekly backups copied (none exist yet, or scp failed).' }
Get-ChildItem $Dest -Filter 'botler-*.sql.age' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name, Length, LastWriteTime
Write-Host "Copied to $Dest"
