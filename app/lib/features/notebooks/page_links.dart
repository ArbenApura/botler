// [[PAGE]] AND [[NOTEBOOK/PAGE]]: THE LINKS ONE PAGE WRITES TO ANOTHER, FOUND IN THE TEXT. PURE, NO WIDGETS.
// A link inside a code span (`like [[this]]`) or a fenced code block is code, not a link. The reader draws these as taps in phase 4; this file
// only says where they are and what they point at, so the reader can be built around them now. The server writes and counts the same two forms
// (page_backlinks), and a title may hold a slash: the first slash is the one that splits the notebook from the page.

// -- TYPES -- //

/// One link: where it sits in the text, and what it names.
class PageLink {
  const PageLink({
    required this.start,
    required this.end,
    required this.page,
    this.notebook,
  });

  /// The offsets of the whole "[[...]]" in the text; [end] is just past the last bracket.
  final int start;
  final int end;

  /// The notebook title when the link names one, otherwise null (the page is looked for in the notebook that holds the link).
  final String? notebook;
  final String page;

  @override
  bool operator ==(Object other) =>
      other is PageLink &&
      other.start == start &&
      other.end == end &&
      other.notebook == notebook &&
      other.page == page;

  @override
  int get hashCode => Object.hash(start, end, notebook, page);

  @override
  String toString() => 'PageLink(${notebook ?? ''}/$page @$start-$end)';
}

// -- CONSTANTS -- //

final RegExp _fence = RegExp(r'^[ \t]*(`{3,}|~{3,})(.*)$');

/// The longest title a link may name: a page title is at most 80 characters, a notebook title likewise, plus the slash.
const int _longest = 170;

// -- FUNCTIONS -- //

PageLink? _link(String inner, int start, int end) {
  if (inner.length > _longest || inner.contains('[') || inner.contains(']')) {
    return null;
  }
  final text = inner.trim();
  if (text.isEmpty) return null;
  final slash = text.indexOf('/');
  if (slash < 0) return PageLink(start: start, end: end, page: text);
  final notebook = text.substring(0, slash).trim();
  final page = text.substring(slash + 1).trim();
  // "[[/Page]]" and "[[Notebook/]]" name nothing useful
  if (notebook.isEmpty || page.isEmpty) return null;
  return PageLink(start: start, end: end, notebook: notebook, page: page);
}

/// The links in one line outside its code spans. A code span is a run of backticks closed by a run of the same length.
void _scanLine(String line, int base, List<PageLink> out) {
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == '`') {
      var run = 0;
      while (i + run < line.length && line[i + run] == '`') {
        run++;
      }
      var j = i + run;
      var closed = -1;
      while (j < line.length) {
        if (line[j] != '`') {
          j++;
          continue;
        }
        var again = 0;
        while (j + again < line.length && line[j + again] == '`') {
          again++;
        }
        if (again == run) {
          closed = j + again;
          break;
        }
        j += again;
      }
      // A run with no closing run is plain backticks, and the text after it is not code
      i = closed < 0 ? i + run : closed;
      continue;
    }
    if (c == '[' && i + 1 < line.length && line[i + 1] == '[') {
      final close = line.indexOf(']]', i + 2);
      if (close > 0) {
        final link = _link(
          line.substring(i + 2, close),
          base + i,
          base + close + 2,
        );
        if (link != null) {
          out.add(link);
          i = close + 2;
          continue;
        }
      }
    }
    i++;
  }
}

/// Every [[Page]] and [[Notebook/Page]] in [text], in order, with its offsets.
List<PageLink> parsePageLinks(String text) {
  final out = <PageLink>[];
  var at = 0;
  String? fenceChar;
  var fenceLen = 0;
  while (at <= text.length) {
    final eol = text.indexOf('\n', at);
    final end = eol < 0 ? text.length : eol;
    // A carriage return is not part of the line's words
    final stop = end > at && text[end - 1] == '\r' ? end - 1 : end;
    final line = text.substring(at, stop);
    final m = _fence.firstMatch(line);
    if (fenceChar != null) {
      if (m != null &&
          m.group(1)!.startsWith(fenceChar) &&
          m.group(1)!.length >= fenceLen &&
          m.group(2)!.trim().isEmpty) {
        fenceChar = null;
      }
    } else if (m != null &&
        !(m.group(1)!.startsWith('`') && m.group(2)!.contains('`'))) {
      fenceChar = m.group(1)!.substring(0, 1);
      fenceLen = m.group(1)!.length;
    } else {
      _scanLine(line, at, out);
    }
    if (eol < 0) break;
    at = eol + 1;
  }
  return out;
}
