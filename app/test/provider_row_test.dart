// THE AI SERVER ROW IN SETTINGS: THE CHOICE LIST COMES FROM THE SERVER, EVERY ODD STATE (NONE, ONE, A SERVER THAT LOST ITS KEY, AN UNKNOWN ONE) STAYS SAFE,
// AND AN OLDER SERVER THAT KNOWS NOTHING OF THE CHOICE CANNOT BREAK THE SETTINGS.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/features/settings/provider_row.dart';
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
  ValueChanged<String>? onChanged,
}) async {
  final picked = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: ProviderRow(
          settings: settings,
          onChanged: onChanged ?? picked.add,
        ),
      ),
    ),
  );
  return picked;
}

/// A container whose server answers every call with [body], as the settings_get of an older or newer server would.
Future<ProviderContainer> containerWith(Map<String, Object?> body) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{'result': body}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    ],
  );
}

void main() {
  group('ProviderRow', () {
    testWidgets(
      'offers the servers the phone was told about and reports a pick',
      (tester) async {
        final picked = await pumpRow(
          tester,
          const Settings(
            modelProvider: 'otherai',
            availableProviders: <String>['otherai', 'deepseek'],
          ),
        );
        expect(find.text('AI server'), findsWidgets);
        expect(find.text('otherai'), findsOneWidget);
        await tester.tap(find.text('otherai'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DeepSeek').last);
        await tester.pumpAndSettle();
        expect(picked, <String>['deepseek']);
      },
    );

    testWidgets('stays out of the way when the server named no server', (
      tester,
    ) async {
      await pumpRow(tester, const Settings());
      expect(find.text('AI server'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('is read only when there is one server', (tester) async {
      await pumpRow(
        tester,
        const Settings(
          modelProvider: 'deepseek',
          availableProviders: <String>['deepseek'],
        ),
      );
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets(
      'shows nothing selected, not a crash, when the shown server is not in the list',
      (tester) async {
        await pumpRow(
          tester,
          const Settings(
            modelProvider: 'deepseek',
            availableProviders: <String>['otherai', 'openai'],
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Server default'), findsOneWidget);
      },
    );

    testWidgets('says so when the chosen server lost its key on the server', (
      tester,
    ) async {
      await pumpRow(
        tester,
        const Settings(
          modelProvider: 'otherai',
          modelProviderChoice: 'deepseek',
          availableProviders: <String>['otherai', 'openai'],
        ),
      );
      expect(find.textContaining('DeepSeek is not available'), findsOneWidget);
    });

    testWidgets('shows a server it has no name for by its id', (tester) async {
      await pumpRow(
        tester,
        const Settings(
          modelProvider: 'openai',
          availableProviders: <String>['openai', 'otherai'],
        ),
      );
      expect(find.text('openai'), findsOneWidget);
    });
  });

  group('settings from the server', () {
    test(
      'an older server without the fields leaves the choice empty',
      () async {
        final c = await containerWith(<String, Object?>{
          'currency': 'USD',
          'language': 'en',
          'replyLanguage': 'auto',
          'weekStartsOn': 1,
        });
        addTearDown(c.dispose);
        await c.read(settingsProvider.notifier).pullFromServer();
        final s = c.read(settingsProvider);
        expect(s.currency, 'USD');
        expect(s.modelProvider, isNull);
        expect(s.modelProviderChoice, isNull);
        expect(s.availableProviders, isEmpty);
      },
    );

    test('a wrong type is read as nothing, never thrown', () async {
      final c = await containerWith(<String, Object?>{
        'modelProvider': 7,
        'modelProviderChoice': <String>[],
        'availableProviders': 'otherai',
      });
      addTearDown(c.dispose);
      await c.read(settingsProvider.notifier).pullFromServer();
      final s = c.read(settingsProvider);
      expect(s.modelProvider, isNull);
      expect(s.availableProviders, isEmpty);
    });

    test(
      'keeps the choice, clears it on a reset and survives a restart',
      () async {
        final c = await containerWith(<String, Object?>{
          'modelProvider': 'deepseek',
          'modelProviderChoice': 'deepseek',
          'availableProviders': <Object>['otherai', 'deepseek', 7],
        });
        addTearDown(c.dispose);
        await c.read(settingsProvider.notifier).pullFromServer();
        var s = c.read(settingsProvider);
        expect(s.modelProvider, 'deepseek');
        expect(s.availableProviders, <String>['otherai', 'deepseek']);
        // The next start reads the same from the phone
        final again = readSettings(c.read(prefsProvider));
        expect(again.modelProviderChoice, 'deepseek');
        expect(again.availableProviders, <String>['otherai', 'deepseek']);
        // An unrelated change keeps it; a null puts the person back on the default
        expect(s.copyWith(currency: 'EUR').modelProviderChoice, 'deepseek');
        s = s.copyWith(modelProviderChoice: null);
        expect(s.modelProviderChoice, isNull);
        await c.read(settingsProvider.notifier).update(s);
        expect(readSettings(c.read(prefsProvider)).modelProviderChoice, isNull);
      },
    );
  });
}
