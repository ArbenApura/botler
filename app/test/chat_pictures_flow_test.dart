// A MESSAGE WITH PICTURES ON THE WIRE: THE PICTURES GO BESIDE THE TEXT ONLY WHEN SENT, NEVER WHEN NOT, A REFUSAL SENDS THE MESSAGE AGAIN ON ITS TEXT, AND A
// SERVER THAT DID NOT USE THEM IS TOLD TO THE PERSON

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

/// A chat server that records every message body and answers from a list of scripted replies.
class PicServer {
  PicServer(this.replies);

  /// What each chat request gets: a list of events to stream, or null for a refusal (400 INVALID).
  final List<List<Json>?> replies;
  final List<Json> bodies = <Json>[];

  MockClient get client => MockClient.streaming((req, body) async {
    final text = await http.ByteStream(body).bytesToString();
    if (!req.url.path.contains('/agent/chat')) {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{'result': <String, Object?>{}}),
          ),
        ),
        200,
      );
    }
    bodies.add(decodeJson(text));
    final reply = bodies.length <= replies.length
        ? replies[bodies.length - 1]
        : null;
    if (reply == null) {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'INVALID',
                'message': 'The request is not valid.',
              },
            }),
          ),
        ),
        400,
      );
    }
    final lines = reply.map((e) => 'data: ${jsonEncode(e)}\n\n').join();
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(lines)),
      200,
    );
  });
}

// -- FUNCTIONS -- //

const List<Json> okTurn = <Json>[
  <String, Object?>{'type': 'start', 'turnId': 't-1', 'chatId': 'c-1'},
  <String, Object?>{'type': 'delta', 'text': 'I see it.'},
  <String, Object?>{
    'type': 'done',
    'reply': 'I see it.',
    'toolsRun': <String>[],
  },
];

Future<ProviderContainer> containerFor(PicServer s) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: s.client,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

List<String> notices(ProviderContainer c) => c
    .read(chatProvider)
    .items
    .whereType<NoticeItem>()
    .map((n) => n.text)
    .toList();

void main() {
  test('a message with pictures sends them beside the text, as JPEG', () async {
    final s = PicServer(<List<Json>?>[okTurn]);
    final c = await containerFor(s);
    await c
        .read(chatProvider.notifier)
        .send(
          'what is this',
          photoTexts: <String>['total 120'],
          images: <String>['QUJD'],
        );
    final body = s.bodies.single;
    expect(body['ocrTexts'], <String>['total 120']);
    expect(body['images'], <Object?>[
      <String, Object?>{'mediaType': 'image/jpeg', 'data': 'QUJD'},
    ]);
  });

  test('a message without pictures has no images key at all, so an older server is never asked about them', () async {
    final s = PicServer(<List<Json>?>[okTurn]);
    final c = await containerFor(s);
    await c.read(chatProvider.notifier).send('hello');
    expect(s.bodies.single.containsKey('images'), isFalse);
  });

  test('a refusal with pictures in it sends the same message again without them and says so', () async {
    final s = PicServer(<List<Json>?>[null, okTurn]);
    final c = await containerFor(s);
    await c
        .read(chatProvider.notifier)
        .send(
          'what is this',
          photoTexts: <String>['total 120'],
          images: <String>['QUJD'],
        );
    expect(s.bodies, hasLength(2));
    expect(s.bodies[0].containsKey('images'), isTrue);
    expect(s.bodies[1].containsKey('images'), isFalse);
    // The same message, so the server replays rather than runs it twice
    expect(s.bodies[1]['clientMessageId'], s.bodies[0]['clientMessageId']);
    expect(s.bodies[1]['ocrTexts'], <String>['total 120']);
    expect(notices(c), hasLength(1));
    expect(
      c.read(chatProvider).items.whereType<AgentItem>().single.text,
      'I see it.',
    );
  });

  test(
    'a refusal with no pictures is not retried as one, and is shown',
    () async {
      final s = PicServer(<List<Json>?>[null]);
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).send('hello');
      expect(s.bodies, hasLength(1));
      expect(notices(c), hasLength(1));
    },
  );

  test(
    'tells the person when the server did not use the pictures that went up',
    () async {
      final s = PicServer(<List<Json>?>[
        <Json>[
          <String, Object?>{
            'type': 'start',
            'turnId': 't-1',
            'usedImages': false,
          },
          <String, Object?>{
            'type': 'done',
            'reply': 'ok',
            'toolsRun': <String>[],
          },
        ],
      ]);
      final c = await containerFor(s);
      await c
          .read(chatProvider.notifier)
          .send(
            'what is this',
            photoTexts: <String>['x'],
            images: <String>['QUJD'],
          );
      expect(notices(c), hasLength(1));
    },
  );

  test('says nothing when the pictures were used, or none went', () async {
    final used = PicServer(<List<Json>?>[
      <Json>[
        <String, Object?>{'type': 'start', 'turnId': 't-1', 'usedImages': true},
        <String, Object?>{
          'type': 'done',
          'reply': 'ok',
          'toolsRun': <String>[],
        },
      ],
    ]);
    final c = await containerFor(used);
    await c.read(chatProvider.notifier).send('x', images: <String>['QUJD']);
    expect(notices(c), isEmpty);
    // No pictures sent: a start that says usedImages false (it cannot) would still show nothing
    final none = PicServer(<List<Json>?>[
      <Json>[
        <String, Object?>{
          'type': 'start',
          'turnId': 't-2',
          'usedImages': false,
        },
        <String, Object?>{
          'type': 'done',
          'reply': 'ok',
          'toolsRun': <String>[],
        },
      ],
    ]);
    final d = await containerFor(none);
    await d.read(chatProvider.notifier).send('x');
    expect(notices(d), isEmpty);
  });

  test(
    'tells the person when the host would not take the pictures mid-turn',
    () async {
      final s = PicServer(<List<Json>?>[
        <Json>[
          <String, Object?>{
            'type': 'start',
            'turnId': 't-1',
            'usedImages': true,
          },
          <String, Object?>{'type': 'pictures', 'used': false},
          <String, Object?>{
            'type': 'done',
            'reply': 'From the text.',
            'toolsRun': <String>[],
          },
        ],
      ]);
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).send('x', images: <String>['QUJD']);
      expect(notices(c), hasLength(1));
    },
  );

  test('uses pictures only when the person chose them and the server said it reads them', () {
    expect(const Settings().usesPictures, isFalse);
    expect(const Settings(photoMode: 'image').usesPictures, isFalse);
    expect(const Settings(photoVision: true).usesPictures, isFalse);
    expect(
      const Settings(photoMode: 'image', photoVision: true).usesPictures,
      isTrue,
    );
  });
}
