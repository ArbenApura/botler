// FOLDS A RUN OF IDENTICAL QUIET "CHECKED ..." LINES INTO ONE LINE WITH A COUNT, SO SIX LOOKUPS OF THE SAME KIND DO NOT FILL THE SCREEN.
// Only plain read lines fold. Anything that draws a chip, a card or an Undo, a tool that is still running, and a failed one are always shown on their own.

// -- MODULES -- //
import 'chat_state.dart';

// -- TYPES -- //

/// One row of the conversation. [more] is how many identical lines were folded into it (0 when it stands alone).
final class ChatRow {
  const ChatRow(this.item, [this.more = 0]);

  final ChatItem item;
  final int more;
}

// -- CONSTANTS -- //

/// The tools whose answer is drawn as something more than the quiet line (a logged line with Undo, a card, a chip).
const Set<String> _drawnTools = <String>{
  'expense_from_text',
  'expense_log',
  'income_record',
  'refund_record',
  'transfer_record',
  'split_propose',
  'rule_from_text',
  'rule_propose',
  'bill_mark_paid',
};

// -- FUNCTIONS -- //

bool _isQuiet(ChatItem i) =>
    i is ToolItem &&
    !i.running &&
    i.status == 'ok' &&
    !_drawnTools.contains(i.name);

/// The same tool, from the same place (this run or an earlier one).
bool _sameKind(ToolItem a, ToolItem b) =>
    a.name == b.name && a.restored == b.restored;

/// Turns the list into rows, folding each run of identical quiet tool lines into its first line. The row keeps the first line's id.
List<ChatRow> groupQuietTools(List<ChatItem> items) {
  final rows = <ChatRow>[];
  for (final item in items) {
    final last = rows.isEmpty ? null : rows.last;
    if (last != null &&
        _isQuiet(item) &&
        _isQuiet(last.item) &&
        _sameKind(item as ToolItem, last.item as ToolItem)) {
      rows[rows.length - 1] = ChatRow(last.item, last.more + 1);
    } else {
      rows.add(ChatRow(item));
    }
  }
  return rows;
}
