// [[PAGE]] LINKS IN THE READER: FOUND IN A BLOCK OF TEXT, LOOKED UP IN THE LIBRARY, AND TURNED INTO MARKDOWN LINKS THE READER CAN DRAW AND TAP.
// A link that names a page becomes a tappable link to it; one that names nothing the library has stays in the text as muted words with a label
// that says so, and does nothing when tapped. The lookup is pure (no network): the page title in the notebook that holds the link first, then
// "Notebook/Page". Links inside code are left alone because parsePageLinks does not see them.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// The markdown package is what flutter_markdown_plus is built on; its element type is needed to write a builder and is not re-exported
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

// -- MODULES -- //
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'page_links.dart';

// -- CONSTANTS -- //

/// The address a link to a known page gets: this, then the page id.
const String pageHrefPrefix = 'botler-page:';

/// The tag a link to a missing page is drawn under (see [MissingLinkSyntax]).
const String missingTag = 'botlerMissing';

/// Marks the words of a link whose page is not in the library: these two private characters around them. A Markdown link would be tapped; this is
/// plain text the reader draws muted.
const String missingOpen = '';
const String missingClose = '';

// -- FUNCTIONS -- //

String _lower(String s) => s.trim().toLowerCase();

LibraryPage? _titled(LibraryNotebook? book, String title) {
  if (book == null) return null;
  for (final p in book.pages) {
    if (_lower(p.title) == _lower(title)) return p;
  }
  return null;
}

/// The page [link] names, or null. A plain [[Page]] is looked for in [currentNotebookId] first and then in the other notebooks when only one
/// has it; [[Notebook/Page]] names the notebook (a page whose own title holds a slash is tried in the current notebook last).
LibraryPage? resolvePageLink(
  Library library,
  PageLink link,
  String currentNotebookId,
) {
  final book = link.notebook;
  if (book != null) {
    for (final n in library.notebooks) {
      if (_lower(n.title) != _lower(book)) continue;
      final hit = _titled(n, link.page);
      if (hit != null) return hit;
    }
    return _titled(library.notebook(currentNotebookId), '$book/${link.page}');
  }
  final here = _titled(library.notebook(currentNotebookId), link.page);
  if (here != null) return here;
  LibraryPage? only;
  for (final p in library.pages) {
    if (_lower(p.title) != _lower(link.page)) continue;
    if (only != null) return null;
    only = p;
  }
  return only;
}

String _escape(String s) =>
    s.replaceAllMapped(RegExp(r'[\\`*_{}\[\]<>~|#]'), (m) => '\\${m[0]}');

/// [markdown] with every [[link]] written as a Markdown link to the page when the library has it, and as marked plain words when it does not.
String linkifyPages(
  String markdown,
  Library library,
  String currentNotebookId,
) {
  final links = parsePageLinks(markdown);
  if (links.isEmpty) return markdown;
  final out = StringBuffer();
  var at = 0;
  for (final l in links) {
    out.write(markdown.substring(at, l.start));
    final words = l.notebook == null ? l.page : '${l.notebook}/${l.page}';
    final page = resolvePageLink(library, l, currentNotebookId);
    out.write(
      page == null
          ? '$missingOpen${words.replaceAll(RegExp('[]'), '')}$missingClose'
          : '[${_escape(words)}]($pageHrefPrefix${page.id})',
    );
    at = l.end;
  }
  out.write(markdown.substring(at));
  return out.toString();
}

/// The page id inside a link address made by [linkifyPages], or null for any other address.
String? pageIdOfHref(String? href) =>
    href != null && href.startsWith(pageHrefPrefix)
    ? href.substring(pageHrefPrefix.length)
    : null;

// -- WIDGETS -- //

/// Reads the marked words of a link to a missing page as an element of its own.
class MissingLinkSyntax extends md.InlineSyntax {
  MissingLinkSyntax() : super('$missingOpen([^$missingClose]*)$missingClose');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(missingTag, match[1] ?? ''));
    return true;
  }
}

/// Draws a link to a missing page as muted words that cannot be tapped.
class MissingLinkBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final words = element.textContent;
    return Semantics(
      label: context.t.pageLinkMissing(words),
      excludeSemantics: true,
      child: Text(
        words,
        style: (parentStyle ?? preferredStyle)?.copyWith(
          color: context.colors.muted,
        ),
      ),
    );
  }
}
