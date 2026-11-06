// THE PHONE'S SIDE OF THE ASSISTANT'S PHONE TOOLS (BTL-20261031-1334): THE CHAT STREAM ANNOUNCES A CALL (script_run OR toolbox) WITH ITS ARGUMENTS AND AN ID,
// THIS RUNS IT, AND THE ANSWER GOES BACK TO THE SERVER UNDER THAT ID. Scripts run in the sandbox (sandbox.dart); the toolbox is the person's own list.
// Every call ends with exactly one answer, even when it failed, so the server never waits for the full 45 seconds on a refusal.

// -- DEP-MODULES -- //
import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:io';

// -- MODULES -- //
import '../json.dart';
import 'sandbox.dart';
import 'storage.dart';
import 'toolbox.dart';

// -- TYPES -- //

/// Starts a script. The real one is [runScript]; a test passes a stand-in.
typedef ScriptStarter = ScriptRun Function({
  required String code,
  required Directory scratch,
  String input,
  List<String> photos,
});

ScriptRun _realStarter({
  required String code,
  required Directory scratch,
  String input = '',
  List<String> photos = const <String>[],
}) => runScript(code: code, scratch: scratch, input: input, photos: photos);

/// Posts one answer to the server: the call id, whether it worked, and the result.
typedef DeviceSender = Future<void> Function(
  String callId,
  bool ok,
  Json result,
);

/// The screens the assistant may open, and the path of each. Set by a call, read by the app's router.
const Map<String, String> healthPaths = <String, String>{
  'health': '/health',
  'today': '/health/today',
  'weight': '/health/weight',
  'train': '/health/train',
  'sleep': '/health/sleep',
  'week': '/health/week',
  'meal': '/health/camera?mode=meal',
  'barcode': '/health/camera?mode=barcode',
  'label': '/health/camera?mode=label',
};

/// The path the assistant last asked to open. The app listens and goes there.
final ValueNotifier<String?> healthOpenSignal = ValueNotifier<String?>(null);

class DeviceToolRunner {
  DeviceToolRunner({
    required this.storage,
    required this.toolbox,
    required this.send,
    ScriptStarter? start,
  }) : _start = start ?? _realStarter;

  final ScriptStorage storage;
  final Toolbox toolbox;
  final DeviceSender send;
  final ScriptStarter _start;

  final Map<String, ScriptRun> _active = <String, ScriptRun>{};
  bool _swept = false;

  /// Counts the times Stop was pressed. A call that began before the last Stop does not start its script when it gets to it.
  int _stops = 0;

  /// The same, for Stop pressed in one chat: another chat that is working keeps its scripts (chats work side by side).
  final Map<String?, int> _stopsOfChat = <String?, int>{};

  /// The chat each running call belongs to.
  final Map<String, String?> _chatOfCall = <String, String?>{};

  // -- FUNCTIONS -- //

  /// Whether a call is running now (for the stop button).
  bool get busy => _active.isNotEmpty;

  /// The person pressed Stop: every running script is given up on. The server cancels its waits when the request closes.
  void stopAll() {
    _stops++;
    for (final run in _active.values.toList()) {
      run.stop();
    }
  }

  /// Stop was pressed in one chat: only the scripts that chat started are given up on.
  void stopChat(String? chatId) {
    _stopsOfChat[chatId] = (_stopsOfChat[chatId] ?? 0) + 1;
    for (final e in _active.entries.toList()) {
      if (_chatOfCall[e.key] == chatId) e.value.stop();
    }
  }

  Future<void> _answer(String callId, bool ok, Json result) async {
    try {
      await send(callId, ok, result);
    } on Object {
      // The server gave up waiting or the connection dropped: nothing more to do for this call
    }
  }

  /// Runs one announced call and posts its answer. Never throws. [photos] are the files of the photos of this message, in the assistant's numbering.
  Future<void> handle({
    required String callId,
    required String tool,
    required Json args,
    String? chatId,
    List<String> photos = const <String>[],
    bool tainted = false,
  }) async {
    try {
      switch (tool) {
        case 'script_run':
          await _script(callId, args, chatId, photos, tainted);
        case 'toolbox':
          await _toolbox(callId, args);
        case 'health_open':
          final path = healthPaths[str(args['screen'])];
          if (path == null) {
            await _answer(callId, false, <String, Object?>{
              'error': 'There is no such screen.',
            });
          } else {
            healthOpenSignal.value = path;
            await _answer(callId, true, <String, Object?>{'opened': true});
          }
        default:
          await _answer(callId, false, <String, Object?>{
            'error': 'The phone does not know the tool "$tool".',
          });
      }
    } on ToolboxException catch (e) {
      await _answer(callId, false, <String, Object?>{'error': e.message});
    } on Object {
      await _answer(callId, false, <String, Object?>{
        'error': 'That did not work on the phone.',
      });
    }
  }

  Future<void> _script(
    String callId,
    Json args,
    String? chatId,
    List<String> photos,
    bool tainted,
  ) async {
    var code = args['code'];
    final saved = args['saved'];
    if (saved is String) {
      final entry = await toolbox.read(saved);
      if (entry == null) {
        return _answer(callId, false, <String, Object?>{
          'error': 'There is no script called "$saved" in the toolbox.',
        });
      }
      code = entry.code;
    }
    if (code is! String) {
      return _answer(callId, false, <String, Object?>{
        'error': 'Give code or the name of a saved script.',
      });
    }
    final stops = _stops;
    final chatStops = _stopsOfChat[chatId] ?? 0;
    if (!_swept) {
      _swept = true;
      unawaited(storage.sweep());
    }
    // A script that runs while untrusted text is in the message may write it to the folder: the folder is then untrusted for good, and so is
    // anything a later script prints from it (the server is told with each answer)
    if (tainted) await storage.markUntrusted(chatId);
    final input = args['input'];
    final scratch = await storage.scratchFor(chatId);
    if (stops != _stops || chatStops != (_stopsOfChat[chatId] ?? 0)) {
      return _answer(callId, false, <String, Object?>{
        'error': 'Stopped by the person.',
      });
    }
    final run = _start(
      code: code,
      scratch: scratch,
      input: input is String ? input : '',
      photos: photos,
    );
    _active[callId] = run;
    _chatOfCall[callId] = chatId;
    try {
      final result = await run.result;
      await _answer(
        callId,
        result.ok,
        result.toJson(untrusted: await storage.isUntrusted(chatId)),
      );
    } finally {
      _active.remove(callId);
      _chatOfCall.remove(callId);
    }
  }

  Future<void> _toolbox(String callId, Json args) async {
    final action = args['action'];
    final name = args['name'];
    final code = args['code'];
    switch (action) {
      case 'list':
        final all = await toolbox.list();
        return _answer(callId, true, <String, Object?>{
          'scripts': <Object?>[
            for (final e in all)
              <String, Object?>{'name': e.name, 'chars': e.code.length},
          ],
          'limit': toolboxMaxScripts,
        });
      case 'read':
        final entry = name is String ? await toolbox.read(name) : null;
        if (entry == null) {
          return _answer(callId, false, <String, Object?>{
            'error': 'There is no script called "$name" in the toolbox.',
          });
        }
        return _answer(callId, true, <String, Object?>{
          'name': entry.name,
          'code': entry.code,
        });
      case 'save':
        if (name is! String || code is! String) {
          return _answer(callId, false, <String, Object?>{
            'error': 'save needs a name and the code.',
          });
        }
        final entry = await toolbox.save(name, code);
        return _answer(callId, true, <String, Object?>{
          'saved': entry.name,
          'count': (await toolbox.list()).length,
        });
      case 'delete':
        final gone = name is String && await toolbox.delete(name);
        return _answer(callId, gone, <String, Object?>{
          if (gone)
            'deleted': name
          else
            'error': 'There is no script called "$name".',
        });
      default:
        return _answer(callId, false, <String, Object?>{
          'error': 'action is list, read, save or delete.',
        });
    }
  }
}
