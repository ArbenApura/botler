// THE SMALL PIECES THE LIBRARY SCREENS SHARE: THE OFFLINE NOTE, THE "BOTLER UPDATED" DOT, THE SEARCH BAR, A NOTEBOOK CARD AND A PAGE ROW.
// Every tappable piece is at least 48 dp tall and says what it opens to a screen reader. Colours come from the tokens only.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

/// The height every row and bar keeps, a little over the 48 dp tap size.
const double libraryRowHeight = 56;

// -- FUNCTIONS -- //

/// A time as the library writes it ("Nov 3, 10:20", in the app's language and Manila time). The format is made here, not once for the app.
String libraryWhen(BuildContext context, DateTime? at) => at == null
    ? ''
    : DateFormat.MMMd(Localizations.localeOf(context).toString())
          .add_Hm()
          .format(manilaWall(at));

// -- WIDGETS -- //

/// "Offline copy" (from when it was saved), shown whenever a screen draws the copy kept on the phone instead of the server's answer.
class OfflineCopyNote extends StatelessWidget {
  const OfflineCopyNote({this.since, super.key});

  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = since == null
        ? context.t.libraryOffline
        : context.t.libraryOfflineSince(libraryWhen(context, since));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: text,
        excludeSemantics: true,
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: 18, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small dot that says Botler wrote something here that has not been looked at yet. The accent marks it; it is not a status.
class UpdatedDot extends StatelessWidget {
  const UpdatedDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.t.libraryUpdated,
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: context.colors.accent,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// The one primary action of the library: a wide bar that opens the search.
class SearchEntry extends StatelessWidget {
  const SearchEntry({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.t.librarySearchHint,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: c.chip,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: libraryRowHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, color: c.accentText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.t.librarySearchHint,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A notebook of the library: title, one line, how many pages, and a dot when Botler wrote in it. A tap opens it; a press and hold opens more.
class NotebookCard extends StatelessWidget {
  const NotebookCard({
    required this.notebook,
    required this.onOpen,
    required this.onMore,
    super.key,
  });

  final LibraryNotebook notebook;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = context.t.libraryPageCount(notebook.pageCount);
    return Padding(
      key: ValueKey<String>('notebook.${notebook.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label:
            '${context.t.libraryOpenNotebook(notebook.title)}, $count'
            '${notebook.botlerUpdated ? ', ${context.t.libraryUpdated}' : ''}',
        onTap: onOpen,
        onLongPress: onMore,
        onLongPressHint: context.t.libraryActionsFor(notebook.title),
        excludeSemantics: true,
        child: PaperCard(
          onTap: onOpen,
          onLongPress: onMore,
          child: Row(
            children: <Widget>[
              Icon(Icons.menu_book_outlined, color: c.accentText),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      notebook.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (notebook.summary.isNotEmpty)
                      Text(
                        notebook.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        count,
                        style: TextStyle(color: c.muted, fontFeatures: tabular),
                      ),
                    ),
                  ],
                ),
              ),
              if (notebook.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.push_pin, size: 18, color: c.muted),
                ),
              if (notebook.botlerUpdated)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: UpdatedDot(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page listed outside its notebook (pinned or recent): its title, the notebook it lives in, and a dot when Botler wrote in it.
class PageShortcut extends StatelessWidget {
  const PageShortcut({
    required this.pageId,
    required this.title,
    required this.notebook,
    required this.onOpen,
    this.pinned = false,
    this.updated = false,
    super.key,
  });

  final String pageId;
  final String title;
  final String notebook;
  final bool pinned;
  final bool updated;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label:
          '${context.t.libraryOpenPage(title)}, $notebook'
          '${pinned ? ', ${context.t.libraryPinned}' : ''}'
          '${updated ? ', ${context.t.libraryUpdated}' : ''}',
      onTap: onOpen,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('shortcut.$pageId'),
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: libraryRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: <Widget>[
                Icon(
                  pinned ? Icons.push_pin_outlined : Icons.history,
                  color: c.muted,
                  size: 20,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        notebook,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
                if (updated)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: UpdatedDot(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet message with one way out (back), for a page or a notebook that is not on the server any more.
class GoneNote extends StatelessWidget {
  const GoneNote({
    required this.title,
    required this.body,
    required this.onBack,
    super.key,
  });

  final String title;
  final String body;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.layers_clear_outlined, size: 32, color: c.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onBack,
              child: Text(context.t.notebookGoBack),
            ),
          ],
        ),
      ),
    );
  }
}
