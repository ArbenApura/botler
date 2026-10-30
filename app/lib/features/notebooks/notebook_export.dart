// EXPORT A NOTEBOOK AS ONE MARKDOWN TEXT: "# Notebook title", then each page as "## Title" with its text, and its sub-pages as "### Title". The app has
// no share sheet (it copies the everything-export to the clipboard), so this copies too. The page texts are read one by one from the server (the
// outline holds none), so it needs a connection and reports plainly when it does not have one.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';
import 'library_actions.dart';

// -- TYPES -- //

/// A page of the outline with the text it was exported with.
class ExportPage {
  const ExportPage(this.title, this.depth, this.text);

  final String title;

  /// 0 for a top-level page, 1 for a sub-page.
  final int depth;
  final String text;
}

// -- FUNCTIONS -- //

/// The notebook as Markdown, the pages in the order they are given. A page with no text is just its heading.
String notebookMarkdown(String title, List<ExportPage> pages) {
  final out = StringBuffer('# $title\n');
  for (final p in pages) {
    out
      ..write('\n${p.depth == 0 ? '##' : '###'} ${p.title}\n')
      ..write(p.text.trim().isEmpty ? '' : '\n${p.text.trim()}\n');
  }
  return out.toString();
}

/// Copies [book] as Markdown to the clipboard and says how many pages went. A failure is reported in plain words.
Future<void> exportNotebook(
  BuildContext context,
  WidgetRef ref,
  LibraryNotebook book,
) async {
  final words = context.t;
  say(context, words.notebookExporting);
  try {
    final api = ref.read(apiProvider);
    final pages = <ExportPage>[];
    for (final p in book.pages) {
      final got = await api.verbJson('page_get', <String, Object?>{
        'pageId': p.id,
      });
      pages.add(
        ExportPage(p.title, p.parentPageId == null ? 0 : 1, str(got['text'])),
      );
    }
    await Clipboard.setData(
      ClipboardData(text: notebookMarkdown(book.title, pages)),
    );
    if (context.mounted) say(context, words.notebookExported(pages.length));
  } catch (e) {
    if (context.mounted) say(context, needsNetworkWords(context, e));
  }
}
