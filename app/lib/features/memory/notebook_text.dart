// THE NOTEBOOK TEXT AS THE PAGE SHOWS IT: HEADINGS BECOME SECTIONS, BULLETS BECOME LINES. PLAIN TEXT ONLY, NOTHING IS EVER RENDERED AS MARKUP.
// The server keeps one Markdown document per person; the app only reads its shape. A line that is not a heading is text, whatever it holds.

// -- TYPES -- //

/// One line under a heading: [bullet] says it began with "- " or "* " (the mark itself is not kept).
class NotebookLine {
  const NotebookLine(this.text, {required this.bullet});

  final String text;
  final bool bullet;
}

/// A heading and the lines under it. Text before the first heading has an empty [heading].
class NotebookSection {
  const NotebookSection(this.heading, this.lines);

  final String heading;
  final List<NotebookLine> lines;
}

// -- CONSTANTS -- //

/// The longest notebook text the server accepts, in characters.
const int notebookMaxChars = 16000;

final RegExp _headingLine = RegExp(r'^#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$');
final RegExp _bulletLine = RegExp(r'^[-*][ \t]+(.*)$');

// -- FUNCTIONS -- //

/// The sections of a notebook text, in order. Blank lines are dropped. A heading with nothing under it is still a section.
List<NotebookSection> parseNotebook(String text) {
  final sections = <NotebookSection>[];
  String? heading;
  var lines = <NotebookLine>[];
  var started = false;

  void flush() {
    final h = heading;
    if (h != null) {
      sections.add(NotebookSection(h, lines));
    } else if (lines.isNotEmpty) {
      sections.add(NotebookSection('', lines));
    }
    lines = <NotebookLine>[];
  }

  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    final h = _headingLine.firstMatch(line);
    if (h != null) {
      if (started || lines.isNotEmpty) flush();
      started = true;
      heading = (h.group(1) ?? '').trim();
      continue;
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final b = _bulletLine.firstMatch(trimmed);
    lines.add(
      b == null
          ? NotebookLine(trimmed, bullet: false)
          : NotebookLine((b.group(1) ?? '').trim(), bullet: true),
    );
  }
  flush();
  return sections;
}

/// True when the notebook holds only headings and blank lines: nothing has been written in it yet.
bool isEmptyNotebook(String text) =>
    parseNotebook(text).every((s) => s.lines.isEmpty);
