// THE EMPTY CHAT: A SKELETON WHILE THE EARLIER CONVERSATION COMES, A RETRY LINE IF IT FAILED, THE GREETING ONLY WHEN IT LOADED EMPTY, AND A TAP THAT ONLY FILLS THE BOX.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, turn;

// -- FUNCTIONS -- //

Future<ProviderContainer> open(
  WidgetTester tester,
  RestoreServer server,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: server.client,
        ),
      ),
      syncProvider.overrideWith((ref) => Completer<Never>().future),
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
  return container;
}

Future<void> arrive(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'while the earlier chat is coming there is a skeleton and no greeting',
    (tester) async {
      final server = RestoreServer()..historyGate = Completer<void>();
      final container = await open(tester, server);
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(chatProvider).restore, RestoreStatus.loading);
      expect(find.text('What can I help with?'), findsNothing);
      expect(find.byType(Skeleton), findsWidgets);
      server.historyGate!.complete();
      await arrive(tester);
    },
  );

  testWidgets('loaded and empty, it greets with three things to tap', (
    tester,
  ) async {
    final container = await open(tester, RestoreServer());
    await arrive(tester);
    expect(container.read(chatProvider).restore, RestoreStatus.done);
    expect(find.text('What can I help with?'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));
  });

  testWidgets('a tap fills the box and sends nothing', (tester) async {
    final server = RestoreServer();
    final container = await open(tester, server);
    await arrive(tester);
    await tester.tap(find.text('What is due this week?'));
    await tester.pump(const Duration(milliseconds: 100));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'What is due this week?');
    expect(container.read(chatProvider).items, isEmpty);
    expect(server.sentIds, isEmpty);
  });

  testWidgets(
    'when the earlier chat could not load there is a retry, never the greeting',
    (tester) async {
      final server = RestoreServer()..historyFails = true;
      final container = await open(tester, server);
      await arrive(tester);
      expect(container.read(chatProvider).restore, RestoreStatus.failed);
      expect(find.text('What can I help with?'), findsNothing);
      expect(find.text('Could not load your earlier chat.'), findsOneWidget);
      // Back online, the retry brings it
      server.historyFails = false;
      await tester.tap(find.text('Try again'));
      await arrive(tester);
      expect(container.read(chatProvider).restore, RestoreStatus.done);
      expect(find.text('What can I help with?'), findsOneWidget);
    },
  );

  testWidgets('with a conversation the greeting is gone', (tester) async {
    final server = RestoreServer()
      ..history = <String, Object?>{
        'turns': <Object?>[turn('hello', reply: 'hi', id: 'm1')],
      };
    await open(tester, server);
    await arrive(tester);
    expect(find.text('What can I help with?'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets(
    'after a new chat the empty chat greets and never asks for the old one again',
    (tester) async {
      final server = RestoreServer()..historyFails = true;
      final container = await open(tester, server);
      await arrive(tester);
      expect(container.read(chatProvider).restore, RestoreStatus.failed);
      await tester.runAsync(container.read(chatProvider.notifier).startNew);
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(chatProvider).restore, RestoreStatus.done);
      expect(find.text('What can I help with?'), findsOneWidget);
      // Asking again does nothing: there is nothing from before to bring back
      final calls = server.historyCalls;
      await tester.runAsync(container.read(chatProvider.notifier).restore);
      expect(server.historyCalls, calls);
      expect(container.read(chatProvider).restore, RestoreStatus.done);
    },
  );
}
