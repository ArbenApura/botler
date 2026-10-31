# CHECKS THE ANDROID CLEARTEXT RULES (reads two files, runs nothing else): powershell deploy/check-android-manifest.ps1
# 1. The MAIN manifest (what a release build ships) has usesCleartextTraffic="false" and names no network security config.
# 2. The debug source set allows cleartext only for 10.0.2.2, localhost and 127.0.0.1.
# 3. The botler:// link filter names a host.
# Exit 0 when all hold, 1 with the failed rule printed otherwise.
$ErrorActionPreference = 'Stop'
$src = Resolve-Path "$PSScriptRoot\..\app\android\app\src"
$main = Get-Content "$src\main\AndroidManifest.xml" -Raw
$nsc = Get-Content "$src\debug\res\xml\network_security_config.xml" -Raw
$failed = @()

# Comments are dropped first, so the explanatory text cannot fool the match
$mainCode = [regex]::Replace($main, '(?s)<!--.*?-->', '')
if ($mainCode -notmatch 'android:usesCleartextTraffic="false"') { $failed += 'main manifest: usesCleartextTraffic="false" is missing' }
if ($mainCode -match 'usesCleartextTraffic="true"') { $failed += 'main manifest: usesCleartextTraffic="true" must never be in the main manifest' }
if ($mainCode -match 'networkSecurityConfig') { $failed += 'main manifest: networkSecurityConfig belongs only in the debug source set' }
if ($mainCode -match '<data android:scheme="botler"\s*/>') { $failed += 'main manifest: the botler:// filter has no android:host' }

$nscCode = [regex]::Replace($nsc, '(?s)<!--.*?-->', '')
$domains = @([regex]::Matches($nscCode, '<domain[^>]*>([^<]+)</domain>') | ForEach-Object { $_.Groups[1].Value.Trim() })
$allowed = @('10.0.2.2', 'localhost', '127.0.0.1')
foreach ($d in $domains) { if ($allowed -notcontains $d) { $failed += "debug network security config: unexpected cleartext host $d" } }
foreach ($d in $allowed) { if ($domains -notcontains $d) { $failed += "debug network security config: $d is missing" } }
if ($nscCode -match '<base-config[^>]*cleartextTrafficPermitted="true"') { $failed += 'debug network security config: base-config must not permit cleartext' }

if ($failed.Count -gt 0) { $failed | ForEach-Object { Write-Host "FAIL  $_" }; exit 1 }
Write-Host 'ok    main manifest refuses cleartext; debug config allows only 10.0.2.2, localhost, 127.0.0.1'
exit 0
