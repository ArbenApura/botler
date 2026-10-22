// THE LOADING LOOK: NO SPINNER, ONE "LOADING" LABEL FOR A SCREEN READER, AND NO PULSE WHEN ANIMATIONS ARE REMOVED.
// The pulse never settles, so these tests pump for a fixed time and never call pumpAndSettle.

// -- DEP-MODULES -- //
import 'package:botler/l10n/l10n.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Widget host(Widget child, {bool still = false}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildTheme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(body: child),
  ),
);

double opacityOf(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(Skeleton),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  testWidgets('a loading list shows blocks and never a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SkeletonRows(count: 4)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Skeleton), findsWidgets);
  });

  testWidgets('every shape builds', (tester) async {
    for (final kind in SkeletonKind.values) {
      await tester.pumpWidget(host(SkeletonRows(kind: kind)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a screen reader hears one Loading, not one per block', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const SkeletonRows(count: 5)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the blocks pulse, and stand still without animations', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SkeletonRows()));
    await tester.pump(const Duration(milliseconds: 100));
    final early = opacityOf(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacityOf(tester), isNot(early));

    await tester.pumpWidget(host(const SkeletonRows(), still: true));
    await tester.pump(const Duration(milliseconds: 100));
    final first = opacityOf(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacityOf(tester), first);
    // Nothing is left animating, so a settle would end at once
    await tester.pumpAndSettle();
  });
}
