// RUNNING A MODEL-WRITTEN SCRIPT (BTL-20261031-1334): QUICKJS IN ITS OWN ISOLATE, WITH A CLOCK AND A MEMORY LIMIT, AND NOTHING BUT THE HOST OPERATIONS IN REACH.
// The engine starts with no network, no files, no timers' fetch and no phone access. Its only way out is the list of operations in host.dart, which reach
// the chat's scratch folder and nothing else. It runs off the main isolate, so the screen stays alive. "Stop" gives up waiting at once; the worker is cut
// by its own clock (30 seconds at most) and its result is thrown away.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_qjs_next/flutter_qjs.dart';

// -- MODULES -- //
import 'host.dart';
import 'scratch.dart';

// -- CONSTANTS -- //

const int scriptTimeoutMs = 30000;
const int scriptMemoryBytes = 128 * 1024 * 1024;
const int scriptOutputChars = 6000;
const int scriptMaxCodeChars = 20000;
const int scriptMaxInputChars = 4000;

/// Workers still alive (a stopped script keeps its worker until its clock cuts it). Past this, a new run waits for one to end.
const int _maxWorkers = 2;

/// The engine's C stack, kept under the thread's own so a deep script ends in an error, not a crash.
const int _stackBytes = 256 * 1024;

/// The most promise jobs one script may run after its main code.
const int _maxJobs = 1000;

/// What the script sees before it runs: print and console, fs, image, csv, base64. The bridge function is taken into a closure and removed
/// from the global scope, so a script cannot call an operation that is not in these objects.
const String _prelude = r'''
(function (g) {
  var send = g.sendMessage;
  function call(op, arg) {
    var r = JSON.parse(send(op, JSON.stringify(arg === undefined ? {} : arg)));
    if (r && r.e) throw new Error(r.e);
    return r ? r.v : undefined;
  }
  function text(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var x = args[i];
      if (typeof x === 'string') parts.push(x);
      else { try { parts.push(JSON.stringify(x) === undefined ? String(x) : JSON.stringify(x)); } catch (e) { parts.push(String(x)); } }
    }
    return parts.join(' ');
  }
  function print() { call('print', { t: text(arguments) }); }
  function merge(a, b) { var o = {}; var k; for (k in a) o[k] = a[k]; for (k in (b || {})) o[k] = b[k]; return o; }
  g.print = print;
  g.console = Object.freeze({ log: print, info: print, warn: print, error: print, debug: print });
  g.fs = Object.freeze({
    write: function (name, t) { return call('fs.write', { name: name, text: String(t) }); },
    read: function (name) { return call('fs.read', { name: name }); },
    list: function () { return call('fs.list', {}); },
    remove: function (name) { return call('fs.remove', { name: name }); },
    writeBase64: function (name, b64) { return call('fs.writeBase64', { name: name, b64: String(b64) }); },
    readBase64: function (name) { return call('fs.readBase64', { name: name }); },
    photo: function (n, name) { return call('fs.photo', { n: n, name: name }); }
  });
  g.image = Object.freeze({
    info: function (src) { return call('image.info', { src: src }); },
    resize: function (src, dst, o) { return call('image.resize', merge({ src: src, dst: dst }, o)); },
    crop: function (src, dst, o) { return call('image.crop', merge({ src: src, dst: dst }, o)); },
    rotate: function (src, dst, degrees) { return call('image.rotate', { src: src, dst: dst, degrees: degrees }); },
    grayscale: function (src, dst) { return call('image.grayscale', { src: src, dst: dst }); }
  });
  g.show = function (name) { return call('show', { name: name }); };
  g.xlsx = Object.freeze({
    write: function (name, rows, o) { return call('xlsx.write', merge({ name: name, rows: rows }, o)); }
  });
  g.pdf = Object.freeze({
    write: function (name, text, o) { return call('pdf.write', merge({ name: name, text: String(text) }, o)); }
  });
  g.base64 = Object.freeze({
    encode: function (t) { return call('base64.encode', { t: String(t) }); },
    decode: function (b) { return call('base64.decode', { b: String(b) }); }
  });
  g.csv = Object.freeze({
    parse: function (t, delim) {
      var d = delim || ','; var rows = []; var row = []; var f = ''; var q = false; var s = String(t);
      for (var i = 0; i < s.length; i++) {
        var c = s[i];
        if (q) {
          if (c === '"') { if (s[i + 1] === '"') { f += '"'; i++; } else q = false; }
          else f += c;
        } else if (c === '"') q = true;
        else if (c === d) { row.push(f); f = ''; }
        else if (c === '\n' || c === '\r') {
          if (c === '\r' && s[i + 1] === '\n') i++;
          row.push(f); f = ''; rows.push(row); row = [];
        } else f += c;
      }
      if (f !== '' || row.length) { row.push(f); rows.push(row); }
      return rows;
    },
    stringify: function (rows, delim) {
      var d = delim || ',';
      return rows.map(function (r) {
        return r.map(function (v) {
          var x = v === null || v === undefined ? '' : String(v);
          return x.indexOf(d) >= 0 || x.indexOf('"') >= 0 || x.indexOf('\n') >= 0 || x.indexOf('\r') >= 0 ? '"' + x.replace(/"/g, '""') + '"' : x;
        }).join(d);
      }).join('\n');
    }
  });
  delete g.sendMessage;
  delete g.DART_TO_QUICKJS_CHANNEL_sendMessage;
})(globalThis);
''';

// -- TYPES -- //

/// How a run ended. [output] is what the script printed; [error] is set when it did not finish.
class ScriptResult {
  const ScriptResult({
    required this.ok,
    required this.output,
    this.error,
    this.files = const <({String name, int size})>[],
    this.ms = 0,
    this.leaked = false,
    this.shown = const <String>[],
  });

  /// The files the script asked to show to the person (they exist in the folder, with their sizes in [files]).
  final List<String> shown;

  /// The engine could not be freed (see [_run]); counted so a phone is not filled with them.
  final bool leaked;

  ScriptResult withLeak() => ScriptResult(
    ok: ok,
    output: output,
    error: error,
    files: files,
    ms: ms,
    leaked: true,
    shown: shown,
  );

  final bool ok;
  final String output;
  final String? error;
  final List<({String name, int size})> files;
  final int ms;

  /// [untrusted] marks an answer whose folder holds text from outside; the server then treats the answer as untrusted.
  Map<String, Object?> toJson({bool untrusted = false}) => <String, Object?>{
    'ok': ok,
    if (untrusted) 'untrusted': true,
    'output': output,
    'error': ?error,
    'files': <Object?>[
      for (final f in files) <String, Object?>{'name': f.name, 'size': f.size},
    ],
    'ms': ms,
    if (shown.isNotEmpty)
      'shown': <Object?>[
        for (final n in shown)
          <String, Object?>{
            'name': n,
            'size':
                files
                    .where((f) => f.name == n)
                    .map((f) => f.size)
                    .firstOrNull ??
                0,
          },
      ],
  };
}

/// A run in progress: its answer, and a way to stop waiting for it.
class ScriptRun {
  ScriptRun._(this._done);

  /// A run that is already over (a refusal before the engine starts, and the stand-in of a test).
  factory ScriptRun.finished(ScriptResult result) =>
      ScriptRun._(Completer<ScriptResult>()..complete(result));

  final Completer<ScriptResult> _done;

  Future<ScriptResult> get result => _done.future;

  /// Gives up waiting now. The worker ends on its own clock; its result is dropped.
  void stop() {
    if (!_done.isCompleted) {
      _done.complete(
        const ScriptResult(
          ok: false,
          output: '',
          error: 'Stopped by the person.',
        ),
      );
    }
  }
}

/// Everything a worker needs, as plain values that can cross to another isolate.
class _Job {
  const _Job({
    required this.code,
    required this.input,
    required this.scratchPath,
    required this.photos,
    required this.timeoutMs,
    required this.memoryBytes,
  });

  final String code;
  final String input;
  final String scratchPath;
  final List<String> photos;
  final int timeoutMs;
  final int memoryBytes;
}

// -- FUNCTIONS -- //

int _workers = 0;

/// Engines that could not be freed since the app started. Past [_maxLeaks] no more scripts run until the app is restarted.
int _leaks = 0;
const int _maxLeaks = 3;

/// Starts a script. [scratch] is the chat's folder and [photos] the files of the photos of the message, in the assistant's numbering.
/// The limits are parameters only so a test can make them small.
ScriptRun runScript({
  required String code,
  required Directory scratch,
  String input = '',
  List<String> photos = const <String>[],
  int timeoutMs = scriptTimeoutMs,
  int memoryBytes = scriptMemoryBytes,
}) {
  final done = Completer<ScriptResult>();
  final run = ScriptRun._(done);
  if (code.trim().isEmpty || code.length > scriptMaxCodeChars) {
    done.complete(
      const ScriptResult(
        ok: false,
        output: '',
        error: 'A script has 1 to 20000 characters.',
      ),
    );
    return run;
  }
  if (_leaks >= _maxLeaks) {
    done.complete(
      const ScriptResult(
        ok: false,
        output: '',
        error: 'Scripts are paused until the app is restarted: earlier scripts left work running that could not be stopped.',
      ),
    );
    return run;
  }
  if (_workers >= _maxWorkers) {
    done.complete(
      const ScriptResult(
        ok: false,
        output: '',
        error: 'Earlier scripts are still winding down. Try again in a few seconds.',
      ),
    );
    return run;
  }
  _workers++;
  final job = _Job(
    code: code,
    input: input.length > scriptMaxInputChars
        ? input.substring(0, scriptMaxInputChars)
        : input,
    scratchPath: scratch.path,
    photos: photos,
    timeoutMs: timeoutMs,
    memoryBytes: memoryBytes,
  );
  // The worker's own failures (a crash of the engine) are an answer too, never an unhandled error
  _spawn(job).then<void>(
    (r) {
      _workers--;
      if (r.leaked) _leaks++;
      if (!done.isCompleted) done.complete(r);
    },
    onError: (Object e) {
      _workers--;
      debugPrint('script worker failed: ${e.runtimeType}');
      if (!done.isCompleted) {
        done.complete(
          const ScriptResult(
            ok: false,
            output: '',
            error: 'The script engine stopped unexpectedly.',
          ),
        );
      }
    },
  );
  return run;
}

/// Makes a message from the engine easier to act on: its clock and memory stops say what happened and what the limit was.
String friendlyError(String raw, {int timeoutMs = scriptTimeoutMs}) {
  final text = raw.trim();
  final lower = text.toLowerCase();
  if (lower.contains('interrupted')) {
    return 'Stopped: the script ran longer than ${timeoutMs ~/ 1000} seconds.';
  }
  if (lower.contains('out of memory')) {
    return 'Stopped: the script used more memory than allowed (128 MB).';
  }
  if (lower.contains('stack overflow')) {
    return 'Stopped: the script nested too deeply (stack overflow).';
  }
  return text.length > 600 ? text.substring(0, 600) : text;
}

/// Starts the worker. A separate function so the closure it sends holds the job only, never the completer of the run.
Future<ScriptResult> _spawn(_Job job) => Isolate.run(() => _work(job));

/// The worker: builds the engine, adds the host, runs the script, and returns what it printed. Always returns; never throws.
ScriptResult _work(_Job job) {
  final left = _Left();
  final result = _run(job, left);
  return left.engineKept ? result.withLeak() : result;
}

/// Set by the worker when it could not free its engine.
class _Left {
  bool engineKept = false;
}

ScriptResult _run(_Job job, _Left left) {
  final clock = Stopwatch()..start();
  final scratch = ScratchFolder(Directory(job.scratchPath));
  final host = ScriptHost(
    scratch: scratch,
    photos: job.photos,
    outputChars: scriptOutputChars,
  );
  JavascriptRuntime? js;
  try {
    js = getJavascriptRuntime(
      timeout: job.timeoutMs,
      memoryLimit: job.memoryBytes,
      stackSize: _stackBytes,
    );
    // The engine would run every queued promise job at once after each evaluate, each with a fresh clock; they are run below against one clock
    final engine = js;
    if (engine is QuickJsRuntime2) engine.autoExecutePendingJobs = false;
    for (final op in ScriptHost.operations) {
      js.onMessage(op, (Object? args) => host.call(op, args));
    }
    final boot = js.evaluate(_prelude);
    if (boot.isError) {
      return ScriptResult(
        ok: false,
        output: '',
        error: 'The script engine could not start.',
        ms: clock.elapsedMilliseconds,
      );
    }
    js.evaluate('globalThis.INPUT = ${jsonEncode(job.input)};');
    final r = js.evaluate(job.code, sourceUrl: 'script.js');
    // Promise jobs run one at a time against the whole clock: the engine gives every job its own clock, so a chain of jobs would never end
    var late = false;
    if (!r.isError) {
      for (var n = 0; n < _maxJobs; n++) {
        if (clock.elapsedMilliseconds >= job.timeoutMs) {
          late = true;
          break;
        }
        if (js.executePendingJob() <= 0) break;
      }
    }
    final over = late || clock.elapsedMilliseconds > job.timeoutMs * 2;
    return ScriptResult(
      ok: !r.isError && !over,
      output: host.output,
      error: r.isError
          ? friendlyError(r.stringResult, timeoutMs: job.timeoutMs)
          : over
          ? friendlyError('interrupted', timeoutMs: job.timeoutMs)
          : null,
      files: scratch.list(),
      ms: clock.elapsedMilliseconds,
      shown: host.shown,
    );
  } on Object catch (e) {
    return ScriptResult(
      ok: false,
      output: host.output,
      error: friendlyError('$e', timeoutMs: job.timeoutMs),
      files: scratch.list(),
      ms: clock.elapsedMilliseconds,
      shown: host.shown,
    );
  } finally {
    // Freeing an engine runs every promise job still queued, with no limit: a script that keeps queueing them would hang here for good.
    // An engine with jobs left is therefore not freed (its memory stays until the app restarts), and the main side counts it
    final engine = js;
    if (engine is QuickJsRuntime2 && engine.hasPendingJobs) {
      left.engineKept = true;
    } else {
      engine?.dispose();
    }
  }
}
