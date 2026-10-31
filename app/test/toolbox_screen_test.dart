// THE TOOLBOX SCREEN (BTL-20261031-1334): THE SAVED SCRIPTS, THEIR CODE, AND DELETING ONE

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:botler/core/script/storage.dart';
import 'package:botler/core/script/toolbox.dart';
import 'package:botler/features/settings/toolbox_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Future<(Toolbox, Widget)> screen(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('toolbox_screen');
  addTearDown(() => dir.deleteSync(recursive: true));
  final toolbox = Toolbox(
    ScriptStorage(owner: 'a@b.c', baseDir: () async => dir),
  );
  final app = ProviderScope(
    overrides: [toolboxProvider.overrideWithValue(toolbox)],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      home: const ToolboxScreen(),
    ),
  );
  return (toolbox, app);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('says so when nothing is saved', (tester) async {
    final (_, app) = await screen(tester);
    await tester.pumpWidget(app);
    await settle(tester);
    expect(find.text('Nothing saved yet.'), findsOneWidget);
    expect(find.textContaining('can never change your money'), findsOneWidget);
  });

  testWidgets(
    'lists a saved script, shows its code, and deletes it after a confirmation',
    (tester) async {
      final (toolbox, app) = await screen(tester);
      await tester.runAsync(() => toolbox.save('Month total', 'print(1 + 1)'));
      await tester.pumpWidget(app);
      await settle(tester);
      expect(find.text('Month total'), findsOneWidget);
      expect(find.text('1 of 30 saved'), findsOneWidget);
      await tester.tap(find.text('Month total'));
      await settle(tester);
      expect(find.text('print(1 + 1)'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Delete this script?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(find.text('Month total'), findsNothing);
      expect(await tester.runAsync(() => toolbox.list()), isEmpty);
    },
  );
}
