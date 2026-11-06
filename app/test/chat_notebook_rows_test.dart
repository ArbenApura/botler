// WHAT THE CHAT SHOWS WHEN THE ASSISTANT WRITES IN THE NOTEBOOKS: ONE QUIET LINE THAT NAMES WHAT WAS SAVED, NEVER "CHECKED ...".
// The words come from the answer, a save that changed nothing says so, a refused or pending write never reads as saved, and each save keeps its own line.

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
  String language = 'en',
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
      locale: Locale(language),
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

ToolItem save(
  int id,
  String name,
  Object? data, {
  bool restored = false,
  String status = 'ok',
  String? message,
}) => ToolItem(
  id,
  name: name,
  status: status,
  data: data,
  message: message,
  restored: restored,
);

const Map<String, Object?> mainEdit = <String, Object?>{
  'notebook': 'main',
  'section': '# Preferences and rules\n- No hearts, only face emoji.',
  'changed': true,
};

void main() {
  for (final mode in Brightness.values) {
    testWidgets('a notebook save names its section (${mode.name})', (
      tester,
    ) async {
      await tester.pumpWidget(
        await screenOf(<ChatItem>[
          save(1, 'notebook_edit', mainEdit),
        ], mode: mode),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Saved to your notebook · Preferences and rules'),
        findsOneWidget,
      );
      expect(find.textContaining('Checked'), findsNothing);
    });
  }

  testWidgets('a save that changed nothing says it was already there', (
    tester,
  ) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        save(1, 'notebook_edit', const <String, Object?>{
          'notebook': 'main',
          'section': '# People',
          'changed': false,
        }),
        save(2, 'page_edit', const <String, Object?>{
          'notebook': 'Trip',
          'page': 'Plans',
          'changed': false,
        }),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Already in your notebook'), findsNWidgets(2));
    expect(find.textContaining('Saved'), findsNothing);
  });

  testWidgets(
    'a page edit and a first text for another notebook name the page',
    (tester) async {
      await tester.pumpWidget(
        await screenOf(<ChatItem>[
          save(1, 'page_edit', const <String, Object?>{
            'notebook': 'Trip',
            'page': 'Plans',
            'section': '# Day 1',
            'changed': true,
          }),
          save(2, 'notebook_edit', const <String, Object?>{
            'notebook': 'Recipes',
            'section': '# Soups',
            'changed': true,
          }),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Saved to Plans in Trip'), findsOneWidget);
      expect(find.text('Saved to Overview in Recipes'), findsOneWidget);
    },
  );

  testWidgets('three saves in a row keep three lines, never a count', (
    tester,
  ) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        for (final (i, page) in <String>['Plans', 'Food', 'Gear'].indexed)
          save(i + 1, 'page_edit', <String, Object?>{
            'notebook': 'Trip',
            'page': page,
            'changed': true,
          }),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Saved to Plans in Trip'), findsOneWidget);
    expect(find.text('Saved to Food in Trip'), findsOneWidget);
    expect(find.text('Saved to Gear in Trip'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets(
    'make, rename, move, merge, delete and put back read from the answer',
    (tester) async {
      await tester.pumpWidget(
        await screenOf(<ChatItem>[
          save(1, 'page_create', const <String, Object?>{'title': 'Trip plan'}),
          save(2, 'page_rename', const <String, Object?>{'title': 'Zebra'}),
          save(3, 'page_merge', const <String, Object?>{
            'page': <String, Object?>{'title': 'Plans'},
          }),
          save(4, 'page_delete', const <String, Object?>{
            'removed': <String, Object?>{'title': 'Old page'},
          }),
          save(5, 'notebook_undelete', const <String, Object?>{
            'title': 'Garden',
          }),
          save(6, 'page_move', null),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Made Trip plan'), findsOneWidget);
      expect(find.text('Updated Zebra'), findsOneWidget);
      expect(find.text('Updated Plans'), findsOneWidget);
      expect(find.text('Deleted Old page'), findsOneWidget);
      expect(find.text('Put back Garden'), findsOneWidget);
      // No answer stored: plain words, never a name taken from somewhere else
      expect(find.text('Updated your notebooks'), findsOneWidget);
    },
  );

  testWidgets('an earlier session shows the same words', (tester) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        save(1, 'notebook_edit', mainEdit, restored: true),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Saved to your notebook · Preferences and rules'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a refused write keeps its failure line and a pending card shows nothing',
    (tester) async {
      await tester.pumpWidget(
        await screenOf(<ChatItem>[
          save(
            1,
            'notebook_edit',
            null,
            status: 'error',
            message: 'That text is not in the notebook.',
          ),
          save(2, 'page_edit', null, status: 'needs_approval'),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('That text is not in the notebook.'), findsOneWidget);
      expect(find.textContaining('Saved'), findsNothing);
    },
  );

  testWidgets(
    'a read of a page is still a lookup, and a running save has its own words',
    (tester) async {
      await tester.pumpWidget(
        await screenOf(<ChatItem>[
          save(1, 'page_get', const <String, Object?>{'title': 'Plans'}),
          const ToolItem(
            2,
            name: 'page_edit',
            status: 'running',
            running: true,
          ),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Checked page get'), findsOneWidget);
      expect(find.text('Updating your notebooks'), findsOneWidget);
      expect(find.textContaining('Checking page edit'), findsNothing);
    },
  );

  testWidgets('the Filipino words match the neighbours', (tester) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        save(1, 'notebook_edit', mainEdit),
        save(2, 'page_edit', const <String, Object?>{
          'notebook': 'Trip',
          'page': 'Plans',
          'changed': true,
        }),
        const ToolItem(
          3,
          name: 'page_create',
          status: 'running',
          running: true,
        ),
      ], language: 'fil'),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Nai-save sa notebook mo · Preferences and rules'),
      findsOneWidget,
    );
    expect(find.text('Nai-save sa Plans sa Trip'), findsOneWidget);
    expect(find.text('Ina-update ang mga notebook mo'), findsOneWidget);
  });
}
