// THE EDITS THE PAGE EDITOR'S TOOLBAR MAKES TO MARKDOWN: A HEADING, BOLD, A LIST ITEM, A CHECKBOX, A LINK AND A [[PAGE LINK]]. PURE, NO WIDGETS.
// Each takes the text with its selection and gives the new text with the selection where typing should go on. A line mark (heading, list,
// checkbox) is put at the start of the line the cursor is in, and a second tap takes it away again.

// -- DEP-MODULES -- //
import 'package:flutter/services.dart';

// -- TYPES -- //

enum MarkdownEdit { heading, bold, list, checkbox, link, pageLink }

// -- FUNCTIONS -- //

TextSelection _valid(TextEditingValue v) {
  final s = v.selection;
  if (!s.isValid) return TextSelection.collapsed(offset: v.text.length);
  return TextSelection(
    baseOffset: s.start.clamp(0, v.text.length),
    extentOffset: s.end.clamp(0, v.text.length),
  );
}

/// Puts [mark] at the start of the line holding the selection, or takes it away when the line already starts with it. A line mark that is
/// another one of the three (list against checkbox) is swapped.
TextEditingValue _lineMark(TextEditingValue v, String mark) {
  const marks = <String>['- [ ] ', '- [x] ', '- ', '## '];
  final sel = _valid(v);
  final text = v.text;
  final start = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1) + 1;
  final lineStart = sel.start == 0 ? 0 : start;
  final rest = text.substring(lineStart);
  String? had;
  for (final m in marks) {
    if (rest.startsWith(m)) {
      had = m;
      break;
    }
  }
  final String next;
  final int shift;
  if (had == mark) {
    next = text.replaceRange(lineStart, lineStart + mark.length, '');
    shift = -mark.length;
  } else if (had != null) {
    next = text.replaceRange(lineStart, lineStart + had.length, mark);
    shift = mark.length - had.length;
  } else {
    next = text.replaceRange(lineStart, lineStart, mark);
    shift = mark.length;
  }
  int move(int o) => (o + shift).clamp(lineStart, next.length);
  return TextEditingValue(
    text: next,
    selection: TextSelection(
      baseOffset: move(sel.start),
      extentOffset: move(sel.end),
    ),
  );
}

/// Wraps the selection in [open] and [close]; with nothing selected the cursor lands between them.
TextEditingValue _wrap(TextEditingValue v, String open, String close) {
  final sel = _valid(v);
  final inner = v.text.substring(sel.start, sel.end);
  final next = v.text.replaceRange(sel.start, sel.end, '$open$inner$close');
  return TextEditingValue(
    text: next,
    selection: TextSelection(
      baseOffset: sel.start + open.length,
      extentOffset: sel.start + open.length + inner.length,
    ),
  );
}

/// [value] after the toolbar button [edit].
TextEditingValue applyMarkdownEdit(TextEditingValue value, MarkdownEdit edit) {
  switch (edit) {
    case MarkdownEdit.heading:
      return _lineMark(value, '## ');
    case MarkdownEdit.list:
      return _lineMark(value, '- ');
    case MarkdownEdit.checkbox:
      return _lineMark(value, '- [ ] ');
    case MarkdownEdit.bold:
      return _wrap(value, '**', '**');
    case MarkdownEdit.pageLink:
      return _wrap(value, '[[', ']]');
    case MarkdownEdit.link:
      final sel = _valid(value);
      final label = value.text.substring(sel.start, sel.end);
      final next = value.text.replaceRange(
        sel.start,
        sel.end,
        '[$label](https://)',
      );
      // With words selected the address is what is left to type; with none, the words are
      return TextEditingValue(
        text: next,
        selection: label.isEmpty
            ? TextSelection.collapsed(offset: sel.start + 1)
            : TextSelection(
                baseOffset: sel.start + label.length + 3,
                extentOffset: sel.start + label.length + 3 + 8,
              ),
      );
  }
}
