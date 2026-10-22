// THE KEYBOARD OPENING ON THE CHAT SCREEN: THE LIST SHRINKS FROM THE BOTTOM, SO THE NEWEST WORDS MUST BE BROUGHT BACK ABOVE IT.

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

void main() {
  testWidgets('opening the keyboard keeps the newest message in view', (
    tester,
  ) async {
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

    // The person scrolls up to read first, so the list is no longer following the end
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(list.position.pixels, lessThan(list.position.maxScrollExtent - 48));

    // The keyboard comes up: 300 logical pixels from the bottom
    final ratio = tester.view.devicePixelRatio;
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * ratio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(list.position.maxScrollExtent, greaterThan(0));
    expect(list.position.pixels, list.position.maxScrollExtent);
  });
}
