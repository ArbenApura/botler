// PHOTOS ACROSS A SEND: SHOWN AT ONCE, FILED UNDER THE TURN WHEN THE SERVER ACCEPTS THE MESSAGE, DELETED WHEN IT NEVER DOES, AND BROUGHT BACK WITH THE CONVERSATION.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/auth.dart';
import 'package:botler/core/chat_photos.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, settle, turn;

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

// -- FUNCTIONS -- //

Future<(ProviderContainer, ChatPhotoStore)> _setup(
  RestoreServer s,
  Directory base,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
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
  return (c, store);
}

void main() {
  late Directory base;
  late Directory picks;

  setUp(() {
    base = Directory.systemTemp.createTempSync('botler_flow_base');
    picks = Directory.systemTemp.createTempSync('botler_flow_picks');
  });

  tearDown(() {
    base.deleteSync(recursive: true);
    picks.deleteSync(recursive: true);
  });

  Future<String> staged(ChatPhotoStore store, String name) async {
    final f = File('${picks.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    return (await store.stage(f.path))!;
  }

  test('the message shows its pictures at once and keeps them once the server accepts it', () async {
    final s = RestoreServer();
    final (c, store) = await _setup(s, base);
    final copy = await staged(store, 'one.png');
    final chat = c.read(chatProvider.notifier);
    final sending = chat.send(
      'receipt',
      photoTexts: <String>['total 120'],
      photoPaths: <String>[copy],
    );
    await settle(20);
    var user = c.read(chatProvider).items.whereType<UserItem>().single;
    expect(user.photoPaths, <String>[copy]);
    s.emit(<String, Object?>{
      'type': 'start',
      'turnId': 'turn-1',
      'chatId': 'chat-1',
    });
    await settle(50);
    user = c.read(chatProvider).items.whereType<UserItem>().single;
    expect(user.turnId, 'turn-1');
    expect(user.photoPaths, hasLength(1));
    expect(user.photoPaths.single, isNot(copy));
    expect(File(user.photoPaths.single).existsSync(), isTrue);
    expect(File(copy).existsSync(), isFalse);
    expect(store.photosOf('turn-1'), user.photoPaths);
    s.emit(<String, Object?>{'type': 'done'});
    await s.streams.last.close();
    await sending;
  });

  test(
    'a message stopped before the server accepted it leaves no pictures behind',
    () async {
      final s = RestoreServer();
      final (c, store) = await _setup(s, base);
      final copy = await staged(store, 'one.png');
      final chat = c.read(chatProvider.notifier);
      final sending = chat.send(
        'receipt',
        photoTexts: <String>['total 120'],
        photoPaths: <String>[copy],
      );
      await settle(20);
      chat.stop();
      await s.streams.last.close();
      await sending;
      await settle(50);
      expect(File(copy).existsSync(), isFalse);
      final user = c.read(chatProvider).items.whereType<UserItem>().single;
      expect(user.photoPaths, isEmpty);
      // The count of photos in words is what is left
      expect(user.photos, 1);
    },
  );

  test('a message with no photos never touches the store', () async {
    final s = RestoreServer();
    final (c, _) = await _setup(s, base);
    final chat = c.read(chatProvider.notifier);
    final sending = chat.send('hello');
    await settle(20);
    s
      ..emit(<String, Object?>{'type': 'start', 'turnId': 'turn-2'})
      ..emit(<String, Object?>{'type': 'done'});
    await s.streams.last.close();
    await sending;
    expect(
      Directory('${base.path}${Platform.pathSeparator}chat_photos')
          .existsSync(),
      isFalse,
    );
  });

  test(
    'the conversation comes back with the pictures of turns that have them',
    () async {
      final s = RestoreServer();
      final (c, store) = await _setup(s, base);
      final copy = await staged(store, 'one.png');
      final kept = await store.promote('row-a', <String>[copy]);
      s.history = <String, Object?>{
        'turns': <Object?>[
          turn('receipt', reply: 'Saved.', id: 'a'),
          turn('hello', reply: 'Hi!', id: 'b'),
        ],
      };
      await c.read(chatProvider.notifier).restore();
      final users = c
          .read(chatProvider)
          .restored
          .whereType<UserItem>()
          .toList();
      expect(users, hasLength(2));
      expect(users[0].photoPaths, kept);
      expect(users[1].photoPaths, isEmpty);
    },
  );

  test(
    'a restore with a store that cannot be read still shows the words',
    () async {
      final s = RestoreServer();
      SharedPreferences.setMockInitialValues(<String, Object>{
        '${photoIndexPrefix}a@x.y': '{"row-a":["gone.png"]}',
      });
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(p),
          sessionStoreProvider.overrideWithValue(_SignedIn()),
          chatPhotoStoreProvider.overrideWithValue(
            ChatPhotoStore(
              prefs: p,
              owner: 'a@x.y',
              baseDir: () async => throw const FileSystemException('no folder'),
            ),
          ),
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
      s.history = <String, Object?>{
        'turns': <Object?>[turn('receipt', reply: 'Saved.', id: 'a')],
      };
      await c.read(chatProvider.notifier).restore();
      final users = c
          .read(chatProvider)
          .restored
          .whereType<UserItem>()
          .toList();
      expect(users.single.text, 'receipt');
      expect(users.single.photoPaths, isEmpty);
    },
  );
}
