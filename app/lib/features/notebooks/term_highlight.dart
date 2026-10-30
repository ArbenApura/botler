// THE WORDS A SEARCH FOUND, MARKED IN A LINE OF TEXT. THE MARK IS A SOFT BACKGROUND AND BOLD, SO IT DOES NOT DEPEND ON COLOUR ALONE.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../theme/tokens.dart';

// -- TYPES -- //

/// A run of text and whether it is the searched word.
class TextRun {
  const TextRun(this.text, this.match);

  final String text;
  final bool match;
}

// -- FUNCTIONS -- //

/// [text] cut into runs, the places where [term] appears (ignoring case) marked. An empty term gives one plain run.
List<TextRun> splitByTerm(String text, String term) {
  final needle = term.trim().toLowerCase();
  if (needle.isEmpty || text.isEmpty) {
    return text.isEmpty ? const <TextRun>[] : <TextRun>[TextRun(text, false)];
  }
  final hay = text.toLowerCase();
  // Lower-casing can change a length in rare scripts; then the text is shown plain rather than cut in the wrong place
  if (hay.length != text.length) return <TextRun>[TextRun(text, false)];
  final runs = <TextRun>[];
  var at = 0;
  while (at < text.length) {
    final found = hay.indexOf(needle, at);
    if (found < 0) break;
    if (found > at) runs.add(TextRun(text.substring(at, found), false));
    runs.add(TextRun(text.substring(found, found + needle.length), true));
    at = found + needle.length;
  }
  if (at < text.length) runs.add(TextRun(text.substring(at), false));
  return runs;
}

// -- WIDGETS -- //

/// A line of text with [term] marked in it.
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    required this.term,
    this.style,
    this.maxLines,
    super.key,
  });

  final String text;
  final String term;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          for (final r in splitByTerm(text, term))
            TextSpan(
              text: r.text,
              style: r.match
                  ? TextStyle(
                      fontWeight: FontWeight.w700,
                      backgroundColor: c.accentSoft,
                    )
                  : null,
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}
