// THE APPROVAL CARD OF "USE THIS PHOTO AS THE PICTURE" (BTL-20261031-1011): THE PHONE CUTS ITS OWN COPY, SHOWS IT, AND SENDS THE SMALL PICTURE WITH THE APPROVAL

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:botler/core/api.dart';
import 'package:botler/core/chat_photos.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/marks.dart';
import 'package:botler/features/chat/chat_items.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

Uint8List photo() {
  final image = img.Image(width: 400, height: 200);
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 199,
    y2: 199,
    color: img.ColorRgb8(255, 0, 0),
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// What the phone and the stand-in server did.
class Rig {
  Rig(this.container, this.posts);

  final ProviderContainer container;
  final List<Json> posts;
}

Future<Rig> rig(
  WidgetTester tester, {
  required bool keepPhoto,
  Json? card,
  Uint8List? photoBytes,
  Duration postDelay = Duration.zero,
}) async {
  final posts = <Json>[];
  final dir = await Directory.systemTemp.createTemp('photo_mark_card');
  addTearDown(() => dir.delete(recursive: true));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final store = ChatPhotoStore(
    prefs: prefs,
    owner: 'a@b.c',
    baseDir: () async => dir,
  );
  if (keepPhoto) {
    final source = File('${dir.path}${Platform.pathSeparator}source.png')
      ..writeAsBytesSync(photoBytes ?? photo());
    final staged = await store.stage(source.path);
    await store.promote('turn-1', <String>[staged!]);
  }
  final client = MockClient.streaming((req, stream) async {
    final body = await http.ByteStream(stream).bytesToString();
    if (req.method == 'GET' && req.url.path == '/api/v1/agent/actions') {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'actions': <Object?>[
                card ??
                    <String, Object?>{
                      'id': 'act-1',
                      'verb': 'mark_from_photo',
                      'args': <String, Object?>{
                        'target': 'account',
                        'name': 'GCash',
                        'photo': 1,
                        'x': 0,
                        'y': 0,
                        'width': 0.5,
                        'height': 1,
                      },
                    },
              ],
            }),
          ),
        ),
        200,
      );
    }
    posts.add(decodeJson(body));
    if (postDelay > Duration.zero) await Future<void>.delayed(postDelay);
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'action': <String, Object?>{'status': 'applied'},
          }),
        ),
      ),
      200,
    );
  });
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      chatPhotoStoreProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: client,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return Rig(c, posts);
}

Future<void> mount(
  WidgetTester tester,
  Rig r, {
  String? turnId,
  String? verb = 'mark_from_photo',
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: r.container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatItemView(
              CardItem(
                1,
                actionId: 'act-1',
                summary: 'Use photo 1 of your message as the picture.',
                turnId: turnId,
                verb: verb,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Lets the isolate that cuts the photo and the stand-in server finish, which the test clock does not.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'shows the cut, and approving sends the small picture with the approval',
    (tester) async {
      final r = await tester.runAsync(() => rig(tester, keepPhoto: true));
      await mount(tester, r!, turnId: 'turn-1');
      await settle(tester);
      expect(find.text('Use this picture'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.text('Use this picture'));
      await settle(tester);
      expect(r.posts, hasLength(1));
      expect(r.posts.single['decision'], 'approve');
      final sent = base64Decode(r.posts.single['imageData'] as String);
      expect(sent.length, lessThanOrEqualTo(markMaxBytes));
      final image = img.decodeJpg(sent)!;
      expect((image.width, image.height), (markEdge, markEdge));
      // The left half of the photo was red
      expect(image.getPixel(markEdge ~/ 2, markEdge ~/ 2).r, greaterThan(180));
    },
  );

  testWidgets('zooming and moving cut again, and the nudges can be tapped', (
    tester,
  ) async {
    final r = await tester.runAsync(() => rig(tester, keepPhoto: true));
    await mount(tester, r!, turnId: 'turn-1');
    await settle(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await settle(tester);
    await tester.tap(find.byTooltip('Move right'));
    await settle(tester);
    await tester.tap(find.text('Whole'));
    await settle(tester);
    await tester.tap(find.text('Use this picture'));
    await settle(tester);
    expect(r.posts.single['decision'], 'approve');
    expect(r.posts.single['imageData'], isA<String>());
  });

  testWidgets(
    'says so when the photo is no longer on this phone, and offers only to dismiss',
    (tester) async {
      final r = await tester.runAsync(() => rig(tester, keepPhoto: false));
      await mount(tester, r!, turnId: 'turn-1');
      await settle(tester);
      expect(find.textContaining('no longer on this phone'), findsOneWidget);
      expect(find.text('Use this picture'), findsNothing);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(r.posts.single['decision'], 'reject');
      expect(r.posts.single.containsKey('imageData'), isFalse);
    },
  );

  testWidgets(
    'a second tap on "Use this picture" sends one approval, not two',
    (tester) async {
      // The answer is slow, so the second tap lands while the first is still being answered
      final r = await tester.runAsync(
        () => rig(
          tester,
          keepPhoto: true,
          postDelay: const Duration(milliseconds: 800),
        ),
      );
      await mount(tester, r!, turnId: 'turn-1');
      await settle(tester);
      await tester.tap(find.text('Use this picture'));
      await tester.tap(find.text('Use this picture'), warnIfMissed: false);
      await settle(tester);
      expect(r.posts, hasLength(1));
    },
  );

  testWidgets('a file that is not a picture says so and cannot be approved', (
    tester,
  ) async {
    final r = await tester.runAsync(
      () => rig(
        tester,
        keepPhoto: true,
        photoBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      ),
    );
    await mount(tester, r!, turnId: 'turn-1');
    await settle(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use this picture'),
    );
    expect(button.onPressed, isNull);
    expect(r.posts, isEmpty);
  });

  testWidgets('a cut over the size limit cannot be approved', (tester) async {
    final noise = img.Image(width: 192, height: 192);
    var v = 7;
    for (final p in noise) {
      v = (v * 1103515245 + 12345) & 0x7fffffff;
      p
        ..r = v & 255
        ..g = (v >> 8) & 255
        ..b = (v >> 16) & 255;
    }
    final r = await tester.runAsync(
      () => rig(
        tester,
        keepPhoto: true,
        card: <String, Object?>{
          'id': 'act-1',
          'verb': 'mark_from_photo',
          'args': <String, Object?>{
            'target': 'account',
            'name': 'GCash',
            'photo': 1,
            'x': 0,
            'y': 0,
            'width': 1,
            'height': 1,
          },
        },
        photoBytes: Uint8List.fromList(img.encodePng(noise)),
      ),
    );
    await mount(tester, r!, turnId: 'turn-1');
    await settle(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use this picture'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'a photo card whose plan did not load never shows a plain Approve',
    (tester) async {
      final r = await tester.runAsync(
        () => rig(
          tester,
          keepPhoto: true,
          card: <String, Object?>{
            'id': 'someone-else',
            'verb': 'mark_from_photo',
            'args': <String, Object?>{},
          },
        ),
      );
      await mount(tester, r!, turnId: 'turn-1');
      await settle(tester);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Use this picture'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    },
  );

  testWidgets('any other card keeps its plain buttons', (tester) async {
    final r = await tester.runAsync(
      () => rig(
        tester,
        keepPhoto: false,
        card: <String, Object?>{
          'id': 'act-1',
          'verb': 'account_create',
          'args': <String, Object?>{'name': 'BPI', 'kind': 'bank'},
        },
      ),
    );
    await mount(tester, r!, turnId: 'turn-1', verb: null);
    await settle(tester);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await settle(tester);
    expect(r.posts.single['decision'], 'approve');
    expect(r.posts.single.containsKey('imageData'), isFalse);
  });
}
