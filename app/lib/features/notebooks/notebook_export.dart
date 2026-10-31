// EXPORT A NOTEBOOK AS ONE MARKDOWN TEXT: "# Notebook title", then each page as "## Title" with its text, and its sub-pages as "### Title". The app has
// no share sheet (it copies the everything-export to the clipboard), so this copies too. The page texts are read one by one from the server (the
// outline holds none), so it needs a connection and reports plainly when it does not have one.

// -- DEP-MODULES -- //
import 'dart:convert';

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

// -- CONSTANTS -- //

/// How many page texts are read at the same time.
const int _batch = 20;

/// Above this many bytes the person is warned before the copy.
const int exportWarnBytes = 1000000;

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
  final List<ExportPage> pages;
  try {
    final api = ref.read(apiProvider);
    pages = <ExportPage>[];
    // Twenty pages at a time: all at once would open hundreds of connections, one by one would take minutes
    for (var from = 0; from < book.pages.length; from += _batch) {
      final batch = book.pages.skip(from).take(_batch).toList();
      final got = await Future.wait(<Future<Json>>[
        for (final p in batch)
          api.verbJson('page_get', <String, Object?>{'pageId': p.id}),
      ]);
      for (var i = 0; i < batch.length; i++) {
        pages.add(
          ExportPage(
            batch[i].title,
            batch[i].parentPageId == null ? 0 : 1,
            str(got[i]['text']),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) say(context, needsNetworkWords(context, e));
    return;
  }
  final markdown = notebookMarkdown(book.title, pages);
  // A very large text on the clipboard can be slow or refused, so the person is told first
  final bytes = utf8.encode(markdown).length;
  if (bytes > exportWarnBytes && context.mounted) {
    say(context, words.notebookExportBig((bytes / 1000000).toStringAsFixed(1)));
  }
  try {
    await Clipboard.setData(ClipboardData(text: markdown));
  } catch (_) {
    // The pages were read; only the copy failed
    if (context.mounted) say(context, words.notebookExportClipFail);
    return;
  }
  if (context.mounted) say(context, words.notebookExported(pages.length));
}
