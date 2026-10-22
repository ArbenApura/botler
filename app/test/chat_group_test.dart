// FOLDING IDENTICAL QUIET TOOL LINES: A RUN BECOMES ONE ROW WITH A COUNT, AND ANYTHING THAT IS MORE THAN A QUIET LINE STANDS ALONE.

// -- DEP-MODULES -- //
import 'package:botler/features/chat/chat_group.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

ToolItem tool(
  int id,
  String name, {
  String status = 'ok',
  bool running = false,
  bool restored = false,
}) => ToolItem(
  id,
  name: name,
  status: status,
  running: running,
  restored: restored,
);

List<String> shape(List<ChatRow> rows) =>
    rows.map((r) => '${r.item.id}+${r.more}').toList();

void main() {
  group('folding quiet tool lines', () {
    test('six identical lines become one row that says five more', () {
      final rows = groupQuietTools(<ChatItem>[
        for (var i = 1; i <= 6; i++) tool(i, 'bill_occurrence_update'),
      ]);
      expect(shape(rows), <String>['1+5']);
    });

    test('a different tool, or the same one after it, starts a new row', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        tool(2, 'bills_due'),
        tool(3, 'bill_occurrence_update'),
        tool(4, 'bill_occurrence_update'),
        tool(5, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1+0', '2+0', '3+1', '5+0']);
    });

    test('words between two runs keep them apart', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        const AgentItem(2, 'Checking.'),
        tool(3, 'bills_list'),
        tool(4, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1+0', '2+0', '3+1']);
    });

    test('a failed, running or approval line is never folded', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        tool(2, 'bills_list', status: 'error'),
        tool(3, 'bills_list', status: 'needs_approval'),
        tool(4, 'bills_list', running: true),
        tool(5, 'bills_list'),
        tool(6, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1+0', '2+0', '3+0', '4+0', '5+1']);
    });

    test('a tool that draws a chip, a card or Undo is never folded', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'expense_log'),
        tool(2, 'expense_log'),
        tool(3, 'split_propose'),
        tool(4, 'split_propose'),
        tool(5, 'bill_mark_paid'),
        tool(6, 'bill_mark_paid'),
      ]);
      expect(rows.map((r) => r.more).toSet(), <int>{0});
      expect(rows, hasLength(6));
    });

    test('lines from an earlier session and from this one stay apart', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list', restored: true),
        tool(2, 'bills_list', restored: true),
        tool(3, 'bills_list'),
        tool(4, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1+1', '3+1']);
    });

    test('an empty list and a list with no tools come back as they are', () {
      expect(groupQuietTools(<ChatItem>[]), isEmpty);
      final rows = groupQuietTools(<ChatItem>[
        const UserItem(1, 'hi'),
        const AgentItem(2, 'hello'),
      ]);
      expect(shape(rows), <String>['1+0', '2+0']);
    });
  });
}
