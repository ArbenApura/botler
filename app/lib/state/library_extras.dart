// THE STATE AROUND A PAGE (RIVERPOD): SEARCH, THE PAGES THAT LINK HERE, WHAT CHANGED SINCE THE PERSON LAST READ, BOTLER'S RECENT CHANGES AND UNDOING ONE.
// All of it needs the server and fails quietly when there is no connection (nothing is invented from the phone's copy). Undo is a plain write that
// is not queued: it checks the page first, so it must be done while the page can be read.

// -- DEP-MODULES -- //
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/json.dart';
import '../core/library.dart';
import '../core/library_extras.dart';
import '../core/line_diff.dart';
import '../ui/once.dart';
import 'library.dart';
import 'providers.dart';

// -- CONSTANTS -- //

/// The Botler changes listed before "show all".
const int activityShown = 3;

// -- TYPES -- //

/// The earlier text Botler replaced is not there (past the kept changes), or the page moved on: nothing is changed.
class UndoUnavailable implements Exception {
  const UndoUnavailable();
}

/// What undoing a change did.
enum UndoResult { restored, deleted }

// -- FUNCTIONS -- //

/// The pages whose text matches [query], at most the server's limit; [SearchAnswer.more] says there are others.
Future<SearchAnswer> searchNotebooks(ApiClient api, String query) async =>
    SearchAnswer.fromJson(
      await api.verbJson('notebook_search', <String, Object?>{'query': query}),
    );

/// Whether Botler's change can be undone from the feed: it made the page or changed its text (a rename or a move is only viewed), and it is
/// still the newest version of the page.
bool canUndoChange(ActivityEntry entry, Library? library) {
  if (!entry.undoable) return false;
  final page = library?.page(entry.pageId);
  if (page == null) return false;
  return page.version == entry.version && page.updatedBy == 'agent';
}

// -- PROVIDERS -- //

/// The pages that link to this one. An empty list when there is no connection or the server cannot say.
final backlinksProvider = FutureProvider.autoDispose
    .family<List<Backlink>, String>((ref, pageId) async {
      try {
        final answer = await ref.watch(apiProvider).verbJson(
          'page_backlinks',
          <String, Object?>{'pageId': pageId},
        );
        return <Backlink>[
          for (final l in asJsonList(answer['links'])) Backlink.fromJson(l),
        ];
      } on ApiException {
        return <Backlink>[];
      }
    });

/// What changed on a page since the version the person last read: (page id, seen version, current version). The text of the version that was
/// read is the saved change with that version number; when it is gone the change is too big to show line by line.
final pageChangesProvider = FutureProvider.autoDispose
    .family<PageChanges, (String, int, int)>((ref, key) async {
      final (pageId, seen, version) = key;
      if (seen <= 0 || seen >= version) return PageChanges.none;
      final api = ref.watch(apiProvider);
      try {
        final answer = await api.verbJson('page_revisions', <String, Object?>{
          'pageId': pageId,
        });
        Json? read;
        for (final r in asJsonList(answer['revisions'])) {
          if (intOf(r['version']) == seen) read = r;
        }
        if (read == null) return const PageChanges(ChangeKind.tooMuch);
        final old = await api.verbJson('page_revision_get', <String, Object?>{
          'revisionId': str(read['id']),
        });
        final doc = ref.read(pageProvider(pageId)).asData?.value;
        if (doc == null || doc.offline || doc.version != version) {
          return PageChanges.none;
        }
        return PageChanges(
          ChangeKind.lines,
          addedLines(str(old['text']), doc.text),
        );
      } on ApiException {
        return PageChanges.none;
      }
    });

/// The pages Botler changed in the last 14 days, newest first. Empty without a connection.
final activityProvider = FutureProvider.autoDispose<List<ActivityEntry>>((
  ref,
) async {
  try {
    final answer = await ref.watch(apiProvider).verbJson('page_activity');
    return <ActivityEntry>[
      for (final e in asJsonList(answer['pages'])) ActivityEntry.fromJson(e),
    ];
  } on ApiException {
    return <ActivityEntry>[];
  }
});

/// The pages of one notebook that were deleted (and can still be put back), newest deletion first.
final deletedPagesProvider = FutureProvider.autoDispose
    .family<List<LibraryPage>, String>((ref, notebookId) async {
      final answer = await ref.watch(apiProvider).verbJson(
        'notebook_outline',
        <String, Object?>{'deleted': true},
      );
      final book = Library.fromOutline(answer).notebook(notebookId);
      return book?.pages ?? <LibraryPage>[];
    });

final Provider<ChangeActions> changeActionsProvider = Provider<ChangeActions>(
  ChangeActions.new,
);

/// Undoing what Botler did to a page.
class ChangeActions {
  ChangeActions(this._ref);

  final Ref _ref;

  // -- STATES -- //
  // One key per undone revision until it works, and no second call of the same one while it runs
  final Once _once = Once();

  /// Puts back the text Botler replaced (the newest saved change), or deletes the page when Botler made it. Throws [UndoUnavailable] when the
  /// earlier text is not there, and the ApiException of a failed call.
  Future<UndoResult> undo(ActivityEntry entry) async {
    final api = _ref.read(apiProvider);
    final actions = _ref.read(libraryActionsProvider);
    if (!entry.undoable) throw const UndoUnavailable();
    // The page must still be at the version of the entry; else somebody wrote on it since
    final now = _ref.read(libraryProvider).asData?.value.page(entry.pageId);
    if (now == null || now.version != entry.version) {
      throw const UndoUnavailable();
    }
    if (entry.created) {
      await actions.deletePage(entry.pageId);
      _ref.invalidate(activityProvider);
      return UndoResult.deleted;
    }
    final answer = await api.verbJson('page_revisions', <String, Object?>{
      'pageId': entry.pageId,
    });
    final revisions = asJsonList(answer['revisions']);
    // The newest saved change holds the text Botler replaced: it is the one of the version before, and Botler made it
    if (revisions.isEmpty ||
        intOf(revisions.first['version']) != entry.version - 1 ||
        str(revisions.first['actor']) != 'agent') {
      throw const UndoUnavailable();
    }
    final revisionId = str(revisions.first['id']);
    await _once.run((key) async {
      await api.verb('page_restore', <String, Object?>{
        'revisionId': revisionId,
      }, key);
    }, intent: 'page_restore:$revisionId');
    actions.refresh(entry.pageId);
    _ref.invalidate(activityProvider);
    return UndoResult.restored;
  }
}
