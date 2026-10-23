// REMINDERS ON THE PHONE. THE SERVER WORKS OUT WHAT NEEDS A REMINDER (/api/v1/sync); THE PHONE REPLACES ALL ITS ALARMS WITH THAT LIST, SO THEY STILL RING
// WITH THE APP CLOSED, OFFLINE, AFTER A REBOOT AND IN DOZE (EXACT ALARMS; THE PLUGIN PUTS THEM BACK AFTER A REBOOT). IT ASKS THE SERVER:
// when the app opens or comes back, and every ~15 minutes from a background task. Alarms and timers are handed to the phone's own clock app.
// The notification says only "Botler" when the person chose to hide details, and the server never puts an amount in a reminder.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

// -- MODULES -- //
import '../l10n/l10n.dart';
import '../state/providers.dart';
import 'api.dart';
import 'auth.dart';
import 'config.dart';
import 'json.dart';
import 'outbox.dart';

// -- CONSTANTS -- //

// A new channel id: Android keeps the importance a channel was first made with, so an old quiet channel could never be made loud
const String _channelId = 'botler_reminders_v2';
const String _cursorKey = 'sync.cursor';
const String _cursorFixKey = 'sync.cursor_fix1';
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
  tzdata.initializeTimeZones();
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
    if (await store.read() == null) return true;
    await _initNotifications();
    final api = ApiClient(
      base: apiBase,
      token: () async => (await store.read())?.token,
    );
    try {
      await Outbox(prefs).flush(api);
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
    if (report.sent > 0 || report.dropped.isNotEmpty)
      container.read(outboxCountProvider.notifier).refresh();
    await syncReminders(api, prefs);
  } on ApiException {
    // Offline: what is already scheduled keeps ringing
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
    final answer = await api.sync(cursor: prefs.getString(_cursorKey));
    await prefs.setString(reminderSyncedKey, DateTime.now().toIso8601String());
    if (!boolOf(answer['changed'], true) ||
        answer['reminders'] is! List<Object?>) {
      return;
    }
    final ok = await applyReminders(
      asJsonList(answer['reminders']),
      readSettings(prefs),
      prefs,
    );
    // A cursor kept only after everything was scheduled: a failed round is asked for again
    if (ok) await prefs.setString(_cursorKey, str(answer['cursor']));
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
  });

  final String key;
  final int id;
  final String title;
  final DateTime at;
  final DateTime fire;
  final bool showNow;
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

int _idOf(String key) {
  // A stable positive 31 bit number from the reminder's key
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return h;
}

/// Brings the phone's notifications in line with [reminders]. Alarms and timers go to the clock app, once each.
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
  } on Object catch (e) {
    fail(e);
  }
  final handled = (prefs.getStringList(_handledKey) ?? <String>[]).toSet();
  final shown = (prefs.getStringList(_shownKey) ?? <String>[]).toSet();
  final notices = planNotices(reminders, settings.leadMinutes, clock, shown);
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
  final stillThere = <String>{};
  for (final r in reminders) {
    final kind = str(r['kind']);
    if (kind != 'alarm' && kind != 'timer') continue;
    final at = dateOf(r['at'])?.toLocal();
    if (at == null) continue;
    final key = str(r['key']);
    stillThere.add(key);
    // Only what falls in the next day: the clock app sets the next time that matches
    if (!handled.contains(key) &&
        at.isAfter(clock) &&
        at.difference(clock) < const Duration(hours: 24)) {
      try {
        await _handToClock(kind, str(r['title']), at, clock);
        handled.add(key);
      } on Object catch (e) {
        fail(e);
      }
    }
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
  for (final n in notices) {
    // Both ways say only "Botler" when the person chose to hide details
    final text = notificationFor(n.title, settings);
    try {
      if (n.showNow) {
        await _plugin.show(
          id: n.id,
          title: text.title,
          body: text.body,
          notificationDetails: details,
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
              notificationDetails: details,
              androidScheduleMode: mode,
              payload: n.key,
            );
        try {
          await schedule(AndroidScheduleMode.exactAllowWhileIdle);
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
  await prefs.setStringList(
    _handledKey,
    handled.intersection(stillThere).toList(),
  );
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

Future<void> _handToClock(
  String kind,
  String title,
  DateTime at,
  DateTime now,
) async {
  if (kind == 'alarm') {
    await AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, Object>{
        'android.intent.extra.alarm.HOUR': at.hour,
        'android.intent.extra.alarm.MINUTES': at.minute,
        'android.intent.extra.alarm.MESSAGE': title,
        'android.intent.extra.alarm.SKIP_UI': true,
      },
    ).launch();
  } else {
    await AndroidIntent(
      action: 'android.intent.action.SET_TIMER',
      arguments: <String, Object>{
        'android.intent.extra.alarm.LENGTH': at.difference(now).inSeconds,
        'android.intent.extra.alarm.MESSAGE': title,
        'android.intent.extra.alarm.SKIP_UI': true,
      },
    ).launch();
  }
}

/// What a notification says. With details hidden it says only that there is a reminder, so a lock screen shows no names and no amounts.
({String title, String? body}) notificationFor(
  String title,
  Settings settings,
) => settings.hideDetails
    ? (title: 'Botler', body: wordsFor(settings.language).notifHiddenBody)
    : (title: title, body: null);
