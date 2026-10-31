// THE STATE OF THE NOTEBOOK LIBRARY (RIVERPOD): THE OUTLINE, ONE PAGE, THE RECENTLY OPENED LIST AND THE WRITES, ALL THROUGH THE VERB CLIENT.
// Reading falls back to the copy kept on the phone when there is no connection (marked offline). Pin, rename and move may be made offline: they are
// kept in the outbox with their request id and a guess is written into the saved copy meanwhile. Save, delete, create and search need the network.
// A refused queued write (the page was deleted meanwhile) is kept in the outbox's failed list; the outline is read again after every flush.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/json.dart';
import '../core/library.dart';
import '../core/page_cache.dart';
import '../ui/once.dart';
import 'providers.dart';

// -- TYPES -- //

/// What a write did: it reached the server, or it is waiting in the outbox for a connection.
enum WriteResult { done, queued }

// -- CONSTANTS -- //

/// How many pinned pages are fetched in the background after the outline arrives, so they can be read without a connection.
const int _prefetchPinnedMax = 10;

// -- STATES -- //

bool _prefetching = false;
(ApiClient, PageCache, Library)? _prefetchAgain;

final Provider<PageCache> pageCacheProvider = Provider<PageCache>(
  (ref) => PageCache(ref.watch(prefsProvider)),
);

/// Every notebook with its pages (the main notebook is not in it). Without a connection, the copy kept on the phone, marked offline.
/// An older server that does not know the page verbs gives [ServerTooOld].
final FutureProvider<Library> libraryProvider =
    FutureProvider.autoDispose<Library>((ref) async {
      final api = ref.watch(apiProvider);
      final cache = ref.watch(pageCacheProvider);
      try {
        final library = Library.fromOutline(
          await api.verbJson('notebook_outline'),
        );
        await cache.saveLibrary(library);
        await _pruneCache(cache, library);
        unawaited(_prefetchPinned(api, cache, library));
        return library;
      } on ApiException catch (e) {
        if (isUnknownVerb(e)) throw const ServerTooOld();
        if (e.isNetwork) {
          final kept = cache.library();
          if (kept != null) return kept;
        }
        rethrow;
      }
    });

/// One page with its text. Without a connection, the saved copy (marked offline). A page the server does not have gives [PageGone].
final pageProvider = FutureProvider.autoDispose.family<PageDoc, String>((
  ref,
  pageId,
) async {
  final api = ref.watch(apiProvider);
  final cache = ref.watch(pageCacheProvider);
  try {
    final doc = PageDoc.fromJson(
      await api.verbJson('page_get', <String, Object?>{'pageId': pageId}),
    );
    await cache.savePage(doc);
    return doc;
  } on ApiException catch (e) {
    if (isUnknownVerb(e)) throw const ServerTooOld();
    if (e.isNetwork) {
      final kept = cache.page(pageId);
      if (kept != null) return kept;
    }
    if (e.code == 'NOT_FOUND') {
      await cache.forgetPage(pageId);
      throw PageGone(pageId);
    }
    rethrow;
  }
});

/// The pages opened lately, newest first. Kept on this phone only.
final NotifierProvider<RecentsNotifier, List<RecentPage>> recentsProvider =
    NotifierProvider<RecentsNotifier, List<RecentPage>>(RecentsNotifier.new);

final Provider<LibraryActions> libraryActionsProvider =
    Provider<LibraryActions>(LibraryActions.new);

// -- FUNCTIONS -- //

/// The server answered that it has no such operation: it is older than the app.
bool isUnknownVerb(ApiException e) =>
    e.code == 'NOT_FOUND' && e.message.contains('no such operation');

/// Fetches the text of pinned pages that are not on the phone yet (or only an older version), so they can be read offline. Stops at the
/// first lost connection and never reports a failure: it is an extra.
Future<void> _prefetchPinned(
  ApiClient api,
  PageCache cache,
  Library library,
) async {
  // One loop at a time: a reload that comes while it runs asks for one more round with the newest outline, never a second parallel loop
  if (_prefetching) {
    _prefetchAgain = (api, cache, library);
    return;
  }
  _prefetching = true;
  try {
    await _prefetchRound(api, cache, library);
  } finally {
    _prefetching = false;
  }
  final again = _prefetchAgain;
  _prefetchAgain = null;
  if (again != null) await _prefetchPinned(again.$1, again.$2, again.$3);
}

/// Forgets the saved text of pages the fresh outline no longer has (deleted, merged or wiped elsewhere). Only called with an outline that
/// came from the server, never with the offline copy.
Future<void> _pruneCache(PageCache cache, Library library) async {
  for (final id in cache.cachedIds()) {
    if (library.page(id) == null) await cache.forgetPage(id);
  }
}

Future<void> _prefetchRound(
  ApiClient api,
  PageCache cache,
  Library library,
) async {
  var left = _prefetchPinnedMax;
  final generation = cache.generation;
  for (final p in library.pinnedPages) {
    if (left == 0) return;
    if (cache.cachedVersion(p.id) == p.version) continue;
    left--;
    try {
      final j = await api.verbJson('page_get', <String, Object?>{
        'pageId': p.id,
      });
      // A wipe (a data reset, the notebook wipe) came while the page was on its way: it is not kept
      if (cache.generation != generation) return;
      await cache.savePage(PageDoc.fromJson(j));
    } on ApiException catch (e) {
      if (e.isNetwork) return;
    }
  }
}

class RecentsNotifier extends Notifier<List<RecentPage>> {
  @override
  List<RecentPage> build() => ref.watch(pageCacheProvider).recents();

  Future<void> _set(List<RecentPage> next) async {
    state = next;
    await ref.read(pageCacheProvider).saveRecents(next);
  }

  /// This page was opened now: it goes first.
  Future<void> touch(PageDoc doc) => _set(
    <RecentPage>[
      RecentPage(
        id: doc.id,
        title: doc.title,
        notebook: doc.notebook,
        at: DateTime.now(),
      ),
      ...state.where((r) => r.id != doc.id),
    ].take(maxRecents).toList(),
  );

  Future<void> forget(String pageId) async {
    if (state.any((r) => r.id == pageId)) {
      await _set(state.where((r) => r.id != pageId).toList());
    }
  }

  /// Drops the pages that are not in the library any more. Only called with an outline that came from the server.
  Future<void> prune(Set<String> live) async {
    if (state.every((r) => live.contains(r.id))) return;
    await _set(state.where((r) => live.contains(r.id)).toList());
  }
}

/// The writes of the library screens. A write that can wait ([pinPage], [pinNotebook], [renamePage], [movePage]) goes to the outbox when
/// there is no connection; the others throw the ApiException so the screen can say "needs a connection".
class LibraryActions {
  LibraryActions(this._ref);

  final Ref _ref;

  // -- STATES -- //
  // One key per intent (the verb and its arguments) until it works, and no second call of the same intent while one runs
  final Once _once = Once();

  void _reread([String? pageId]) {
    _ref.invalidate(libraryProvider);
    if (pageId != null) _ref.invalidate(pageProvider(pageId));
  }

  Future<void> _patchLibrary(Library Function(Library) change) async {
    final cache = _ref.read(pageCacheProvider);
    final kept = cache.library();
    if (kept != null) await cache.saveLibrary(change(kept));
  }

  Future<void> _patchPage(String id, PageDoc Function(PageDoc) change) async {
    final cache = _ref.read(pageCacheProvider);
    final kept = cache.page(id);
    if (kept != null) await cache.savePage(change(kept));
  }

  /// Sends [verb] under a fresh request id. With no connection the same id goes to the outbox, [guess] is written into the saved copy and
  /// the answer is [WriteResult.queued]. Any other failure is thrown.
  Future<WriteResult> _queueable(
    String verb,
    Json args, {
    required Future<void> Function() guess,
    String? pageId,
  }) async {
    final intent = '$verb:${jsonEncode(args)}';
    // The same thing asked again while it is on its way is the first call's business: nothing is sent or queued a second time
    if (_once.running(intent)) return WriteResult.done;
    final key = _once.key(intent);
    final result = await _once.run((_) async {
      try {
        await _ref.read(apiProvider).verb(verb, args, key);
        _reread(pageId);
        return WriteResult.done;
      } on ApiException catch (e) {
        if (!e.isNetwork) rethrow;
        // Kept under the same key: if the first try did arrive, the server knows it and does not do it twice
        await _ref.read(outboxProvider).add(verb, args, key: key);
        _ref.read(outboxCountProvider.notifier).refresh();
        await guess();
        _reread(pageId);
        return WriteResult.queued;
      }
    }, intent: intent);
    return result ?? WriteResult.done;
  }

  Future<WriteResult> pinPage(String pageId, {required bool pinned}) =>
      _queueable(
        'page_pin',
        <String, Object?>{'pageId': pageId, 'pinned': pinned},
        pageId: pageId,
        guess: () async {
          final now = DateTime.now().toUtc().toIso8601String();
          await _patchLibrary(
            (l) => l.withPage(
              pageId,
              (p) => pinned
                  ? p.copyWith(pinnedAt: now)
                  : p.copyWith(clearPin: true),
            ),
          );
          await _patchPage(
            pageId,
            (d) =>
                pinned ? d.copyWith(pinnedAt: now) : d.copyWith(clearPin: true),
          );
        },
      );

  Future<WriteResult> pinNotebook(String notebookId, {required bool pinned}) =>
      _queueable(
        'notebook_pin',
        <String, Object?>{'notebookId': notebookId, 'pinned': pinned},
        guess: () => _patchLibrary(
          (l) => l.withNotebook(
            notebookId,
            (n) => pinned
                ? n.copyWith(pinnedAt: DateTime.now().toUtc().toIso8601String())
                : n.copyWith(clearPin: true),
          ),
        ),
      );

  Future<WriteResult> renamePage(String pageId, String newTitle) => _queueable(
    'page_rename',
    <String, Object?>{'pageId': pageId, 'newTitle': newTitle},
    pageId: pageId,
    guess: () async {
      await _patchLibrary(
        (l) => l.withPage(pageId, (p) => p.copyWith(title: newTitle)),
      );
      await _patchPage(pageId, (d) => d.copyWith(title: newTitle));
    },
  );

  /// Moves a page to another notebook ([toNotebookId]) and/or under a top-level page ([toParentPageId]); neither means the top level of its
  /// own notebook. [position] is the place among its new siblings (0 is first).
  Future<WriteResult> movePage(
    String pageId, {
    String? toNotebookId,
    String? toParentPageId,
    int? position,
  }) => _queueable(
    'page_move',
    <String, Object?>{
      'pageId': pageId,
      'toNotebookId': ?toNotebookId,
      'toParentPageId': ?toParentPageId,
      'position': ?position,
    },
    pageId: pageId,
    guess: () => _patchLibrary(
      (l) => l.withMoved(
        pageId,
        toNotebookId: toNotebookId,
        toParentPageId: toParentPageId,
        position: position,
      ),
    ),
  );

  /// Needs a connection. The page and its sub-pages are hidden for 30 days; the answer holds what was removed.
  Future<Json> deletePage(String pageId) async {
    final answer = asJson(
      await _once.run<Object?>(
        (key) => _ref.read(apiProvider).verb('page_delete', <String, Object?>{
          'pageId': pageId,
        }, key),
        intent: 'page_delete:$pageId',
      ),
    );
    await _ref.read(pageCacheProvider).forgetPage(pageId);
    await _ref.read(recentsProvider.notifier).forget(pageId);
    _reread();
    return answer;
  }

  /// Needs a connection. Puts a deleted page (and the sub-pages deleted with it) back.
  Future<void> restorePage(String pageId) async {
    await _once.run((key) async {
      await _ref.read(apiProvider).verb('page_undelete', <String, Object?>{
        'pageId': pageId,
      }, key);
    }, intent: 'page_undelete:$pageId');
    _reread();
  }

  /// Needs a connection. A new page, empty or with [text], under [parentPageId] when it is a sub-page.
  Future<PageDoc> createPage(
    String notebookId,
    String title, {
    String? parentPageId,
    String? text,
  }) async {
    final body = <String, Object?>{
      'notebookId': notebookId,
      'title': title,
      'parentPageId': ?parentPageId,
      'text': ?text,
    };
    // The intent is the whole body: the same page asked for twice is one page, a different one is another
    final answer = asJson(
      await _once.run<Object?>(
        (key) => _ref.read(apiProvider).verb('page_create', body, key),
        intent: 'page_create:${jsonEncode(body)}',
      ),
    );
    if (answer.isEmpty) {
      // A second tap while the first create is on its way: the first one's screen takes the page
      throw ApiException(
        'CONFLICT',
        'That page is already being created.',
        409,
      );
    }
    _reread();
    return PageDoc.fromJson(answer);
  }

  /// The person looked at this version of the page. Fire and forget: a failure changes nothing the person can see.
  Future<void> markSeen(PageDoc doc) async {
    try {
      // A mark of what was seen: the same page and version always give the same request, so one key per pair is stable
      await _ref.read(apiProvider).verb('page_seen', <String, Object?>{
        'pageId': doc.id,
        'version': doc.version,
      }, _once.key('page_seen:${doc.id}:${doc.version}'));
      // The library on screen shows no dot for this version (opening a page Botler did not just write): nothing to read again. Else the saved
      // copy is patched and the library is read again; a provider cannot be patched in place, so it is the read that clears the dot.
      final known = _ref.read(libraryProvider).asData?.value.page(doc.id);
      if (known != null &&
          known.version == doc.version &&
          !known.botlerUpdated) {
        return;
      }
      await _patchLibrary(
        (l) => l.withPage(
          doc.id,
          (p) => p.version == doc.version && p.seenVersion < doc.version
              ? p.copyWith(seenVersion: doc.version)
              : p,
        ),
      );
      _ref.invalidate(libraryProvider);
    } on Object {
      // The mark is only a nicety; the dot stays until the next time
    }
  }

  /// Everything about the library is read again (after an edit, a restore or a change of a notebook).
  void refresh([String? pageId]) => _reread(pageId);
}
