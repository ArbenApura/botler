// CHATS THAT WORK SIDE BY SIDE: ANOTHER CHAT OPENS OR STARTS WHILE ONE IS ANSWERING, EACH KEEPS ITS OWN TURN, THE LIST SAYS WHAT EACH IS DOING,
// AND AT MOST THREE WORK AT ONCE (BTL-20261106-1502-b).

// -- DEP-MODULES -- //
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, containerFor;

// -- FUNCTIONS -- //

const Duration _beat = Duration(milliseconds: 60);

/// Sends one message in the chat on screen and tells the server which chat it is, so the session knows its chat.
Future<Future<bool>> _send(
  ProviderContainer c,
  RestoreServer server,
  String text,
  String chatId,
  String turnId,
) async {
  final sending = c.read(chatProvider.notifier).send(text);
  await Future<void>.delayed(_beat);
  server.emit(<String, Object?>{
    'type': 'start',
    'turnId': turnId,
    'chatId': chatId,
  }, server.streams.length - 1);
  await Future<void>.delayed(_beat);
  return sending;
}

/// Ends the answer of the n-th message sent.
Future<void> _finish(RestoreServer server, int n, String reply) async {
  server
    ..emit(<String, Object?>{'type': 'delta', 'text': reply}, n)
    ..emit(<String, Object?>{
      'type': 'done',
      'reply': reply,
      'toolsRun': <String>[],
    }, n);
  await server.streams[n].close();
  await Future<void>.delayed(_beat);
}

void main() {
  test('a chat can be opened while another one is answering, and the first keeps working', () async {
    final server = RestoreServer();
    final c = await containerFor(server);
    c.listen(chatProvider, (_, _) {}, fireImmediately: true);
    final first = await _send(c, server, 'rent next week', 'c-1', 't-1');
    expect(c.read(chatProvider).busy, isTrue);
    expect(c.read(chatProvider).chatId, 'c-1');

    // Before: this was refused while busy. Now another chat opens at once, in its own session
    await c.read(chatProvider.notifier).openChat('c-2');
    expect(c.read(chatProvider).chatId, 'c-2');
    expect(c.read(chatProvider).busy, isFalse);
    expect(c.read(activeChatKeyProvider), isNot('main'));
    // The first chat is still working, on its own
    expect(c.read(chatSessionProvider('main')).busy, isTrue);
    expect(c.read(chatActivityProvider)['c-1'], ChatActivity.working);

    await _finish(server, 0, 'Done: 4,000 left.');
    expect(await first.timeout(const Duration(seconds: 5)), isTrue);
    // It finished while another chat was on screen: the list and the menu button say so
    expect(c.read(chatActivityProvider)['c-1'], ChatActivity.newAnswer);
    expect(c.read(otherChatWaitsProvider), isTrue);
    expect(
      c
          .read(chatSessionProvider('main'))
          .items
          .whereType<AgentItem>()
          .last
          .text,
      contains('4,000 left'),
    );

    // Going back shows it as it was, with no waiting, and the dot goes
    await c.read(chatProvider.notifier).openChat('c-1');
    expect(c.read(activeChatKeyProvider), 'main');
    expect(c.read(chatProvider).chatId, 'c-1');
    expect(c.read(chatActivityProvider)['c-1'], isNull);
    expect(c.read(otherChatWaitsProvider), isFalse);
  });

  test('a new chat starts while one is answering, and stopping one leaves the other alone', () async {
    final server = RestoreServer();
    final c = await containerFor(server);
    c.listen(chatProvider, (_, _) {}, fireImmediately: true);
    final first = await _send(c, server, 'first', 'c-1', 't-1');

    await c.read(chatProvider.notifier).startNew();
    expect(server.newCalls, 1);
    expect(c.read(chatProvider).chatId, 'chat-new');
    expect(c.read(chatProvider).busy, isFalse);
    final second = await _send(c, server, 'second', 'chat-new', 't-2');
    expect(c.read(chatSessionProvider('main')).busy, isTrue);
    expect(c.read(chatProvider).busy, isTrue);

    // Stop the one on screen: the other is not touched
    c.read(chatProvider.notifier).stop();
    // The fake server's socket closes when the request is abandoned
    await server.streams[1].close();
    await second.timeout(const Duration(seconds: 5));
    expect(c.read(chatProvider).busy, isFalse);
    expect(c.read(chatSessionProvider('main')).busy, isTrue);

    await _finish(server, 0, 'Done.');
    expect(await first.timeout(const Duration(seconds: 5)), isTrue);
  });

  test(
    'at most three chats work at once, and the fourth says so without sending',
    () async {
      final server = RestoreServer();
      final c = await containerFor(server);
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final sends = <Future<bool>>[];
      sends.add(await _send(c, server, 'one', 'c-1', 't-1'));
      await c.read(chatProvider.notifier).openChat('c-2');
      sends.add(await _send(c, server, 'two', 'c-2', 't-2'));
      await c.read(chatProvider.notifier).openChat('c-3');
      sends.add(await _send(c, server, 'three', 'c-3', 't-3'));
      await c.read(chatProvider.notifier).openChat('c-4');
      expect(server.streams, hasLength(3));

      final refused = await c.read(chatProvider.notifier).send('four');
      expect(refused, isFalse);
      expect(server.streams, hasLength(3));
      expect(
        c.read(chatProvider).items.whereType<NoticeItem>().map((n) => n.text),
        contains(wordsFor('en').chatsLimit),
      );

      // One finishes: a fourth may start
      await _finish(server, 0, 'Done.');
      await sends[0].timeout(const Duration(seconds: 5));
      final fourth = c.read(chatProvider.notifier).send('four again');
      await Future<void>.delayed(_beat);
      expect(server.streams, hasLength(4));
      for (var i = 1; i < 4; i++) {
        await _finish(server, i, 'Done.');
      }
      await Future.wait<bool>(<Future<bool>>[...sends.skip(1), fourth])
          .timeout(const Duration(seconds: 5));
    },
  );

  test('a fresh start (another person signs in) drops every session', () async {
    final server = RestoreServer();
    final c = await containerFor(server);
    c.listen(chatProvider, (_, _) {}, fireImmediately: true);
    final first = await _send(c, server, 'one', 'c-1', 't-1');
    await c.read(chatProvider.notifier).openChat('c-2');
    expect(c.read(chatKeysProvider), hasLength(2));

    chatProviders.forEach(c.invalidate);
    expect(c.read(chatKeysProvider), <String>['main']);
    expect(c.read(activeChatKeyProvider), 'main');
    expect(c.read(chatProvider).chatId, isNull);
    expect(c.read(chatProvider).busy, isFalse);
    // The answer still on its way for the old start is thrown away
    await server.streams[0].close();
    expect(await first.timeout(const Duration(seconds: 5)), isFalse);
  });
}
