// WHAT THE KEYBOARD IS ASKED TO CAPITALISE: FREE TEXT STARTS A SENTENCE, NAMES START EVERY WORD, A TYPED CODE IS ALL CAPITALS AND A SEARCH BOX STAYS AS TYPED.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/history/history_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

/// A screen inside the same providers and theme the app uses, with no sync timer left running.
Future<ProviderContainer> pumpScreen(WidgetTester tester, Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          // Every request fails at once, so no request timeout is left pending
          client: MockClient((_) async => http.Response('{}', 500)),
        ),
      ),
      syncProvider.overrideWith((ref) => Completer<Never>().future),
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
  // A few bounded steps: a loading skeleton pulses forever, so the screen never settles
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

/// Takes the screen down and disposes the providers, so a retry timer of a failed request is not left pending.
Future<void> closeScreen(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

TextCapitalization capsOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).textCapitalization;

void main() {
  group('Field', () {
    Future<void> pumpField(WidgetTester tester, Field field) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));

    testWidgets('starts a sentence by default', (tester) async {
      await pumpField(
        tester,
        Field(controller: TextEditingController(), label: 'Note'),
      );
      expect(
        capsOf(tester, find.byType(TextField)),
        TextCapitalization.sentences,
      );
    });

    testWidgets('a name starts every word', (tester) async {
      await pumpField(
        tester,
        Field(
          controller: TextEditingController(),
          label: 'Name',
          capitalization: TextCapitalization.words,
        ),
      );
      expect(capsOf(tester, find.byType(TextField)), TextCapitalization.words);
    });

    testWidgets('a typed code is all capitals', (tester) async {
      await pumpField(
        tester,
        Field(
          controller: TextEditingController(),
          label: 'Type RESET',
          capitalization: TextCapitalization.characters,
        ),
      );
      expect(
        capsOf(tester, find.byType(TextField)),
        TextCapitalization.characters,
      );
    });
  });

  testWidgets('the chat box starts a sentence', (tester) async {
    final c = await pumpScreen(tester, const ChatScreen());
    expect(
      capsOf(tester, find.byType(TextField)),
      TextCapitalization.sentences,
    );
    await closeScreen(tester, c);
  });

  testWidgets('a search box keeps what is typed', (tester) async {
    final c = await pumpScreen(tester, const HistoryScreen());
    expect(capsOf(tester, find.byType(TextField)), TextCapitalization.none);
    await closeScreen(tester, c);
  });
}
