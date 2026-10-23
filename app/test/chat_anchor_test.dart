// WHERE THE CHAT PAGE STOPS WHILE AN ANSWER COMES IN: THINKING AND TOOLS FOLLOW THE END, THE WRITTEN ANSWER HOLDS ITS FIRST LINE AT THE TOP (ALSO WHEN IT IS DONE), AND THE JUMP BUTTON STILL GOES TO THE TRUE END.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, turn;

// -- FUNCTIONS -- //

Future<(RestoreServer, ProviderContainer)> openLongChat(
  WidgetTester tester,
) async {
  final s = RestoreServer()
    ..history = <String, Object?>{
      'turns': <Object?>[
        for (var i = 0; i < 12; i++)
          turn('message $i', reply: 'answer $i', id: 'm$i'),
      ],
    };
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: s.client,
        ),
      ),
      syncProvider.overrideWith((ref) async => <String, Object?>{}),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (s, container);
}

/// Lets events through the stream and the batching, then draws.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Object?> ev(
  String type, [
  Map<String, Object?> more = const <String, Object?>{},
]) => <String, Object?>{'type': type, ...more};

String longText(String first) =>
    '$first\n${List<String>.generate(80, (i) => 'line $i of a long answer').join('\n\n')}';

/// Ends the turn so no timer outlives the test.
Future<void> finish(WidgetTester tester, RestoreServer s) async {
  s.emit(ev('done'));
  await s.streams.last.close();
  await settle(tester);
}

ScrollPosition position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('thinking and tools follow the end, never the earlier answer', (
    tester,
  ) async {
    final (s, c) = await openLongChat(tester);
    final p = position(tester);
    expect(p.maxScrollExtent - p.pixels < 100, true);

    unawaited(c.read(chatProvider.notifier).send('go'));
    await settle(tester);
    s.emit(ev('start'));
    s.emit(ev('phase', <String, Object?>{'phase': 'thinking'}));
    s.emit(ev('reasoning', <String, Object?>{'text': 'Let me look.'}));
    await settle(tester);
    expect(p.maxScrollExtent - p.pixels < 100, true);

    s.emit(
      ev('tool_start', <String, Object?>{'id': 'c1', 'name': 'accounts_list'}),
    );
    await settle(tester);
    expect(p.maxScrollExtent - p.pixels < 100, true);
    await finish(tester, s);
  });

  testWidgets('a long answer holds its first line at the top, also when done', (
    tester,
  ) async {
    final (s, c) = await openLongChat(tester);
    final p = position(tester);
    unawaited(c.read(chatProvider.notifier).send('go'));
    await settle(tester);
    s.emit(ev('start'));
    s.emit(ev('phase', <String, Object?>{'phase': 'writing'}));
    s.emit(ev('delta', <String, Object?>{'text': longText('FIRSTLINE')}));
    await settle(tester);
    final first = find.textContaining('FIRSTLINE', findRichText: true);
    expect(first, findsOneWidget);
    expect(p.maxScrollExtent - p.pixels > 300, true);
    expect(tester.getTopLeft(first).dy < 250, true);

    s.emit(ev('delta', <String, Object?>{'text': '\n\nmore words'}));
    await settle(tester);
    expect(tester.getTopLeft(first).dy < 250, true);

    s.emit(ev('done'));
    await s.streams.last.close();
    await settle(tester);
    expect(tester.getTopLeft(first).dy < 250, true);
  });

  testWidgets(
    'the jump button goes to the true end and stays while streaming',
    (tester) async {
      final (s, c) = await openLongChat(tester);
      final p = position(tester);
      unawaited(c.read(chatProvider.notifier).send('go'));
      await settle(tester);
      s.emit(ev('start'));
      s.emit(ev('phase', <String, Object?>{'phase': 'writing'}));
      s.emit(ev('delta', <String, Object?>{'text': longText('FIRSTLINE')}));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey<String>('jumpLatest')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.maxScrollExtent - p.pixels < 100, true);

      s.emit(ev('delta', <String, Object?>{'text': '\n\nmore words'}));
      await settle(tester);
      expect(p.maxScrollExtent - p.pixels < 100, true);
      await finish(tester, s);
    },
  );
}
