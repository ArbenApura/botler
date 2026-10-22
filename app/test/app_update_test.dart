// APP UPDATES: THE DECISION (WHO IS ASKED TO UPDATE AND WHO IS NEVER BLOCKED), THE CHECK (QUIET WHEN OFFLINE, THROTTLED), AND THE DOWNLOAD
// (EXACT SIZE, EXACT HASH, THE ANDROID CHECK, ONE AT A TIME, NOTHING LEFT BEHIND, NO TOKEN IN ANY ERROR).

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/app_update.dart';
import 'package:botler/core/json.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class _Host implements UpdateHost {
  _Host(this.dir, {this.verdict = 'ok', this.free = 1 << 30});

  final Directory dir;
  String verdict;
  int free;
  int code = 1;
  String installVerdict = 'ok';
  final List<String> checked = <String>[];

  @override
  Future<int> installedCode() async => code;
  @override
  Future<String> installedName() async => '1.0.0';
  @override
  Future<String> updateDir() async => dir.path;
  @override
  Future<int> freeBytes() async => free;
  @override
  Future<String> archiveCheck(String path, int code) async {
    checked.add(path);
    return verdict;
  }

  @override
  Future<bool> canInstall() async => true;
  @override
  Future<void> openInstallSettings() async {}
  @override
  Future<String> install(String path) async => installVerdict;
}

// -- FUNCTIONS -- //

final List<int> _bytes = List<int>.generate(5000, (i) => i % 251);
final String _hash = sha256.convert(_bytes).toString();

Json _answer({
  int code = 2,
  int minimum = 1,
  int size = 5000,
  String? hash,
  String? path,
}) => <String, Object?>{
  'status': 'optional',
  'latest': <String, Object?>{
    'versionName': '1.0.1',
    'versionCode': code,
    'sha256': hash ?? _hash,
    'size': size,
    'minSupportedCode': minimum,
    'notes': '',
    'publishedAt': '2026-10-22T10:00:00Z',
  },
  'downloadPath': path ?? '/api/v1/app/update/apk/$code',
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

ApiClient _api(MockClient c) => ApiClient(
  base: 'https://botler.test',
  token: () async => 'SECRET',
  client: c,
);

UpdateOffer _offer({int size = 5000, String? hash}) =>
    decideOffer(_answer(size: size, hash: hash), 1)!;

void main() {
  group('the decision', () {
    test('offers a newer build and ignores an equal or older one', () {
      expect(decideOffer(_answer(code: 2), 1)?.kind, UpdateKind.optional);
      expect(decideOffer(_answer(code: 2), 2), isNull);
      expect(decideOffer(_answer(code: 2), 9), isNull);
    });

    test('requires an update only below the minimum', () {
      expect(
        decideOffer(_answer(code: 3, minimum: 3), 2)?.kind,
        UpdateKind.required,
      );
      expect(
        decideOffer(_answer(code: 3, minimum: 3), 3),
        isNull,
        reason: 'the phone already runs the minimum',
      );
      expect(
        decideOffer(_answer(code: 3, minimum: 2), 2)?.kind,
        UpdateKind.optional,
      );
    });

    test('never requires a build that cannot meet its own minimum', () {
      // minSupportedCode 5 above the offered build 3: offered as optional at most, never a lock out
      final offer = decideOffer(_answer(code: 3, minimum: 5), 1);
      expect(offer?.kind, UpdateKind.optional);
    });

    test('ignores the words of the status and any odd answer', () {
      final answer = _answer(code: 2)..['status'] = 'required';
      expect(decideOffer(answer, 1)?.kind, UpdateKind.optional);
      expect(decideOffer(<String, Object?>{}, 1), isNull);
      expect(decideOffer(_answer(hash: 'xyz'), 1), isNull);
      expect(decideOffer(_answer(size: 0), 1), isNull);
      expect(
        decideOffer(_answer(path: 'https://evil.test/a.apk'), 1),
        isNull,
        reason: 'the download must be the server\'s own update path',
      );
      expect(decideOffer(_answer(path: '/api/v1/app/update/apk/9'), 1), isNull);
    });

    test('a check is due when never done, after 12 hours, or if the clock moved back', () {
      final now = DateTime(2026, 10, 22, 12);
      expect(checkDue(null, now), isTrue);
      expect(checkDue(now.subtract(const Duration(hours: 11)), now), isFalse);
      expect(checkDue(now.subtract(const Duration(hours: 12)), now), isTrue);
      expect(checkDue(now.add(const Duration(hours: 1)), now), isTrue);
    });
  });

  group('the check', () {
    late Directory dir;
    late SharedPreferences prefs;
    var now = DateTime(2026, 10, 22, 12);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('botler-upd-');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 10, 22, 12);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    AppUpdater updater(MockClient c, _Host host) =>
        AppUpdater(api: _api(c), host: host, prefs: prefs, clock: () => now);

    test('asks with the installed build and remembers a good answer', () async {
      Uri? seen;
      final u = updater(
        MockClient((r) async {
          seen = r.url;
          return _json(_answer(code: 2));
        }),
        _Host(dir),
      );
      final offer = await u.check();
      expect(offer?.versionCode, 2);
      expect(seen?.queryParameters['versionCode'], '1');
      expect(u.lastCheck, now);
    });

    test('does not ask again within 12 hours unless forced', () async {
      var calls = 0;
      final u = updater(
        MockClient((r) async {
          calls++;
          return _json(_answer(code: 2));
        }),
        _Host(dir),
      );
      await u.check();
      now = now.add(const Duration(hours: 3));
      expect(await u.check(), isNull);
      expect(calls, 1);
      await u.check(force: true);
      expect(calls, 2);
    });

    test('offline, signed out or a server fault is quiet and does not move the time', () async {
      for (final status in <int>[401, 500, 503]) {
        final u = updater(
          MockClient(
            (r) async => _json(<String, Object?>{
              'error': <String, Object?>{'code': 'X', 'message': 'no'},
            }, status),
          ),
          _Host(dir),
        );
        expect(await u.check(), isNull);
        expect(u.lastCheckFailed, isTrue);
        expect(u.lastCheck, isNull);
      }
      final offline = updater(
        MockClient((r) async => throw const SocketException('down')),
        _Host(dir),
      );
      expect(await offline.check(), isNull);
      expect(offline.lastCheckFailed, isTrue);
      expect(offline.lastCheck, isNull);
    });

    test('remembers a dismissed build', () async {
      final u = updater(MockClient((r) async => _json(_answer())), _Host(dir));
      expect(u.dismissedCode, 0);
      await u.dismiss(2);
      expect(u.dismissedCode, 2);
    });
  });

  group('the download', () {
    late Directory dir;
    late SharedPreferences prefs;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('botler-dl-');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    MockClient serving(List<int> body, {int status = 200, int? length}) =>
        MockClient.streaming((request, _) async {
          // The token goes only as a header to the Botler host, and nothing else follows a redirect
          expect(request.headers['authorization'], 'Bearer SECRET');
          expect(request.followRedirects, isFalse);
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              body.sublist(0, body.length ~/ 2),
              body.sublist(body.length ~/ 2),
            ]),
            status,
            contentLength: length ?? body.length,
          );
        });

    AppUpdater make(MockClient c, _Host h) =>
        AppUpdater(api: _api(c), host: h, prefs: prefs);

    List<String> left() => dir.listSync().map((e) => e.path).toList();

    test(
      'saves a file whose size and hash match, and has Android check it',
      () async {
        final host = _Host(dir);
        final progress = <double>[];
        final path = await make(
          serving(_bytes),
          host,
        ).download(_offer(), progress.add);
        expect(File(path).readAsBytesSync(), _bytes);
        expect(path, endsWith('botler-2.apk'));
        expect(host.checked, <String>[path]);
        expect(progress.last, 1.0);
        expect(left().where((p) => p.endsWith('.part')), isEmpty);
      },
    );

    test('refuses a changed byte, and leaves nothing behind', () async {
      final bad = List<int>.of(_bytes)..[10] = 255;
      await expectLater(
        make(serving(bad), _Host(dir)).download(_offer(), (_) {}),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.damaged,
          ),
        ),
      );
      expect(left(), isEmpty);
    });

    test('refuses a body that is shorter or longer than promised', () async {
      for (final body in <List<int>>[
        _bytes.sublist(0, 4000),
        <int>[..._bytes, 1, 2, 3],
      ]) {
        await expectLater(
          make(
            serving(body, length: body.length),
            _Host(dir),
          ).download(_offer(), (_) {}),
          throwsA(isA<UpdateException>()),
        );
        expect(left(), isEmpty);
      }
    });

    test('without a declared length, a body that is too long or too short is refused', () async {
      for (final body in <List<int>>[
        <int>[..._bytes, 1, 2, 3],
        _bytes.sublist(0, 4000),
      ]) {
        final client = MockClient.streaming(
          (r, _) async =>
              http.StreamedResponse(Stream<List<int>>.value(body), 200),
        );
        await expectLater(
          make(client, _Host(dir)).download(_offer(), (_) {}),
          throwsA(
            isA<UpdateException>().having(
              (e) => e.failure,
              'failure',
              UpdateFailure.damaged,
            ),
          ),
        );
        expect(left(), isEmpty);
      }
    });

    test('a connection that breaks while the body arrives is a network failure and leaves nothing', () async {
      final client = MockClient.streaming((r, _) async {
        Stream<List<int>> broken() async* {
          yield _bytes.sublist(0, 1000);
          throw http.ClientException('Connection closed while receiving data');
        }

        return http.StreamedResponse(
          broken(),
          200,
          contentLength: _bytes.length,
        );
      });
      await expectLater(
        make(client, _Host(dir)).download(_offer(), (_) {}),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.network,
          ),
        ),
      );
      expect(left(), isEmpty);
    });

    test('a 404 is tried once more, then the download works', () async {
      var calls = 0;
      final client = MockClient.streaming((r, _) async {
        calls++;
        if (calls == 1) {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('{}')),
            404,
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(_bytes),
          200,
          contentLength: _bytes.length,
        );
      });
      final path = await make(client, _Host(dir)).download(_offer(), (_) {});
      expect(calls, 2);
      expect(File(path).existsSync(), isTrue);
    });

    test(
      'deletes the file when Android says it is not an update for this app',
      () async {
        for (final verdict in <String>['signature', 'package', 'version']) {
          await expectLater(
            make(
              serving(_bytes),
              _Host(dir, verdict: verdict),
            ).download(_offer(), (_) {}),
            throwsA(
              isA<UpdateException>().having(
                (e) => e.failure,
                'failure',
                UpdateFailure.wrongBuild,
              ),
            ),
          );
          expect(left(), isEmpty);
        }
      },
    );

    test('stops before downloading when the phone is short of space', () async {
      var calls = 0;
      final client = MockClient.streaming((r, _) async {
        calls++;
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
      });
      await expectLater(
        make(client, _Host(dir, free: 100)).download(_offer(), (_) {}),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.space,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('a redirect or a server error is a failure, never followed', () async {
      for (final status in <int>[302, 404, 500]) {
        final client = MockClient.streaming(
          (r, _) async => http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('{}')),
            status,
          ),
        );
        await expectLater(
          make(client, _Host(dir)).download(_offer(), (_) {}),
          throwsA(isA<UpdateException>()),
        );
      }
    });

    test('a lost connection is a network failure', () async {
      final client = MockClient.streaming(
        (r, _) async => throw const SocketException('gone'),
      );
      await expectLater(
        make(client, _Host(dir)).download(_offer(), (_) {}),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.network,
          ),
        ),
      );
    });

    test('allows only one download at a time', () async {
      final started = Completer<void>();
      final client = MockClient.streaming((r, _) async {
        await started.future;
        return http.StreamedResponse(
          Stream<List<int>>.value(_bytes),
          200,
          contentLength: _bytes.length,
        );
      });
      final u = make(client, _Host(dir));
      final first = u.download(_offer(), (_) {});
      await expectLater(
        u.download(_offer(), (_) {}),
        throwsA(isA<UpdateException>()),
      );
      started.complete();
      expect(await first, endsWith('botler-2.apk'));
    });

    test('errors carry a code only, never the token or a path', () async {
      final client = MockClient.streaming(
        (r, _) async => throw const SocketException('SECRET /data/x'),
      );
      try {
        await make(client, _Host(dir)).download(_offer(), (_) {});
        fail('should have thrown');
      } on UpdateException catch (e) {
        expect(e.toString(), isNot(contains('SECRET')));
        expect(e.toString(), isNot(contains('/data')));
      }
    });

    test('installing reports a missing permission and a refusal', () async {
      final host = _Host(dir)..installVerdict = 'needs_permission';
      final u = make(serving(_bytes), host);
      await expectLater(
        u.install('x'),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.permission,
          ),
        ),
      );
      host.installVerdict = 'error';
      await expectLater(
        u.install('x'),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.installer,
          ),
        ),
      );
    });

    test('the sweep removes old downloads', () async {
      File('${dir.path}/botler-2.apk').writeAsBytesSync(<int>[1]);
      File('${dir.path}/botler-3.apk.part').writeAsBytesSync(<int>[1]);
      await make(serving(_bytes), _Host(dir)).sweep();
      expect(left(), isEmpty);
    });
  });
}
