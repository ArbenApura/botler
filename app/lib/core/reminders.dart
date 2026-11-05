// REMINDERS ON THE PHONE. THE SERVER WORKS OUT WHAT NEEDS A REMINDER (/api/v1/sync); THE PHONE REPLACES ALL ITS ALARMS WITH THAT LIST, SO THEY STILL RING
// WITH THE APP CLOSED, OFFLINE, AFTER A REBOOT AND IN DOZE (EXACT ALARMS; THE PLUGIN PUTS THEM BACK AFTER A REBOOT). IT ASKS THE SERVER:
// when the app opens or comes back, and every ~15 minutes from a background task. Alarms and timers ring from this app too: a loud channel with
// the system alarm sound that repeats until it is tapped or swiped (a hand-off to the clock app needs a permission and a screen in front).
// The notification says only "Botler" when the person chose to hide details, and the server never puts an amount in a reminder.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

// -- MODULES -- //
import 'clock.dart' show ensureTimeZones;
import '../l10n/l10n.dart';
import '../state/library.dart';
import '../state/providers.dart';
import 'api.dart';
import 'auth.dart';
import 'config.dart';
import 'json.dart';
import 'outbox.dart';

// -- CONSTANTS -- //

// A new channel id: Android keeps the importance a channel was first made with, so an old quiet channel could never be made loud
const String _channelId = 'botler_reminders_v2';
// Alarms and timers: loud, the system alarm sound, always its own channel so a quiet reminder setting never mutes an alarm
const String _alarmChannelId = 'botler_alarms_v1';
const String _cursorKey = 'sync.cursor';
const String _cursorFixKey = 'sync.cursor_fix1';
// Kept only to be cleared: an older build remembered which alarms it had handed to the clock app
const String _handledKey = 'sync.clock_handled';
const String _shownKey = 'sync.shown';
const String _taskName = 'botler-sync';

/// What the settings screen reads: the class of the last failure (never message text) and when the phone last brought its alarms in line.
const String reminderErrorKey = 'reminders.last_error';
const String reminderSyncedKey = 'reminders.last_sync';

/// A reminder this long past its time is still shown once; the server hands over the same window.
const Duration lateGrace = Duration(minutes: 10);

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

// One sync at a time in this isolate: two overlapping runs would cancel each other's alarms
Future<void> _syncTail = Future<void>.value();

// -- FUNCTIONS -- //

Future<void> _initNotifications() async {
  // The one place that loads the zone database is the clock, so a later load can never reset the phone's zone set below
  ensureTimeZones();
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } on Object {
    // No zone from the phone: the person's zone is Manila
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
  }
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

/// Sets up notifications and the background sync. Called once at start.
Future<void> initReminders() async {
  await _initNotifications();
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.requestNotificationsPermission();
  await Workmanager().initialize(callbackDispatcher);
  // The shortest repeat Android allows is 15 minutes
  await Workmanager().registerPeriodicTask(
    _taskName,
    _taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Starts the background task's own Dart isolate: no screen, no providers, just the session, the server and the notifications.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async => backgroundSyncOnce());
}

/// One background round with no screen and no providers: send what waits in the outbox, then bring the alarms in line with the server.
/// Used by the periodic task and by a silent push. True when it is done or not worth repeating; false when the task should be retried.
Future<bool> backgroundSyncOnce() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    const store = SecureSessionStore();
    final session = await store.read();
    if (session == null) return true;
    await _initNotifications();
    final api = ApiClient(
      base: apiBase,
      token: () async => (await store.read())?.token,
    );
    try {
      // The same person's id the app tags its writes with, so this isolate sends only that person's items
      final report = await Outbox(prefs, userId: session.email).flush(api);
      // A session that no longer works cannot sync either; the app shows the notice when it is opened
      if (report.needsSignIn) return true;
      await syncReminders(api, prefs);
    } finally {
      api.close();
    }
    return true;
  } on ApiException catch (e) {
    // No connection or a busy server: the next run tries again
    return e.isRetryable;
  }
}

/// Sends what is waiting in the outbox, then brings the alarms in line with the server. Used when the app is in front.
Future<void> flushAndSync(ProviderContainer container) async {
  final api = container.read(apiProvider);
  final prefs = container.read(prefsProvider);
  try {
    final report = await container.read(outboxProvider).flush(api);
    // The session was refused: the writes are kept, the app says to sign in again, and nothing else is asked of the server
    if (report.needsSignIn) {
      container.read(needsSignInProvider.notifier).set(true);
      return;
    }
    if (report.sent > 0 || report.dropped.isNotEmpty) {
      container.read(outboxCountProvider.notifier).refresh();
      // A pin, rename or move may have gone out (or been refused): the notebooks are read again
      container
        ..invalidate(libraryProvider)
        ..invalidate(pageProvider);
    }
    await syncReminders(api, prefs);
  } on ApiException catch (e) {
    // A refused session on the sync itself says the same; anything else is offline, and what is already scheduled keeps ringing
    if (e.isUnauthenticated) {
      container.read(needsSignInProvider.notifier).set(true);
    }
  }
}

/// Asks the server what the alarms should be and replaces the phone's set with it. Does nothing when the server says nothing changed.
Future<void> syncReminders(ApiClient api, SharedPreferences prefs) async {
  // The background isolate writes the same keys: read what it left
  await prefs.reload();
  final previous = _syncTail;
  final done = Completer<void>();
  _syncTail = done.future;
  await previous;
  try {
    // Once after this fix: forget the cursor, so reminders an older build dropped are handed over again
    if (!(prefs.getBool(_cursorFixKey) ?? false)) {
      await prefs.remove(_cursorKey);
      await prefs.setBool(_cursorFixKey, true);
    }
    // The cursor is the server's opaque text (it may carry a suffix for the edge of its window): kept and sent back exactly as it came
    final answer = await api.sync(cursor: prefs.getString(_cursorKey));
    if (!boolOf(answer['changed'], true) ||
        answer['reminders'] is! List<Object?>) {
      // Nothing to set, and the server was reached: the phone is in line
      await prefs.setString(
        reminderSyncedKey,
        DateTime.now().toIso8601String(),
      );
      return;
    }
    final ok = await applyReminders(
      asJsonList(answer['reminders']),
      readSettings(prefs),
      prefs,
    );
    // The time and the cursor are kept only after everything was scheduled: a failed round is asked for again, and is not shown as in line
    if (ok) {
      await prefs.setString(_cursorKey, str(answer['cursor']));
      await prefs.setString(
        reminderSyncedKey,
        DateTime.now().toIso8601String(),
      );
    }
  } finally {
    done.complete();
  }
}

/// One notification the phone should have: ring at [fire], or show at once when [showNow] (its time came while the phone was not looking).
class PlannedNotice {
  const PlannedNotice({
    required this.key,
    required this.id,
    required this.title,
    required this.at,
    required this.fire,
    required this.showNow,
    this.alarm = false,
  });

  final String key;
  final int id;
  final String title;
  final DateTime at;
  final DateTime fire;
  final bool showNow;

  /// An alarm or a timer: rings loudly and repeats until the person answers it.
  final bool alarm;
}

/// What stops reminders from showing right now, read live from the phone plus the last failure kept by the sync (its class only).
class ReminderHealth {
  const ReminderHealth({
    required this.notificationsOn,
    required this.exactOn,
    this.lastError,
  });

  final bool notificationsOn;
  final bool exactOn;
  final String? lastError;

  bool get ok => notificationsOn && exactOn && lastError == null;
}

Future<ReminderHealth> readReminderHealth(SharedPreferences prefs) async {
  // The failure may have been written by the background sync, in another isolate
  await prefs.reload();
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  bool on = true;
  bool exact = true;
  try {
    on = await android?.areNotificationsEnabled() ?? true;
    exact = await android?.canScheduleExactNotifications() ?? true;
  } on Object {
    // Cannot tell: say nothing rather than a wrong thing
  }
  return ReminderHealth(
    notificationsOn: on,
    exactOn: exact,
    lastError: prefs.getString(reminderErrorKey),
  );
}

/// Opens this app's notification settings in the system.
Future<void> openReminderSettings() async {
  await const AndroidIntent(
    action: 'android.settings.APP_NOTIFICATION_SETTINGS',
    arguments: <String, Object>{
      'android.provider.extra.APP_PACKAGE': 'com.arbenger.botler',
    },
  ).launch();
}

/// True when a chat reply ran a verb that can change what the phone should ring for. [toolsRun] is the list of verb names on the done event.
bool changesReminders(Object? toolsRun) =>
    toolsRun is List<Object?> &&
    toolsRun.any(
      (n) =>
          n is String &&
          (n.startsWith('reminder_') ||
              n.startsWith('alarm_') ||
              n.startsWith('timer_') ||
              n.startsWith('task_') ||
              n.startsWith('event_') ||
              n.startsWith('routine_') ||
              n.startsWith('bill_') ||
              n.startsWith('income_')),
    );

String shownKeyOf(String key, DateTime at) =>
    '$key|${at.toUtc().toIso8601String()}';

/// Works out the ordinary notifications (not alarms or timers) from the server's list. Pure, so it can be tested without a phone.
/// A reminder whose ring time is already past is shown at once, once, unless the thing itself is more than [lateGrace] over.
List<PlannedNotice> planNotices(
  List<Json> reminders,
  int leadMinutes,
  DateTime clock,
  Set<String> shown,
) {
  final out = <PlannedNotice>[];
  for (final r in reminders) {
    final kind = str(r['kind']);
    if (kind == 'alarm' || kind == 'timer') continue;
    final at = dateOf(r['at'])?.toLocal();
    if (at == null) continue;
    final key = str(r['key']);
    final fire = at.subtract(Duration(minutes: leadMinutes));
    final id = _idOf(key);
    final title = str(r['title']);
    if (fire.isAfter(clock)) {
      out.add(
        PlannedNotice(
          key: key,
          id: id,
          title: title,
          at: at,
          fire: fire,
          showNow: false,
        ),
      );
    } else if (clock.difference(at) <= lateGrace &&
        !shown.contains(shownKeyOf(key, at))) {
      out.add(
        PlannedNotice(
          key: key,
          id: id,
          title: title,
          at: at,
          fire: fire,
          showNow: true,
        ),
      );
    }
  }
  return out;
}

/// Works out the alarms and timers from the server's list: they ring at their own time (no lead), loudly. Pure, so it can be tested without a phone.
/// The same late rule as [planNotices]: one whose time is past is rung at once, once, unless it is more than [lateGrace] over.
List<PlannedNotice> planAlarms(
  List<Json> reminders,
  DateTime clock,
  Set<String> shown,
) {
  final out = <PlannedNotice>[];
  for (final r in reminders) {
    final kind = str(r['kind']);
    if (kind != 'alarm' && kind != 'timer') continue;
    final at = dateOf(r['at'])?.toLocal();
    if (at == null) continue;
    final key = str(r['key']);
    final future = at.isAfter(clock);
    if (!future &&
        (clock.difference(at) > lateGrace ||
            shown.contains(shownKeyOf(key, at)))) {
      continue;
    }
    out.add(
      PlannedNotice(
        key: key,
        id: _idOf(key),
        title: str(r['title']),
        at: at,
        fire: at,
        showNow: !future,
        alarm: true,
      ),
    );
  }
  return out;
}

int _idOf(String key) {
  // A stable positive 31 bit number from the reminder's key
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return h;
}

/// Brings the phone's notifications in line with [reminders]. Alarms and timers ring from this app on their own loud channel.
/// Nothing is cancelled that is still wanted and nothing already on screen is wiped. True when every one was set; false when some failed
/// (the next sync then tries again). A failure is kept as its class only, never the reminder's words.
Future<bool> applyReminders(
  List<Json> reminders,
  Settings settings,
  SharedPreferences prefs, {
  DateTime? now,
}) async {
  final clock = now ?? DateTime.now();
  var ok = true;
  String? failure;
  void fail(Object e) {
    ok = false;
    failure = e.runtimeType.toString();
  }

  final words = wordsFor(settings.language);
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  try {
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        words.notifChannel,
        description: words.notifChannelDescription,
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName(settings.language),
        description: _alarmChannelDescription(settings.language),
        importance: Importance.max,
        sound: _alarmSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        bypassDnd: false,
      ),
    );
  } on Object catch (e) {
    fail(e);
  }
  // An older build handed alarms to the clock app and kept a list of them: nothing reads it any more
  await prefs.remove(_handledKey);
  final shown = (prefs.getStringList(_shownKey) ?? <String>[]).toSet();
  final notices = <PlannedNotice>[
    ...planNotices(reminders, settings.leadMinutes, clock, shown),
    ...planAlarms(reminders, clock, shown),
  ];
  // Only what is no longer wanted is cancelled; the rest is replaced by id below
  final wanted = <int>{
    for (final n in notices)
      if (!n.showNow) n.id,
  };
  try {
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (wanted.contains(p.id)) continue;
      try {
        await _plugin.cancel(id: p.id);
      } on Object catch (e) {
        fail(e);
      }
    }
  } on Object catch (e) {
    fail(e);
  }
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      // Made without a screen, so the words come from the stored language
      words.notifChannel,
      channelDescription: words.notifChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  final alarmDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName(settings.language),
      channelDescription: _alarmChannelDescription(settings.language),
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      sound: _alarmSound,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      // FLAG_INSISTENT: the sound repeats until the notification is tapped or swiped away
      additionalFlags: Int32List.fromList(<int>[4]),
      // Tapping it opens the app and stops the sound
      autoCancel: true,
      ongoing: false,
    ),
  );
  for (final n in notices) {
    // Both ways say only "Botler" when the person chose to hide details
    final text = notificationFor(n.title, settings);
    try {
      if (n.showNow) {
        await _plugin.show(
          id: n.id,
          title: text.title,
          body: text.body,
          notificationDetails: n.alarm ? alarmDetails : details,
          payload: n.key,
        );
        shown.add(shownKeyOf(n.key, n.at));
      } else {
        Future<void> schedule(AndroidScheduleMode mode) =>
            _plugin.zonedSchedule(
              id: n.id,
              title: text.title,
              body: text.body,
              scheduledDate: tz.TZDateTime.from(n.fire, tz.local),
              notificationDetails: n.alarm ? alarmDetails : details,
              androidScheduleMode: mode,
              payload: n.key,
            );
        try {
          // An alarm clock entry is exempt from doze and shows the alarm icon; a reminder only needs to be exact
          await schedule(
            n.alarm
                ? AndroidScheduleMode.alarmClock
                : AndroidScheduleMode.exactAllowWhileIdle,
          );
        } on Object {
          // No exact alarm allowed: a slightly late reminder beats none, and the failure is still reported below
          await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
          fail(StateError('exact'));
        }
        // Once its ring time has passed, a later sync must not show it a second time
        shown.add(shownKeyOf(n.key, n.at));
      }
    } on Object catch (e) {
      fail(e);
    }
  }
  final listed = <String>{
    for (final r in reminders)
      if (dateOf(r['at']) case final DateTime moment)
        shownKeyOf(str(r['key']), moment.toLocal()),
  };
  await prefs.setStringList(_shownKey, shown.intersection(listed).toList());
  final problem = failure;
  if (problem != null) {
    await prefs.setString(reminderErrorKey, problem);
  } else {
    await prefs.remove(reminderErrorKey);
  }
  return ok;
}

// The system's own alarm sound, so the ring is the one the person already knows
const UriAndroidNotificationSound _alarmSound = UriAndroidNotificationSound(
  'content://settings/system/alarm_alert',
);

String _alarmChannelName(String language) =>
    language == 'fil' ? 'Mga alarm at timer' : 'Alarms and timers';

String _alarmChannelDescription(String language) => language == 'fil'
    ? 'Tumutunog hanggang pindutin mo'
    : 'Rings until you tap it';

/// What a notification says. With details hidden it says only that there is a reminder, so a lock screen shows no names and no amounts.
({String title, String? body}) notificationFor(
  String title,
  Settings settings,
) => settings.hideDetails
    ? (title: 'Botler', body: wordsFor(settings.language).notifHiddenBody)
    : (title: title, body: null);
