// THE LIBRARY: EVERY NOTEBOOK BOTLER KEEPS FOR YOU. THE MAIN NOTEBOOK IS ALWAYS AT THE TOP, THEN THE PAGES YOU PINNED AND OPENED LATELY, THEN THE
// NOTEBOOKS. The one primary action is Search. Asking Botler to file something, copying everything, a new notebook and the deleted notebooks are
// in the overflow menu. The route stays /memory so an older link still opens it. Without a connection the copy kept on the phone is shown.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../memory/notebook_list.dart';
import '../memory/notebook_screen.dart';
import 'activity_feed.dart';
import 'library_actions.dart';
import 'library_search.dart';
import 'library_widgets.dart';
import 'notebook_pages_screen.dart';
import 'page_reader.dart';

// -- CONSTANTS -- //

/// How many recently opened pages the library lists.
const int _recentShown = 5;

// -- TYPES -- //

enum _More { ask, newNotebook, copy, deleted }

// -- WIDGETS -- //

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // -- FUNCTIONS -- //

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    // The screen may be gone by the time the other one closes
    if (!mounted) return;
    // What was changed in there shows here when this page comes back
    ref.invalidate(libraryProvider);
  }

  Future<void> _openNotebook(LibraryNotebook n) =>
      _push(NotebookPagesScreen(notebookId: n.id, title: n.title));

  Future<void> _newNotebook() async {
    final made = await showFormSheet<Json>(
      context,
      title: context.t.notebookNew,
      builder: (sheet, close) => NotebookInfoForm(onDone: close),
    );
    if (!mounted) return;
    ref.read(libraryActionsProvider).refresh();
    if (made != null && mounted) {
      await _push(
        NotebookPagesScreen(
          notebookId: str(made['id']),
          title: str(made['title']),
        ),
      );
    }
  }

  Future<void> _deleted() async {
    await showFormSheet<void>(
      context,
      title: context.t.notebookDeleted,
      builder: (sheet, close) =>
          DeletedNotebooks(onRestored: () => close(null)),
    );
    if (!mounted) return;
    ref.read(libraryActionsProvider).refresh();
  }

  Future<void> _copy() async {
    final copied = context.t.memoryCopied;
    try {
      final all = await ref.read(apiProvider).verb('memory_export');
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(all)),
      );
      if (mounted) say(context, copied);
    } catch (e) {
      if (mounted) say(context, needsNetworkWords(context, e));
    }
  }

  Future<void> _notebookMore(LibraryNotebook n) async {
    final chosen = await showNotebookActions(context, notebook: n);
    if (chosen == null || !mounted) return;
    await runNotebookAction(context, ref, chosen, n);
  }

  void _more(_More what) {
    switch (what) {
      case _More.ask:
        // The chat is where Botler is asked; the library is a screen on top of it
        context.go('/');
      case _More.newNotebook:
        _newNotebook();
      case _More.copy:
        _copy();
      case _More.deleted:
        _deleted();
    }
  }

  // -- WIDGETS -- //

  /// The pages listed outside their notebook: the pinned ones, then the ones opened lately that are not pinned.
  List<Widget> _shortcuts(BuildContext context, Library library) {
    final pinned = library.pinnedPages;
    final pinnedIds = <String>{for (final p in pinned) p.id};
    final recents = ref.watch(recentsProvider);
    final out = <Widget>[];
    String bookOf(LibraryPage p) => library.notebook(p.notebookId)?.title ?? '';
    for (final p in pinned) {
      out.add(
        PageShortcut(
          pageId: p.id,
          title: p.title,
          notebook: bookOf(p),
          pinned: true,
          updated: p.botlerUpdated,
          onOpen: () => openPage(context, p.id, title: p.title),
        ),
      );
    }
    var shown = 0;
    for (final r in recents) {
      if (shown == _recentShown) break;
      if (pinnedIds.contains(r.id)) continue;
      final live = library.page(r.id);
      // An outline from the server is the truth: a recent page missing from it is gone
      if (live == null && !library.offline) continue;
      shown++;
      out.add(
        PageShortcut(
          pageId: r.id,
          title: live?.title ?? r.title,
          notebook: live == null ? r.notebook : bookOf(live),
          updated: live?.botlerUpdated ?? false,
          onOpen: () => openPage(context, r.id, title: r.title),
        ),
      );
    }
    return out;
  }

  Widget _body(BuildContext context, Library library) {
    final c = context.colors;
    final shortcuts = _shortcuts(context, library);
    final books = library.sorted;
    // One builder per row, so a long library is built as it scrolls
    final items = <Widget Function(BuildContext)>[
      (_) => SearchEntry(onTap: () => _push(const LibrarySearchScreen())),
      if (library.offline)
        (_) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OfflineCopyNote(since: library.cachedAt),
        ),
      (_) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 10),
        child: Semantics(
          button: true,
          label: context.t.libraryMain,
          onTap: () => _push(const NotebookScreen()),
          excludeSemantics: true,
          child: PaperCard(
            onTap: () => _push(const NotebookScreen()),
            child: Row(
              children: <Widget>[
                Icon(Icons.psychology_alt_outlined, color: c.accentText),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t.libraryMain,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        context.t.libraryMainLine,
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.muted),
              ],
            ),
          ),
        ),
      ),
      if (shortcuts.isNotEmpty) ...<Widget Function(BuildContext)>[
        (_) => SectionTitle(context.t.libraryPinnedRecent),
        for (final s in shortcuts) (_) => s,
      ],
      // Botler's recent changes: not there at all without a connection
      if (!library.offline)
        (_) => ActivityFeed(
          onOpen: (e) => openPage(context, e.pageId, title: e.page),
        ),
      (_) => SectionTitle(context.t.libraryNotebooks),
      if (books.isEmpty)
        (_) => Note(context.t.libraryEmpty)
      else
        for (final n in books)
          (_) => NotebookCard(
            notebook: n,
            onOpen: () => _openNotebook(n),
            onMore: () => _notebookMore(n),
          ),
    ];
    return RefreshIndicator(
      onRefresh: () => ref.refresh(libraryProvider.future),
      child: ListView.builder(
        padding: pagePadding(context),
        itemCount: items.length,
        itemBuilder: (context, i) => items[i](context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The outline came from the server: the recent pages that are not in it any more are forgotten
    ref.listen<AsyncValue<Library>>(libraryProvider, (_, next) {
      final library = next.asData?.value;
      if (library != null && !library.offline) {
        ref.read(recentsProvider.notifier).prune(<String>{
          for (final p in library.pages) p.id,
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.libraryTitle),
        actions: <Widget>[
          PopupMenuButton<_More>(
            tooltip: context.t.memoryMore,
            onSelected: _more,
            itemBuilder: (_) => <PopupMenuEntry<_More>>[
              PopupMenuItem<_More>(
                value: _More.ask,
                child: Text(context.t.libraryAsk),
              ),
              PopupMenuItem<_More>(
                value: _More.newNotebook,
                child: Text(context.t.notebookNew),
              ),
              PopupMenuItem<_More>(
                value: _More.copy,
                child: Text(context.t.memoryCopyAll),
              ),
              PopupMenuItem<_More>(
                value: _More.deleted,
                child: Text(context.t.notebookDeleted),
              ),
            ],
          ),
        ],
      ),
      body: AsyncBody<Library>(
        value: ref.watch(libraryProvider),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        onRetry: () => ref.invalidate(libraryProvider),
        data: (l) => _body(context, l),
      ),
    );
  }
}
