// THE CLIENT'S SAFETY NETS: A SECURE-CONNECTION FAILURE IS "OFFLINE", A 401 DURING A FLUSH IS KEPT AND SAID, AND A SCHEDULE'S FIRST, LAST AND LEFT-OUT DATES ARE READ.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/reminders.dart';
import 'package:botler/core/schedule_text.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

ApiClient clientFor(MockClient c) =>
    ApiClient(base: 'https://botler.test', token: () async => 'tok', client: c);

AppLocalizations words(String code) => lookupAppLocalizations(Locale(code));

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('the client', () {
    test('a failed secure handshake is offline, not a bad answer', () async {
      for (final failure in <Object>[
        const HandshakeException('bad certificate'),
        const TlsException('tls'),
      ]) {
        final api = clientFor(MockClient((_) async => throw failure));
        await expectLater(
          api.get('/x'),
          throwsA(
            isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
          ),
        );
        await expectLater(
          api.post('/x', <String, Object?>{}),
          throwsA(
            isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
          ),
        );
        await expectLater(
          api.chat(id: 'msg-00000001', text: 'hi').toList(),
          throwsA(
            isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
          ),
        );
      }
    });
  });

  group('a 401 during a flush', () {
    test('keeps the queue and raises the sign-in notice', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          apiProvider.overrideWithValue(
            clientFor(
              MockClient(
                (_) async => http.Response(
                  jsonEncode(<String, Object?>{
                    'error': <String, Object?>{
                      'code': 'UNAUTHENTICATED',
                      'message': 'Sign in again.',
                    },
                  }),
                  401,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(outboxProvider).add('expense_log', <String, Object?>{});
      expect(c.read(needsSignInProvider), isFalse);
      await flushAndSync(c);
      expect(c.read(needsSignInProvider), isTrue);
      expect(c.read(outboxProvider).items(), hasLength(1));
      expect(c.read(outboxProvider).failed(), isEmpty);
      expect(
        (await c.read(outboxProvider).flush(c.read(apiProvider))).needsSignIn,
        isTrue,
      );
    });
  });

  group('a schedule sentence', () {
    final base = <String, Object?>{'kind': 'monthly', 'day': 5};

    test('adds the first date, the last date and the dates left out', () {
      final t = words('en');
      expect(describeSchedule(t, 'en', base), 'On the 5th of the month');
      expect(
        describeSchedule(t, 'en', <String, Object?>{
          ...base,
          'startsOn': '2026-01-01',
          'endsOn': '2026-12-31',
          'skipDates': <String>['2026-03-05', '2026-02-05'],
        }),
        'On the 5th of the month (from 2026-01-01, until 2026-12-31, not on 2026-02-05, 2026-03-05)',
      );
    });

    test('reads in Filipino too, and an unknown kind stays null', () {
      final t = words('fil');
      final said = describeSchedule(t, 'fil', <String, Object?>{
        ...base,
        'endsOn': '2026-12-31',
      });
      expect(said, contains('hanggang 2026-12-31'));
      expect(
        describeSchedule(t, 'fil', <String, Object?>{'kind': 'lunar'}),
        isNull,
      );
    });
  });
}
