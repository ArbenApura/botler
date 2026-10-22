# COPY THE ENCRYPTED BACKUPS FROM THE VPS TO THIS PC (the off-host copy): powershell deploy/vps/pull-backups.ps1
# Only encrypted files travel. They are readable only with the private age key, which is kept off the server and off the repo.
param(
	[string]$Server = 'ubuntu@15.235.241.169',
	[string]$Dest = "$HOME\Desktop\botler-backups"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Dest | Out-Null
scp "${Server}:botler/backups/botler-*.sql.age" $Dest
Get-ChildItem $Dest -Filter 'botler-*.sql.age' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name, Length, LastWriteTime
Write-Host "Copied to $Dest"
