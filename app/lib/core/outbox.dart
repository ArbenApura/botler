// THE OUTBOX: WRITES MADE WITHOUT A CONNECTION WAIT HERE WITH THEIR REQUEST ID AND GO OUT WHEN THE PHONE IS BACK ONLINE.
// The server applies a request id once and answers a repeat with the first result, so sending an item twice (a lost answer, a crash between send and
// removal) never doubles an entry. An item the server refuses for good (a bad amount) is dropped and reported, not retried for ever.
// A refused write of ANY verb is not lost without a trace: it is kept, with the server's reason, until the person looks at it and dismisses it,
// so a payment they made never silently disappears. The same goes for an item that failed 8 times or waited 14 days.
// Storage: one preferences key per item (outbox.i.KEY) and per refused item (outbox.f.KEY), so adding and removing one never rewrites the others
// and the background isolate and the app agree (every read reloads first). The two old blobs (outbox.v1, outbox.failed.v1) are read once and moved.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    this.userId,
    this.seq = 0,
  });

  factory OutboxItem.fromJson(Json j) => OutboxItem(
    key: str(j['key']),
    verb: str(j['verb']),
    args: asJson(j['args']),
    createdAt: dateOf(j['createdAt']) ?? DateTime.now(),
    attempts: intOf(j['attempts']),
    userId: j['userId'] is String ? j['userId'] as String : null,
    seq: intOf(j['seq']),
  );

  /// The request id. Fixed when the item is made, so every attempt carries the same one.
  final String key;
  final String verb;
  final Json args;
  final DateTime createdAt;
  final int attempts;

  /// The person who queued it (null on items queued by an older build). Only that person's session sends it.
  final String? userId;

  /// The order of queueing: a number that only grows, so the oldest goes first even when two items share a clock tick.
  final int seq;

  Json toJson() => <String, Object?>{
    'key': key,
    'verb': verb,
    'args': args,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
    'userId': ?userId,
    'seq': seq,
  };

  OutboxItem tried() => OutboxItem(
    key: key,
    verb: verb,
    args: args,
    createdAt: createdAt,
    attempts: attempts + 1,
    userId: userId,
    seq: seq,
  );

  OutboxItem withSeq(int next) => OutboxItem(
    key: key,
    verb: verb,
    args: args,
    createdAt: createdAt,
    attempts: attempts,
    userId: userId,
    seq: next,
  );
}

/// A write the server refused for good (or that failed too often), kept so the person can see what did not go through.
class FailedItem {
  const FailedItem({
    required this.key,
    required this.verb,
    required this.args,
    required this.reason,
    required this.at,
    this.userId,
  });

  factory FailedItem.fromJson(Json j) => FailedItem(
    key: str(j['key']),
    verb: str(j['verb']),
    args: asJson(j['args']),
    reason: str(j['reason']),
    at: dateOf(j['at']) ?? DateTime.now(),
    userId: j['userId'] is String ? j['userId'] as String : null,
  );

  final String key;
  final String verb;
  final Json args;

  /// The plain-words reason the server gave.
  final String reason;
  final DateTime at;
  final String? userId;

  Json toJson() => <String, Object?>{
    'key': key,
    'verb': verb,
    'args': args,
    'reason': reason,
    'at': at.toIso8601String(),
    'userId': ?userId,
  };
}

/// What one flush did.
class FlushReport {
  const FlushReport({
    this.sent = 0,
    this.dropped = const <String>[],
    this.left = 0,
    this.needsSignIn = false,
    this.offline = false,
  });
  final int sent;

  /// The plain-words reason for each item the server refused for good (each is also on the failed list).
  final List<String> dropped;
  final int left;

  /// The server answered 401: the session is no longer good. The whole queue was kept; the person must sign in again.
  final bool needsSignIn;

  /// The pass stopped because the server could not be reached.
  final bool offline;
}

// -- CONSTANTS -- //

const String _legacyKey = 'outbox.v1';
const String _legacyFailedKey = 'outbox.failed.v1';
const String _itemPrefix = 'outbox.i.';
const String _failedPrefix = 'outbox.f.';

/// An item that failed this many times for a reason that is not the network is given up on (moved to the failed list).
const int _maxAttempts = 8;

/// An item this old is given up on too, so a write that can never go does not wait for ever.
const Duration _maxAge = Duration(days: 14);

// The last number handed out by this isolate; the clock keeps the numbers of other isolates in order
int _lastSeq = 0;

// One flush at a time per preferences store (one per isolate in the app), and the short writes (add, clear, dismiss, one step of a flush) one
// at a time in their own lane, so an add never waits for the network. Kept per store so a test's abandoned wait never blocks the next test.
final Expando<_Lanes> _lanesOf = Expando<_Lanes>('outbox lanes');

// -- FUNCTIONS -- //

int _nextSeq() {
  final now = DateTime.now().microsecondsSinceEpoch;
  _lastSeq = now > _lastSeq ? now : _lastSeq + 1;
  return _lastSeq;
}

/// True for the failures that mean "the server was not reached", whatever layer raised them.
bool _isOffline(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is TlsException;

class _Lanes {
  Future<void> flush = Future<void>.value();
  Future<void> write = Future<void>.value();
}

class Outbox {
  /// [userId] is the signed-in person (the session's e-mail). Items are tagged with it, and a flush sends only that person's items and
  /// the ones an older build queued with no tag. [now] is for tests.
  Outbox(this._prefs, {this._userId, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final String? _userId;
  final DateTime Function() _now;

  _Lanes get _lanes => _lanesOf[_prefs] ??= _Lanes();

  Future<T> _writeLane<T>(Future<T> Function() job) {
    final lanes = _lanes;
    final run = lanes.write.then((_) => job());
    lanes.write = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<T> _flushLane<T>(Future<T> Function() job) {
    final lanes = _lanes;
    final run = lanes.flush.then((_) => job());
    lanes.flush = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  // -- READING -- //

  bool _mine(String? owner) => owner == null || owner == _userId;

  List<OutboxItem> _readAll() {
    final out = <OutboxItem>[];
    for (final k in _prefs.getKeys()) {
      if (!k.startsWith(_itemPrefix)) continue;
      final raw = _prefs.getString(k);
      if (raw == null) continue;
      try {
        final item = OutboxItem.fromJson(decodeJson(raw));
        if (item.key.isNotEmpty) out.add(item);
      } on Object {
        // An unreadable item is skipped, never a crash
      }
    }
    out.addAll(_legacyItems());
    out.sort((a, b) {
      final c = a.seq.compareTo(b.seq);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return out;
  }

  // Items still in the old single blob; they sort first (their seq is their place in the blob)
  List<OutboxItem> _legacyItems() {
    final raw = _prefs.getString(_legacyKey);
    if (raw == null) return <OutboxItem>[];
    try {
      final list = asJsonList(jsonDecode(raw)).map(OutboxItem.fromJson);
      final have = <String>{
        for (final k in _prefs.getKeys())
          if (k.startsWith(_itemPrefix)) k.substring(_itemPrefix.length),
      };
      var n = 0;
      return <OutboxItem>[
        for (final i in list)
          if (!have.contains(i.key)) i.withSeq(++n),
      ];
    } on FormatException {
      return <OutboxItem>[];
    }
  }

  List<FailedItem> _readAllFailed() {
    final out = <FailedItem>[];
    for (final k in _prefs.getKeys()) {
      if (!k.startsWith(_failedPrefix)) continue;
      final raw = _prefs.getString(k);
      if (raw == null) continue;
      try {
        final item = FailedItem.fromJson(decodeJson(raw));
        if (item.key.isNotEmpty) out.add(item);
      } on Object {
        // Skipped
      }
    }
    final legacy = _prefs.getString(_legacyFailedKey);
    if (legacy != null) {
      try {
        final have = out.map((f) => f.key).toSet();
        out.addAll(
          asJsonList(jsonDecode(legacy))
              .map(FailedItem.fromJson)
              .where((f) => !have.contains(f.key)),
        );
      } on FormatException {
        // Skipped
      }
    }
    out.sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return out;
  }

  /// The writes waiting for this person (and the untagged old ones), oldest first.
  List<OutboxItem> items() => <OutboxItem>[
    for (final i in _readAll())
      if (_mine(i.userId)) i,
  ];

  /// Every waiting write on the phone, whoever queued it. For the sign-out warning and for tests.
  List<OutboxItem> allItems() => _readAll();

  int get length => items().length;

  /// The refused writes that are kept for this person, oldest first.
  List<FailedItem> failed() => <FailedItem>[
    for (final f in _readAllFailed())
      if (_mine(f.userId)) f,
  ];

  // -- WRITING -- //

  // Moves the old blobs to per-item keys (once). Called inside the write lane.
  Future<void> _migrate() async {
    if (_prefs.getString(_legacyKey) == null &&
        _prefs.getString(_legacyFailedKey) == null) {
      return;
    }
    // Written under the new keys before the old blob goes, so a crash in between loses nothing
    for (final i in _legacyItems()) {
      await _prefs.setString('$_itemPrefix${i.key}', jsonEncode(i.toJson()));
    }
    for (final f in _readAllFailed()) {
      if (_prefs.containsKey('$_failedPrefix${f.key}')) continue;
      await _prefs.setString('$_failedPrefix${f.key}', jsonEncode(f.toJson()));
    }
    await _prefs.remove(_legacyKey);
    await _prefs.remove(_legacyFailedKey);
  }

  Future<void> _fresh() async {
    await _prefs.reload();
    await _migrate();
  }

  /// The person has seen the refused writes: they are forgotten.
  Future<void> dismissFailed() => _writeLane(() async {
    await _fresh();
    for (final f in _readAllFailed()) {
      if (_mine(f.userId)) await _prefs.remove('$_failedPrefix${f.key}');
    }
  });

  /// Drops everything waiting to be sent for this person. Used after a data reset, so old writes never replay onto the empty account.
  /// Another person's waiting writes are not touched.
  Future<void> clear() => _writeLane(() async {
    await _fresh();
    for (final i in _readAll()) {
      if (_mine(i.userId)) await _prefs.remove('$_itemPrefix${i.key}');
    }
  });

  /// Keeps a write for later. Returns its request id. Pass [key] when the write was already tried once under that id, so the server
  /// recognises a repeat if the first try did get through but its answer was lost. A key that is already waiting is kept as it is.
  Future<String> add(String verb, Json args, {String? key}) {
    final id = key ?? newRequestId();
    return _writeLane(() async {
      await _fresh();
      if (_prefs.containsKey('$_itemPrefix$id')) return id;
      final item = OutboxItem(
        key: id,
        verb: verb,
        args: args,
        createdAt: _now(),
        userId: _userId,
        seq: _nextSeq(),
      );
      await _prefs.setString('$_itemPrefix$id', jsonEncode(item.toJson()));
      return id;
    });
  }

  // One step of a flush: the item is gone (sent, or moved to the failed list)
  Future<void> _finish(OutboxItem item, {String? reason}) =>
      _writeLane(() async {
        await _prefs.reload();
        if (reason != null) {
          await _prefs.setString(
            '$_failedPrefix${item.key}',
            jsonEncode(
              FailedItem(
                key: item.key,
                verb: item.verb,
                args: item.args,
                reason: reason,
                at: _now(),
                userId: item.userId,
              ).toJson(),
            ),
          );
        }
        await _prefs.remove('$_itemPrefix${item.key}');
      });

  Future<void> _countAttempt(OutboxItem item) => _writeLane(() async {
    await _prefs.reload();
    // A clear in the meantime wins: the item is not brought back
    if (!_prefs.containsKey('$_itemPrefix${item.key}')) return;
    await _prefs.setString(
      '$_itemPrefix${item.key}',
      jsonEncode(item.tried().toJson()),
    );
  });

  Future<bool> _stillQueued(OutboxItem item) => _writeLane(() async {
    await _prefs.reload();
    return _prefs.containsKey('$_itemPrefix${item.key}');
  });

  /// Sends this person's items, oldest first. Stops at the first item the connection blocks (nothing counted), at a 401 (the whole queue
  /// is kept) and at a busy server (an attempt is counted), so the order is kept. An item the server refuses, or that failed
  /// 8 times or is 14 days old, moves to the failed list with the reason; one that fails in the app itself counts an attempt and the pass
  /// goes on, so it cannot block the rest for ever. Every step is saved as it happens, so a crash or a second pass never works from a stale list.
  Future<FlushReport> flush(ApiClient api) => _flushLane(() => _flush(api));

  Future<FlushReport> _flush(ApiClient api) async {
    await _writeLane(_fresh);
    final dropped = <String>[];
    var sent = 0;
    var needsSignIn = false;
    var offline = false;
    try {
      for (final item in items()) {
        // It may have been cleared since the pass began
        if (!await _stillQueued(item)) continue;
        if (_now().difference(item.createdAt) > _maxAge) {
          const reason =
              'This was waiting for more than 14 days and was given up.';
          dropped.add(reason);
          await _finish(item, reason: reason);
          continue;
        }
        if (item.attempts >= _maxAttempts) {
          const reason = 'This failed too many times and was given up.';
          dropped.add(reason);
          await _finish(item, reason: reason);
          continue;
        }
        try {
          await api.verb(item.verb, item.args, item.key, 'outbox');
          sent++;
          await _finish(item);
        } on ApiException catch (e) {
          if (e.isUnauthenticated) {
            needsSignIn = true;
            break;
          }
          if (e.isNetwork) {
            offline = true;
            break;
          }
          if (e.isRetryable) {
            await _countAttempt(item);
            break;
          }
          dropped.add(e.message);
          await _finish(item, reason: e.message);
        } on Object catch (e) {
          if (_isOffline(e)) {
            offline = true;
            break;
          }
          // Something broke in the app (a bad answer, an argument that cannot be encoded): counted, and the next item still goes
          await _countAttempt(item);
        }
      }
    } finally {
      await _writeLane(_fresh);
    }
    return FlushReport(
      sent: sent,
      dropped: dropped,
      left: items().length,
      needsSignIn: needsSignIn,
      offline: offline,
    );
  }
}
