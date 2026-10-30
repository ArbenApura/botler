// THE PHOTOS CHOICE: THE SECTION IN SETTINGS (BOTH LANGUAGES, EVERY STATE), WHAT THE PHONE BELIEVES WHEN THE SERVER SAYS NOTHING, AND THE ONE-TIME
// NOTICE THAT A PICTURE IS SENT AS IT IS

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/features/settings/photo_mode_row.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

Future<List<String>> pumpRow(
  WidgetTester tester,
  Settings settings, {
  String language = 'en',
}) async {
  final picked = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: PhotoModeRow(settings: settings, onChanged: picked.add),
      ),
    ),
  );
  return picked;
}

/// A container whose server answers every call with [body]. [sent] collects what the phone sent.
Future<ProviderContainer> containerWith(
  Map<String, Object?> body, {
  Map<String, Object> prefs = const <String, Object>{},
  List<String>? sent,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: MockClient((req) async {
            sent?.add(req.body);
            return http.Response(
              jsonEncode(<String, Object?>{'result': body}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      ),
    ],
  );
}

void main() {
  group('PhotoModeRow', () {
    testWidgets('says what is sent for the picture, naming the server', (
      tester,
    ) async {
      await pumpRow(
        tester,
        const Settings(
          photoMode: 'image',
          photoVision: true,
          modelProvider: 'anthropic',
        ),
      );
      expect(find.text('Photos for the assistant'), findsOneWidget);
      expect(find.textContaining('goes to Anthropic as it is'), findsOneWidget);
      expect(find.textContaining('not hidden'), findsOneWidget);
    });

    testWidgets(
      'names both servers when the pictures go to another one than the chat',
      (tester) async {
        await pumpRow(
          tester,
          const Settings(
            photoMode: 'image',
            photoVision: true,
            photoHost: 'anthropic',
            modelProvider: 'deepseek',
          ),
        );
        expect(
          find.textContaining(
            'DeepSeek cannot look at pictures, so Anthropic looks at them',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('The rest of your chat stays on DeepSeek'),
          findsOneWidget,
        );
      },
    );

    testWidgets('says plainly when no server can look at pictures', (
      tester,
    ) async {
      await pumpRow(
        tester,
        const Settings(photoMode: 'image', modelProvider: 'deepseek'),
      );
      expect(
        find.textContaining('DeepSeek cannot look at pictures'),
        findsOneWidget,
      );
      expect(find.textContaining('goes to'), findsNothing);
    });

    testWidgets('says the words alone are sent in text mode', (tester) async {
      await pumpRow(tester, const Settings(photoMode: 'text'));
      expect(find.textContaining('only those words are sent'), findsOneWidget);
    });

    testWidgets('reports the pick, in either direction', (tester) async {
      final picked = await pumpRow(tester, const Settings(photoMode: 'text'));
      await tester.tap(find.text('Picture'));
      await tester.pump();
      expect(picked, <String>['image']);
      final again = await pumpRow(tester, const Settings(photoMode: 'image'));
      await tester.tap(find.text('Text only'));
      await tester.pump();
      expect(again, <String>['text']);
    });

    testWidgets('holds in Filipino at a large text size', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpRow(
        tester,
        const Settings(
          photoMode: 'image',
          photoVision: true,
          modelProvider: 'anthropic',
        ),
        language: 'fil',
      );
      expect(find.text('Mga litrato para sa assistant'), findsOneWidget);
      expect(find.textContaining('Anthropic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('what the phone believes', () {
    test(
      'is text only, with no vision, until a server says otherwise',
      () async {
        final c = await containerWith(<String, Object?>{});
        addTearDown(c.dispose);
        final s = c.read(settingsProvider);
        expect(s.photoMode, 'text');
        expect(s.photoVision, isFalse);
      },
    );

    test('keeps its mode and reads no vision from an older server that sends neither', () async {
      final c = await containerWith(
        <String, Object?>{'currency': 'PHP'},
        prefs: <String, Object>{'settings.photoMode': 'image'},
      );
      addTearDown(c.dispose);
      await c.read(settingsProvider.notifier).pullFromServer();
      final s = c.read(settingsProvider);
      expect(s.photoMode, 'image');
      expect(s.photoVision, isFalse);
    });

    test(
      'takes the mode and the vision from the server, and keeps only the mode',
      () async {
        final c = await containerWith(<String, Object?>{
          'photoMode': 'image',
          'photoVision': true,
          'photoHost': 'anthropic',
        });
        addTearDown(c.dispose);
        await c.read(settingsProvider.notifier).pullFromServer();
        expect(c.read(settingsProvider).photoMode, 'image');
        expect(c.read(settingsProvider).photoVision, isTrue);
        expect(c.read(settingsProvider).photoHost, 'anthropic');
        final prefs = await SharedPreferences.getInstance();
        expect(readSettings(prefs).photoMode, 'image');
        // A stale copy of "the server can read pictures" is never believed on the next start
        expect(readSettings(prefs).photoVision, isFalse);
      },
    );

    test('saves the choice on the server', () async {
      final sent = <String>[];
      final c = await containerWith(<String, Object?>{
        'settings': <String, Object?>{
          'photoMode': 'text',
          'photoVision': false,
        },
      }, sent: sent);
      addTearDown(c.dispose);
      await c.read(settingsProvider.notifier).saveToServer(photoMode: 'text');
      expect(sent.single, contains('"photoMode":"text"'));
      expect(c.read(settingsProvider).photoMode, 'text');
    });
  });

  group('the one-time notice', () {
    Future<(ProviderContainer, List<bool?>)> pumpButton(
      WidgetTester tester, {
      Map<String, Object> prefs = const <String, Object>{},
    }) async {
      final c = await containerWith(<String, Object?>{
        'settings': <String, Object?>{'photoMode': 'text', 'photoVision': true},
      }, prefs: prefs);
      addTearDown(c.dispose);
      final answers = <bool?>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(Brightness.light),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      answers.add(await pictureNoticeAccepted(context, ref)),
                  child: const Text('ask'),
                ),
              ),
            ),
          ),
        ),
      );
      return (c, answers);
    }

    testWidgets('asks once, remembers a yes, and never asks again', (
      tester,
    ) async {
      final (c, answers) = await pumpButton(tester);
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.text('Send the picture itself?'), findsOneWidget);
      await tester.tap(find.text('Send pictures'));
      await tester.pumpAndSettle();
      expect(answers, <bool?>[true]);
      expect(c.read(prefsProvider).getBool(pictureNoticeKey), isTrue);
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.text('Send the picture itself?'), findsNothing);
      expect(answers, <bool?>[true, true]);
    });

    testWidgets('a no turns pictures off and is asked again next time', (
      tester,
    ) async {
      final (c, answers) = await pumpButton(tester);
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text only'));
      await tester.pumpAndSettle();
      expect(answers, <bool?>[false]);
      expect(c.read(settingsProvider).photoMode, 'text');
      expect(c.read(prefsProvider).getBool(pictureNoticeKey), isNull);
    });
  });
}
