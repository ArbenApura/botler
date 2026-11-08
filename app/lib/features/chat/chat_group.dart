// GROUPS A RUN OF TOOL CALLS OF THE SAME KIND (READING PAGES, SEARCHING THE WEB, QUIET LOOKUPS) INTO ONE ROW WITH A COUNT THAT OPENS TO THE LIST.
// Only calls that are running or done quietly join a group. A failed or blocked call, a write, anything that draws a chip, a card or an Undo, and a call the
// phone runs always stand on their own, and a notebook save is never folded: each one names its own section or page.

// -- MODULES -- //
import 'chat_state.dart';
import 'tool_words.dart';

// -- TYPES -- //

/// One row of the conversation. For a group, [item] is its first member (so the row keeps a steady id) and [members] holds all of them (two or more).
final class ChatRow {
  const ChatRow(this.item, [this.members = const <ToolItem>[]]);

  final ChatItem item;
  final List<ToolItem> members;

  bool get isGroup => members.length > 1;
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
  'research',
};

// -- FUNCTIONS -- //

/// Turns the list into rows. A run of calls of one kind from the same place (this run or an earlier one) becomes one group row.
List<ChatRow> groupQuietTools(List<ChatItem> items) {
  final rows = <ChatRow>[];
  var run = <ToolItem>[];
  String? runFamily;
  var runRestored = false;

  void flush() {
    if (run.isEmpty) return;
    rows.add(
      ChatRow(
        run.first,
        run.length > 1 ? List<ToolItem>.unmodifiable(run) : const <ToolItem>[],
      ),
    );
    run = <ToolItem>[];
    runFamily = null;
  }

  for (final item in items) {
    final family = item is ToolItem ? groupFamilyOf(item, _drawnTools) : null;
    if (item is ToolItem && family != null) {
      if (run.isNotEmpty &&
          runFamily == family &&
          runRestored == item.restored) {
        run.add(item);
      } else {
        flush();
        run = <ToolItem>[item];
        runFamily = family;
        runRestored = item.restored;
      }
    } else {
      flush();
      rows.add(ChatRow(item));
    }
  }
  flush();
  return rows;
}
