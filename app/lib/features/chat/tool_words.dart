// THE WORDS FOR WHAT A TOOL IS DOING OR DID, FROM THE KIND ("family") AND SUBJECT THE SERVER SENT: "Reading page Trip plan", "Read page Trip plan, 1 s".
// A tool with no label (an older server, or a tool that has no family wording) gets nothing from here, and the row keeps its old wording.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import 'chat_state.dart';
import 'notebook_rows.dart';

// -- CONSTANTS -- //

/// The kinds of call that fold into one counted row when they come one after another. A write never folds.
const Set<String> groupFamilies = <String>{
  'page_read',
  'notebook_read',
  'notebook_search',
  'web',
  'web_read',
  'lookup',
};

// -- FUNCTIONS -- //

/// What the call is doing right now ("Reading page Trip plan"), or null when it has no wording of its own.
String? runningWords(BuildContext context, ToolItem item) {
  final t = context.t;
  final s = item.subject;
  switch (item.family) {
    case 'page_read':
      return s == null ? t.toolReadingPageNone : t.toolReadingPage(s);
    case 'notebook_read':
      return s == null ? t.toolReadingNotebookNone : t.toolReadingNotebook(s);
    case 'notebook_search':
      return s == null
          ? t.toolSearchingNotebooksNone
          : t.toolSearchingNotebooks(s);
    case 'notebook_write':
      return s == null ? t.chatSavingNotebook : t.toolUpdatingNotebook(s);
    case 'page_write':
      return s == null ? t.toolUpdatingPageNone : t.toolUpdatingPage(s);
    case 'web':
      return s == null ? t.toolSearchingWebNone : t.toolSearchingWeb(s);
    case 'web_read':
      return s == null ? t.toolOpeningPageNone : t.toolOpeningPage(s);
  }
  return null;
}

/// What the call did, without its time ("Read page Trip plan"), or null when it has no wording of its own.
String? _doneBase(BuildContext context, ToolItem item) {
  final t = context.t;
  final s = item.subject;
  switch (item.family) {
    case 'page_read':
      return s == null ? t.toolReadPageNone : t.toolReadPage(s);
    case 'notebook_read':
      return s == null ? t.toolReadNotebookNone : t.toolReadNotebook(s);
    case 'notebook_search':
      return s == null
          ? t.toolSearchedNotebooksNone
          : t.toolSearchedNotebooks(s);
    case 'page_write':
      return s == null ? t.toolUpdatedPageNone : t.toolUpdatedPage(s);
    case 'web':
      return s == null ? t.toolSearchedWebNone : t.toolSearchedWeb(s);
    case 'web_read':
      return s == null ? t.toolOpenedPageNone : t.toolOpenedPage(s);
  }
  return null;
}

/// How many whole seconds to show for a time, never less than one.
int _seconds(int ms) => ms < 1000 ? 1 : (ms / 1000).round();

/// What the call did, with a short time when it is known ("Read page Trip plan, 1 s"), or null when it has no wording of its own.
String? doneWords(BuildContext context, ToolItem item) {
  final base = _doneBase(context, item);
  if (base == null) return null;
  final ms = item.ms;
  return ms == null ? base : context.t.toolTook(base, _seconds(ms));
}

/// A tool's name as plain words, for "Checking accounts list".
String _plain(String name) => name.replaceAll('_', ' ');

/// The name of a call for a failed or blocked row: what it was doing, else its tool name as plain words.
String _what(BuildContext context, ToolItem item) =>
    runningWords(context, item) ?? context.t.chatChecking(_plain(item.name));

/// The headline of a failed row ("Failed: Reading page Budget 2027"), or of a blocked one.
String failedWords(BuildContext context, ToolItem item) =>
    item.status == 'blocked'
    ? context.t.toolBlockedNamed(_what(context, item))
    : context.t.toolFailedNamed(_what(context, item));

/// The words of one member inside an opened group: running or done, with the old wording when it has none of its own.
String memberWords(BuildContext context, ToolItem item) {
  if (item.running) {
    return runningWords(context, item) ??
        context.t.chatChecking(_plain(item.name));
  }
  return doneWords(context, item) ?? context.t.chatChecked(_plain(item.name));
}

/// The one line of a group: "Reading pages" while any member runs, "Read 3 pages" once all are done.
String groupWords(
  BuildContext context,
  String family, {
  required int count,
  required bool running,
}) {
  final t = context.t;
  return switch (family) {
    'page_read' =>
      running ? t.toolGroupReadingPages : t.toolGroupReadPages(count),
    'notebook_read' =>
      running ? t.toolGroupReadingNotebooks : t.toolGroupReadNotebooks(count),
    'notebook_search' =>
      running
          ? t.toolGroupSearchingNotebooks
          : t.toolGroupSearchedNotebooks(count),
    'web' => running ? t.toolGroupSearchingWeb : t.toolGroupSearchedWeb(count),
    'web_read' =>
      running ? t.toolGroupOpeningPages : t.toolGroupOpenedPages(count),
    _ => running ? t.toolGroupChecking : t.toolGroupChecked(count),
  };
}

/// The small icon in front of a group of this kind.
IconData familyIcon(String family) => switch (family) {
  'page_read' => Icons.description_outlined,
  'notebook_read' || 'notebook_search' => Icons.menu_book_outlined,
  'web' || 'web_read' => Icons.public,
  _ => Icons.search,
};

/// The kind a finished or running call folds under, or null when it stands alone (a write, a failure, a card, a phone tool, a call with no label that is still running).
String? groupFamilyOf(ToolItem i, Set<String> drawnTools) {
  if (i.name == 'script_run' ||
      i.name == 'toolbox' ||
      i.name == 'health_open') {
    return null;
  }
  if (!i.running && i.status != 'ok') return null;
  if (drawnTools.contains(i.name) || isNotebookWrite(i.name)) return null;
  final family = i.family ?? (i.running ? null : 'lookup');
  return family != null && groupFamilies.contains(family) ? family : null;
}
