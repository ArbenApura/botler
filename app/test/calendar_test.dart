// THE CALENDAR: THE RANGE IS READ INTO ITEMS, THE MONTH GRID LABELS EACH DAY IN WORDS, LAYERS HIDE AND SHOW, AND THE FORECAST SAYS IT IS AN ESTIMATE.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/features/calendar/calendar_data.dart';
import 'package:botler/features/calendar/calendar_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

String firstOfThisMonth() {
  final n = DateTime.now();
  return dayOf(DateTime(n.year, n.month, 5));
}

/// The phone's saved copy of the month grid the screen opens on (six weeks from the week start before the 1st).
String savedCopy() {
  final n = DateTime.now();
  final from = weekStart(DateTime(n.year, n.month), 1);
  final key = '${dayOf(from)}|${dayOf(from.add(const Duration(days: 41)))}';
  return jsonEncode(<String, Object?>{
    'key': key,
    'data': answerFor(dayOf(from)),
  });
}

Map<String, Object?> answerFor(String from) {
  final day = firstOfThisMonth();
  return <String, Object?>{
    'from': from,
    'to': from,
    'items': <Object?>[
      <String, Object?>{
        'type': 'bill',
        'id': 'b1',
        'title': 'Rent',
        'date': day,
        'endDate': day,
        'amount': 500000,
        'unknownAmount': false,
        'paid': false,
        'overdue': false,
        'accountId': 'a1',
      },
      <String, Object?>{
        'type': 'event',
        'id': 'e1',
        'title': 'Dentist',
        'date': day,
        'endDate': day,
        'startsAt': '${day}T02:00:00.000Z',
        'allDay': false,
        'source': 'botler',
        'untrusted': false,
      },
    ],
    'forecast': <String, Object?>{
      'estimate': true,
      'days': <Object?>[
        <String, Object?>{
          'date': day,
          'total': 900000,
          'lowAccountIds': <Object?>[],
        },
        <String, Object?>{
          'date': dayOf(DateTime.now().add(const Duration(days: 10))),
          'total': 400000,
          'lowAccountIds': <Object?>['a1'],
        },
      ],
      'accounts': <Object?>[
        <String, Object?>{'id': 'a1', 'name': 'Wallet', 'minBalance': 0},
      ],
      'unknownBills': 1,
    },
  };
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  test('reads a range into items and finds a day', () {
    final r = CalRange(answerFor('2026-10-01'));
    expect(r.items.length, 2);
    expect(r.on(firstOfThisMonth()).length, 2);
    expect(r.on('1999-01-01'), isEmpty);
    expect(r.items.first.layer, CalLayer.bills);
    expect(r.unknownBills, 1);
    expect(r.accountNames['a1'], 'Wallet');
  });

  test('the week starts on the chosen weekday', () {
    // 22 October 2026 is a Thursday
    final d = DateTime(2026, 10, 22);
    expect(weekStart(d, 1), DateTime(2026, 10, 19));
    expect(weekStart(d, 0), DateTime(2026, 10, 18));
    expect(weekStart(DateTime(2026, 10, 18), 1), DateTime(2026, 10, 12));
  });

  group('the screen', () {
    Future<void> open(WidgetTester tester, {bool offline = false}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        if (offline) 'calendar.range.v1': savedCopy(),
      });
      final prefs = await SharedPreferences.getInstance();
      final api = ApiClient(
        base: 'https://botler.test',
        token: () async => 'tok',
        client: MockClient((req) async {
          if (offline) throw http.ClientException('offline');
          final body = jsonDecode(req.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'result': answerFor(body['from']! as String),
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final container = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          apiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CalendarScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The screen opens on Week; these tests are about the month grid
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'labels the day in words and says the forecast is an estimate',
      (tester) async {
        await open(tester);
        expect(
          find.bySemanticsLabel(RegExp(r'5 [A-Za-z]+, 1 bill, 1 event')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Estimate'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Estimate'), findsOneWidget);
        expect(find.textContaining('has no amount yet'), findsOneWidget);
      },
    );

    testWidgets('a layer switched off takes its marks away', (tester) async {
      await open(tester);
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'5 [A-Za-z]+, 1 event')),
        findsOneWidget,
      );
    });

    testWidgets('every day cell is at least 48 dp tall', (tester) async {
      await open(tester);
      final cell = find.bySemanticsLabel(RegExp(r'5 [A-Za-z]+, 1 bill'));
      expect(tester.getSize(cell).height, greaterThanOrEqualTo(48));
    });

    testWidgets('says the copy is old when the server cannot be reached', (
      tester,
    ) async {
      await open(tester, offline: true);
      expect(
        find.text('Showing the last calendar this phone saw.'),
        findsOneWidget,
      );
    });
  });
}
