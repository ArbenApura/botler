// A PAGE'S MARKDOWN SPLIT INTO TOP-LEVEL BLOCKS, AND ITS HEADINGS: WHAT THE READER DRAWS LAZILY AND WHAT THE CONTENTS LIST JUMPS TO.
// Pure functions, no widgets. A heading is a block of its own; a paragraph, a list, a table, a quote or a fenced code block is one block each.
// A blank line inside a fenced code block never splits it, and a list with blank lines between its items stays one block (so a numbered list keeps
// counting). Only "#" headings count; the text is not rendered here, so a block is always the exact source it came from.

// -- TYPES -- //

/// One top-level piece of a page. [level] and [heading] are set when the block is a heading.
class ReaderBlock {
  const ReaderBlock(
    this.index,
    this.markdown, {
    this.level,
    this.heading,
    this.line = 0,
  });

  /// The place of the block in the page, from 0.
  final int index;

  /// The source of the block, as written.
  final String markdown;

  /// The line of the page (from 0) where the block starts, and [lineCount] how many lines it spans, blank ones inside it included.
  final int line;

  int get lineCount => '\n'.allMatches(markdown).length + 1;

  /// 1 to 6 for a heading, null otherwise.
  final int? level;

  /// The heading's words without the # marks and without inline marks (bold, code, link addresses).
  final String? heading;

  bool get isHeading => level != null;
}

// -- CONSTANTS -- //

final RegExp _headingLine = RegExp(
  r'^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$',
);
final RegExp _emptyHeading = RegExp(r'^ {0,3}#{1,6}[ \t]*$');
final RegExp _fenceLine = RegExp(r'^([ \t]*)(`{3,}|~{3,})(.*)$');
final RegExp _listItem = RegExp(r'^ {0,3}(?:[-*+]|\d{1,9}[.)])[ \t]+');

// -- FUNCTIONS -- //

bool _isList(String line) => _listItem.hasMatch(line);

int _indent(String line) {
  var n = 0;
  for (final unit in line.codeUnits) {
    if (unit == 0x20) {
      n++;
    } else if (unit == 0x09) {
      n += 4;
    } else {
      break;
    }
  }
  return n;
}

/// The words of a heading as plain text: links keep their label, emphasis and code marks go.
String plainHeading(String raw) {
  var out = raw.replaceAllMapped(
    RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  out = out.replaceAll(RegExp(r'[`*_~]'), '');
  return out.trim();
}

/// The blocks of [text], in order. An empty text has none.
List<ReaderBlock> splitBlocks(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks = <ReaderBlock>[];
  final buf = <String>[];
  var blanks = 0;
  var inList = false;
  var bufStart = 0;
  // The fence that is open: its character and length, or null
  String? fenceChar;
  var fenceLen = 0;

  void flush() {
    if (buf.isEmpty) return;
    blocks.add(ReaderBlock(blocks.length, buf.join('\n'), line: bufStart));
    buf.clear();
    inList = false;
  }

  void startBlock(String line) {
    inList = _isList(line);
  }

  for (var n = 0; n < lines.length; n++) {
    final line = lines[n];
    if (fenceChar != null) {
      buf.add(line);
      final m = _fenceLine.firstMatch(line);
      if (m != null &&
          m.group(2)!.startsWith(fenceChar) &&
          m.group(2)!.length >= fenceLen &&
          m.group(3)!.trim().isEmpty) {
        fenceChar = null;
      }
      continue;
    }
    if (line.trim().isEmpty) {
      blanks++;
      continue;
    }
    final fence = _fenceLine.firstMatch(line);
    final opensFence =
        fence != null &&
        !(fence.group(2)!.startsWith('`') && fence.group(3)!.contains('`'));
    if (blanks > 0 && buf.isNotEmpty) {
      // A list goes on over a blank line when the next line is another item or is indented under one
      final continues = inList && (_isList(line) || _indent(line) >= 2);
      if (continues) {
        buf.addAll(List<String>.filled(blanks, ''));
      } else {
        flush();
      }
    }
    blanks = 0;
    final heading = _headingLine.firstMatch(line);
    if ((heading != null || _emptyHeading.hasMatch(line)) &&
        !(inList && _indent(line) >= 2)) {
      flush();
      final level = heading?.group(1)?.length ?? line.trim().length;
      blocks.add(
        ReaderBlock(
          blocks.length,
          line,
          level: level,
          heading: plainHeading(heading?.group(2) ?? ''),
          line: n,
        ),
      );
      continue;
    }
    if (opensFence) {
      // A fence under a list item belongs to the list; any other fence starts its own block
      if (!(inList && _indent(line) >= 2)) flush();
      if (buf.isEmpty) {
        inList = false;
        bufStart = n;
      }
      buf.add(line);
      fenceChar = fence.group(2)!.substring(0, 1);
      fenceLen = fence.group(2)!.length;
      continue;
    }
    if (buf.isEmpty) {
      startBlock(line);
      bufStart = n;
    }
    buf.add(line);
  }
  flush();
  return blocks;
}

/// The heading blocks of a page, in order.
List<ReaderBlock> extractHeadings(List<ReaderBlock> blocks) => <ReaderBlock>[
  for (final b in blocks)
    if (b.isHeading) b,
];
