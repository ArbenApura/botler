// REMINDERS ON THE PHONE. THE SERVER WORKS OUT WHAT NEEDS A REMINDER (/api/v1/sync); THE PHONE REPLACES ALL ITS ALARMS WITH THAT LIST, SO THEY STILL RING
// WITH THE APP CLOSED, OFFLINE, AFTER A REBOOT AND IN DOZE (EXACT ALARMS; THE PLUGIN PUTS THEM BACK AFTER A REBOOT). IT ASKS THE SERVER:
// when the app opens or comes back, and every ~15 minutes from a background task. Alarms and timers are handed to the phone's own clock app.
// The notification says only "Botler" when the person chose to hide details, and the server never puts an amount in a reminder.

// -- DEP-MODULES -- //
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

const String _channelId = 'botler_reminders';
const String _cursorKey = 'sync.cursor';
const String _handledKey = 'sync.clock_handled';
const String _taskName = 'botler-sync';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

// -- FUNCTIONS -- //

Future<void> _initNotifications() async {
  tzdata.initializeTimeZones();
  final zone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(zone.identifier));
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
  final answer = await api.sync(cursor: prefs.getString(_cursorKey));
  if (!boolOf(answer['changed'], true) || answer['reminders'] is! List<Object?>)
    return;
  await applyReminders(
    asJsonList(answer['reminders']),
    readSettings(prefs),
    prefs,
  );
  await prefs.setString(_cursorKey, str(answer['cursor']));
}

int _idOf(String key) {
  // A stable positive 31 bit number from the reminder's key
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return h;
}

/// Replaces every scheduled notification of ours with [reminders]. Alarms and timers go to the clock app, once each.
Future<void> applyReminders(
  List<Json> reminders,
  Settings settings,
  SharedPreferences prefs, {
  DateTime? now,
}) async {
  final clock = now ?? DateTime.now();
  await _plugin.cancelAll();
  final handled = (prefs.getStringList(_handledKey) ?? <String>[]).toSet();
  final stillThere = <String>{};
  for (final r in reminders) {
    final at = dateOf(r['at'])?.toLocal();
    if (at == null) continue;
    final key = str(r['key']);
    final kind = str(r['kind']);
    if (kind == 'alarm' || kind == 'timer') {
      stillThere.add(key);
      // Only what falls in the next day: the clock app sets the next time that matches
      if (!handled.contains(key) &&
          at.isAfter(clock) &&
          at.difference(clock) < const Duration(hours: 24)) {
        await _handToClock(kind, str(r['title']), at, clock);
        handled.add(key);
      }
      continue;
    }
    final fire = at.subtract(Duration(minutes: settings.leadMinutes));
    if (!fire.isAfter(clock)) continue;
    final words = notificationFor(str(r['title']), settings);
    await _plugin.zonedSchedule(
      id: _idOf(key),
      title: words.title,
      body: words.body,
      scheduledDate: tz.TZDateTime.from(fire, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          // Made without a screen, so the words come from the stored language
          wordsFor(settings.language).notifChannel,
          channelDescription: wordsFor(settings.language)
              .notifChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: key,
    );
  }
  await prefs.setStringList(
    _handledKey,
    handled.intersection(stillThere).toList(),
  );
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
