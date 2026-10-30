// A FAKE BOTLER SERVER FOR THE LIBRARY TESTS: NOTEBOOKS WITH PAGES, THE OUTLINE, ONE PAGE, PIN, RENAME, MOVE, DELETE, SEARCH, SAVE AND THE
// SEEN MARK, WITH SWITCHES FOR "NO CONNECTION" AND "AN OLDER SERVER". Every call is recorded with its idempotency key.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class LibCall {
  const LibCall(this.verb, this.body, this.key);

  final String verb;
  final Json body;
  final String? key;
}

/// An earlier text of a page, kept when the page is saved over (version is the one that text was).
class FakeRevision {
  FakeRevision(this.id, this.version, this.text, {this.actor = 'agent'});

  final String id;
  final int version;
  final String text;

  /// Who made the change that replaced this text.
  final String actor;
}

class FakePage {
  FakePage(
    this.id,
    this.notebookId,
    this.title, {
    this.parent,
    this.text = '',
    this.version = 1,
    this.seen = 0,
    this.by = 'user',
    this.pinnedAt,
    this.userMade = false,
  });

  final String id;
  String notebookId;
  String? parent;
  String title;
  String text;
  int version;
  int seen;
  String by;
  String? pinnedAt;
  bool deleted = false;
  String? deletedAt;

  /// The person made the page; Botler only renamed or moved it (the version stays).
  final bool userMade;
  final List<FakeRevision> revisions = <FakeRevision>[];

  /// Saved over: the text it had goes to the revisions, with who replaced it.
  void keep({String actor = 'agent'}) => revisions.add(
    FakeRevision('rev-$id-$version', version, text, actor: actor),
  );

  /// Botler made the latest change to the text.
  bool get textChangedByBotler {
    for (final r in revisions) {
      if (r.version == version - 1) return r.actor == 'agent';
    }
    return false;
  }
}

class FakeNotebook {
  FakeNotebook(this.id, this.title, {this.summary = '', this.pinnedAt});

  final String id;
  String title;
  String summary;
  String? pinnedAt;
}

class FakeLibrary {
  FakeLibrary({List<FakeNotebook>? books, List<FakePage>? pages})
    : books = books ?? <FakeNotebook>[],
      pages = pages ?? <FakePage>[];

  final List<FakeNotebook> books;
  final List<FakePage> pages;
  final List<LibCall> calls = <LibCall>[];

  /// Every call fails as if the phone had no connection.
  bool offline = false;

  /// The server does not know the page verbs (an older server).
  bool oldServer = false;

  /// Every call fails with a server error.
  bool broken = false;

  /// The next saves answer CONFLICT.
  int conflicts = 0;

  /// The search answers that there are more matches than it lists.
  bool searchMore = false;

  /// The next search is slow by this long, to test an old answer arriving late.
  Duration searchDelay = Duration.zero;

  /// The next page_get is slow by this long, to test a wipe that comes while a page is on its way.
  Duration pageGetDelay = Duration.zero;

  /// How many saved changes the server keeps per page (the real one keeps 50).
  int revisionsKept = 50;

  /// The activity feed names this many versions less than the page has now (the owner wrote on it after Botler did).
  int activityVersionLag = 0;

  /// When Botler's changes in the activity feed happened (an ISO time).
  String activityAt = '2026-10-30T01:00:00.000Z';

  /// When a page deleted now counts as deleted (an ISO time).
  String deletedAtStamp = '2026-10-20T01:00:00.000Z';

  Iterable<LibCall> of(String verb) => calls.where((c) => c.verb == verb);

  FakePage? page(String id) {
    for (final p in pages) {
      if (p.id == id && !p.deleted) return p;
    }
    return null;
  }

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

  Json _line(FakePage p, int position) => <String, Object?>{
    'id': p.id,
    'parentPageId': p.parent,
    'parent': p.parent == null ? null : page(p.parent!)?.title,
    'title': p.title,
    'position': position,
    'chars': p.text.length,
    'version': p.version,
    'seenVersion': p.seen,
    'pinnedAt': p.pinnedAt,
    'updatedBy': p.by,
    'updatedAt': '2026-10-30T01:00:00.000Z',
    'deletedAt': p.deletedAt,
  };

  Json outline() => <String, Object?>{
    'notebooks': <Json>[
      for (final b in books)
        () {
          final mine = pages
              .where((p) => p.notebookId == b.id && !p.deleted)
              .toList();
          final ordered = <FakePage>[];
          for (final top in mine.where((p) => p.parent == null)) {
            ordered.add(top);
            ordered.addAll(mine.where((p) => p.parent == top.id));
          }
          return <String, Object?>{
            'id': b.id,
            'title': b.title,
            'summary': b.summary,
            'pinnedAt': b.pinnedAt,
            'pageCount': ordered.length,
            'pages': <Json>[
              for (var i = 0; i < ordered.length; i++) _line(ordered[i], i),
            ],
          };
        }(),
    ],
    'deleted': false,
    'maxPages': 500,
  };

  /// The deleted pages, each notebook with its own.
  Json deletedOutline() => <String, Object?>{
    'notebooks': <Json>[
      for (final b in books)
        <String, Object?>{
          'id': b.id,
          'title': b.title,
          'summary': b.summary,
          'pinnedAt': b.pinnedAt,
          'pageCount': 0,
          'pages': <Json>[
            for (final p in pages.where(
              (p) => p.notebookId == b.id && p.deleted,
            ))
              _line(p, 0),
          ],
        },
    ],
    'deleted': true,
    'maxPages': 500,
  };

  Json view(FakePage p) {
    final book = books.firstWhere((b) => b.id == p.notebookId);
    final kids = pages.where((k) => k.parent == p.id && !k.deleted);
    return <String, Object?>{
      'id': p.id,
      'notebookId': p.notebookId,
      'notebook': book.title,
      'parentPageId': p.parent,
      'parent': p.parent == null ? null : page(p.parent!)?.title,
      'title': p.title,
      'text': p.text,
      'version': p.version,
      'position': 0,
      'pinnedAt': p.pinnedAt,
      'seenVersion': p.seen,
      'updatedBy': p.by,
      'updatedAt': '2026-10-30T01:00:00.000Z',
      'createdAt': '2026-10-29T01:00:00.000Z',
      'chars': p.text.length,
      'maxChars': 30000,
      'subpages': <Json>[
        for (final k in kids)
          <String, Object?>{
            'id': k.id,
            'title': k.title,
            'chars': k.text.length,
            'version': k.version,
            'position': 0,
            'updatedAt': '2026-10-30T01:00:00.000Z',
          },
      ],
    };
  }

  Future<http.Response> _handle(http.Request r) async {
    final verb = r.url.pathSegments.last;
    final body = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    calls.add(LibCall(verb, body, r.headers['idempotency-key']));
    if (offline) throw http.ClientException('no connection');
    if (broken) return _err(500, 'INTERNAL', 'Something went wrong');
    final pageVerbs = verb.startsWith('page_') || verb == 'notebook_outline';
    if (oldServer && pageVerbs) {
      return _err(404, 'NOT_FOUND', 'There is no such operation: $verb');
    }
    final id = body['pageId'];
    switch (verb) {
      case 'notebook_outline':
        return _ok(body['deleted'] == true ? deletedOutline() : outline());
      case 'page_get':
        final wait = pageGetDelay;
        pageGetDelay = Duration.zero;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        return _ok(view(p));
      case 'page_seen':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'That page is gone.');
        p.seen = body['version']! as int;
        return _ok(<String, Object?>{
          'pageId': p.id,
          'seenVersion': p.seen,
          'version': p.version,
        });
      case 'page_pin':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        p.pinnedAt = body['pinned'] == true ? '2026-10-30T02:00:00.000Z' : null;
        return _ok(view(p));
      case 'notebook_pin':
        final b = books.firstWhere((x) => x.id == body['notebookId']);
        b.pinnedAt = body['pinned'] == true ? '2026-10-30T02:00:00.000Z' : null;
        return _ok(<String, Object?>{'id': b.id, 'pinnedAt': b.pinnedAt});
      case 'page_rename':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        p.title = body['newTitle']! as String;
        return _ok(view(p));
      case 'page_move':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        p.notebookId = (body['toNotebookId'] as String?) ?? p.notebookId;
        p.parent = body['toParentPageId'] as String?;
        return _ok(view(p));
      case 'page_delete':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        p.deleted = true;
        p.deletedAt = deletedAtStamp;
        for (final k in pages.where((k) => k.parent == p.id)) {
          k.deleted = true;
          k.deletedAt = deletedAtStamp;
        }
        return _ok(<String, Object?>{
          'removed': view(p),
          'alsoRemoved': <Object?>[],
          'note': '',
        });
      case 'page_create':
        final made = FakePage(
          'new-${pages.length + 1}',
          body['notebookId']! as String,
          body['title']! as String,
          parent: body['parentPageId'] as String?,
          text: (body['text'] as String?) ?? '',
        );
        pages.add(made);
        return _ok(view(made));
      case 'page_save':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        if (conflicts > 0) {
          conflicts--;
          p.keep();
          p
            ..text = '${p.text}\nAdded by Botler.'
            ..version += 1
            ..by = 'agent';
          return _err(409, 'CONFLICT', 'The page changed.');
        }
        if (body['expectVersion'] != p.version) {
          return _err(409, 'CONFLICT', 'The page changed.');
        }
        p.keep(actor: 'user');
        // The server marks the person's own version as seen
        p
          ..text = body['text']! as String
          ..version += 1
          ..by = 'user'
          ..seen = p.version;
        return _ok(<String, Object?>{...view(p), 'changed': true});
      case 'notebook_search':
        final q = (body['query']! as String).toLowerCase();
        final wait = searchDelay;
        searchDelay = Duration.zero;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        return _ok(<String, Object?>{
          'results': <Json>[
            for (final p in pages)
              if (!p.deleted &&
                  (p.title.toLowerCase().contains(q) ||
                      p.text.toLowerCase().contains(q)))
                <String, Object?>{
                  'pageId': p.id,
                  'notebookId': p.notebookId,
                  'notebook': books
                      .firstWhere((b) => b.id == p.notebookId)
                      .title,
                  'page': p.title,
                  'parent': p.parent == null ? null : page(p.parent!)?.title,
                  'matchIn': p.title.toLowerCase().contains(q)
                      ? 'title'
                      : 'text',
                  'snippet': p.text
                      .split('\n')
                      .firstWhere(
                        (l) => l.toLowerCase().contains(q),
                        orElse: () => p.text.split('\n').first,
                      ),
                  'updatedAt': '2026-10-30T01:00:00.000Z',
                },
          ],
          'more': searchMore,
        });
      case 'page_backlinks':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        final book = books.firstWhere((b) => b.id == p.notebookId).title;
        return _ok(<String, Object?>{
          'links': <Json>[
            for (final o in pages)
              if (!o.deleted &&
                  o.id != p.id &&
                  (o.text.contains('[[${p.title}]]') ||
                      o.text.contains('[[$book/${p.title}]]')))
                <String, Object?>{
                  'pageId': o.id,
                  'notebookId': o.notebookId,
                  'notebook': books
                      .firstWhere((b) => b.id == o.notebookId)
                      .title,
                  'page': o.title,
                  'snippet': o.text
                      .split('\n')
                      .firstWhere((l) => l.contains('[[')),
                },
          ],
        });
      case 'page_activity':
        return _ok(<String, Object?>{
          'pages': <Json>[
            for (final p in pages)
              if (!p.deleted && p.by == 'agent')
                <String, Object?>{
                  'pageId': p.id,
                  'notebookId': p.notebookId,
                  'notebook': books
                      .firstWhere((b) => b.id == p.notebookId)
                      .title,
                  'page': p.title,
                  'version': p.version - activityVersionLag,
                  'seenVersion': p.seen,
                  'updatedAt': activityAt,
                  'created': p.version == 1 && !p.userMade,
                  'textChanged': p.textChangedByBotler,
                },
          ],
        });
      case 'page_revisions':
        final p = page('$id');
        if (p == null) return _err(404, 'NOT_FOUND', 'The page is gone.');
        final newest = p.revisions.toList()
          ..sort((a, b) => b.version.compareTo(a.version));
        return _ok(<String, Object?>{
          'revisions': <Json>[
            for (final r in newest.take(revisionsKept))
              <String, Object?>{
                'id': r.id,
                'version': r.version,
                'actor': r.actor,
                'at': '2026-10-30T01:00:00.000Z',
                'chars': r.text.length,
                'preview': r.text,
              },
          ],
        });
      case 'page_revision_get':
        for (final p in pages) {
          for (final r in p.revisions) {
            if (r.id == body['revisionId']) {
              return _ok(<String, Object?>{
                'id': r.id,
                'pageId': p.id,
                'version': r.version,
                'actor': r.actor,
                'at': '2026-10-30T01:00:00.000Z',
                'text': r.text,
                'chars': r.text.length,
              });
            }
          }
        }
        return _err(404, 'NOT_FOUND', 'That change is not there any more.');
      case 'page_restore':
        for (final p in pages) {
          for (final r in p.revisions) {
            if (r.id == body['revisionId']) {
              final back = r.text;
              p.keep(actor: 'user');
              p
                ..text = back
                ..version += 1
                ..by = 'user'
                ..seen = p.version;
              return _ok(view(p));
            }
          }
        }
        return _err(404, 'NOT_FOUND', 'That change is not there any more.');
      case 'page_undelete':
        for (final p in pages) {
          if (p.id == id && p.deleted) {
            p.deleted = false;
            p.deletedAt = null;
            for (final k in pages.where((k) => k.parent == p.id)) {
              k.deleted = false;
              k.deletedAt = null;
            }
            return _ok(view(p));
          }
        }
        return _err(404, 'NOT_FOUND', 'That page is not deleted.');
      default:
        return _ok(<String, Object?>{});
    }
  }

  http.Client get client => MockClient(_handle);

  ApiClient get api => ApiClient(
    base: 'https://botler.test',
    token: () async => 'tok',
    client: client,
  );
}

// -- FUNCTIONS -- //

/// A screen on the fake server inside the app's providers and theme. Pass [prefs] to keep what an earlier visit saved on the phone.
Future<ProviderContainer> pumpLibrary(
  WidgetTester tester,
  FakeLibrary fake,
  Widget home, {
  SharedPreferences? prefs,
  bool settle = true,
}) async {
  SharedPreferences? kept = prefs;
  if (kept == null) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    kept = await SharedPreferences.getInstance();
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(kept),
        apiProvider.overrideWithValue(fake.api),
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// A small library: two notebooks, one with a page that has a sub-page.
FakeLibrary sampleLibrary() => FakeLibrary(
  books: <FakeNotebook>[
    FakeNotebook('nb-1', 'Home manual', summary: 'How things work here'),
    FakeNotebook('nb-2', 'Trip to Japan', summary: 'Flights and hotels'),
  ],
  pages: <FakePage>[
    FakePage(
      'p-1',
      'nb-1',
      'Wi-Fi',
      text: '# Wi-Fi\n\nThe router is in the hall.\n\n## Reset\n\nHold the button.\n',
      by: 'agent',
      version: 2,
      seen: 1,
    ),
    FakePage(
      'p-2',
      'nb-1',
      'Router settings',
      parent: 'p-1',
      text: 'Admin page.',
    ),
    FakePage('p-3', 'nb-1', 'Boiler', text: 'Turn the dial.'),
    FakePage(
      'p-4',
      'nb-2',
      'Flights',
      text: '# Flights\n\nLeave on 3 March.\n',
    ),
  ],
);

/// A piece of text anywhere on screen, rich text included.
Finder richText(String text) => find.text(text, findRichText: true);

/// The semantics label of a Semantics widget on screen.
Finder semanticsLabel(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Taps the link whose words are [words] (calls its tap handler, since a link is one span inside a paragraph).
void tapLinkText(WidgetTester tester, String words) {
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    TapGestureRecognizer? hit;
    r.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == words &&
          span.recognizer is TapGestureRecognizer) {
        hit = span.recognizer! as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    final tap = hit?.onTap;
    if (tap != null) {
      tap();
      return;
    }
  }
  throw StateError('No link with the words "$words" on screen');
}

/// The words marked (bold on a soft background) inside the rich texts on screen.
List<String> markedSpans(WidgetTester tester) {
  final out = <String>[];
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    r.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.style?.backgroundColor != null) {
        out.add(span.text!);
      }
      return true;
    });
  }
  return out;
}
