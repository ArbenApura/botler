// THE PICTURES IN THE CHAT: THE STRIP BEFORE SENDING (TILES, SPINNER WHILE READING, REMOVE, OPEN) AND THE GRID UNDER A SENT MESSAGE.

// -- DEP-MODULES -- //
import 'package:botler/features/chat/photo_widgets.dart';
import 'package:botler/l10n/app_localizations.dart';
import 'package:botler/theme/tokens.dart';
import 'package:botler/ui/photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[lightColors]),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 320, child: child),
      ),
    ),
  ),
);

void main() {
  const paths = <String>['/nope/a.jpg', '/nope/b.jpg', '/nope/c.jpg'];

  group('PhotoStrip', () {
    testWidgets('shows a tile for each photo, a spinner while one is read', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          PhotoStrip(
            photos: const <StripPhoto>[
              StripPhoto('/nope/a.jpg', 120),
              StripPhoto('/nope/b.jpg', null),
            ],
            onRemove: (_) {},
          ),
        ),
      );
      expect(find.byType(PhotoThumb), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The number of characters read is not shown
      expect(find.text('120'), findsNothing);
    });

    testWidgets(
      'remove reports the tile, its target is at least 48 dp, and opening goes to the viewer',
      (tester) async {
        final handle = tester.ensureSemantics();
        final removed = <int>[];
        await tester.pumpWidget(
          _app(
            PhotoStrip(
              photos: const <StripPhoto>[
                StripPhoto('/nope/a.jpg', 5),
                StripPhoto('/nope/b.jpg', 6),
              ],
              onRemove: removed.add,
            ),
          ),
        );
        final remove = find.bySemanticsLabel('Remove photo 2');
        expect(remove, findsOneWidget);
        final box = tester.getSize(
          find.ancestor(of: remove, matching: find.byType(Positioned)).first,
        );
        expect(box.width, greaterThanOrEqualTo(48));
        expect(box.height, greaterThanOrEqualTo(48));
        await tester.tap(remove);
        expect(removed, <int>[1]);
        // The tile's own corner holds the remove target, so open it from its lower left
        final tile = tester.getTopLeft(
          find.bySemanticsLabel('Open photo 1 of 2'),
        );
        await tester.tapAt(tile + const Offset(10, 50));
        await tester.pumpAndSettle();
        expect(find.byType(PhotoViewer), findsOneWidget);
        expect(find.text('1 of 2'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('keeps one height whatever it holds and at any text size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          PhotoStrip(
            photos: const <StripPhoto>[StripPhoto('/nope/a.jpg', 5)],
            onRemove: (_) {},
          ),
        ),
      );
      final one = tester.getSize(find.byType(PhotoStrip)).height;
      await tester.pumpWidget(
        _app(
          PhotoStrip(
            photos: const <StripPhoto>[
              StripPhoto('/nope/a.jpg', 5),
              StripPhoto('/nope/b.jpg', null),
              StripPhoto('/nope/c.jpg', 77777),
            ],
            onRemove: (_) {},
          ),
        ),
      );
      expect(tester.getSize(find.byType(PhotoStrip)).height, one);
      await tester.pumpWidget(
        _app(
          PhotoStrip(
            photos: const <StripPhoto>[StripPhoto('/nope/a.jpg', 5)],
            onRemove: (_) {},
          ),
          textScale: 2,
        ),
      );
      expect(tester.getSize(find.byType(PhotoStrip)).height, one);
      expect(tester.takeException(), isNull);
    });
  });

  group('PhotoGrid', () {
    testWidgets('one photo is a wide tile', (tester) async {
      await tester.pumpWidget(
        _app(const PhotoGrid(paths: <String>['/nope/a.jpg'])),
      );
      expect(find.byType(PhotoThumb), findsOneWidget);
      final size = tester.getSize(find.byType(PhotoThumb));
      expect(size.width / size.height, closeTo(4 / 3, 0.05));
    });

    testWidgets('several photos are two columns of squares', (tester) async {
      await tester.pumpWidget(_app(const PhotoGrid(paths: paths)));
      expect(find.byType(PhotoThumb), findsNWidgets(3));
      final a = tester.getTopLeft(find.byType(PhotoThumb).at(0));
      final b = tester.getTopLeft(find.byType(PhotoThumb).at(1));
      final c = tester.getTopLeft(find.byType(PhotoThumb).at(2));
      expect(a.dy, b.dy);
      expect(c.dy, greaterThan(a.dy));
      final s = tester.getSize(find.byType(PhotoThumb).first);
      expect(s.width, closeTo(s.height, 0.5));
    });

    testWidgets('tapping a tile opens the viewer at that photo', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const PhotoGrid(paths: paths)));
      await tester.tap(find.byType(PhotoThumb).at(1));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('a file that is gone shows a quiet tile, not an error', (
      tester,
    ) async {
      // Its own path: the image cache would hand this tile a stream another test already used
      await tester.pumpWidget(
        _app(const PhotoGrid(paths: <String>['/nope/only-here.jpg'])),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
