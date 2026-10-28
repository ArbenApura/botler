// THE KEYBOARD OPENING ON THE CHAT SCREEN: THE LIST SHRINKS FROM THE BOTTOM. AT THE BOTTOM THE NEWEST WORDS STAY ABOVE IT; SCROLLED UP, THE READING PLACE STAYS.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, turn;

/// Opens the chat with thirty turns and lets the list settle at its end.
Future<ScrollableState> _open(WidgetTester tester) async {
  final s = RestoreServer()
    ..history = <String, Object?>{
      'turns': <Object?>[
        for (var i = 0; i < 30; i++)
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
      // The summary card's sync never answers, so no timer is left running
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
  // The earlier conversation arrives and the list settles at its end
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
  expect(list.position.pixels, list.position.maxScrollExtent);
  return list;
}

/// The keyboard comes up: 300 logical pixels from the bottom.
Future<void> _raiseKeyboard(WidgetTester tester) async {
  final ratio = tester.view.devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: 300 * ratio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'opening the keyboard at the bottom keeps the newest message in view',
    (tester) async {
      final list = await _open(tester);
      await _raiseKeyboard(tester);
      expect(list.position.maxScrollExtent, greaterThan(0));
      expect(list.position.pixels, list.position.maxScrollExtent);
    },
  );

  testWidgets(
    'opening the keyboard while reading older messages keeps the place',
    (tester) async {
      final list = await _open(tester);
      // The person scrolls up to read first, so the list is no longer following the end
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        list.position.pixels,
        lessThan(list.position.maxScrollExtent - 48),
      );
      final place = list.position.pixels;
      await _raiseKeyboard(tester);
      expect(list.position.pixels, place);
    },
  );
}
