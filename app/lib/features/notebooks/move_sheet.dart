// WHERE TO PUT A PAGE: A SHEET THAT FIRST ASKS FOR THE NOTEBOOK, THEN FOR THE TOP LEVEL OR A TOP-LEVEL PAGE TO PUT IT UNDER. PAGES GO ONE LEVEL DEEP,
// so a page that has sub-pages of its own can only be put at the top level (the server refuses anything else, and the sheet does not offer it).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

/// Where the page goes: a notebook, and a top-level page of it to sit under (null for the top level).
class MoveTarget {
  const MoveTarget(this.notebookId, [this.parentPageId]);

  final String notebookId;
  final String? parentPageId;
}

// -- FUNCTIONS -- //

/// Asks where [page] should go. Returns null when the person closes the sheet.
Future<MoveTarget?> pickMoveTarget(
  BuildContext context,
  Library library,
  LibraryPage page,
) {
  return showFormSheet<MoveTarget>(
    context,
    title: context.t.pageMoveTitle(page.title),
    builder: (sheet, close) =>
        MovePicker(library: library, page: page, onPick: close),
  );
}

// -- WIDGETS -- //

class MovePicker extends StatefulWidget {
  const MovePicker({
    required this.library,
    required this.page,
    required this.onPick,
    super.key,
  });

  final Library library;
  final LibraryPage page;
  final void Function(MoveTarget target) onPick;

  @override
  State<MovePicker> createState() => _MovePickerState();
}

class _MovePickerState extends State<MovePicker> {
  // -- STATES -- //

  /// The notebook chosen in the first step, or null while that step is shown.
  LibraryNotebook? _book;

  // -- FUNCTIONS -- //

  bool get _hasKids =>
      widget.library.pages.any((p) => p.parentPageId == widget.page.id);

  // -- WIDGETS -- //

  Widget _tile({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? hint,
    bool here = false,
  }) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: here ? '$label, ${context.t.pageMoveHere}' : label,
      onTap: onTap,
      excludeSemantics: true,
      child: ListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        minTileHeight: 56,
        leading: Icon(icon, color: c.muted),
        title: Text(label),
        subtitle: hint == null ? null : Text(hint),
        trailing: here ? Icon(Icons.check, color: c.accentText) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _books(BuildContext context) {
    final books = widget.library.sorted;
    return ListView.builder(
      shrinkWrap: true,
      itemCount: books.length,
      itemBuilder: (context, i) {
        final b = books[i];
        return _tile(
          key: ValueKey<String>('move.book.${b.id}'),
          icon: Icons.menu_book_outlined,
          label: b.title,
          here: b.id == widget.page.notebookId,
          onTap: () => setState(() => _book = b),
        );
      },
    );
  }

  Widget _places(BuildContext context, LibraryNotebook book) {
    final tops = <LibraryPage>[
      for (final p in book.pages)
        if (p.parentPageId == null && p.id != widget.page.id) p,
    ];
    // A page with sub-pages of its own cannot become a sub-page
    final candidates = _hasKids ? const <LibraryPage>[] : tops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(minTap, minTap)),
          onPressed: () => setState(() => _book = null),
          icon: const Icon(Icons.arrow_back),
          label: Text(book.title),
        ),
        _tile(
          key: const ValueKey<String>('move.top'),
          icon: Icons.vertical_align_top,
          label: context.t.pageMoveTop,
          here:
              book.id == widget.page.notebookId &&
              widget.page.parentPageId == null,
          onTap: () => widget.onPick(MoveTarget(book.id)),
        ),
        if (_hasKids)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.t.pageMoveHasKids,
              style: TextStyle(color: context.colors.muted),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, i) {
              final p = candidates[i];
              return _tile(
                key: ValueKey<String>('move.under.${p.id}'),
                icon: Icons.subdirectory_arrow_right,
                label: context.t.pageMoveUnder(p.title),
                here: widget.page.parentPageId == p.id,
                onTap: () => widget.onPick(MoveTarget(book.id, p.id)),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return book == null
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: _books(context),
          )
        : _places(context, book);
  }
}
