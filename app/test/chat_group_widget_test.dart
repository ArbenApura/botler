// SIX IDENTICAL QUIET TOOL LINES ON THE SCREEN: ONE LINE WITH "+5", READ OUT IN WORDS, FOR THIS RUN AND FOR AN EARLIER ONE.

// -- DEP-MODULES -- //
import 'package:botler/core/json.dart';
import 'package:botler/features/chat/chat_group.dart';
import 'package:botler/features/chat/chat_items.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

/// The rows of a conversation, drawn the way the chat screen draws them.
Future<Widget> screenOf(
  List<ChatItem> items, {
  Brightness mode = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final rows = groupQuietTools(items);
  return ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      balancesProvider.overrideWith((ref) async => const <Json>[]),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(mode),
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            for (final r in rows)
              ChatItemView(r.item, more: r.more, key: ValueKey<int>(r.item.id)),
          ],
        ),
      ),
    ),
  );
}

ToolItem lookup(int id, {bool restored = false}) => ToolItem(
  id,
  name: 'bill_occurrence_update',
  status: 'ok',
  restored: restored,
);

void main() {
  for (final mode in Brightness.values) {
    testWidgets('six identical lines show as one with +5 (${mode.name})', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        await screenOf(<ChatItem>[
          const ToolItem(1, name: 'bills_list', status: 'ok'),
          for (var i = 2; i <= 7; i++) lookup(i),
        ], mode: mode),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Checked bill occurrence update'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      // The other kind of lookup stays its own line, with no count
      expect(find.text('Checked bills list'), findsOneWidget);
      expect(find.textContaining('+'), findsOneWidget);
      // Read out in words for a screen reader
      expect(
        find.bySemanticsLabel('Checked bill occurrence update, 5 more times'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  }

  testWidgets('a line from an earlier session folds the same way', (
    tester,
  ) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        for (var i = 1; i <= 3; i++) lookup(i, restored: true),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Checked bill occurrence update'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('one line alone has no count and no extra words', (tester) async {
    await tester.pumpWidget(await screenOf(<ChatItem>[lookup(1)]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Checked bill occurrence update'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
  });
}
