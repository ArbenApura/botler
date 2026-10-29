// THE UPDATE STATE AND SCREENS: THE BLOCKING SCREEN APPEARS ONLY AFTER A GOOD ANSWER, A FAILURE ALWAYS HAS A WAY BACK, AN OFFLINE PHONE IS NEVER BLOCKED.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/app_update.dart';
import 'package:botler/core/auth.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/update/update_gate.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/state/update.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class _Host implements UpdateHost {
  List<String> abiList = <String>['arm64-v8a', 'armeabi-v7a'];
  _Host(this.dir);

  final Directory dir;
  bool allowed = true;
  bool explode = false;

  @override
  Future<int> installedCode() async => 1;
  @override
  Future<String> installedName() async => '1.0.0';
  @override
  Future<String> updateDir() async => dir.path;
  @override
  Future<int> freeBytes() async => 1 << 30;
  @override
  Future<List<String>> abis() async => abiList;
  @override
  Future<String> archiveCheck(String path, int code) async => 'ok';
  @override
  Future<bool> canInstall() async {
    if (explode) throw PlatformException(code: 'update');
    return allowed;
  }

  @override
  Future<void> openInstallSettings() async {}
  @override
  Future<String> install(String path) async => 'ok';
}

class _Fixed extends SessionNotifier {
  @override
  Future<Session?> build() async =>
      const Session(token: 't', email: 'a@b.test', name: 'A');
}

// -- FUNCTIONS -- //

Json _answer({required int minimum}) => <String, Object?>{
  'status': 'x',
  'latest': <String, Object?>{
    'versionName': '1.0.1',
    'versionCode': 2,
    'sha256': 'a' * 64,
    'size': 5000,
    'minSupportedCode': minimum,
    'notes': '',
    'publishedAt': '2026-10-22T10:00:00Z',
  },
  'downloadPath': '/api/v1/app/update/apk/2',
};

Future<ProviderContainer> _boot(
  WidgetTester tester,
  MockClient client, {
  bool allowed = true,
  bool explode = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('botler-gate-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(_Fixed.new),
      updateHostProvider.overrideWithValue(
        _Host(dir)
          ..allowed = allowed
          ..explode = explode,
      ),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: client,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: const UpdateGate(child: Scaffold(body: Text('the app'))),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

MockClient _server(int minimum, {int status = 200}) => MockClient(
  (r) async => http.Response(
    jsonEncode(
      status == 200
          ? _answer(minimum: minimum)
          : <String, Object?>{
              'error': <String, Object?>{'code': 'X', 'message': 'no'},
            },
    ),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  ),
);

void main() {
  testWidgets(
    'a good answer below the minimum blocks the app with one action',
    (tester) async {
      await _boot(tester, _server(2));
      expect(find.text('Update needed'), findsOneWidget);
      expect(find.text('the app'), findsNothing);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Use the app for now'), findsNothing);
    },
  );

  testWidgets('an optional update never blocks', (tester) async {
    final container = await _boot(tester, _server(1));
    expect(find.text('the app'), findsOneWidget);
    expect(container.read(updateProvider).offer?.isRequired, isFalse);
  });

  testWidgets(
    'a server fault, a signed out answer or no connection never blocks',
    (tester) async {
      for (final status in <int>[401, 500]) {
        await _boot(tester, _server(2, status: status));
        expect(find.text('the app'), findsOneWidget);
        expect(find.text('Update needed'), findsNothing);
      }
      await _boot(
        tester,
        MockClient((r) async => throw const SocketException('down')),
      );
      expect(find.text('the app'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed attempt shows the reason, a retry and a way back into the app',
    (tester) async {
      final container = await _boot(tester, _server(2), allowed: false);
      await container.read(updateProvider.notifier).start();
      await tester.pump();
      expect(
        find.textContaining('Allow Botler to install apps'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Open Android settings'), findsOneWidget);
      expect(find.text('Use the app for now'), findsOneWidget);
      await tester.tap(find.text('Use the app for now'));
      await tester.pump();
      expect(find.text('the app'), findsOneWidget);
    },
  );

  testWidgets(
    'the installer cancelled: the next resume says it did not finish',
    (tester) async {
      final container = await _boot(tester, _server(1));
      // Pretend the person tapped Update and the installer opened
      final notifier = container.read(updateProvider.notifier);
      notifier.state = container
          .read(updateProvider)
          .copyWith(phase: UpdatePhase.installing);
      await notifier.onResumed();
      final u = container.read(updateProvider);
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateFailure.installer);
    },
  );

  testWidgets(
    'an unexpected error while updating ends in a failure with a way back, never a stuck screen',
    (tester) async {
      final container = await _boot(tester, _server(2), explode: true);
      await container.read(updateProvider.notifier).start();
      await tester.pump();
      expect(container.read(updateProvider).phase, UpdatePhase.failed);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Use the app for now'), findsOneWidget);
      // And it can be tried again
      await container.read(updateProvider.notifier).start();
      expect(container.read(updateProvider).phase, UpdatePhase.failed);
    },
  );

  testWidgets('two taps start one update', (tester) async {
    final container = await _boot(tester, _server(2), allowed: false);
    final notifier = container.read(updateProvider.notifier);
    await Future.wait(<Future<void>>[notifier.start(), notifier.start()]);
    expect(container.read(updateProvider).phase, UpdatePhase.failed);
    expect(container.read(updateProvider).failure, UpdateFailure.permission);
  });

  testWidgets(
    'a failed check keeps a known offer, and a page that is not the server\'s answer is a failed check',
    (tester) async {
      var broken = false;
      final client = MockClient((r) async {
        if (broken) {
          return http.Response('<html>login</html>', 200);
        }
        return _server(1).get(r.url);
      });
      final container = await _boot(tester, client);
      final notifier = container.read(updateProvider.notifier);
      expect(container.read(updateProvider).offer, isNotNull);
      broken = true;
      await notifier.checkNow();
      final u = container.read(updateProvider);
      expect(u.checkFailed, isTrue);
      expect(u.offer, isNotNull, reason: 'a quiet failure forgets nothing');
    },
  );

  testWidgets('dismissing the banner hides that build only', (tester) async {
    final container = await _boot(tester, _server(1));
    await container.read(updateProvider.notifier).dismiss();
    expect(container.read(updateProvider).dismissedCode, 2);
    expect(
      container.read(appUpdaterProvider).dismissedCode,
      2,
      reason: 'kept for the next start',
    );
  });
}
