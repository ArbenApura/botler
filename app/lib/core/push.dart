// PUSH THROUGH FIREBASE CLOUD MESSAGING: REGISTER THIS PHONE'S TOKEN WITH THE SERVER, KEEP IT FRESH, FORGET IT ON SIGN OUT, AND ANSWER A SILENT "SYNC" PUSH.
// A push is only a nudge. The phone's own alarms and the 15 minute background sync are the source of truth, so every failure here is quiet and
// push can be missing (no Play services, no permission, offline) without anything else changing. The token is never logged or shown.
// Firebase itself sits behind [PushHost], so tests run without it.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'api.dart';
import 'json.dart';
import 'reminders.dart';

// -- TYPES -- //

/// What the push service needs from Firebase. A seam, so tests run without it.
abstract class PushHost {
  /// This phone's token, or null when there is none (no Play services, permission refused).
  Future<String?> token();

  /// A new token, when Firebase rotates it.
  Stream<String> get tokenRefresh;

  /// The data of each push that arrives while the app is open.
  Stream<Map<String, String>> get messages;

  Future<void> deleteToken();
}

// The classic registration token (getToken) is what the server's FCM HTTP v1 sends use. The newer register() API hands out an installation id
// for a different kind of send, so the older calls stay on purpose until the server is moved.
class FirebasePushHost implements PushHost {
  const FirebasePushHost();

  @override
  // ignore: deprecated_member_use
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<Map<String, String>> get messages => FirebaseMessaging.onMessage.map(
    (m) => <String, String>{
      for (final e in m.data.entries) e.key: '${e.value}',
    },
  );

  @override
  // ignore: deprecated_member_use
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();
}

// -- CONSTANTS -- //

const String _deviceKey = 'push.deviceId';

// -- FUNCTIONS -- //

/// Starts Firebase and the handler for a push that arrives while the app is closed. Quiet on failure: push is optional.
Future<void> initPush() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  } on Exception {
    // No Play services or no configuration: the phone still syncs when opened and every 15 minutes
  }
}

/// A push while the app is not running. Its own isolate: no screen, no providers. Only the silent "sync" push does anything; a visible
/// notice is shown by Android itself.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'sync') return;
  await backgroundSyncOnce();
}

class PushService {
  PushService({required this.host, required this.api, required this.prefs});

  final PushHost host;
  final ApiClient api;
  final SharedPreferences prefs;

  /// Called for a silent "sync" push while the app is open. Set by the app shell.
  void Function()? onSync;

  // -- STATES -- //

  StreamSubscription<String>? _refresh;
  StreamSubscription<Map<String, String>>? _messages;

  // -- FUNCTIONS -- //

  /// Gives the server this phone's token (a repeat only refreshes it) and starts listening for a new token and for sync pushes.
  Future<void> register() async {
    try {
      _refresh ??= host.tokenRefresh.listen(
        (_) => unawaited(register()),
        onError: (Object _) {},
      );
      _messages ??= host.messages.listen((data) {
        if (data['type'] == 'sync') onSync?.call();
      }, onError: (Object _) {});
      final token = await host.token();
      if (token == null || token.length < 10) return;
      final answer = await api.post('/api/v1/devices', <String, Object?>{
        'platform': 'android',
        'pushToken': token,
        'label': 'Android phone',
      });
      final id = str(asJson(answer['device'])['id']);
      if (id.isNotEmpty) await prefs.setString(_deviceKey, id);
    } on ApiException {
      // Offline or a busy server: the next start registers again
    } on Exception {
      // No Firebase on this phone (no Play services, or it did not start)
    }
  }

  /// Sign out: the server forgets this phone and Firebase drops the token, so no push reaches an account that is no longer signed in.
  /// Must run before the session is cleared, because the call needs it.
  Future<void> unregister() async {
    await _refresh?.cancel();
    await _messages?.cancel();
    _refresh = null;
    _messages = null;
    final id = prefs.getString(_deviceKey);
    try {
      if (id != null && id.isNotEmpty) {
        await api.delete('/api/v1/devices', query: <String, String>{'id': id});
      }
    } on ApiException {
      // The server drops a dead token itself the first time a push to it fails
    }
    try {
      await host.deleteToken();
    } on Exception {
      // Nothing to delete
    }
    await prefs.remove(_deviceKey);
  }
}
