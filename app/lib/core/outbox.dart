// THE OUTBOX: WRITES MADE WITHOUT A CONNECTION WAIT HERE WITH THEIR REQUEST ID AND GO OUT WHEN THE PHONE IS BACK ONLINE.
// The server applies a request id once and answers a repeat with the first result, so sending an item twice (a lost answer, a crash between send and
// removal) never doubles an entry. An item the server refuses for good (a bad amount) is dropped and reported, not retried for ever.
// A refused write that moves money (a bill paid, money moved) is not lost without a trace: it is kept, with the server's reason, until the person
// looks at it and dismisses it, so a payment they made never silently disappears.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'api.dart';
import 'json.dart';

// -- TYPES -- //

class OutboxItem {
  const OutboxItem({
    required this.key,
    required this.verb,
    required this.args,
    required this.createdAt,
    this.attempts = 0,
  });

  factory OutboxItem.fromJson(Json j) => OutboxItem(
    key: str(j['key']),
    verb: str(j['verb']),
    args: asJson(j['args']),
    createdAt: dateOf(j['createdAt']) ?? DateTime.now(),
    attempts: intOf(j['attempts']),
  );

  /// The request id. Fixed when the item is made, so every attempt carries the same one.
  final String key;
  final String verb;
  final Json args;
  final DateTime createdAt;
  final int attempts;

  Json toJson() => <String, Object?>{
    'key': key,
    'verb': verb,
    'args': args,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };

  OutboxItem tried() => OutboxItem(
    key: key,
    verb: verb,
    args: args,
    createdAt: createdAt,
    attempts: attempts + 1,
  );
}

/// A write the server refused for good, kept so the person can see what did not go through.
class FailedItem {
  const FailedItem({
    required this.key,
    required this.verb,
    required this.args,
    required this.reason,
    required this.at,
  });

  factory FailedItem.fromJson(Json j) => FailedItem(
    key: str(j['key']),
    verb: str(j['verb']),
    args: asJson(j['args']),
    reason: str(j['reason']),
    at: dateOf(j['at']) ?? DateTime.now(),
  );

  final String key;
  final String verb;
  final Json args;

  /// The plain-words reason the server gave.
  final String reason;
  final DateTime at;

  Json toJson() => <String, Object?>{
    'key': key,
    'verb': verb,
    'args': args,
    'reason': reason,
    'at': at.toIso8601String(),
  };
}

/// What one flush did.
class FlushReport {
  const FlushReport({
    this.sent = 0,
    this.dropped = const <String>[],
    this.left = 0,
  });
  final int sent;

  /// The plain-words reason for each item the server refused for good.
  final List<String> dropped;
  final int left;
}

// -- CONSTANTS -- //

const String _prefsKey = 'outbox.v1';
const String _failedKey = 'outbox.failed.v1';

/// The writes that move money, and the changes to pages made offline. When the server refuses one for good it is kept for the person to see,
/// not only reported once.
const Set<String> _keptWhenRefused = <String>{
  'bill_mark_paid',
  'transfer_record',
  'expense_log',
  'income_record',
  // A move, a rename or a pin aimed at a page that is gone by the time it is sent stays visible, so the person knows it did not happen
  'page_move',
  'page_rename',
  'page_pin',
  'notebook_pin',
};

/// An item that failed this many times for a reason that is not the network is given up on.
const int _maxAttempts = 8;

// -- FUNCTIONS -- //

class Outbox {
  Outbox(this._prefs);

  final SharedPreferences _prefs;

  List<OutboxItem> items() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return <OutboxItem>[];
    try {
      return asJsonList(jsonDecode(raw)).map(OutboxItem.fromJson).toList();
    } on FormatException {
      return <OutboxItem>[];
    }
  }

  int get length => items().length;

  /// The refused writes that are kept, oldest first.
  List<FailedItem> failed() {
    final raw = _prefs.getString(_failedKey);
    if (raw == null) return <FailedItem>[];
    try {
      return asJsonList(jsonDecode(raw)).map(FailedItem.fromJson).toList();
    } on FormatException {
      return <FailedItem>[];
    }
  }

  Future<void> _saveFailed(List<FailedItem> list) => _prefs.setString(
    _failedKey,
    jsonEncode(list.map((i) => i.toJson()).toList()),
  );

  /// The person has seen the refused writes: they are forgotten.
  Future<void> dismissFailed() => _saveFailed(<FailedItem>[]);

  Future<void> _save(List<OutboxItem> list) => _prefs.setString(
    _prefsKey,
    jsonEncode(list.map((i) => i.toJson()).toList()),
  );

  /// Drops everything waiting to be sent. Used after a data reset, so old writes never replay onto the empty account.
  Future<void> clear() => _save(<OutboxItem>[]);

  /// Keeps a write for later. Returns its request id. Pass [key] when the write was already tried once under that id, so the server
  /// recognises a repeat if the first try did get through but its answer was lost.
  Future<String> add(String verb, Json args, {String? key}) async {
    final item = OutboxItem(
      key: key ?? newRequestId(),
      verb: verb,
      args: args,
      createdAt: DateTime.now(),
    );
    await _save(<OutboxItem>[...items(), item]);
    return item.key;
  }

  /// Sends everything, oldest first, and stops at the first item that cannot be delivered because of the connection, so the order is kept.
  Future<FlushReport> flush(ApiClient api) async {
    final pending = items();
    final left = <OutboxItem>[];
    final dropped = <String>[];
    final refused = <FailedItem>[];
    var sent = 0;
    var offline = false;
    for (final item in pending) {
      if (offline) {
        left.add(item);
        continue;
      }
      try {
        await api.verb(item.verb, item.args, item.key, 'outbox');
        sent++;
      } on ApiException catch (e) {
        if (e.isRetryable && item.attempts < _maxAttempts) {
          left.add(item.tried());
          offline = e.isNetwork;
        } else {
          dropped.add(e.message);
          // A refused payment or move stays visible until the person dismisses it
          if (_keptWhenRefused.contains(item.verb)) {
            refused.add(
              FailedItem(
                key: item.key,
                verb: item.verb,
                args: item.args,
                reason: e.message,
                at: DateTime.now(),
              ),
            );
          }
        }
      }
    }
    await _save(left);
    if (refused.isNotEmpty)
      await _saveFailed(<FailedItem>[...failed(), ...refused]);
    return FlushReport(sent: sent, dropped: dropped, left: left.length);
  }
}
