// GROUPING TOOL CALLS OF ONE KIND: A RUN BECOMES ONE ROW (RUNNING MEMBERS INCLUDED), AND A FAILURE, A WRITE, A CARD OR A PHONE TOOL STANDS ALONE.

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
  String? family,
}) => ToolItem(
  id,
  name: name,
  status: running ? 'running' : status,
  running: running,
  restored: restored,
  family: family,
);

/// Each row as its first id and how many calls it holds (0 when it stands alone).
List<String> shape(List<ChatRow> rows) =>
    rows.map((r) => '${r.item.id}x${r.members.length}').toList();

void main() {
  group('grouping tool calls', () {
    test('six lookups of one tool become one row', () {
      final rows = groupQuietTools(<ChatItem>[
        for (var i = 1; i <= 6; i++) tool(i, 'bill_occurrence_update'),
      ]);
      expect(shape(rows), <String>['1x6']);
      expect(rows.single.isGroup, isTrue);
    });

    test('lookups of different tools join the same group', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        tool(2, 'bills_due'),
        tool(3, 'accounts_list'),
      ]);
      expect(shape(rows), <String>['1x3']);
    });

    test(
      'a different kind starts a new row, and one call alone is no group',
      () {
        final rows = groupQuietTools(<ChatItem>[
          tool(1, 'page_get', family: 'page_read'),
          tool(2, 'page_get', family: 'page_read'),
          tool(3, 'research', family: 'web'),
          tool(4, 'page_get', family: 'page_read'),
        ]);
        expect(shape(rows), <String>['1x2', '3x0', '4x0']);
        expect(rows[1].isGroup, isFalse);
      },
    );

    test('words between two runs keep them apart', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        const AgentItem(2, 'Checking.'),
        tool(3, 'bills_list'),
        tool(4, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1x0', '2x0', '3x2']);
    });

    test('a running call joins its group and keeps the first id', () {
      final before = groupQuietTools(<ChatItem>[
        tool(1, 'page_get', family: 'page_read'),
        tool(2, 'page_get', family: 'page_read'),
        tool(3, 'page_get', family: 'page_read', running: true),
      ]);
      expect(shape(before), <String>['1x3']);
      expect(before.single.members.last.running, isTrue);
      // The same call done: still the same row id, so the open state stays
      final after = groupQuietTools(<ChatItem>[
        tool(1, 'page_get', family: 'page_read'),
        tool(2, 'page_get', family: 'page_read'),
        tool(3, 'page_get', family: 'page_read'),
      ]);
      expect(after.single.item.id, before.single.item.id);
    });

    test('a running call with no label from an older server stands alone', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        tool(2, 'bills_list', running: true),
      ]);
      expect(shape(rows), <String>['1x0', '2x0']);
    });

    test('a failed, blocked or approval call is never grouped', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list'),
        tool(2, 'bills_list', status: 'error'),
        tool(3, 'bills_list', status: 'blocked'),
        tool(4, 'bills_list', status: 'needs_approval'),
        tool(5, 'bills_list'),
        tool(6, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1x0', '2x0', '3x0', '4x0', '5x2']);
    });

    test(
      'a write never folds: notebook saves and page edits keep their own rows',
      () {
        final rows = groupQuietTools(<ChatItem>[
          tool(1, 'notebook_edit', family: 'notebook_write'),
          tool(2, 'notebook_edit', family: 'notebook_write'),
          tool(3, 'page_edit', family: 'page_write'),
          tool(4, 'page_edit', family: 'page_write'),
          tool(5, 'bill_create', family: 'record'),
          tool(6, 'bill_create', family: 'record'),
        ]);
        expect(rows, hasLength(6));
        expect(rows.every((r) => !r.isGroup), isTrue);
      },
    );

    test('a tool that draws a chip, a card or Undo is never grouped', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'expense_log'),
        tool(2, 'expense_log'),
        tool(3, 'split_propose'),
        tool(4, 'split_propose'),
        tool(5, 'bill_mark_paid'),
        tool(6, 'bill_mark_paid'),
      ]);
      expect(rows, hasLength(6));
      expect(rows.every((r) => !r.isGroup), isTrue);
    });

    test('the phone tools stand alone', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'script_run', family: 'lookup'),
        tool(2, 'script_run', family: 'lookup'),
        tool(3, 'toolbox'),
        tool(4, 'toolbox'),
      ]);
      expect(rows, hasLength(4));
    });

    test('lines from an earlier session and from this one stay apart', () {
      final rows = groupQuietTools(<ChatItem>[
        tool(1, 'bills_list', restored: true),
        tool(2, 'bills_list', restored: true),
        tool(3, 'bills_list'),
        tool(4, 'bills_list'),
      ]);
      expect(shape(rows), <String>['1x2', '3x2']);
    });

    test('an empty list and a list with no tools come back as they are', () {
      expect(groupQuietTools(<ChatItem>[]), isEmpty);
      final rows = groupQuietTools(<ChatItem>[
        const UserItem(1, 'hi'),
        const AgentItem(2, 'hello'),
      ]);
      expect(shape(rows), <String>['1x0', '2x0']);
    });
  });
}
