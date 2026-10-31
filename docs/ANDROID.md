# Android runbook: build, install, reminders, Doze

Everything here is for the Flutter app in `app/`. Flutter lives in `C:\Users\Admin\dev\flutter` (add its `bin` to PATH). The Android SDK is Android Studio's.

## Build and run

```powershell
$env:Path = "C:\Users\Admin\dev\flutter\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools;" + $env:Path
cd C:\Users\Admin\Desktop\botler\app
flutter pub get
flutter analyze ; flutter test
# Against the live server (needs the Google web client id, see below)
flutter run --release --dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>.apps.googleusercontent.com
# Against a server on this PC (yarn dev on port 5280). A DEBUG build may use plain http to exactly three hosts: 10.0.2.2 (the PC as the
# emulator sees it), localhost and 127.0.0.1 (for a real phone: adb reverse tcp:5280 tcp:5280, then BOTLER_API=http://localhost:5280)
flutter run --dart-define=BOTLER_API=http://10.0.2.2:5280
```

**Cleartext rules.** The main manifest (what every release build ships) has `usesCleartextTraffic="false"` and no network security config, so a release build refuses plain http everywhere. The debug source set (`app/android/app/src/debug/`) adds `res/xml/network_security_config.xml` through its own manifest overlay; it allows cleartext only for `10.0.2.2`, `localhost` and `127.0.0.1` and keeps everything else https only. Because it lives in the debug source set, it is not in a release APK. `powershell deploy/check-android-manifest.ps1` reads both files and fails if the main manifest ever allows cleartext or names a config, or if the debug config allows another host. The `botler://` link filter on `MainActivity` is limited to the host `quickadd` (the only link the app handles, from the home screen widget).

**Permissions** (all in the main manifest, unchanged): `INTERNET`; `POST_NOTIFICATIONS`, `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `WAKE_LOCK` for reminders; `USE_BIOMETRIC` for the app lock; `RECORD_AUDIO` for talking to Botler; `REQUEST_INSTALL_PACKAGES` for the in-app update.

A release build also needs the web client id from `server/.env` (`GOOGLE_CLIENT_ID`) as `--dart-define=GOOGLE_WEB_CLIENT_ID=...` (read it without printing it). R8 shrinking is off on purpose: it removed code `shared_preferences` needs and crashed the release app, so always run a release build on a device or emulator before shipping. Strings live in `app/lib/l10n/parts/*.en.arb` and `*.fil.arb`; after editing run `dart run tool/l10n.dart` then `flutter gen-l10n`.

## What the owner must create (nothing here can be done by the app)

1. **Google OAuth Android client** (Google Cloud console, the project that holds Botler's web client): package `com.arbenger.botler` and the SHA-1 of the signing key. Debug SHA-1: `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android` . Release SHA-1: of the keystore below. The app signs in with the **web** client id (`--dart-define=GOOGLE_WEB_CLIENT_ID=...`); the Android client only has to exist for the same package and SHA-1.
2. **Release keystore** (kept off the repo and backed up in the password manager): `keytool -genkey -v -keystore botler-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias botler`, then `app/android/key.properties` (gitignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Without it a release build now fails (no debug-key fallback): Android only installs an update signed with the same key as the installed app, so losing this keystore means one uninstall and reinstall. Created 2026-10-22 at `%USERPROFILE%\botler-keys\botler-release.jks` (alias `botler`, PKCS12, valid to 2054, store and key password are the same random value kept only in `key.properties`). **Back up both the `.jks` and `key.properties` in the password manager now.** Certificate fingerprints (public): SHA-1 `F8:9D:78:A9:D5:48:D6:A6:7C:DF:C6:F5:CA:1A:E9:8A:3A:0D:2D:A1`, SHA-256 `77:B2:F6:1A:C0:C7:85:8B:C7:8F:49:F6:E7:CC:98:66:12:B6:46:AA:A2:E7:D6:EB:13:23:88:71:E4:C3:7B:F4`. The release script pins the SHA-256.
3. **Firebase project** (done 2026-10-23, project `botler-46418`): the Android app `com.arbenger.botler` is registered, `google-services.json` sits in `app/android/app/` (gitignored; a release build stops without it) and the server has `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT` (base64 of the service account JSON) in `deploy/vps/.env`; the values are also in `CREDENTIALS.md`. Both must be set or neither (the server refuses half). The app (`app/lib/core/push.dart`) gets the FCM token after sign in and registers it with `POST /api/v1/devices`, registers again when Firebase rotates it, and removes it on sign out before the session is cleared. A silent `type=sync` push makes the phone send its outbox and refresh its alarms (the same round as the 15 minute background sync); a `type=notice` push is a plain Android notification with a short title. Push is only a nudge and is optional: the phone syncs when opened and every ~15 minutes without it. To prove the key still works without a phone, run a Firebase dry run: token exchange 200 and a send with `validate_only` answering INVALID_ARGUMENT for a fake token.

## Updating the app (in-app updates)

The app updates itself from the VPS; no store and no cable after the first install.

1. **Publish a new build** from the repo root: add an entry for the new build to `app/assets/changelog.json` (its `versionCode`, `versionName`, and plain user-facing `en` and `fil` lines; the release script refuses a version without one, and `release-app.ps1 -CheckChangelogOnly` checks just that, with no build), then raise `version:` in `app/pubspec.yaml` (for example `1.0.1+2`; the number after `+` must be higher than the live one), then `powershell deploy/vps/release-app.ps1` (build and checks only, nothing leaves the PC), and when it passes `powershell deploy/vps/release-app.ps1 -Publish -Notes "what changed"`. `-Publish` reaches the VPS (`ubuntu@15.235.241.169`, folder `/srv/botler-releases`): confirm with the owner first (VPS.md). `-MinSupported N` makes phones below build N show the blocking update screen; leave it at 1 normally. The script refuses an APK whose package, version or signing certificate does not match, and writes `latest.json` last.
2. **On the phone**: after an update installs, the first time the app opens on the chat screen it shows a "What's new" sheet with the notes of every build since the last one seen (once; Settings reopens the notes of the installed build). A fresh install shows nothing. The app asks on every start, and after 12 hours when it comes to the front. Settings shows the version, the result of the last check and how many writes still wait to sync; tapping the row checks now. A banner on the home screen offers an optional update (dismissing hides that build only). Tap "Update now": the app downloads (about 25 MB, only on your tap: the build for your phone's processor only), checks it, then Android's installer opens and you tap **Install**. The first time, Android sends you to "Install unknown apps" for Botler: allow it and come back. Expect extra screens on the realme (Play Protect scan, a confirm dialog).
   **Split builds.** A release is built once per processor type (`arm64-v8a`, `armeabi-v7a`, `x86_64`, with `--split-per-abi`) plus one universal APK. All of them carry the same `versionCode` (`force-version-code-ignoring-abi` in `app/android/gradle.properties`), and native libraries are stored compressed in the APK (`useLegacyPackaging`). The phone sends its processor types with the update check (`abis`), the server answers with that build's size and hash, and only that file is downloaded. The universal APK stays on the server for phones on 1.1.6 or older, which send no processor type and cannot pick. `latest.json` holds `apks` (size and hash per processor type) beside the universal `size` and `sha256`. The script keeps the newest three builds with all their files.
3. **If something fails** the screen says why (no connection, no space, damaged download, not an update for this app, permission missing, installer cancelled) and offers Try again. A required update also offers "Use the app for now", so a broken update never locks you out. Updates only install over a build signed with the same key: never build a release without `key.properties`.
4. **First time (the key switch)**: the build installed before 2026-10-22 was debug-signed and cannot be updated in place. One time only: add the release SHA-1 above to the Google OAuth Android client, make sure the app shows nothing waiting to sync (Settings), uninstall the old app, install the release-signed build by cable (`adb install app/build/release/botler-1.0.0+1.apk`), sign in again. Local-only choices (app lock, theme, reminder lead) are set again; everything else comes back from the server.

## Scripts on the phone

Botler runs the assistant's small JavaScript programs inside the app with QuickJS (`flutter_qjs_next`, built into the APK as a native library for each ABI). Android 10 and later forbids executing files that were downloaded into the app's storage, so the engine is part of the APK and scripts are only text it interprets; they have no network and reach only a scratch folder inside the app's private storage (`script_data/<person>/scratch/<chat>`). Signing out removes the folder; a scratch folder not used for 30 days is swept. The Android permissions of the app do not change. If an update ever shows `libflutter_qjs_next.so` missing at runtime, check that the release build kept the plugin's native library (no R8 rule is needed for FFI).

## Exact alarms decision

The manifest asks for `USE_EXACT_ALARM`: it is granted automatically to apps whose core job is alarms or calendar reminders, and Botler's reminders are that. It needs no settings screen for the person. The alternative, `SCHEDULE_EXACT_ALARM`, needs the person to grant "Alarms & reminders" in system settings. If Play Store review ever objects, switch the permission in `AndroidManifest.xml` and call `requestExactAlarmsPermission()` in `initReminders()`. A personal install is not affected.

## Making reminders survive the phone's power saving (OEM phones)

Some phones (Xiaomi, Oppo, Vivo, Samsung, Huawei) stop apps in the background. If a reminder did not ring: Settings, Apps, Botler, Battery, choose "Unrestricted" (or "No restrictions"), and on Xiaomi/Oppo also allow "Autostart". Botler also re-arms every alarm after a reboot and after an update (the plugin's boot receiver) and reconciles with the server every ~15 minutes and whenever the app opens.

## Doze test runbook (adb)

A reminder must ring with the phone asleep. With the emulator or a phone connected (`adb devices`):

1. Open Botler, sign in, make a reminder in Agenda for 5 minutes ahead. Check `adb shell dumpsys alarm | findstr botler` shows it.
2. Put the phone to sleep and force Doze: `adb shell dumpsys battery unplug` then `adb shell dumpsys deviceidle force-idle`. Confirm: `adb shell dumpsys deviceidle get deep` prints `IDLE`.
3. Wait for the time. The notification should arrive (exact alarms are allowed while idle). Leave Doze: `adb shell dumpsys deviceidle unforce` and `adb shell dumpsys battery reset`.
4. Reboot test: `adb reboot`; after boot, without opening Botler, `adb shell dumpsys alarm | findstr botler` still lists the next reminder (M4).
5. App closed test: swipe Botler away from recents (or `adb shell am force-stop com.arbenger.botler`) , then wait: reminders scheduled earlier still ring. Note: force-stop cancels alarms on Android by design; a swipe-away does not. Use the swipe for this check, and use force-stop only to see the next sync re-arm them.

## Quick-add widget

Long-press the home screen, Widgets, Botler: "Add an expense". One tap opens the expense box (`botler://quickadd`). With no connection the entry is kept in the outbox and sent once later.
