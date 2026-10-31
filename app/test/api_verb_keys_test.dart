// EVERY WRITE VERB THE SCREENS AND STATE CALL CARRIES A REQUEST KEY (THE THIRD ARGUMENT OF verb / verbJson). A CALL WITHOUT ONE GETS A NEW KEY EVERY TIME
// IT IS MADE, SO A SECOND TAP OR A RETRY IS A SECOND WRITE. THE KEY HAS TO COME FROM THE SHEET OR CHIP THAT STARTED THE ACTION (ui/once.dart).
// The write verbs are listed here from the server registry (server/src/lib/server/ops/registry.ts): everything that is not a plain read.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// -- CONSTANTS -- //

/// The verbs of the server registry that change something (classes free, gated and person) plus the app-only ones.
const Set<String> writeVerbs = <String>{
  'task_create',
  'task_update',
  'event_create',
  'event_update',
  'event_delete',
  'routine_create',
  'routine_update',
  'reminder_create',
  'alarm_create',
  'timer_create',
  'reminder_cancel',
  'notebook_edit',
  'notebook_create',
  'notebook_update',
  'notebook_delete',
  'notebook_undelete',
  'page_create',
  'page_edit',
  'page_rename',
  'page_move',
  'page_merge',
  'page_delete',
  'page_undelete',
  'expense_log',
  'expense_from_text',
  'income_record',
  'refund_record',
  'transfer_record',
  'undo',
  'rule_propose',
  'rule_from_text',
  'split_propose',
  'split_mark_sent',
  'bill_mark_paid',
  'account_update',
  'income_update',
  'bill_update',
  'bill_occurrence_update',
  'bill_occurrence_reset',
  'goal_update',
  'account_create',
  'account_wallet_add',
  'account_archive',
  'income_create',
  'bill_create',
  'goal_create',
  'goal_delete',
  'bill_delete',
  'income_delete',
  'rule_update',
  'split_delete',
  'rule_delete',
  'account_delete',
  'account_wallet_remove',
  'snapshot_record',
  'fx_rates_refresh',
  'data_reset',
  'chat_clear',
  'chat_new',
  'chat_open',
  'chat_rename',
  'chat_pin',
  'chat_archive',
  'chat_fork',
  'chat_rewind',
  'settings_set',
  'rule_approve',
  'rule_retire',
  'notebook_save',
  'notebook_restore',
  'page_save',
  'page_restore',
  'page_pin',
  'notebook_pin',
  'page_seen',
  'memory_wipe',
  'split_approve',
  'profile_set',
};

/// Calls that may go without a key, as "file:verb". Each is a call whose file belongs to a part of the app that makes the key itself in a
/// way this check cannot see, with the reason. Adding to this list needs a reason; a new write call needs a key instead.
const Map<String, String> allowed = <String, String>{
  // chat_state.dart and providers.dart are owned by the chat and settings work; their calls are named here until they pass keys too
  'features/chat/chat_state.dart:chat_new':
      'opens a fresh chat; owned by chat_state',
  'features/chat/chat_state.dart:chat_open':
      'moves to a chat; owned by chat_state',
  'features/chat/chat_state.dart:chat_fork':
      'copies a chat; owned by chat_state',
  'state/providers.dart:settings_set':
      'a setting set to a value is idempotent by itself',
  'features/settings/reset_screen.dart:data_reset':
      'single-use token from data_reset_preview is the key',
};

// -- FUNCTIONS -- //

/// The index just after the string literal that starts at [i] (a quote), looking through `${...}` parts.
int _skipString(String s, int i) {
  final quote = s[i];
  var j = i + 1;
  while (j < s.length) {
    final ch = s[j];
    if (ch == r'\') {
      j += 2;
    } else if (ch == quote) {
      return j + 1;
    } else if (ch == r'$' && j + 1 < s.length && s[j + 1] == '{') {
      j = _skipCode(s, j + 2, '}') + 1;
    } else {
      j++;
    }
  }
  return j;
}

/// The index of the [close] bracket that ends the code starting at [i], counting nested brackets and skipping strings.
int _skipCode(String s, int i, String close) {
  var depth = 0;
  var j = i;
  while (j < s.length) {
    final ch = s[j];
    if (ch == "'" || ch == '"') {
      j = _skipString(s, j);
      continue;
    }
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') {
      if (depth == 0 && ch == close) return j;
      depth--;
    }
    j++;
  }
  return s.length;
}

/// How many arguments the call whose opening bracket is at [open] has at its own level.
int argumentCount(String s, int open) {
  final end = _skipCode(s, open + 1, ')');
  var depth = 0;
  var count = 0;
  var any = false;
  var j = open + 1;
  while (j < end) {
    final ch = s[j];
    if (ch == "'" || ch == '"') {
      any = true;
      j = _skipString(s, j);
      continue;
    }
    // A type argument list at the start of an argument (`<String, Object?>{...}`) is skipped whole: its commas are not arguments
    if (ch == '<' && !any) {
      var angle = 0;
      while (j < end) {
        if (s[j] == '<') angle++;
        if (s[j] == '>') angle--;
        j++;
        if (angle == 0) break;
      }
      any = true;
      continue;
    }
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') depth--;
    if (ch == ',' && depth == 0) {
      count++;
      any = false;
    } else if (ch.trim().isNotEmpty) {
      any = true;
    }
    j++;
  }
  // A trailing comma adds no argument
  return count + (any ? 1 : 0);
}

/// The calls without a key in [source]: "verb" for each write verb called with fewer than three arguments.
List<String> keylessWrites(String source) {
  final found = <String>[];
  final call = RegExp(r"\.verb(?:Json)?\(\s*'([a-z_]+)'");
  for (final m in call.allMatches(source)) {
    final verb = m.group(1) ?? '';
    if (!writeVerbs.contains(verb)) continue;
    final open = source.indexOf('(', m.start);
    if (argumentCount(source, open) < 3) found.add(verb);
  }
  return found;
}

void main() {
  test('the argument counter reads calls the way the compiler does', () {
    expect(argumentCount("f('a', {'x': 1, 'y': g(2, 3)}, key)", 1), 3);
    expect(argumentCount("f('a', {'x': '\${m['k']}'}, key)", 1), 3);
    expect(argumentCount("f('a', {'x': '(,['})", 1), 2);
    expect(argumentCount("f('a', <String, Object?>{'x': 1},)", 1), 2);
    expect(argumentCount("f('a')", 1), 1);
  });

  test('the finder sees a missing key and a present one', () {
    expect(keylessWrites("api.verb('expense_log', {'a': 1})"), <String>[
      'expense_log',
    ]);
    expect(keylessWrites("api.verb('expense_log', {'a': 1}, key)"), isEmpty);
    expect(
      keylessWrites(
        "api.verb(\n 'undo',\n <String, Object?>{'j': 1},\n key,\n)",
      ),
      isEmpty,
    );
    // Reads never need one
    expect(keylessWrites("api.verbList('bills_list')"), isEmpty);
    expect(keylessWrites("api.verb('memory_export')"), isEmpty);
  });

  test('every write verb call in the screens and the state has a key', () {
    final missing = <String>[];
    for (final dir in <String>['lib/features', 'lib/state']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/').replaceFirst('lib/', '');
        for (final verb in keylessWrites(f.readAsStringSync())) {
          if (!allowed.containsKey('$path:$verb')) missing.add('$path:$verb');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'These write calls have no request key. Make the key in the sheet or '
          'chip that starts the action (ui/once.dart) and pass it as the third '
          'argument.',
    );
  });
}
