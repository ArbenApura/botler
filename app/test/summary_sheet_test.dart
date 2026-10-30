// THE SUMMARY SHEET (THE WALLET ICON): IT FITS ITS CARD, LOADING OR LOADED, AND DOES NOT OPEN TALL WITH EMPTY SPACE UNDER IT.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/features/chat/summary_card.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

const Map<String, Object?> answer = <String, Object?>{
  'offline': true,
  'summary': <String, Object?>{
    'total': 4781000,
    'nextBill': <String, Object?>{'name': 'Meralco', 'dueDate': '2026-10-25'},
    'firstEventToday': null,
  },
};

Future<void> openSheet(WidgetTester tester, Future<Object?> sync) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // The card reads the net setting, so it needs the stored settings
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        syncProvider.overrideWith(
          (ref) => sync.then((v) => v! as Map<String, Object?>),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSummarySheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 600));
}

double sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(BottomSheet)).height;

void main() {
  testWidgets('loaded, the sheet is as tall as its card and no more', (
    tester,
  ) async {
    await openSheet(tester, Future<Object?>.value(answer));
    await tester.pump(const Duration(milliseconds: 400));
    final card = tester.getSize(find.byType(SummaryCard)).height;
    // The card, the drag handle and the padding: far less than the 733 dp screen
    expect(sheetHeight(tester), lessThan(card + 120));
    expect(find.text('offline'), findsOneWidget);
  });

  testWidgets('loading, the sheet shows a skeleton and is about as tall', (
    tester,
  ) async {
    final never = Completer<Object?>();
    await openSheet(tester, never.future);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Skeleton), findsWidgets);
    final loading = sheetHeight(tester);
    expect(loading, lessThan(400));
  });

  testWidgets('a refresh keeps the last answer on screen, not a skeleton', (
    tester,
  ) async {
    await openSheet(tester, Future<Object?>.value(answer));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Skeleton), findsNothing);
    // Pull to refresh invalidates the provider while the next answer is still on its way
    final element = tester.element(find.byType(SummaryCard));
    final container = ProviderScope.containerOf(element);
    container.invalidate(syncProvider);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('offline'), findsOneWidget);
  });
}
