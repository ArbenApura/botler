// THE DATE AND TIME SECTION OF SETTINGS: IT SHOWS THE ZONE AND THE CHOICES, AND A CHOICE IS SAVED THROUGH THE SCREEN'S OWN SAVE.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// -- MODULES -- //
import 'package:botler/core/clock.dart';
import 'package:botler/features/settings/date_time_rows.dart';
import 'package:botler/l10n/app_localizations.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';

// -- FUNCTIONS -- //

Future<List<Map<String, Object?>>> show(
  WidgetTester tester,
  Settings settings,
) async {
  final saved = <Map<String, Object?>>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DateTimeRows(
            settings: settings,
            onSave: ({timeZone, timeFormat, dateStyle, weekStartsOn}) async {
              saved.add(<String, Object?>{
                'timeZone': ?timeZone,
                'timeFormat': ?timeFormat,
                'dateStyle': ?dateStyle,
                'weekStartsOn': ?weekStartsOn,
              });
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fil');
  });

  setUp(() {
    ensureTimeZones();
    clockPrefs = const ClockPrefs();
  });

  testWidgets('shows the zone and saves a choice of clock and date order', (
    tester,
  ) async {
    clockPrefs = const ClockPrefs(zone: 'Asia/Tokyo', timeFormat: '24');
    final saved = await show(
      tester,
      const Settings(timeZone: 'Asia/Tokyo', timeFormat: '24'),
    );
    expect(find.text('Tokyo · Asia'), findsOneWidget);
    expect(find.text('UTC+9'), findsOneWidget);
    expect(find.textContaining('Now:'), findsOneWidget);

    await tester.tap(find.text('12 hour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Y M D'));
    await tester.pumpAndSettle();
    expect(saved, <Map<String, Object?>>[
      <String, Object?>{'timeFormat': '12'},
      <String, Object?>{'dateStyle': 'ymd'},
    ]);
  });

  testWidgets('searches the zone list and returns the zone chosen', (
    tester,
  ) async {
    final saved = await show(tester, const Settings());
    await tester.tap(find.text('Manila · Asia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tokyo');
    await tester.pumpAndSettle();
    expect(find.text('Tokyo · Asia'), findsOneWidget);
    expect(find.text('Singapore · Asia'), findsNothing);
    await tester.tap(find.text('Tokyo · Asia'));
    await tester.pumpAndSettle();
    expect(saved, <Map<String, Object?>>[
      <String, Object?>{'timeZone': 'Asia/Tokyo'},
    ]);
  });

  testWidgets('says so when no zone matches the search', (tester) async {
    await show(tester, const Settings());
    await tester.tap(find.text('Manila · Asia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    expect(find.text('No time zone matches that.'), findsOneWidget);
  });
}
