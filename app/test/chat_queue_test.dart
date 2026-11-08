// THE SEND QUEUE: MESSAGES WAIT THEIR TURN AND RUN IN ORDER, STOP AND A FAILURE PAUSE THE QUEUE, AND PHOTOS ARE MADE READY IN THE BACKGROUND SO A MESSAGE IS ON
// SCREEN AT ONCE AND ITS REQUEST WAITS FOR THEM ONLY AT THE LAST MOMENT.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/auth.dart';
import 'package:botler/core/chat_photos.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/photo_prep.dart';
import 'package:botler/core/photo_upload.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, containerFor, settle;

// -- TYPES -- //

/// A signed-in person: photos belong to one.
class _SignedIn implements SessionStore {
  @override
  Future<Session?> read() async =>
      const Session(token: 'tok', email: 'a@x.y', name: 'A');

  @override
  Future<void> write(Session s) async {}

  @override
  Future<void> clear() async {}
}

/// A scripted chat server and the container that talks to it.
class ProviderContainerHolder {
  ProviderContainerHolder(this.client, this.bodies);

  final MockClient client;
  final List<Json> bodies;

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final p = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(p),
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
    return c;
  }
}

// -- FUNCTIONS -- //

/// The server answers the request number [which] and ends its stream.
Future<void> finish(RestoreServer s, int which, {String turn = 't'}) async {
  s
    ..emit(<String, Object?>{
      'type': 'start',
      'turnId': '$turn-$which',
      'chatId': 'chat-1',
    }, which)
    ..emit(<String, Object?>{
      'type': 'done',
      'reply': 'ok',
      'toolsRun': <String>[],
    }, which);
  await s.streams[which].close();
  await settle(60);
}

List<String> waiting(ProviderContainer c) => <String>[
  for (final m in c.read(chatProvider).queue) m.text,
];

List<String> asked(RestoreServer s) => <String>[
  for (final b in s.sentBodies) b['text'] as String,
];

void main() {
  group('the queue of messages', () {
    test(
      'three messages sent while one is answered run in order, one at a time',
      () async {
        final s = RestoreServer();
        final c = await containerFor(s);
        c.listen(chatProvider, (_, _) {}, fireImmediately: true);
        final chat = c.read(chatProvider.notifier);
        final first = chat.send('one');
        await settle(20);
        expect(await chat.send('two'), isTrue);
        expect(await chat.send('three'), isTrue);
        // Waiting messages are chips, not part of the conversation yet
        expect(waiting(c), <String>['two', 'three']);
        expect(c.read(chatProvider).items.whereType<UserItem>(), hasLength(1));
        expect(s.streams, hasLength(1));
        await finish(s, 0);
        await first;
        expect(asked(s), <String>['one', 'two']);
        expect(waiting(c), <String>['three']);
        expect(c.read(chatProvider).busy, isTrue);
        await finish(s, 1);
        expect(asked(s), <String>['one', 'two', 'three']);
        await finish(s, 2);
        final state = c.read(chatProvider);
        expect(state.queue, isEmpty);
        expect(state.busy, isFalse);
        expect(state.queuePaused, isFalse);
        expect(
          <String>[for (final u in state.items.whereType<UserItem>()) u.text],
          <String>['one', 'two', 'three'],
        );
      },
    );

    test('a message keeps the id it was given when it waited', () async {
      final s = RestoreServer();
      final c = await containerFor(s);
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final chat = c.read(chatProvider.notifier);
      final first = chat.send('one');
      await settle(20);
      await chat.send('two');
      final id = c.read(chatProvider).queue.single.messageId;
      await finish(s, 0);
      await first;
      expect(s.sentIds[1], id);
      await finish(s, 1);
    });

    test('Stop pauses the queue, and Send now goes on', () async {
      final s = RestoreServer();
      final c = await containerFor(s);
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final chat = c.read(chatProvider.notifier);
      final first = chat.send('one');
      await settle(20);
      await chat.send('two');
      await chat.send('three');
      chat.stop();
      await s.streams[0].close();
      await first;
      await settle(60);
      var state = c.read(chatProvider);
      expect(state.queuePaused, isTrue);
      expect(state.queue, hasLength(2));
      expect(
        s.streams,
        hasLength(1),
        reason: 'nothing is sent unasked after a Stop',
      );
      chat.resumeQueue();
      await settle(60);
      expect(asked(s), <String>['one', 'two']);
      await finish(s, 1);
      expect(asked(s), <String>['one', 'two', 'three']);
      await finish(s, 2);
      state = c.read(chatProvider);
      expect(state.queue, isEmpty);
      expect(state.queuePaused, isFalse);
    });

    test('Clear forgets the waiting messages', () async {
      final s = RestoreServer();
      final c = await containerFor(s);
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final chat = c.read(chatProvider.notifier);
      final first = chat.send('one');
      await settle(20);
      await chat.send('two');
      chat.stop();
      await s.streams[0].close();
      await first;
      await settle(60);
      chat.clearQueue();
      final state = c.read(chatProvider);
      expect(state.queue, isEmpty);
      expect(state.queuePaused, isFalse);
      await settle(60);
      expect(s.streams, hasLength(1));
    });

    test(
      'a failed message pauses the queue instead of sending the rest',
      () async {
        final s = RestoreServer();
        final c = await containerFor(s);
        c.listen(chatProvider, (_, _) {}, fireImmediately: true);
        final chat = c.read(chatProvider.notifier);
        final first = chat.send('one');
        await settle(20);
        await chat.send('two');
        s.emit(<String, Object?>{'type': 'error'});
        await s.streams[0].close();
        await first;
        await settle(60);
        final state = c.read(chatProvider);
        expect(state.queuePaused, isTrue);
        expect(waiting(c), <String>['two']);
        expect(s.streams, hasLength(1));
      },
    );

    test(
      'a waiting message can be taken off, and the rest still run',
      () async {
        final s = RestoreServer();
        final c = await containerFor(s);
        c.listen(chatProvider, (_, _) {}, fireImmediately: true);
        final chat = c.read(chatProvider.notifier);
        final first = chat.send('one');
        await settle(20);
        await chat.send('two');
        await chat.send('three');
        final two = c.read(chatProvider).queue.first;
        expect(chat.removeQueued(two.id)?.text, 'two');
        expect(chat.removeQueued(two.id), isNull);
        await finish(s, 0);
        await first;
        expect(asked(s), <String>['one', 'three']);
        await finish(s, 1);
      },
    );

    test(
      'sending while the queue is paused adds to its end and goes on in order',
      () async {
        final s = RestoreServer();
        final c = await containerFor(s);
        c.listen(chatProvider, (_, _) {}, fireImmediately: true);
        final chat = c.read(chatProvider.notifier);
        final first = chat.send('one');
        await settle(20);
        await chat.send('two');
        chat.stop();
        await s.streams[0].close();
        await first;
        await settle(60);
        expect(c.read(chatProvider).queuePaused, isTrue);
        expect(await chat.send('three'), isTrue);
        await settle(60);
        expect(asked(s), <String>['one', 'two']);
        expect(waiting(c), <String>['three']);
        await finish(s, 1);
        expect(asked(s), <String>['one', 'two', 'three']);
        await finish(s, 2);
      },
    );

    test(
      'at most five messages wait, and the sixth is refused with a notice',
      () async {
        final s = RestoreServer();
        final c = await containerFor(s);
        c.listen(chatProvider, (_, _) {}, fireImmediately: true);
        final chat = c.read(chatProvider.notifier);
        final first = chat.send('one');
        await settle(20);
        for (var i = 0; i < maxQueuedMessages; i++) {
          expect(await chat.send('q$i'), isTrue);
        }
        expect(await chat.send('too many'), isFalse);
        expect(c.read(chatProvider).queue, hasLength(maxQueuedMessages));
        expect(c.read(chatProvider).items.whereType<NoticeItem>(), isNotEmpty);
        chat.stop();
        await s.streams[0].close();
        await first;
        chat.clearQueue();
      },
    );

    test('the chat cannot be rewound while messages wait', () async {
      final s = RestoreServer();
      final c = await containerFor(s);
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final chat = c.read(chatProvider.notifier);
      final first = chat.send('one');
      await settle(20);
      s.emit(<String, Object?>{
        'type': 'start',
        'turnId': 't-x',
        'chatId': 'chat-1',
      });
      await settle(40);
      await chat.send('two');
      expect(await chat.rewindFrom('t-x'), isFalse);
      expect(s.count('chat_rewind'), 0);
      chat.stop();
      await s.streams[0].close();
      await first;
      chat.clearQueue();
    });
  });

  group('photos made ready in the background', () {
    late Directory base;
    late Directory picks;

    setUp(() {
      base = Directory.systemTemp.createTempSync('botler_queue_base');
      picks = Directory.systemTemp.createTempSync('botler_queue_picks');
    });

    tearDown(() {
      base.deleteSync(recursive: true);
      picks.deleteSync(recursive: true);
    });

    Future<(ProviderContainer, ChatPhotoStore, RestoreServer)> setup({
      bool pictures = true,
    }) async {
      final s = RestoreServer();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'photos.noticeSeen': true,
      });
      final p = await SharedPreferences.getInstance();
      final store = ChatPhotoStore(
        prefs: p,
        owner: 'a@x.y',
        baseDir: () async => base,
      );
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(p),
          chatPhotoStoreProvider.overrideWithValue(store),
          sessionStoreProvider.overrideWithValue(_SignedIn()),
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
      await c.read(sessionProvider.future);
      if (pictures) {
        await c
            .read(settingsProvider.notifier)
            .update(
              c
                  .read(settingsProvider)
                  .copyWith(photoMode: 'image', photoVision: true),
            );
      }
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      return (c, store, s);
    }

    Future<String> stage(ChatPhotoStore store, String name) async {
      final f = File('${picks.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      return (await store.stage(f.path))!;
    }

    test(
      'the message is on screen at once and its request waits for the photos',
      () async {
        final (c, store, s) = await setup();
        final copy = await stage(store, 'a.png');
        final gate = Completer<PhotoResult>();
        final sending = c
            .read(chatProvider.notifier)
            .send(
              'receipt',
              photoJobs: <PhotoJob>[PhotoJob(copy, gate.future)],
            );
        await settle(30);
        final user = c.read(chatProvider).items.whereType<UserItem>().single;
        expect(user.preparing, isTrue);
        expect(user.photoPaths, <String>[copy]);
        expect(s.streams, isEmpty, reason: 'the request waits for the photo');
        gate.complete(const PhotoResult('total 120', UploadPicture('QUJD', 3)));
        await settle(60);
        expect(s.sentBodies, hasLength(1));
        final body = s.sentBodies.single;
        expect(body['text'], 'receipt');
        expect(body['ocrTexts'], <String>['total 120']);
        expect(body['images'], isNotEmpty);
        expect(
          c.read(chatProvider).items.whereType<UserItem>().single.preparing,
          isFalse,
        );
        await finish(s, 0);
        await sending;
      },
    );

    test('a picture that could not be made goes by its text alone', () async {
      final (c, store, s) = await setup();
      final copy = await stage(store, 'a.png');
      final sending = c
          .read(chatProvider.notifier)
          .send(
            'receipt',
            photoJobs: <PhotoJob>[
              PhotoJob(
                copy,
                Future<PhotoResult>.value(const PhotoResult('total 120', null)),
              ),
            ],
          );
      await settle(60);
      final body = s.sentBodies.single;
      expect(body['ocrTexts'], <String>['total 120']);
      expect(body.containsKey('images'), isFalse);
      await finish(s, 0);
      await sending;
    });

    test('when the person refused pictures only the text goes, though the picture was made', () async {
      final (c, store, s) = await setup();
      final copy = await stage(store, 'a.png');
      final sending = c
          .read(chatProvider.notifier)
          .send(
            'receipt',
            allowPictures: false,
            photoJobs: <PhotoJob>[
              PhotoJob(
                copy,
                Future<PhotoResult>.value(
                  const PhotoResult('total 120', UploadPicture('QUJD', 3)),
                ),
              ),
            ],
          );
      await settle(60);
      expect(s.sentBodies.single.containsKey('images'), isFalse);
      expect(s.sentBodies.single['ocrTexts'], <String>['total 120']);
      await finish(s, 0);
      await sending;
    });

    test('a mode changed to text only before the turn starts drops the prepared picture', () async {
      final (c, store, s) = await setup();
      final copy = await stage(store, 'a.png');
      final gate = Completer<PhotoResult>();
      final sending = c
          .read(chatProvider.notifier)
          .send('receipt', photoJobs: <PhotoJob>[PhotoJob(copy, gate.future)]);
      await settle(30);
      await c
          .read(settingsProvider.notifier)
          .update(c.read(settingsProvider).copyWith(photoMode: 'text'));
      gate.complete(const PhotoResult('total 120', UploadPicture('QUJD', 3)));
      await settle(60);
      expect(s.sentBodies.single.containsKey('images'), isFalse);
      await finish(s, 0);
      await sending;
    });

    test('a photo with neither words nor a picture is left out and its copy deleted', () async {
      final (c, store, s) = await setup();
      final empty = await stage(store, 'a.png');
      final good = await stage(store, 'b.png');
      final sending = c
          .read(chatProvider.notifier)
          .send(
            'two receipts',
            photoJobs: <PhotoJob>[
              PhotoJob(
                empty,
                Future<PhotoResult>.value(const PhotoResult('', null)),
              ),
              PhotoJob(
                good,
                Future<PhotoResult>.value(const PhotoResult('milk 90', null)),
              ),
            ],
          );
      await settle(60);
      expect(s.sentBodies.single['ocrTexts'], <String>['milk 90']);
      expect(File(empty).existsSync(), isFalse);
      expect(c.read(chatProvider).items.whereType<NoticeItem>(), isNotEmpty);
      await finish(s, 0);
      await sending;
    });

    test('a message of photos that hold nothing sends nothing and leaves the screen', () async {
      final (c, store, s) = await setup();
      final empty = await stage(store, 'a.png');
      final ok = await c
          .read(chatProvider.notifier)
          .send(
            '',
            photoJobs: <PhotoJob>[
              PhotoJob(
                empty,
                Future<PhotoResult>.value(const PhotoResult('', null)),
              ),
            ],
          );
      await settle(60);
      expect(ok, isFalse);
      expect(s.sentBodies, isEmpty);
      expect(c.read(chatProvider).items.whereType<UserItem>(), isEmpty);
      expect(c.read(chatProvider).busy, isFalse);
      expect(File(empty).existsSync(), isFalse);
    });

    test('Stop while the photos are still being made sends nothing and deletes the copies', () async {
      final (c, store, s) = await setup();
      final copy = await stage(store, 'a.png');
      final gate = Completer<PhotoResult>();
      final chat = c.read(chatProvider.notifier);
      final sending = chat.send(
        'receipt',
        photoJobs: <PhotoJob>[PhotoJob(copy, gate.future)],
      );
      await settle(30);
      chat.stop();
      gate.complete(const PhotoResult('total 120', null));
      await sending;
      await settle(60);
      expect(s.sentBodies, isEmpty);
      expect(File(copy).existsSync(), isFalse);
      expect(c.read(chatProvider).busy, isFalse);
    });

    test(
      'a queued message with photos waits its turn and then runs with them',
      () async {
        final (c, store, s) = await setup();
        final copy = await stage(store, 'a.png');
        final chat = c.read(chatProvider.notifier);
        final first = chat.send('one');
        await settle(20);
        await chat.send(
          'receipt',
          photoJobs: <PhotoJob>[
            PhotoJob(
              copy,
              Future<PhotoResult>.value(const PhotoResult('milk 90', null)),
            ),
          ],
        );
        expect(c.read(chatProvider).queue.single.photoCount, 1);
        expect(s.sentBodies, hasLength(1));
        await finish(s, 0);
        await first;
        expect(s.sentBodies, hasLength(2));
        expect(s.sentBodies[1]['ocrTexts'], <String>['milk 90']);
        await finish(s, 1);
      },
    );
  });

  group('an earlier message still being answered on the server', () {
    // A server that answers BUSY_CHAT [busy] times and then streams a normal answer
    ProviderContainerHolder build(int busy) {
      final bodies = <Json>[];
      final client = MockClient.streaming((req, body) async {
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
        if (bodies.length <= busy) {
          return http.StreamedResponse(
            Stream<List<int>>.value(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'error': <String, Object?>{
                    'code': 'BUSY_CHAT',
                    'message': 'Still being answered.',
                  },
                }),
              ),
            ),
            409,
          );
        }
        final lines = <Json>[
          <String, Object?>{'type': 'start', 'turnId': 't-1', 'chatId': 'c-1'},
          <String, Object?>{
            'type': 'done',
            'reply': 'ok',
            'toolsRun': <String>[],
          },
        ].map((e) => 'data: ${jsonEncode(e)}\n\n').join();
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(lines)),
          200,
        );
      });
      return ProviderContainerHolder(client, bodies);
    }

    setUp(() => busyWaitUnit = const Duration(milliseconds: 1));
    tearDown(() => busyWaitUnit = const Duration(seconds: 1));

    test('waits and asks again under the same id, then runs', () async {
      final h = build(2);
      final c = await h.container();
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final accepted = await c.read(chatProvider.notifier).send('hello');
      expect(accepted, isTrue);
      expect(h.bodies, hasLength(3));
      expect(h.bodies.map((b) => b['clientMessageId']).toSet(), hasLength(1));
      final state = c.read(chatProvider);
      expect(state.busy, isFalse);
      // The line that said it was waiting went away when the message began
      expect(state.items.whereType<NoticeItem>(), isEmpty);
    });

    test('gives up after the cap, says so and pauses the queue', () async {
      final h = build(100000);
      final c = await h.container();
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final chat = c.read(chatProvider.notifier);
      final first = chat.send('one');
      await settle(5);
      await chat.send('two');
      await first;
      await settle(60);
      final state = c.read(chatProvider);
      expect(state.busy, isFalse);
      expect(state.queuePaused, isTrue);
      expect(state.queue, hasLength(1));
      expect(state.items.whereType<NoticeItem>(), isNotEmpty);
      // About 130 units of waiting, in growing pauses: a few dozen tries, not hundreds
      expect(h.bodies.length, lessThan(40));
      chat.clearQueue();
    });

    test('Stop ends the wait at once', () async {
      busyWaitUnit = const Duration(seconds: 1);
      final h = build(100000);
      final c = await h.container();
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final chat = c.read(chatProvider.notifier);
      final sending = chat.send('one');
      await settle(100);
      chat.stop();
      await sending.timeout(const Duration(seconds: 2));
      expect(c.read(chatProvider).busy, isFalse);
      expect(h.bodies, hasLength(1));
    });
  });

  group('the background worker', () {
    test('works on at most two photos at once', () async {
      var running = 0;
      var most = 0;
      final gates = <Completer<void>>[];
      final prepper = PhotoPrepper(
        read: (_) async => 'text',
        prepare: (_) async {
          running++;
          if (running > most) most = running;
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          running--;
          return const UploadPicture('QUJD', 3);
        },
      );
      final jobs = <PhotoJob>[
        for (var i = 0; i < 5; i++) prepper.start('/p/$i.jpg', picture: true),
      ];
      await settle(30);
      expect(most, photoJobsAtOnce);
      expect(gates, hasLength(photoJobsAtOnce));
      while (gates.any((g) => !g.isCompleted)) {
        for (final g in gates) {
          if (!g.isCompleted) g.complete();
        }
        await settle(10);
      }
      final results = await Future.wait(<Future<PhotoResult>>[
        for (final j in jobs) j.result,
      ]);
      expect(
        results.every((r) => r.text == 'text' && r.picture != null),
        isTrue,
      );
      expect(most, photoJobsAtOnce);
    });

    test(
      'a failed read means no text and a failed prepare means text only',
      () async {
        final prepper = PhotoPrepper(
          read: (p) async {
            if (p.contains('badread')) throw StateError('no reader');
            return 'words';
          },
          prepare: (p) async {
            if (p.contains('badprep')) throw StateError('no picture');
            return const UploadPicture('QUJD', 3);
          },
        );
        final noText = await prepper
            .start('/badread.jpg', picture: true)
            .result;
        expect(noText.text, '');
        expect(noText.picture, isNotNull);
        final textOnly = await prepper
            .start('/badprep.jpg', picture: true)
            .result;
        expect(textOnly.text, 'words');
        expect(textOnly.picture, isNull);
        final skipped = await prepper.start('/ok.jpg', picture: false).result;
        expect(skipped.picture, isNull);
        expect(skipped.empty, isFalse);
      },
    );
  });
}
