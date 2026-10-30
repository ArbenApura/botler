// THE PHOTO VIEWER: OPENS AT THE PHOTO TAPPED, SWIPES BETWEEN PHOTOS, ZOOMS BY DOUBLE TAP, LOCKS PAGING WHILE ZOOMED, CLOSES, AND SAYS WHEN A FILE IS GONE.

// -- DEP-MODULES -- //
import 'package:botler/l10n/l10n.dart';
import 'package:botler/theme/tokens.dart';
import 'package:botler/ui/photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botler/l10n/app_localizations.dart';

// -- FUNCTIONS -- //

Widget _app(List<String> paths, {int initial = 0}) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[lightColors]),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () =>
              showPhotoViewer(context, paths: paths, initial: initial),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

double _scale(WidgetTester tester) {
  final iv = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer).first,
  );
  return iv.transformationController!.value.getMaxScaleOnAxis();
}

void main() {
  const paths = <String>['/nope/a.jpg', '/nope/b.jpg', '/nope/c.jpg'];

  testWidgets('opens at the chosen photo and shows its place', (tester) async {
    await tester.pumpWidget(_app(paths, initial: 1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    // The files do not exist, so the page says so instead of crashing (the failed read finishes outside the fake clock)
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('This photo is no longer on this phone.'), findsOneWidget);
  });

  testWidgets('swiping sideways moves to the next photo', (tester) async {
    await tester.pumpWidget(_app(paths));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('double tap zooms in, locks paging, and zooms back out', (
    tester,
  ) async {
    await tester.pumpWidget(_app(paths));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    final centre = tester.getCenter(find.byType(PageView));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(_scale(tester), closeTo(photoDoubleTapScale, 0.01));
    // Zoomed: a sideways drag does not turn the page
    final physics = tester.widget<PageView>(find.byType(PageView)).physics;
    expect(physics, isA<NeverScrollableScrollPhysics>());
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<PageScrollPhysics>(),
    );
  });

  testWidgets('the close button closes it', (tester) async {
    await tester.pumpWidget(_app(paths));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('a long swipe down closes it, a short one does not', (
    tester,
  ) async {
    await tester.pumpWidget(_app(paths));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('a single photo shows no counter', (tester) async {
    await tester.pumpWidget(_app(<String>['/nope/a.jpg']));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' of '), findsNothing);
  });

  test('zoomAbout keeps the tapped point still and stays inside the edges', () {
    const size = Size(400, 800);
    final m = zoomAbout(const Offset(200, 400), 2.5, size);
    final p = MatrixUtils.transformPoint(m, const Offset(200, 400));
    expect(p.dx, closeTo(200, 0.01));
    expect(p.dy, closeTo(400, 0.01));
    // A tap in the corner cannot pull empty space into view
    final corner = zoomAbout(Offset.zero, 2.5, size);
    expect(MatrixUtils.transformPoint(corner, Offset.zero), Offset.zero);
    final far = zoomAbout(const Offset(400, 800), 2.5, size);
    final end = MatrixUtils.transformPoint(far, const Offset(400, 800));
    expect(end.dx, closeTo(400, 0.01));
  });
}
