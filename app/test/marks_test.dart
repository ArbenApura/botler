// THE MARK OF AN ACCOUNT OR A BILL: WHAT IS SENT TO CHANGE IT, THE SMALL PICTURE THE PHONE MAKES, THE PICTURE CACHE, THE BADGE AND THE PICKER.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// -- MODULES -- //
import 'package:botler/core/api.dart';
import 'package:botler/core/auth.dart';
import 'package:botler/core/marks.dart';
import 'package:botler/features/money/mark_picker.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/marks.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/mark_badge.dart';

// -- TYPES -- //

/// A session that can change hands in the middle of a test.
class _Who extends SessionNotifier {
  @override
  Future<Session?> build() async =>
      const Session(token: 't', email: 'a@b.test', name: 'A');

  void signInAs(String? email) {
    state = AsyncData<Session?>(
      email == null ? null : Session(token: 't', email: email, name: 'B'),
    );
  }
}

// -- FUNCTIONS -- //

Widget host(Widget child, {List<Override> overrides = const <Override>[]}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

/// A picture of the given size, as the bytes of a PNG.
Uint8List png(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(90, 140, 100));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('the icon list', () {
    test('every icon of the server has a glyph here, and no other', () {
      final text = File('../server/src/lib/finance/visual.ts')
          .readAsStringSync();
      final block = RegExp(
        r'ICON_KEYS = \[(.*?)\] as const',
        dotAll: true,
      ).firstMatch(text)!.group(1)!;
      final server = RegExp(r"'([a-z]+)'")
          .allMatches(block)
          .map((m) => m.group(1)!)
          .toList();
      expect(kIconKeys, server);
      for (final key in kIconKeys) {
        expect(Mark(icon: key).iconData, isNotNull, reason: key);
      }
    });

    test('an icon this app does not know shows nothing, not a crash', () {
      expect(const Mark(icon: 'future-icon').iconData, isNull);
      expect(const Mark(icon: 'future-icon').isEmpty, isTrue);
    });
  });

  group('markOf and markArgs', () {
    test('reads a row, and an older server sends neither key', () {
      expect(markOf(<String, Object?>{'icon': 'bank'}).icon, 'bank');
      expect(markOf(<String, Object?>{'imageId': 'p1'}).imageId, 'p1');
      expect(
        markOf(<String, Object?>{'icon': null, 'imageId': ''}).isEmpty,
        isTrue,
      );
      expect(markOf(null).isEmpty, isTrue);
      expect(markOf(<String, Object?>{'name': 'GCash'}).isEmpty, isTrue);
    });

    test('a bill with no mark of its own shows its account\'s', () {
      final accounts = <String, Mark>{'a1': const Mark(icon: 'wallet')};
      expect(
        billMarkOf(<String, Object?>{'accountId': 'a1'}, accounts).icon,
        'wallet',
      );
      expect(
        billMarkOf(<String, Object?>{
          'accountId': 'a1',
          'icon': 'bolt',
        }, accounts).icon,
        'bolt',
      );
      expect(
        billMarkOf(<String, Object?>{'accountId': 'zz'}, accounts).isEmpty,
        isTrue,
      );
    });

    test('only what changes is sent', () {
      const none = Mark();
      expect(markArgs(const MarkChoice.unchanged(), none), isEmpty);
      expect(markArgs(const MarkChoice.icon('cart'), none), <String, Object?>{
        'icon': 'cart',
      });
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(markArgs(MarkChoice.picture(bytes), none), <String, Object?>{
        'imageData': base64Encode(bytes),
      });
    });

    test('removing clears whatever is there and nothing else', () {
      expect(markArgs(const MarkChoice.none(), const Mark()), isEmpty);
      expect(
        markArgs(const MarkChoice.none(), const Mark(icon: 'bank')),
        <String, Object?>{'icon': null},
      );
      expect(
        markArgs(const MarkChoice.none(), const Mark(imageId: 'p1')),
        <String, Object?>{'clearImage': true},
      );
    });
  });

  group('the small picture', () {
    test('is a square under the size the server accepts', () {
      final out = encodeMarkPicture(png(640, 480));
      expect(out, isNotNull);
      expect(out!.length, lessThanOrEqualTo(markMaxBytes));
      final back = img.decodeJpg(out)!;
      expect(back.width, markEdge);
      expect(back.height, markEdge);
    });

    test('a picture smaller than the square is not blown up', () {
      final back = img.decodeJpg(encodeMarkPicture(png(60, 100))!)!;
      expect(back.width, 60);
      expect(back.height, 60);
    });

    test('bytes that are not a picture give nothing', () {
      expect(encodeMarkPicture(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    });
  });

  group('the picture cache', () {
    test('fetches an id once however many rows ask, and keeps it', () async {
      var calls = 0;
      final images = MarkImages((id) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return <String, Object?>{
          'id': id,
          'mime': 'image/png',
          'data': base64Encode(<int>[7, 8, 9]),
        };
      });
      final results = await Future.wait(<Future<Uint8List?>>[
        images.load('p1'),
        images.load('p1'),
      ]);
      expect(results.first, <int>[7, 8, 9]);
      expect(calls, 1);
      expect(images.peek('p1'), <int>[7, 8, 9]);
      await images.load('p1');
      expect(calls, 1);
    });

    test('a failed fetch gives nothing and the next ask tries again', () async {
      var calls = 0;
      final images = MarkImages((id) async {
        calls++;
        throw const ApiException('NETWORK', 'No connection.', 0);
      });
      expect(await images.load('p1'), isNull);
      expect(await images.load('p1'), isNull);
      expect(calls, 2);
    });
  });

  group('the cache of a person', () {
    test('a new person gets a new cache, the same person keeps theirs', () {
      final notifier = _Who();
      final container = ProviderContainer(
        overrides: <Override>[
          sessionProvider.overrideWith(() => notifier),
          apiProvider.overrideWithValue(
            ApiClient(base: 'https://botler.test', token: () async => 't'),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider);
      final first = container.read(markImagesProvider);
      expect(container.read(markImagesProvider), same(first));
      notifier.signInAs('b@b.test');
      final other = container.read(markImagesProvider);
      expect(other, isNot(same(first)));
      notifier.signInAs(null);
      expect(container.read(markImagesProvider), isNot(same(other)));
    });
  });

  group('the badge', () {
    testWidgets('shows the first letter when there is no mark', (tester) async {
      await tester.pumpWidget(host(const MarkBadge(name: 'gcash')));
      expect(find.text('G'), findsOneWidget);
    });

    testWidgets('shows the icon and says whose it is', (tester) async {
      await tester.pumpWidget(
        host(
          const MarkBadge(
            name: 'RCBC',
            mark: Mark(icon: 'bank'),
            announce: true,
          ),
        ),
      );
      expect(find.byIcon(Icons.account_balance), findsOneWidget);
      expect(find.bySemanticsLabel('Icon of RCBC'), findsOneWidget);
    });

    testWidgets('is silent by default, the name beside it is read', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const MarkBadge(
            name: 'RCBC',
            mark: Mark(icon: 'bank'),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Icon of RCBC'), findsNothing);
    });

    testWidgets('shows a stored picture once it is fetched', (tester) async {
      final bytes = png(8, 8);
      final images = MarkImages(
        (id) async => <String, Object?>{'data': base64Encode(bytes)},
      );
      await tester.pumpWidget(
        host(
          const MarkBadge(
            name: 'Rent',
            mark: Mark(imageId: 'p1'),
          ),
          overrides: <Override>[markImagesProvider.overrideWithValue(images)],
        ),
      );
      // Until the picture arrives the letter stands in
      expect(find.text('R'), findsOneWidget);
      await tester.runAsync(() => images.load('p1'));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('the picker', () {
    testWidgets('choosing an icon reports it, and remove reports none', (
      tester,
    ) async {
      MarkChoice? latest;
      await tester.pumpWidget(
        host(
          MarkField(
            name: 'RCBC',
            current: const Mark(icon: 'bank'),
            onChanged: (c) => latest = c,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Icon: Groceries'));
      await tester.pump();
      expect(latest?.kind, MarkKind.icon);
      expect(latest?.icon, 'cart');
      await tester.tap(find.text('Remove icon or picture'));
      await tester.pump();
      expect(latest?.kind, MarkKind.none);
    });

    testWidgets('every icon tile is a 48 dp target', (tester) async {
      await tester.pumpWidget(
        host(MarkField(name: 'RCBC', current: const Mark(), onChanged: (_) {})),
      );
      final tile = tester.getSize(find.bySemanticsLabel('Icon: Bank'));
      expect(tile.width, greaterThanOrEqualTo(48));
      expect(tile.height, greaterThanOrEqualTo(48));
    });
  });
}
