// THE CHAT'S TWO CONTROLS FOR A LONG CONVERSATION: A BUTTON BACK TO THE NEWEST WORDS (ONLY WHILE FAR ABOVE THEM), THE SUMMARY IN THE APP BAR, AND "NEW CHAT" THAT ASKS, TELLS THE SERVER AND EMPTIES THE SCREEN.

// -- DEP-MODULES -- //
import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/chat/summary_card.dart';
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

Future<RestoreServer> openChat(WidgetTester tester, int turns) async {
  final s = RestoreServer()
    ..history = <String, Object?>{
      'turns': <Object?>[
        for (var i = 0; i < turns; i++)
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
      syncProvider.overrideWith(
        (ref) async => <String, Object?>{
          'summary': <String, Object?>{'total': 500000},
        },
      ),
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
  return s;
}

/// Whether the jump button is showing: faded in and able to be tapped.
bool jumpShown(WidgetTester tester) {
  final button = find.byKey(const ValueKey<String>('jumpLatest'));
  final fade = tester.widget<AnimatedOpacity>(
    find.ancestor(of: button, matching: find.byType(AnimatedOpacity)).first,
  );
  final ignore = tester.widget<IgnorePointer>(
    find.ancestor(of: button, matching: find.byType(IgnorePointer)).first,
  );
  return fade.opacity == 1 && !ignore.ignoring;
}

void main() {
  testWidgets('at the end of a chat the jump button stays away', (
    tester,
  ) async {
    await openChat(tester, 30);
    expect(jumpShown(tester), false);
  });

  testWidgets('scrolled well above the end it shows, and one tap goes back', (
    tester,
  ) async {
    await openChat(tester, 30);
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    list.position.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(jumpShown(tester), true);

    await tester.tap(find.byKey(const ValueKey<String>('jumpLatest')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(list.position.maxScrollExtent - list.position.pixels < 100, true);
    expect(jumpShown(tester), false);
  });

  testWidgets('the summary opens from the app bar', (tester) async {
    await openChat(tester, 30);
    await tester.tap(find.byTooltip('Money summary'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SummaryCard), findsWidgets);
    expect(find.text('₱5,000.00'), findsWidgets);
  });

  testWidgets(
    'new chat from the drawer tells the server and empties the screen',
    (tester) async {
      final s = await openChat(tester, 3);
      expect(find.text('message 0'), findsOneWidget);

      await tester.tap(find.byTooltip('Chats'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.newCalls, 0);
      await tester.tap(find.text('New chat'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(s.newCalls, 1);
      expect(find.text('message 0'), findsNothing);
      // The summary card stays
      expect(find.text('Across your accounts'), findsOneWidget);
    },
  );
}
