// THE SMALL ROW OF MARKDOWN BUTTONS OVER THE KEYBOARD IN THE PAGE EDITOR: HEADING, BOLD, LIST, CHECKBOX, LINK AND [[PAGE LINK]].
// Six buttons of 48 dp share the width, so nothing scrolls sideways. Each says what it does to a screen reader. The edits themselves are
// in markdown_edit.dart.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'markdown_edit.dart';

// -- WIDGETS -- //

class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({required this.onEdit, super.key});

  final void Function(MarkdownEdit edit) onEdit;

  Widget _button(
    BuildContext context,
    MarkdownEdit edit,
    IconData icon,
    String label,
  ) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: () => onEdit(edit),
        child: IconButton(
          key: ValueKey<String>('md.${edit.name}'),
          tooltip: label,
          constraints: const BoxConstraints(
            minHeight: minTap,
            minWidth: minTap,
          ),
          onPressed: () => onEdit(edit),
          icon: Icon(icon, color: context.colors.ink),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: <Widget>[
          _button(context, MarkdownEdit.heading, Icons.title, t.mdHeading),
          _button(context, MarkdownEdit.bold, Icons.format_bold, t.mdBold),
          _button(
            context,
            MarkdownEdit.list,
            Icons.format_list_bulleted,
            t.mdList,
          ),
          _button(
            context,
            MarkdownEdit.checkbox,
            Icons.check_box_outlined,
            t.mdCheckbox,
          ),
          _button(context, MarkdownEdit.link, Icons.link, t.mdLink),
          _button(
            context,
            MarkdownEdit.pageLink,
            Icons.note_add_outlined,
            t.mdPageLink,
          ),
        ],
      ),
    );
  }
}
