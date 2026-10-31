# THE ONE PLACE THAT NAMES THE SERVER LOGIN. Dot-sourced by deploy.ps1, pull-backups.ps1 and release-app.ps1: `. "$PSScriptRoot\host.ps1"`.
# Change the host here and nowhere else. A script can still be given -Server on the command line to override it.
$BotlerServer = 'ubuntu@15.235.241.169'
