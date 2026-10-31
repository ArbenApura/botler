// ONE ROW OF A NOTEBOOK'S PAGE LIST: A PAGE, INDENTED WHEN IT IS A SUB-PAGE, WITH A FOLD BUTTON WHEN IT HAS SUB-PAGES.
// A tap opens the page in the reader; a press and hold opens the sheet of rename, pin and delete. Both targets are at least 48 dp.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'library_widgets.dart';

// -- CONSTANTS -- //

/// How far a sub-page is pushed in.
const double _subIndent = 28;

// -- WIDGETS -- //

class PageTreeRow extends StatelessWidget {
  const PageTreeRow({
    required this.row,
    required this.onOpen,
    required this.onMore,
    required this.onToggle,
    super.key,
  });

  final TreeRow row;
  final VoidCallback onOpen;
  final VoidCallback onMore;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final page = row.page;
    final label =
        '${context.t.libraryOpenPage(page.title)}'
        '${page.pinned ? ', ${context.t.libraryPinned}' : ''}'
        '${page.botlerUpdated ? ', ${context.t.libraryUpdated}' : ''}';
    return Padding(
      padding: EdgeInsets.only(left: row.depth * _subIndent),
      child: Row(
        children: <Widget>[
          // The fold button, or a quiet page mark of the same width so the titles line up
          SizedBox(
            width: 48,
            height: libraryRowHeight,
            child: row.hasChildren
                ? Semantics(
                    button: true,
                    label: row.collapsed
                        ? context.t.pageToggleOpen(page.title)
                        : context.t.pageToggleClose(page.title),
                    onTap: onToggle,
                    excludeSemantics: true,
                    child: IconButton(
                      key: ValueKey<String>('fold.${page.id}'),
                      tooltip: row.collapsed
                          ? context.t.pageToggleOpen(page.title)
                          : context.t.pageToggleClose(page.title),
                      onPressed: onToggle,
                      icon: AnimatedRotation(
                        turns: row.collapsed ? 0 : 0.25,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        child: Icon(Icons.chevron_right, color: c.muted),
                      ),
                    ),
                  )
                : Icon(Icons.article_outlined, size: 20, color: c.muted),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: label,
              onTap: onOpen,
              onLongPress: onMore,
              onLongPressHint: context.t.libraryActionsFor(page.title),
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey<String>('page.${page.id}'),
                borderRadius: BorderRadius.circular(12),
                onTap: onOpen,
                onLongPress: onMore,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: libraryRowHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            page.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: row.depth == 0
                                ? Theme.of(context).textTheme.titleSmall
                                : Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        if (page.pinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.push_pin,
                              size: 16,
                              color: c.muted,
                            ),
                          ),
                        if (page.botlerUpdated)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: UpdatedDot(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
