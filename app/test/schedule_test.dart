// THE SCHEDULE PICKER: EACH PATTERN GIVES THE EXACT SCHEDULE THE SERVER TAKES, IS READ BACK AS A SENTENCE IN BOTH LANGUAGES, AND SHOWS THE NEXT DATES.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/schedule_text.dart';
import 'package:botler/features/money/schedule_picker.dart';
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

AppLocalizations words(String code) => lookupAppLocalizations(Locale(code));

String say(String code, Json schedule) =>
    describeSchedule(words(code), code, schedule) ?? 'UNKNOWN';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('the sentence for a schedule', () {
    test('reads the new patterns in English', () {
      expect(
        say('en', <String, Object?>{
          'kind': 'nth_weekday',
          'n': 1,
          'weekday': 3,
        }),
        'Every 1st Wednesday of the month',
      );
      expect(
        say('en', <String, Object?>{
          'kind': 'nth_weekday',
          'n': -1,
          'weekday': 5,
        }),
        'Every last Friday of the month',
      );
      expect(
        say('en', <String, Object?>{
          'kind': 'week_of_month',
          'n': 1,
          'basis': 'days',
          'pick': 'window',
        }),
        'Any day in the 1st week of the month (days 1 to 7)',
      );
      expect(
        say('en', <String, Object?>{'kind': 'day_range', 'from': 5, 'to': 10}),
        'Any day between the 5th and the 10th',
      );
      expect(
        say('en', <String, Object?>{
          'kind': 'monthly',
          'day': 15,
          'everyMonths': 2,
          'anchorMonth': '2026-10',
        }),
        'On the 15th of the month, every 2 months',
      );
      expect(
        say('en', <String, Object?>{
          'kind': 'weekly',
          'days': <int>[5],
          'everyWeeks': 2,
          'anchor': '2026-10-02',
        }),
        'Every 2 weeks on Friday',
      );
      expect(
        say('en', <String, Object?>{'kind': 'monthly', 'day': 31}),
        'On the 31st of the month',
      );
      expect(
        say('en', <String, Object?>{'kind': 'monthly', 'day': -1}),
        'On the last day of the month',
      );
    });

    test('reads them in Filipino with the Filipino weekday and ordinal', () {
      final out = say('fil', <String, Object?>{
        'kind': 'nth_weekday',
        'n': 1,
        'weekday': 3,
      });
      expect(out, startsWith('Tuwing ika-1 '));
      expect(out, endsWith('ng buwan'));
      expect(out, isNot(contains('Wednesday')));
      expect(
        say('fil', <String, Object?>{'kind': 'monthly', 'day': 5}),
        'Sa ika-5 ng buwan',
      );
    });

    test('says nothing for a kind it does not know', () {
      expect(
        describeSchedule(words('en'), 'en', <String, Object?>{'kind': 'lunar'}),
        isNull,
      );
      expect(
        ScheduleValue.fromJson(<String, Object?>{'kind': 'lunar'}),
        isNull,
      );
    });
  });

  group('the first date, last date and skipped dates', () {
    final saved = <String, Object?>{
      'kind': 'weekly',
      'days': <int>[1],
      'startsOn': '2026-11-09',
      'endsOn': '2026-12-31',
      'skipDates': <String>['2026-11-16'],
    };

    test('survive opening a schedule and saving it again', () {
      expect(ScheduleValue.fromJson(saved)!.toJson(), saved);
    });

    test('are kept when the person picks another pattern', () {
      final v = ScheduleValue.fromJson(saved)!;
      v.pattern = SchedulePattern.monthlyDay;
      v.day = 5;
      expect(v.toJson(), <String, Object?>{
        'kind': 'monthly',
        'day': 5,
        'startsOn': '2026-11-09',
        'endsOn': '2026-12-31',
        'skipDates': <String>['2026-11-16'],
      });
    });

    test('add nothing to a schedule that has none', () {
      expect(
        ScheduleValue.fromJson(<String, Object?>{
          'kind': 'weekly',
          'days': <int>[1],
        })!.toJson(),
        <String, Object?>{
          'kind': 'weekly',
          'days': <int>[1],
        },
      );
    });
  });

  group('what each pattern sends to the server', () {
    test('matches the server shapes exactly', () {
      expect(ScheduleValue(day: 5).toJson(), <String, Object?>{
        'kind': 'monthly',
        'day': 5,
      });
      expect(
        ScheduleValue(
          pattern: SchedulePattern.nthWeekday,
          nth: 1,
          weekday: 3,
        ).toJson(),
        <String, Object?>{'kind': 'nth_weekday', 'n': 1, 'weekday': 3},
      );
      expect(
        ScheduleValue(
          pattern: SchedulePattern.weekOfMonth,
          nth: 1,
          basis: 'days',
          pick: 'window',
        ).toJson(),
        <String, Object?>{
          'kind': 'week_of_month',
          'n': 1,
          'basis': 'days',
          'pick': 'window',
        },
      );
      expect(
        ScheduleValue(
          pattern: SchedulePattern.weekOfMonth,
          nth: 2,
          basis: 'calendar',
          pick: 'weekday',
          weekday: 5,
        ).toJson(),
        <String, Object?>{
          'kind': 'week_of_month',
          'n': 2,
          'basis': 'calendar',
          'pick': 'weekday',
          'weekday': 5,
        },
      );
      expect(
        ScheduleValue(
          pattern: SchedulePattern.dayRange,
          from: 5,
          to: -1,
        ).toJson(),
        <String, Object?>{'kind': 'day_range', 'from': 5, 'to': -1},
      );
      expect(
        ScheduleValue(
          pattern: SchedulePattern.semiMonthly,
          day: 15,
          day2: 30,
        ).toJson(),
        <String, Object?>{
          'kind': 'semi_monthly',
          'days': <int>[15, 30],
        },
      );
      expect(
        ScheduleValue(
          pattern: SchedulePattern.yearly,
          month: 2,
          day: 29,
        ).toJson(),
        <String, Object?>{'kind': 'yearly', 'month': 2, 'day': 29},
      );
    });

    test('a one-time schedule is one date, read back in both languages', () {
      final once = ScheduleValue(
        pattern: SchedulePattern.once,
        anchor: DateTime(2026, 11, 5),
      );
      expect(once.toJson(), <String, Object?>{
        'kind': 'once',
        'date': '2026-11-05',
      });
      expect(once.isSingleDay, true);
      final back = ScheduleValue.fromJson(once.toJson());
      expect(back?.pattern, SchedulePattern.once);
      expect(back?.anchor, DateTime(2026, 11, 5));
      expect(say('en', once.toJson()), 'One time only, on 5 Nov 2026');
      expect(say('fil', once.toJson()), startsWith('Isang beses lang'));
    });

    test('adds the month cycle only when it is more than every month', () {
      final json = ScheduleValue(day: 15, everyMonths: 3).toJson();
      expect(json['everyMonths'], 3);
      expect(json['anchorMonth'], matches(RegExp(r'^\d{4}-\d{2}$')));
      expect(ScheduleValue(day: 15).toJson().containsKey('everyMonths'), false);
    });

    test('knows a window from a single day', () {
      expect(ScheduleValue().isSingleDay, true);
      expect(
        ScheduleValue(pattern: SchedulePattern.dayRange).isSingleDay,
        false,
      );
      expect(
        ScheduleValue(
          pattern: SchedulePattern.weekOfMonth,
          pick: 'weekday',
        ).isSingleDay,
        true,
      );
      expect(
        isWindowSchedule(<String, Object?>{
          'kind': 'day_range',
          'from': 5,
          'to': 9,
        }),
        true,
      );
    });

    test('opens a saved schedule for editing and sends the same one back', () {
      final saved = <String, Object?>{
        'kind': 'week_of_month',
        'n': 1,
        'basis': 'calendar',
        'pick': 'weekday',
        'weekday': 3,
        'everyMonths': 2,
        'anchorMonth': '2026-10',
      };
      final back = ScheduleValue.fromJson(saved)!.toJson();
      expect(back['kind'], 'week_of_month');
      expect(back['n'], 1);
      expect(back['basis'], 'calendar');
      expect(back['weekday'], 3);
      expect(back['everyMonths'], 2);
    });
  });

  group('the picker on screen', () {
    Future<ProviderContainer> start(
      WidgetTester tester,
      ScheduleValue value, {
      bool offline = false,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final api = ApiClient(
        base: 'https://botler.test',
        token: () async => 'tok',
        client: MockClient((req) async {
          if (offline) throw http.ClientException('offline');
          return http.Response(
            jsonEncode(<String, Object?>{
              'result': <String, Object?>{
                'text': 'ignored',
                'windows': <Object?>[
                  <String, Object?>{'start': '2026-11-04', 'end': '2026-11-04'},
                  <String, Object?>{'start': '2026-12-01', 'end': '2026-12-07'},
                ],
              },
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
            home: Scaffold(
              body: SingleChildScrollView(
                child: SchedulePicker(value: value, onChanged: () {}),
              ),
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('reads the choice back and lists the next windows', (
      tester,
    ) async {
      await start(
        tester,
        ScheduleValue(pattern: SchedulePattern.nthWeekday, nth: 1, weekday: 3),
      );
      expect(find.text('Every 1st Wednesday of the month'), findsOneWidget);
      // The preview waits a moment after the last change, then asks the server
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Wed, 4 Nov'), findsOneWidget);
      expect(find.text('Tue, 1 Dec to Mon, 7 Dec'), findsOneWidget);
    });

    testWidgets('says plainly when the dates cannot be fetched', (
      tester,
    ) async {
      await start(tester, ScheduleValue(day: 5), offline: true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        find.text('Connect to the internet to see the next dates.'),
        findsOneWidget,
      );
      expect(find.text('On the 5th of the month'), findsOneWidget);
    });

    testWidgets('every control is at least 48 dp tall', (tester) async {
      await start(tester, ScheduleValue(day: 5));
      await tester.pump(const Duration(milliseconds: 500));
      for (final f in find.byType(DropdownButtonFormField<int>).evaluate()) {
        expect(
          tester.getSize(find.byWidget(f.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
    });
  });
}
