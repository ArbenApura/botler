// PUSH: THE PHONE GIVES THE SERVER ITS TOKEN, KEEPS IT FRESH, FORGETS IT ON SIGN OUT AND ANSWERS ONLY THE SILENT SYNC PUSH. EVERY FAILURE IS QUIET.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/clock.dart' show ClockPrefs, clockPrefs;
import 'package:botler/core/push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class _Host implements PushHost {
  String? current = 'token-aaaaaaaaaa';
  bool deleted = false;
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final StreamController<Map<String, String>> incoming =
      StreamController<Map<String, String>>.broadcast();

  @override
  Future<String?> token() async => current;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<Map<String, String>> get messages => incoming.stream;
  @override
  Future<void> deleteToken() async => deleted = true;
}

// -- FUNCTIONS -- //

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

void main() {
  late SharedPreferences prefs;
  late _Host host;
  late List<http.Request> sent;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    host = _Host();
    sent = <http.Request>[];
  });

  PushService make({int status = 200, Object? error}) => PushService(
    host: host,
    api: ApiClient(
      base: 'https://botler.test',
      token: () async => 'SESSION',
      client: MockClient((r) async {
        sent.add(r);
        if (error != null) throw error;
        return _json(<String, Object?>{
          'device': <String, Object?>{'id': 'dev-1'},
        }, status);
      }),
    ),
    prefs: prefs,
  );

  test(
    'registers the token as an android phone and remembers the device id',
    () async {
      await make().register();
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/api/v1/devices');
      final body = jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['platform'], 'android');
      expect(body['pushToken'], 'token-aaaaaaaaaa');
      expect(prefs.getString('push.deviceId'), 'dev-1');
    },
  );

  test(
    'reports the clock the phone reads, so reminder times follow it',
    () async {
      // The person's own choice decides what the phone reads
      clockPrefs = const ClockPrefs(timeFormat: '24');
      await make().register();
      expect(
        (jsonDecode(sent.last.body) as Map<String, Object?>)['clock'],
        '24',
      );
      clockPrefs = const ClockPrefs(timeFormat: '12');
      await make().register();
      expect(
        (jsonDecode(sent.last.body) as Map<String, Object?>)['clock'],
        '12',
      );
      clockPrefs = const ClockPrefs();
    },
  );

  test('registers again when Firebase rotates the token', () async {
    final service = make();
    await service.register();
    host.current = 'token-bbbbbbbbbb';
    host.refresh.add('token-bbbbbbbbbb');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sent.length, 2);
    expect(
      (jsonDecode(sent.last.body) as Map<String, Object?>)['pushToken'],
      'token-bbbbbbbbbb',
    );
  });

  test('a phone with no token, or a failed call, stays quiet and sends nothing it should not', () async {
    host.current = null;
    await make().register();
    expect(sent, isEmpty);
    host.current = 'token-aaaaaaaaaa';
    await make(status: 500).register();
    await make(error: const SocketException('down')).register();
    expect(prefs.getString('push.deviceId'), isNull);
  });

  test('Firebase being unavailable never throws', () async {
    final broken = _BrokenHost();
    final service = PushService(
      host: broken,
      api: ApiClient(
        base: 'https://botler.test',
        token: () async => 'x',
        client: MockClient((r) async => _json(<String, Object?>{})),
      ),
      prefs: prefs,
    );
    await service.register();
    await service.unregister();
  });

  test('signing out removes the device on the server, drops the token and stops listening', () async {
    final service = make();
    await service.register();
    sent.clear();
    await service.unregister();
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.queryParameters['id'], 'dev-1');
    expect(sent.single.headers['authorization'], 'Bearer SESSION');
    expect(host.deleted, isTrue);
    expect(prefs.getString('push.deviceId'), isNull);
    var synced = 0;
    service.onSync = () => synced++;
    host.incoming.add(<String, String>{'type': 'sync'});
    await Future<void>.delayed(Duration.zero);
    expect(synced, 0, reason: 'no longer listening');
  });

  test('only a silent sync push makes the open app sync', () async {
    final service = make();
    var synced = 0;
    service.onSync = () => synced++;
    await service.register();
    host.incoming.add(<String, String>{'type': 'notice', 'key': 'k'});
    host.incoming.add(<String, String>{});
    host.incoming.add(<String, String>{'type': 'sync'});
    await Future<void>.delayed(Duration.zero);
    expect(synced, 1);
  });
}

class _BrokenHost implements PushHost {
  @override
  Future<String?> token() => throw Exception('no firebase');
  @override
  Stream<String> get tokenRefresh => throw Exception('no firebase');
  @override
  Stream<Map<String, String>> get messages => throw Exception('no firebase');
  @override
  Future<void> deleteToken() => throw Exception('no firebase');
}
