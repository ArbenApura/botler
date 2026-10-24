# BUILD, CHECK AND (WITH -Publish) PUBLISH A NEW ANDROID BUILD FOR THE IN-APP UPDATE: powershell deploy/vps/release-app.ps1 [-Publish]
# Without -Publish nothing leaves this PC: it builds the release APK, checks it and writes app/build/release/latest.json.
# With -Publish it also uploads to the VPS releases folder. That reaches the live server: the user confirms immediately before every run (VPS.md).
# The server code is not deployed or restarted by this script, and AFB's containers, Caddyfile and volumes are never touched.
# The signing key is read only by Gradle (app/android/key.properties). This script never opens it, never prints the password.
param(
	[switch]$Publish,
	[string]$Server = 'ubuntu@15.235.241.169',
	[string]$RemoteDir = '/srv/botler-releases',
	# Phones running a build older than this must update before they can be used. Keep it at 1 unless an old build must be shut out
	[int]$MinSupported = 1,
	[string]$Notes = '',
	[string]$FlutterBin = "$env:USERPROFILE\dev\flutter\bin\flutter.bat",
	# Only validate app/assets/changelog.json and print the notes it gives, then stop: no build, no ssh, no upload
	[switch]$CheckChangelogOnly,
	# A changelog file to check instead of app/assets/changelog.json (to try the gate on a temporary copy)
	[string]$ChangelogPath = ''
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $root

# A native command's exit code is not an exception, so every step checks it
function Check([string]$what) {
	if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE). Nothing was published." }
}

# -- VERSION -- #
$pub = Get-Content "$root\app\pubspec.yaml" -Raw
if ($pub -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'app/pubspec.yaml needs a version like 1.0.1+2' }
$versionName = $Matches[1]
$versionCode = [int]$Matches[2]
if ($MinSupported -gt $versionCode -or $MinSupported -lt 1) { throw "MinSupported must be between 1 and $versionCode" }
Write-Host "Version $versionName+$versionCode"

# -- THE CHANGELOG (BEFORE ANY SSH, .env READ OR BUILD) -- #
# Every update tells the person what is new, so a version without an entry in English and Filipino is not built. UTF-8 without a BOM:
# Windows PowerShell 5.1 would otherwise read the Filipino text as ANSI
if ($ChangelogPath -and -not $CheckChangelogOnly) { throw '-ChangelogPath is only for -CheckChangelogOnly: a build always bundles app/assets/changelog.json.' }
if (-not $ChangelogPath) { $ChangelogPath ="$root\app\assets\changelog.json" }
if (-not (Test-Path $ChangelogPath)) { throw "Changelog not found at $ChangelogPath" }
$changelog = [IO.File]::ReadAllText($ChangelogPath, (New-Object Text.UTF8Encoding $false)) | ConvertFrom-Json
$mine = @($changelog | Where-Object { [int]$_.versionCode -eq $versionCode })
if ($mine.Count -ne 1) { throw "app/assets/changelog.json needs exactly one entry for versionCode $versionCode (found $($mine.Count)). Nothing was built." }
if ("$($mine[0].versionName)" -ne $versionName) { throw "The changelog entry says version $($mine[0].versionName) but app/pubspec.yaml says $versionName. Nothing was built." }
$linesEn = @($mine[0].en | Where-Object { "$_".Trim() })
$linesFil = @($mine[0].fil | Where-Object { "$_".Trim() })
if ($linesEn.Count -eq 0) { throw "The changelog entry for $versionCode has no English lines. Nothing was built." }
if ($linesFil.Count -eq 0) { throw "The changelog entry for $versionCode has no Filipino lines. Nothing was built." }
# The notes the phone shows before the update default to the English lines; the server accepts at most 2000 characters
if (-not $Notes) { $Notes = ($linesEn | ForEach-Object { "- $("$_".Trim())" }) -join "`n" }
if ($Notes.Length -gt 2000) { throw "The release notes are $($Notes.Length) characters; the server accepts 2000. Shorten the changelog entry. Nothing was built." }
Write-Host "Changelog ok: $($linesEn.Count) English and $($linesFil.Count) Filipino lines."
if ($CheckChangelogOnly) { Write-Host "Notes:`n$Notes"; exit 0 }

# -- THE PINNED CERTIFICATE -- #
$android = Get-Content "$root\docs\ANDROID.md" -Raw
if ($android -notmatch 'SHA-256 `([0-9A-F:]{95})`') { throw 'docs/ANDROID.md does not hold the pinned SHA-256 certificate fingerprint' }
$pinned = ($Matches[1] -replace ':', '').ToLower()

# -- WHAT IS LIVE (only when publishing) -- #
if ($Publish) {
	$live = & ssh $Server "cat $RemoteDir/latest.json 2>/dev/null || true"
	Check 'ssh (reading the live manifest)'
	if ($live) {
		$liveCode = [int](($live | ConvertFrom-Json).versionCode)
		if ($versionCode -le $liveCode) { throw "versionCode $versionCode is not higher than the live $liveCode. Raise the build number in app/pubspec.yaml." }
	}
}

# -- BUILD -- #
# The web client id is public (it ships inside the app) but is still read from the one exact line and never printed
$idLine = Get-Content "$root\server\.env" | Where-Object { $_ -match '^GOOGLE_CLIENT_ID=' } | Select-Object -First 1
if (-not $idLine) { throw 'server/.env has no GOOGLE_CLIENT_ID= line' }
$clientId = ($idLine -replace '^GOOGLE_CLIENT_ID=', '').Trim().Trim('"')
if (-not $clientId) { throw 'GOOGLE_CLIENT_ID is empty' }
if (-not (Test-Path $FlutterBin)) { throw "Flutter not found at $FlutterBin (pass -FlutterBin)" }
Push-Location "$root\app"
& $FlutterBin build apk --release "--dart-define=GOOGLE_WEB_CLIENT_ID=$clientId"
Check 'flutter build apk'
Pop-Location

$out = "$root\app\build\release"
New-Item -ItemType Directory -Force $out | Out-Null
$name = "botler-$versionName+$versionCode.apk"
$apk = "$out\$name"
Copy-Item "$root\app\build\app\outputs\flutter-apk\app-release.apk" $apk -Force

# -- CHECK THE APK ITSELF -- #
$tools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory | Sort-Object Name -Descending | Where-Object { Test-Path "$($_.FullName)\aapt2.exe" } | Select-Object -First 1
if (-not $tools) { throw 'Android build-tools (aapt2, apksigner) not found' }
$badgingAll = & "$($tools.FullName)\aapt2.exe" dump badging $apk
Check 'aapt2 dump badging'
$badging = $badgingAll | Select-Object -First 1
if ($badging -notmatch "package: name='com\.arbenger\.botler' versionCode='$versionCode' versionName='$([regex]::Escape($versionName))'") { throw 'The APK package, versionCode or versionName does not match app/pubspec.yaml' }

$certs = & "$($tools.FullName)\apksigner.bat" verify --print-certs $apk
Check 'apksigner verify'
$digest = ($certs | Where-Object { $_ -match 'Signer.*certificate SHA-256 digest: ([0-9a-f]{64})' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
if ($digest -ne $pinned) { throw 'The APK is signed with a different certificate than the pinned one in docs/ANDROID.md. An update could never install over the app.' }

# The changelog must be inside the APK, or the phone has nothing to show after the update
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apk)
try { $hasChangelog = $null -ne ($zip.Entries | Where-Object { $_.FullName -eq 'assets/flutter_assets/assets/changelog.json' } | Select-Object -First 1) } finally { $zip.Dispose() }
if (-not $hasChangelog) { throw 'The APK does not hold assets/changelog.json. Check the assets: entry in app/pubspec.yaml.' }

$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $apk).Length
$manifest = [ordered]@{
	versionName = $versionName; versionCode = $versionCode; sha256 = $sha; size = $size
	minSupportedCode = $MinSupported; notes = $Notes; publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
[IO.File]::WriteAllText("$out\latest.json", ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
Write-Host ("Built {0} ({1:N1} MB), signature matches the pinned certificate." -f $name, ($size / 1MB))

if (-not $Publish) { Write-Host "Not published (no -Publish). Files are in $out"; exit 0 }

# -- UPLOAD: APK FIRST (AS .part), VERIFIED, THEN THE MANIFEST LAST -- #
ssh $Server "[ -d $RemoteDir ] || (sudo mkdir -p $RemoteDir && sudo chown `$(id -u):`$(id -g) $RemoteDir); chmod 755 $RemoteDir"
Check 'ssh (creating the releases folder)'
scp $apk "${Server}:$RemoteDir/$name.part"
Check 'scp of the APK'
scp "$out\latest.json" "${Server}:$RemoteDir/latest.json.part"
Check 'scp of the manifest'
# The names are fixed by the checks above (digits and dots only), so they are safe to put in the remote command
$remote = @"
set -euo pipefail
cd $RemoteDir
# A failed check leaves nothing half published
trap "rm -f '$name.part' latest.json.part" ERR
test "`$(stat -c %s '$name.part')" = '$size'
echo '$sha  $name.part' | sha256sum -c - >/dev/null
chmod 644 '$name.part' latest.json.part
mv '$name.part' '$name'
mv latest.json.part latest.json
# Keep the newest three builds; the one in the manifest is always among them
ls -1 botler-*.apk | sort -t+ -k2,2nr | tail -n +4 | xargs -r rm -f
ls -1 botler-*.apk
"@
# Sent as a file, like deploy.ps1 does: a multi-line quoted argument is mangled by Windows PowerShell
$tmp = Join-Path $env:TEMP 'botler-release-remote.sh'
[IO.File]::WriteAllText($tmp, ($remote -replace "`r", ''), (New-Object Text.UTF8Encoding $false))
scp $tmp "${Server}:/tmp/botler-release-remote.sh"
Check 'scp of the publish script'
Remove-Item $tmp -Force
ssh $Server 'bash /tmp/botler-release-remote.sh; code=$?; rm -f /tmp/botler-release-remote.sh; exit $code'
Check 'the remote publish'
Write-Host "Published $name. Phones will see it on their next update check."
