// THE READER'S TEXT WITH EVERYTHING THAT NEEDS THE LIBRARY AND THE SERVER AROUND IT: THE [[LINKS]] LOOKED UP, THE LINES ADDED SINCE THE PERSON LAST READ
// MARKED, AND THE "LINKED FROM" LIST AT THE END. The version the person had read is given by the screen (it is taken before this opening moves
// it), so the marks survive the first drawing. Without a connection or without that version nothing is marked and nothing is said.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../core/library_extras.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/library_extras.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import 'backlinks_section.dart';
import 'reader_links.dart';
import 'reader_view.dart';

// -- WIDGETS -- //

class ReaderBody extends ConsumerWidget {
  const ReaderBody({
    required this.doc,
    required this.controller,
    required this.header,
    required this.footer,
    required this.onOpenPage,
    this.seenAtOpen,
    super.key,
  });

  final PageDoc doc;
  final ReaderController controller;
  final Widget header;
  final Widget footer;

  /// Opens a page of the library (a tapped [[link]] or a row of "Linked from").
  final void Function(String pageId, String? title) onOpenPage;

  /// The newest version the person had looked at before this opening, or null when it is not known.
  final int? seenAtOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).asData?.value;
    final seen = seenAtOpen;
    final changes = seen == null || doc.offline
        ? PageChanges.none
        : ref
                  .watch(pageChangesProvider((doc.id, seen, doc.version)))
                  .asData
                  ?.value ??
              PageChanges.none;
    return ReaderView(
      doc: doc,
      controller: controller,
      library: library,
      changes: changes,
      onTapLink: (text, href) {
        final id = pageIdOfHref(href);
        if (id != null) {
          onOpenPage(id, null);
        } else {
          openWebLink(href);
        }
      },
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          ChangesNote(changes: changes),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          footer,
          if (!doc.offline)
            BacklinksSection(
              pageId: doc.id,
              onOpen: (l) => onOpenPage(l.pageId, l.page),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// What the marks on the page mean, or that too much changed to mark. Nothing when there is nothing to say.
class ChangesNote extends StatelessWidget {
  const ChangesNote({required this.changes, super.key});

  final PageChanges changes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final String words;
    final IconData icon;
    if (changes.kind == ChangeKind.tooMuch) {
      words = context.t.pageChangedALot;
      icon = Icons.history_toggle_off;
    } else if (changes.marksLines) {
      words = context.t.pageChangesLegend;
      icon = Icons.vertical_split_outlined;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: words,
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: c.accentText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                words,
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
