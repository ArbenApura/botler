// A NOTEBOOK: ITS PAGES AS A LAZY TREE (A PAGE, THEN ITS SUB-PAGES THAT FOLD AWAY). THE ONE PRIMARY ACTION IS TO OPEN THE FIRST PAGE.
// New page, pin, name and summary and delete are in the overflow menu; a press and hold on a page opens its own sheet. The list is built row by
// row, so a notebook of 500 pages is no heavier than one of five. A notebook deleted while this screen is open says so.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'library_actions.dart';
import 'deleted_pages.dart';
import 'library_widgets.dart';
import 'notebook_export.dart';
import 'page_reader.dart';
import 'page_tree.dart';

// -- TYPES -- //

enum _More { newPage, pin, describe, deleted, export, delete }

// -- WIDGETS -- //

class NotebookPagesScreen extends ConsumerStatefulWidget {
  const NotebookPagesScreen({required this.notebookId, this.title, super.key});

  final String notebookId;

  /// The title to show in the bar while the library loads.
  final String? title;

  @override
  ConsumerState<NotebookPagesScreen> createState() =>
      _NotebookPagesScreenState();
}

class _NotebookPagesScreenState extends ConsumerState<NotebookPagesScreen> {
  // -- STATES -- //

  /// The pages whose sub-pages are folded away.
  final Set<String> _collapsed = <String>{};

  // -- FUNCTIONS -- //

  void _toggle(String pageId) => setState(() {
    if (!_collapsed.remove(pageId)) _collapsed.add(pageId);
  });

  Future<void> _more(_More what, LibraryNotebook book) async {
    switch (what) {
      case _More.newPage:
        await _newPage(book);
      case _More.pin:
        await runNotebookAction(context, ref, NotebookAction.pin, book);
      case _More.describe:
        await runNotebookAction(context, ref, NotebookAction.describe, book);
      case _More.deleted:
        await showFormSheet<void>(
          context,
          title: context.t.pageDeletedTitle,
          builder: (sheet, close) =>
              DeletedPages(notebookId: book.id, onRestored: () => close(null)),
        );
        ref.read(libraryActionsProvider).refresh();
      case _More.export:
        await exportNotebook(context, ref, book);
      case _More.delete:
        await runNotebookAction(
          context,
          ref,
          NotebookAction.delete,
          book,
          onDeleted: () {
            if (mounted) Navigator.of(context).pop();
          },
        );
    }
  }

  Future<void> _newPage(LibraryNotebook book) async {
    final actions = ref.read(libraryActionsProvider);
    final made = await showFormSheet<PageDoc>(
      context,
      title: context.t.pageNew,
      builder: (sheet, close) => PageTitleForm(
        label: sheet.t.pageCreate,
        onSubmit: (title) async =>
            close(await actions.createPage(book.id, title)),
      ),
    );
    if (made != null && mounted) {
      await openPage(context, made.id, title: made.title);
    }
  }

  Future<void> _rowMore(LibraryPage page) async {
    final library = ref.read(libraryProvider).asData?.value;
    final mates = library?.siblings(page) ?? const <LibraryPage>[];
    final at = mates.indexWhere((p) => p.id == page.id);
    final chosen = await showPageActions(
      context,
      title: page.title,
      pinned: page.pinned,
      canMoveUp: at > 0,
      canMoveDown: at >= 0 && at < mates.length - 1,
    );
    if (chosen == null || !mounted) return;
    await runPageAction(
      context,
      ref,
      chosen,
      pageId: page.id,
      title: page.title,
      pinned: page.pinned,
    );
  }

  // -- WIDGETS -- //

  Widget _list(BuildContext context, Library library, LibraryNotebook book) {
    final c = context.colors;
    final rows = flattenTree(book.pages, _collapsed);
    // Above the rows: the primary action, the summary and count, the offline note
    const header = 2;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(libraryProvider.future),
      child: ListView.builder(
        padding: pagePadding(context),
        itemCount: header + (rows.isEmpty ? 1 : rows.length),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (library.offline) OfflineCopyNote(since: library.cachedAt),
                if (book.pages.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => openPage(
                      context,
                      book.pages.first.id,
                      title: book.pages.first.title,
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(context.t.notebookOpenFirst),
                  ),
              ],
            );
          }
          if (i == 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (book.summary.isNotEmpty)
                    Text(book.summary, style: TextStyle(color: c.muted)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.t.libraryPageCount(book.pageCount),
                      style: TextStyle(color: c.muted, fontFeatures: tabular),
                    ),
                  ),
                ],
              ),
            );
          }
          if (rows.isEmpty) return Note(context.t.notebookNoPages);
          final row = rows[i - header];
          return PageTreeRow(
            key: ValueKey<String>('row.${row.page.id}'),
            row: row,
            onOpen: () => openPage(context, row.page.id, title: row.page.title),
            onMore: () => _rowMore(row.page),
            onToggle: () => _toggle(row.page.id),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final book = library.asData?.value.notebook(widget.notebookId);
    return Scaffold(
      appBar: AppBar(
        title: Text(book?.title ?? widget.title ?? ''),
        actions: <Widget>[
          if (book != null)
            PopupMenuButton<_More>(
              tooltip: context.t.memoryMore,
              onSelected: (what) => _more(what, book),
              itemBuilder: (_) => <PopupMenuEntry<_More>>[
                PopupMenuItem<_More>(
                  value: _More.newPage,
                  child: Text(context.t.pageNew),
                ),
                PopupMenuItem<_More>(
                  value: _More.pin,
                  child: Text(
                    book.pinned ? context.t.pageUnpin : context.t.pagePin,
                  ),
                ),
                PopupMenuItem<_More>(
                  value: _More.describe,
                  child: Text(context.t.notebookDescribe),
                ),
                PopupMenuItem<_More>(
                  value: _More.deleted,
                  child: Text(context.t.pageDeletedTitle),
                ),
                if (book.pages.isNotEmpty)
                  PopupMenuItem<_More>(
                    value: _More.export,
                    child: Text(context.t.notebookExport),
                  ),
                PopupMenuItem<_More>(
                  value: _More.delete,
                  child: Text(
                    context.t.notebookDelete,
                    style: TextStyle(color: context.colors.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: AsyncBody<Library>(
        value: library,
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 5, kind: SkeletonKind.row),
        ),
        onRetry: () => ref.invalidate(libraryProvider),
        data: (l) {
          final b = l.notebook(widget.notebookId);
          if (b == null) {
            return GoneNote(
              title: context.t.notebookGone,
              body: context.t.notebookGoneBody,
              onBack: () => Navigator.of(context).maybePop(),
            );
          }
          return _list(context, l, b);
        },
      ),
    );
  }
}
