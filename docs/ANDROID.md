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
# Against a server on this PC (the emulator reaches the PC at 10.0.2.2). Plain http is refused by the release manifest, so use a debug build
flutter run --dart-define=BOTLER_API=http://10.0.2.2:5280
```

A release build also needs the web client id from `server/.env` (`GOOGLE_CLIENT_ID`) as `--dart-define=GOOGLE_WEB_CLIENT_ID=...` (read it without printing it). R8 shrinking is off on purpose: it removed code `shared_preferences` needs and crashed the release app, so always run a release build on a device or emulator before shipping. Strings live in `app/lib/l10n/parts/*.en.arb` and `*.fil.arb`; after editing run `dart run tool/l10n.dart` then `flutter gen-l10n`.

## What the owner must create (nothing here can be done by the app)

1. **Google OAuth Android client** (Google Cloud console, the project that holds Botler's web client): package `com.arbenger.botler` and the SHA-1 of the signing key. Debug SHA-1: `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android` . Release SHA-1: of the keystore below. The app signs in with the **web** client id (`--dart-define=GOOGLE_WEB_CLIENT_ID=...`); the Android client only has to exist for the same package and SHA-1.
2. **Release keystore** (kept off the repo and backed up in the password manager): `keytool -genkey -v -keystore botler-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias botler`, then `app/android/key.properties` (gitignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Without it a release build is signed with the debug key: fine for the owner's own phone.
3. **Firebase project** (only for push): add the Android app, download `google-services.json` into `app/android/app/`, and give the server `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT` (base64 of the service account JSON). Push is optional: the phone syncs when opened and every ~15 minutes without it. The Firebase packages are added to `pubspec.yaml` at that point.

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
