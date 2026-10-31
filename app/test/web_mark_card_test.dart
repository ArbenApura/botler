// THE APPROVAL CARD OF "FIND A LOGO ON THE WEB" (BTL-20261031-1334): THE PHONE DOWNLOADS THE CANDIDATES, SHOWS THEM, AND SENDS THE PICKED PICTURE WITH THE APPROVAL

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:botler/core/api.dart';
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

Uint8List logo(int size) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillCircle(
    image,
    x: size ~/ 2,
    y: size ~/ 2,
    radius: size ~/ 5,
    color: img.ColorRgb8(200, 0, 0),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Future<List<InternetAddress>> publicHost(String host) async =>
    <InternetAddress>[InternetAddress('93.184.216.34')];

class Rig {
  Rig(this.container, this.posts);

  final ProviderContainer container;
  final List<Json> posts;
}

Future<Rig> rig({required bool found}) async {
  final posts = <Json>[];
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final api = MockClient.streaming((req, stream) async {
    final body = await http.ByteStream(stream).bytesToString();
    if (req.method == 'GET' && req.url.path == '/api/v1/agent/actions') {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'actions': <Object?>[
                <String, Object?>{
                  'id': 'act-1',
                  'verb': 'mark_from_web',
                  'args': <String, Object?>{
                    'target': 'account',
                    'name': 'RCBC',
                    'domain': 'rcbc.com',
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
  final web = MockClient((r) async {
    if (!found) return http.Response('no', 404);
    if (r.url.path == '/') {
      return http.Response(
        '<link rel="apple-touch-icon" href="/big.png"><link rel="icon" href="/small.png">',
        200,
      );
    }
    if (r.url.path == '/big.png') {
      return http.Response.bytes(logo(256), 200);
    }
    if (r.url.path == '/small.png') {
      return http.Response.bytes(logo(128), 200);
    }
    return http.Response('no', 404);
  });
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      webClientProvider.overrideWithValue(web),
      webResolverProvider.overrideWithValue(publicHost),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: api,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return Rig(c, posts);
}

Future<void> mount(WidgetTester tester, Rig r) async {
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
                summary: 'Find a logo for the account "RCBC".',
                verb: 'mark_from_web',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('shows the candidates and approving sends the picked picture', (
    tester,
  ) async {
    final r = await tester.runAsync(() => rig(found: true));
    await mount(tester, r!);
    await settle(tester);
    expect(find.text('Use this picture'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    // Two different pictures were found: both can be picked
    expect(find.bySemanticsLabel('Logo option 2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Logo option 2'));
    await settle(tester);
    await tester.tap(find.text('Use this picture'));
    await settle(tester);
    expect(r.posts, hasLength(1));
    expect(r.posts.single['decision'], 'approve');
    final sent = base64Decode(r.posts.single['imageData'] as String);
    expect(sent.length, lessThanOrEqualTo(markMaxBytes));
    final image = img.decodeJpg(sent)!;
    // A small candidate is not enlarged: the result is square and never above the mark size
    expect(image.width, image.height);
    expect(image.width, lessThanOrEqualTo(markEdge));
  });

  testWidgets('says so when no logo could be loaded, and offers only Not now', (
    tester,
  ) async {
    final r = await tester.runAsync(() => rig(found: false));
    await mount(tester, r!);
    await settle(tester);
    expect(find.textContaining('could not load a usable logo'), findsOneWidget);
    expect(find.text('Use this picture'), findsNothing);
    expect(find.text('Not now'), findsOneWidget);
  });
}
