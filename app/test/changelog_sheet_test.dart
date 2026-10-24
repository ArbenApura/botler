// THE "WHAT IS NEW" SHEET: SHOWN ONCE FOR AN UNSEEN BUILD ON THE CHAT SCREEN, NEVER FOR A FRESH INSTALL, AND REOPENED FROM SETTINGS.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'package:botler/core/api.dart';
import 'package:botler/core/changelog.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/settings/changelog_row.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/changelog.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';

// -- FUNCTIONS -- //

const List<ChangelogEntry> _entries = <ChangelogEntry>[
  ChangelogEntry(
    versionCode: 8,
    versionName: '1.0.7',
    en: <String>['Newest english line'],
    fil: <String>['Pinakabagong linya'],
  ),
  ChangelogEntry(
    versionCode: 7,
    versionName: '1.0.6',
    en: <String>['Older english line'],
    fil: <String>[],
  ),
];

Future<(ProviderContainer, SharedPreferences)> _pump(
  WidgetTester tester,
  Widget home, {
  required Map<String, Object> prefsValues,
  int installed = 8,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: MockClient((_) async => http.Response('{}', 500)),
        ),
      ),
      syncProvider.overrideWith((ref) => Completer<Never>().future),
      installedBuildProvider.overrideWith((ref) async => installed),
      changelogEntriesProvider.overrideWith((ref) async => _entries),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: home,
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (container, prefs);
}

Future<void> _close(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
  await tester.pump(const Duration(seconds: 61));
}

void main() {
  testWidgets('an unseen build opens the sheet once and stores the build', (
    tester,
  ) async {
    final (c, prefs) = await _pump(
      tester,
      const ChatScreen(),
      prefsValues: <String, Object>{'changelog.seen': 6},
    );
    expect(find.text('What is new in 1.0.7'), findsOneWidget);
    expect(find.text('Newest english line'), findsOneWidget);
    expect(find.text('Older english line'), findsOneWidget);
    // Stored at once: leaving the sheet any way (back, swipe, the lock taking the screen) never shows it again
    expect(seenCode(prefs), 8);

    await tester.tap(find.text('Got it'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Got it'), findsNothing);

    // A screen built again in the same run (back from the lock, a return from the menu) does not open it a second time
    expect(c.read(changelogShownProvider), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.light),
          home: const ChatScreen(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Got it'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('a build that was already seen shows nothing', (tester) async {
    final (c, _) = await _pump(
      tester,
      const ChatScreen(),
      prefsValues: <String, Object>{'changelog.seen': 8},
    );
    expect(find.text('Got it'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('a phone where nothing was decided yet shows nothing', (
    tester,
  ) async {
    final (c, prefs) = await _pump(
      tester,
      const ChatScreen(),
      prefsValues: <String, Object>{},
    );
    expect(find.text('Got it'), findsNothing);
    expect(seenCode(prefs), isNull);
    await _close(tester, c);
  });

  testWidgets('an unknown installed build shows nothing and writes nothing', (
    tester,
  ) async {
    final (c, prefs) = await _pump(
      tester,
      const ChatScreen(),
      prefsValues: <String, Object>{'changelog.seen': 6},
      installed: 0,
    );
    expect(find.text('Got it'), findsNothing);
    expect(seenCode(prefs), 6);
    await _close(tester, c);
  });

  testWidgets('Filipino lines show in Filipino, with English as the fallback', (
    tester,
  ) async {
    final (c, _) = await _pump(
      tester,
      const ChatScreen(),
      prefsValues: <String, Object>{
        'changelog.seen': 6,
        'settings.language': 'fil',
      },
    );
    expect(find.text('Pinakabagong linya'), findsOneWidget);
    // The older entry has no Filipino lines, so it falls back to English
    expect(find.text('Older english line'), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('the Settings row reopens the notes of the installed build', (
    tester,
  ) async {
    final (c, _) = await _pump(
      tester,
      const Scaffold(body: ChangelogRow()),
      prefsValues: <String, Object>{'changelog.seen': 8},
    );
    expect(find.text('What is new in this version'), findsOneWidget);
    await tester.tap(find.text('What is new in this version'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Newest english line'), findsOneWidget);
    // Only the installed build, not the older one
    expect(find.text('Older english line'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('the Settings row is hidden when the build has no entry', (
    tester,
  ) async {
    final (c, _) = await _pump(
      tester,
      const Scaffold(body: ChangelogRow()),
      prefsValues: <String, Object>{'changelog.seen': 8},
      installed: 9,
    );
    expect(find.text('What is new in this version'), findsNothing);
    await _close(tester, c);
  });
}
