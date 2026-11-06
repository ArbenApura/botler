// THE NOTEBOOK PAGE AND THE GOAL DELETE: READING, EDITING AND SAVING WITH A VERSION CONFLICT AND A LOST CONNECTION, THE CHANGES AND THEIR RESTORE,
// THE PRIVATE NAMES, AND A GOAL DELETED ONLY AFTER A CONFIRM

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/library.dart';
import 'package:botler/features/auth/lock_gate.dart';
import 'package:botler/features/memory/notebook_screen.dart';
import 'package:botler/features/notebooks/library_screen.dart';
import 'package:botler/features/money/goals_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/library.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class Call {
  const Call(this.verb, this.body, this.key);

  final String verb;
  final Map<String, Object?> body;
  final String? key;
}

/// A server that keeps one notebook, its changes, the private names and the goals, and answers the verbs the pages call.
class FakeBotler {
  FakeBotler({
    this.text = '# People\n- Nena is my mother\n',
    this.version = 2,
    this.updatedBy = 'user',
  });

  String text;
  int version;
  String updatedBy;
  List<Map<String, Object?>> revisions = <Map<String, Object?>>[];
  List<String> people = <String>['Mama'];

  /// The other notebooks, each with an id, title, summary and text; deleted ones wait in [bin].
  List<Map<String, Object?>> others = <Map<String, Object?>>[];
  List<Map<String, Object?>> bin = <Map<String, Object?>>[];
  List<Map<String, Object?>> goals = <Map<String, Object?>>[];
  final List<Call> calls = <Call>[];

  /// The next saves answer CONFLICT, as if another writer got in first.
  int conflicts = 0;

  /// The next saves never reach the server.
  int drops = 0;

  Iterable<Call> of(String verb) => calls.where((c) => c.verb == verb);

  Map<String, Object?> get _view => <String, Object?>{
    'text': text,
    'version': version,
    'updatedBy': updatedBy,
    'updatedAt': '2026-10-27T01:00:00.000Z',
    'chars': text.length,
    'maxChars': 16000,
  };

  http.Response _ok(Object? result) => http.Response(
    jsonEncode(<String, Object?>{'result': result}),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );

  http.Response _err(int status, String code, String message) => http.Response(
    jsonEncode(<String, Object?>{
      'error': <String, Object?>{'code': code, 'message': message},
    }),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  void _keep(String why) => revisions.insert(0, <String, Object?>{
    'id': 'rev-${revisions.length + 1}',
    'version': version,
    'actor': why,
    'at': '2026-10-27T00:00:00.000Z',
    'chars': text.length,
    'preview': text,
  });

  Future<http.Response> _handle(http.Request r) async {
    final verb = r.url.pathSegments.last;
    final body = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    calls.add(Call(verb, body, r.headers['idempotency-key']));
    switch (verb) {
      case 'notebook_get':
        final id = body['notebookId'];
        if (id != null) {
          final n = others.firstWhere((x) => x['id'] == id);
          return _ok(<String, Object?>{
            ...n,
            'version': 1,
            'updatedBy': 'agent',
            'updatedAt': '2026-10-27T01:00:00.000Z',
          });
        }
        return _ok(_view);
      case 'notebook_list':
        final listed = body['deleted'] == true ? bin : others;
        return _ok(<String, Object?>{
          'notebooks': <Map<String, Object?>>[
            if (body['deleted'] != true)
              <String, Object?>{
                'id': 'main-1',
                'kind': 'main',
                'title': '',
                'summary': '',
                'chars': text.length,
              },
            for (final n in listed)
              <String, Object?>{
                'id': n['id'],
                'kind': 'extra',
                'title': n['title'],
                'summary': n['summary'],
                'chars': (n['text']! as String).length,
              },
          ],
        });
      case 'notebook_outline':
        // Each other notebook has its one page, Overview, as an older notebook does on the new server
        return _ok(<String, Object?>{
          'notebooks': <Map<String, Object?>>[
            for (final n in others)
              <String, Object?>{
                'id': n['id'],
                'title': n['title'],
                'summary': n['summary'],
                'pinnedAt': null,
                'pageCount': 1,
                'pages': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'page-${n['id']}',
                    'parentPageId': null,
                    'title': 'Overview',
                    'position': 0,
                    'chars': (n['text']! as String).length,
                    'version': 1,
                    'seenVersion': 0,
                    'pinnedAt': null,
                    'updatedBy': 'user',
                  },
                ],
              },
          ],
          'deleted': false,
          'maxPages': 500,
        });
      case 'notebook_create':
        final made = <String, Object?>{
          'id': 'nb-${others.length + 10}',
          'kind': 'extra',
          'title': body['title'],
          'summary': body['summary'] ?? '',
          'text': '',
        };
        others.add(made);
        return _ok(<String, Object?>{
          ...made,
          'version': 1,
          'updatedBy': 'user',
          'updatedAt': '2026-10-27T01:00:00.000Z',
        });
      case 'notebook_delete':
        final gone = others.firstWhere((x) => x['id'] == body['notebookId']);
        others.remove(gone);
        bin.add(gone);
        return _ok(<String, Object?>{'removed': gone});
      case 'notebook_undelete':
        final back = bin.firstWhere((x) => x['id'] == body['notebookId']);
        bin.remove(back);
        others.add(back);
        return _ok(back);
      case 'notebook_save':
        if (drops > 0) {
          drops--;
          throw http.ClientException('lost');
        }
        if (conflicts > 0) {
          conflicts--;
          // Someone else saved first: the version moves on
          _keep('agent');
          text = '$text- added by Botler\n';
          version++;
          updatedBy = 'agent';
          return _err(409, 'CONFLICT', 'The notebook changed.');
        }
        if (body['expectVersion'] != version) {
          return _err(409, 'CONFLICT', 'The notebook changed.');
        }
        _keep('user');
        text = body['text']! as String;
        version++;
        updatedBy = 'user';
        return _ok(<String, Object?>{..._view, 'changed': true});
      case 'notebook_revisions':
        return _ok(<String, Object?>{'revisions': revisions});
      case 'notebook_restore':
        final rev = revisions.firstWhere((x) => x['id'] == body['revisionId']);
        final back = rev['preview']! as String;
        _keep('user');
        text = back;
        version++;
        updatedBy = 'user';
        return _ok(_view);
      case 'profile_get':
        return _ok(<String, Object?>{
          'people': people,
          'persona': '',
          'about': '',
        });
      case 'profile_set':
        people = (body['people']! as List<Object?>).cast<String>();
        return _ok(<String, Object?>{'saved': true});
      case 'goals_list':
        return _ok(goals);
      case 'goal_delete':
        goals.removeWhere((g) => g['id'] == body['goalId']);
        return _ok(<String, Object?>{'deleted': true});
      default:
        return _ok(<String, Object?>{});
    }
  }

  http.Client get client => MockClient(_handle);
}

// -- FUNCTIONS -- //

Future<void> pump(WidgetTester tester, FakeBotler fake, Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        // The phone's lock is answered at once; a wipe asks for it
        authenticateProvider.overrideWithValue(() async => true),
        apiProvider.overrideWithValue(
          ApiClient(
            base: 'https://botler.test',
            token: () async => 'tok',
            client: fake.client,
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> openEditor(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
  await tester.pumpAndSettle();
}

Finder saveButton() => find.widgetWithText(FilledButton, 'Save');

void main() {
  group('the notebook page', () {
    testWidgets('shows the sections, bullets and the character count', (
      tester,
    ) async {
      final fake = FakeBotler(
        text: '# How Botler talks to you\nShort and warm.\n\n# People\n- Nena is my mother\n',
      );
      await pump(tester, fake, const NotebookScreen());
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('How Botler talks to you'), findsOneWidget);
      expect(find.text('Short and warm.'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Nena is my mother'), findsOneWidget);
      expect(
        find.text('${fake.text.length} of 16000 characters'),
        findsOneWidget,
      );
      // One primary action
      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
      expect(
        find.text(
          'Made from what Botler remembered before',
          findRichText: true,
        ),
        findsNothing,
      );
    });

    testWidgets('says it is the first draft while the tidy-up has not come', (
      tester,
    ) async {
      final fake = FakeBotler(
        text: '# About you\n- Likes tea\n',
        version: 1,
        updatedBy: 'seed',
      );
      await pump(tester, fake, const NotebookScreen());
      expect(
        find.textContaining('Made from what Botler remembered before'),
        findsOneWidget,
      );
    });

    testWidgets('shows a short note for a notebook with nothing in it yet', (
      tester,
    ) async {
      final fake = FakeBotler(
        text: '# How Botler talks to you\n\n# About you\n',
        version: 1,
        updatedBy: 'seed',
      );
      await pump(tester, fake, const NotebookScreen());
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
      expect(
        find.textContaining('Made from what Botler remembered before'),
        findsNothing,
      );
    });

    testWidgets(
      'shows a plain error with a retry when the server cannot be reached',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              prefsProvider.overrideWithValue(prefs),
              apiProvider.overrideWithValue(
                ApiClient(
                  base: 'https://botler.test',
                  token: () async => 'tok',
                  client: MockClient(
                    (_) async => throw http.ClientException('down'),
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(Brightness.light),
              home: const NotebookScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Try again'), findsOneWidget);
      },
    );
  });

  group('the other notebooks', () {
    FakeBotler withTrip() => FakeBotler()
      ..others = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'nb-1',
          'kind': 'extra',
          'title': 'Trip to Japan',
          'summary': 'Flights and hotels',
          'text': '# Flights\n- Leave on 3 March\n',
        },
      ];

    testWidgets(
      'the library lists them under the main notebook and opens one',
      (tester) async {
        final fake = withTrip();
        await pump(tester, fake, const LibraryScreen());
        expect(find.text('Main notebook'), findsOneWidget);
        expect(find.text('Trip to Japan'), findsOneWidget);
        expect(find.text('Flights and hotels'), findsOneWidget);
        expect(find.text('1 page'), findsOneWidget);
        await tester.tap(find.text('Trip to Japan'));
        await tester.pumpAndSettle();
        // Its pages: an older notebook has the one, Overview
        expect(find.text('Overview'), findsOneWidget);
        expect(find.text('Open the first page'), findsOneWidget);
      },
    );

    testWidgets('says so when there are none yet', (tester) async {
      await pump(tester, FakeBotler(), const LibraryScreen());
      expect(
        find.text(
          'No notebooks yet. Ask Botler to start one for a trip, a project or a list.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'makes a new notebook with a title and a summary, then opens it',
      (tester) async {
        final fake = FakeBotler();
        await pump(tester, fake, const LibraryScreen());
        await openMenuItem(tester, 'New notebook');
        await tester.enterText(
          find.widgetWithText(TextField, 'Title'),
          'Recipes',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'What is in it?'),
          'Dinners I like',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        await tester.pumpAndSettle();
        final sent = fake.of('notebook_create').single.body;
        expect(sent['title'], 'Recipes');
        expect(sent['summary'], 'Dinners I like');
        expect(find.text('Recipes'), findsWidgets);
      },
    );

    testWidgets('edits one of them by its id', (tester) async {
      final fake = withTrip();
      await pump(
        tester,
        fake,
        const NotebookScreen(notebookId: 'nb-1', title: 'Trip to Japan'),
      );
      expect(find.text('Flights and hotels'), findsOneWidget);
      await openEditor(tester);
      await tester.enterText(
        find.byType(TextField),
        '# Flights\n- Leave on 5 March\n',
      );
      await tester.pump();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      final sent = fake.of('notebook_save').single.body;
      expect(sent['notebookId'], 'nb-1');
      expect(sent['expectVersion'], 1);
    });

    testWidgets('deletes one only after a confirm', (tester) async {
      final fake = withTrip();
      await pump(
        tester,
        fake,
        const NotebookScreen(notebookId: 'nb-1', title: 'Trip to Japan'),
      );
      await openMenuItem(tester, 'Delete notebook');
      expect(find.text('Delete this notebook?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(fake.of('notebook_delete'), isEmpty);
      await openMenuItem(tester, 'Delete notebook');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete notebook'));
      await tester.pumpAndSettle();
      expect(fake.of('notebook_delete').single.body['notebookId'], 'nb-1');
      expect(fake.others, isEmpty);
    });

    testWidgets('shows the deleted notebooks and restores one', (tester) async {
      final fake = FakeBotler()
        ..bin = <Map<String, Object?>>[
          <String, Object?>{
            'id': 'nb-2',
            'kind': 'extra',
            'title': 'Old plans',
            'summary': '',
            'text': 'x',
          },
        ];
      await pump(tester, fake, const LibraryScreen());
      await openMenuItem(tester, 'Deleted notebooks');
      expect(find.text('Old plans'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(fake.of('notebook_undelete').single.body['notebookId'], 'nb-2');
      expect(fake.others.single['title'], 'Old plans');
    });
  });

  group('editing and saving', () {
    testWidgets(
      'saves the whole text from the version it opened, and the page shows it',
      (tester) async {
        final fake = FakeBotler();
        await pump(tester, fake, const NotebookScreen());
        await openEditor(tester);
        expect(find.text('Edit your notebook'), findsOneWidget);
        // Save waits until something changed
        expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
        await tester.enterText(
          find.byType(TextField),
          '# Rules\n- Reply in English\n',
        );
        await tester.pump();
        await tester.tap(saveButton());
        await tester.pumpAndSettle();
        final save = fake.of('notebook_save').single;
        expect(save.body, <String, Object?>{
          'text': '# Rules\n- Reply in English\n',
          'expectVersion': 2,
        });
        expect(save.key, isNotNull);
        expect(find.text('Rules'), findsOneWidget);
        expect(find.text('Reply in English'), findsOneWidget);
        expect(find.text('Saved.'), findsOneWidget);
      },
    );

    testWidgets('counts the characters and refuses a text over the limit', (
      tester,
    ) async {
      final fake = FakeBotler(text: '# A\n- one\n');
      await pump(tester, fake, const NotebookScreen());
      await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'x' * 16001);
      await tester.pump();
      expect(find.text('16001 of 16000 characters'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'x' * 16000);
      await tester.pump();
      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    });

    testWidgets(
      'keeps the typed text when the version changed, and saves it over the new one on request',
      (tester) async {
        final fake = FakeBotler()..conflicts = 1;
        await pump(tester, fake, const NotebookScreen());
        await openEditor(tester);
        await tester.enterText(find.byType(TextField), '# Mine\n- my words\n');
        await tester.pump();
        await tester.tap(saveButton());
        await tester.pumpAndSettle();
        // The conflict is explained and the text is still in the field
        expect(find.text('The notebook changed'), findsOneWidget);
        expect(find.text('Keep editing'), findsOneWidget);
        expect(find.text('Copy my text'), findsOneWidget);
        await tester.tap(find.text('Save mine'));
        await tester.pumpAndSettle();
        // It read the newest version first, then saved from it
        final saves = fake.of('notebook_save').toList();
        expect(saves, hasLength(2));
        expect(saves.first.body['expectVersion'], 2);
        expect(saves.last.body['expectVersion'], 3);
        expect(saves.last.body['text'], '# Mine\n- my words\n');
        expect(fake.text, '# Mine\n- my words\n');
        // What it replaced is in the changes
        expect(fake.revisions.length, greaterThanOrEqualTo(2));
      },
    );

    testWidgets(
      'can keep editing or copy after a conflict, and the text stays',
      (tester) async {
        final fake = FakeBotler()..conflicts = 1;
        await pump(tester, fake, const NotebookScreen());
        await openEditor(tester);
        await tester.enterText(find.byType(TextField), 'my text');
        await tester.pump();
        await tester.tap(saveButton());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.text('my text'), findsOneWidget);
        expect(find.text('Edit your notebook'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps the text when the connection is lost, and a retry carries the same request id',
      (tester) async {
        final fake = FakeBotler()..drops = 1;
        await pump(tester, fake, const NotebookScreen());
        await openEditor(tester);
        await tester.enterText(find.byType(TextField), '# Rules\n- later\n');
        await tester.pump();
        await tester.tap(saveButton());
        await tester.pumpAndSettle();
        expect(find.textContaining('No connection'), findsOneWidget);
        expect(find.text('# Rules\n- later\n'), findsOneWidget);
        await tester.tap(saveButton());
        await tester.pumpAndSettle();
        final saves = fake.of('notebook_save').toList();
        expect(saves, hasLength(2));
        expect(saves.first.key, saves.last.key);
        expect(fake.text, '# Rules\n- later\n');
      },
    );

    testWidgets(
      'asks before throwing typed words away, and lets go when nothing changed',
      (tester) async {
        final fake = FakeBotler();
        await pump(tester, fake, const NotebookScreen());
        await openEditor(tester);
        // Nothing typed: it closes at once
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        expect(find.text('Edit your notebook'), findsNothing);
        await openEditor(tester);
        await tester.enterText(find.byType(TextField), 'typed');
        await tester.pump();
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        expect(find.text('Leave without saving?'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('Edit your notebook'), findsOneWidget);
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
        await tester.pumpAndSettle();
        expect(find.text('Edit your notebook'), findsNothing);
        expect(fake.of('notebook_save'), isEmpty);
      },
    );
  });

  group('the changes', () {
    testWidgets('lists who changed it, and restores one after a confirm', (
      tester,
    ) async {
      final fake = FakeBotler(text: '# Now\n- current words\n', version: 4)
        ..revisions = <Map<String, Object?>>[
          <String, Object?>{
            'id': 'rev-b',
            'version': 3,
            'actor': 'agent',
            'at': '2026-10-27T03:00:00.000Z',
            'chars': 20,
            'preview': '# Before Botler\n- older words',
          },
          <String, Object?>{
            'id': 'rev-a',
            'version': 1,
            'actor': 'seed',
            'at': '2026-10-26T03:00:00.000Z',
            'chars': 20,
            'preview': '# Raw draft',
          },
        ];
      await pump(tester, fake, const NotebookScreen());
      await openMenuItem(tester, 'Changes');
      expect(find.textContaining('Botler ·'), findsOneWidget);
      expect(find.textContaining('Tidy-up ·'), findsOneWidget);
      expect(find.textContaining('# Before Botler'), findsOneWidget);
      // Restore asks first, and Not now changes nothing
      await tester.tap(find.widgetWithText(TextButton, 'Restore').first);
      await tester.pumpAndSettle();
      expect(find.text('Put this text back?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(fake.of('notebook_restore'), isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'Restore').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(fake.of('notebook_restore').single.body, <String, Object?>{
        'revisionId': 'rev-b',
      });
      // The sheet closes and the page shows the restored text
      expect(find.text('Put this text back?'), findsNothing);
      expect(find.text('Before Botler'), findsOneWidget);
      expect(find.text('Restored.'), findsOneWidget);
    });

    testWidgets('says so when there are no changes yet', (tester) async {
      await pump(tester, FakeBotler(), const NotebookScreen());
      await openMenuItem(tester, 'Changes');
      expect(find.text('No changes yet.'), findsOneWidget);
    });
  });

  group('the private names', () {
    testWidgets(
      'shows the names as chips, adds one, removes one and saves the whole list',
      (tester) async {
        final fake = FakeBotler()..people = <String>['Mama', 'Ate Liza'];
        await pump(tester, fake, const NotebookScreen());
        await openMenuItem(tester, 'Private names');
        expect(find.byKey(const ValueKey<String>('name.Mama')), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('name.Ate Liza')),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField), 'Nena Reyes');
        await tester.tap(find.widgetWithText(TextButton, 'Add'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('name.Nena Reyes')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Remove Mama'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(fake.of('profile_set').single.body, <String, Object?>{
          'people': <String>['Ate Liza', 'Nena Reyes'],
        });
        // Only the names: the persona and about lines are not sent, so they are not touched
        expect(
          fake.of('profile_set').single.body.containsKey('persona'),
          isFalse,
        );
      },
    );

    testWidgets(
      'adds a name that was typed but not added when Save is tapped',
      (tester) async {
        final fake = FakeBotler()..people = <String>[];
        await pump(tester, fake, const NotebookScreen());
        await openMenuItem(tester, 'Private names');
        await tester.enterText(find.byType(TextField), 'Ben');
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(fake.of('profile_set').single.body['people'], <String>['Ben']);
      },
    );
  });

  group('wipe and copy', () {
    testWidgets('wipes only after the word is typed, and says what it erases', (
      tester,
    ) async {
      final fake = FakeBotler();
      await pump(tester, fake, const NotebookScreen());
      await openMenuItem(tester, 'Wipe the notebook and conversations');
      expect(
        find.textContaining('deletes your notebook and its changes'),
        findsOneWidget,
      );
      // A wrong word does nothing
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.widgetWithText(FilledButton, 'Wipe'));
      await tester.pumpAndSettle();
      expect(fake.of('memory_wipe'), isEmpty);
      await openMenuItem(tester, 'Wipe the notebook and conversations');
      await tester.enterText(find.byType(TextField), 'WIPE');
      await tester.tap(find.widgetWithText(FilledButton, 'Wipe'));
      await tester.pumpAndSettle();
      expect(fake.of('memory_wipe').single.body, <String, Object?>{
        'confirm': true,
      });
    });

    testWidgets('a wipe also clears the pages kept on the phone', (
      tester,
    ) async {
      final fake = FakeBotler();
      await pump(tester, fake, const NotebookScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotebookScreen)),
      );
      await container.read(pageCacheProvider).saveRecents(<RecentPage>[
        RecentPage(
          id: 'p-1',
          title: 'Wi-Fi',
          notebook: 'Home manual',
          at: DateTime(2026, 10, 30),
        ),
      ]);
      container.invalidate(recentsProvider);
      expect(container.read(recentsProvider), hasLength(1));
      await openMenuItem(tester, 'Wipe the notebook and conversations');
      await tester.enterText(find.byType(TextField), 'WIPE');
      await tester.tap(find.widgetWithText(FilledButton, 'Wipe'));
      await tester.pumpAndSettle();
      expect(fake.of('memory_wipe'), hasLength(1));
      expect(container.read(pageCacheProvider).recents(), isEmpty);
      expect(container.read(recentsProvider), isEmpty);
    });
  });

  group('deleting a goal', () {
    Map<String, Object?> goal(String id, String name) => <String, Object?>{
      'id': id,
      'name': name,
      'perPayday': 100000,
      'targetAmount': null,
      'active': true,
    };

    testWidgets('asks first and does nothing on Not now', (tester) async {
      final fake = FakeBotler()
        ..goals = <Map<String, Object?>>[goal('g1', 'Phone repair')];
      await pump(tester, fake, const GoalsScreen());
      await tester.tap(find.byTooltip('More about this goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for good'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this goal?'), findsOneWidget);
      expect(find.textContaining('Phone repair'), findsWidgets);
      expect(
        find.textContaining('The money you saved for it stays where it is'),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(fake.of('goal_delete'), isEmpty);
      expect(find.text('Phone repair'), findsOneWidget);
    });

    testWidgets(
      'deletes the goal after the confirm and the list no longer shows it',
      (tester) async {
        final fake = FakeBotler()
          ..goals = <Map<String, Object?>>[
            goal('g1', 'Phone repair'),
            goal('g2', 'Holiday'),
          ];
        await pump(tester, fake, const GoalsScreen());
        await tester.tap(find.byTooltip('More about this goal').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete for good'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete it'));
        await tester.pumpAndSettle();
        expect(fake.of('goal_delete').single.body, <String, Object?>{
          'goalId': 'g1',
        });
        expect(find.text('Phone repair'), findsNothing);
        expect(find.text('Holiday'), findsOneWidget);
        expect(find.text('Deleted.'), findsOneWidget);
      },
    );

    testWidgets('keeps the on and off switch beside the menu', (tester) async {
      final fake = FakeBotler()
        ..goals = <Map<String, Object?>>[goal('g1', 'Phone repair')];
      await pump(tester, fake, const GoalsScreen());
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byTooltip('More about this goal'), findsOneWidget);
    });
  });
}
