// THE TOOLBOX (BTL-20261031-1334): THE SCRIPTS THE PERSON KEEPS ON THIS PHONE, SAVED BY BOTLER ONLY WHEN THEY ASK OR AGREE, VISIBLE IN SETTINGS, RUN BY NAME.
// Up to 30 scripts of up to 20000 characters. One small JSON file; a damaged file reads as empty and is replaced by the next save.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

// -- MODULES -- //
import 'storage.dart';

// -- CONSTANTS -- //

const int toolboxMaxScripts = 30;
const int toolboxMaxCodeChars = 20000;
const int toolboxMaxNameChars = 60;

// -- TYPES -- //

class ToolboxEntry {
  const ToolboxEntry({
    required this.name,
    required this.code,
    required this.savedAt,
  });

  final String name;
  final String code;
  final DateTime savedAt;
}

/// A refusal with words the assistant (or the person) can act on.
class ToolboxException implements Exception {
  const ToolboxException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Toolbox {
  Toolbox(this._storage);

  final ScriptStorage _storage;

  // -- FUNCTIONS -- //

  Future<List<ToolboxEntry>> _load() async {
    try {
      final file = await _storage.toolboxFile();
      if (!file.existsSync()) return <ToolboxEntry>[];
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! List<Object?>) return <ToolboxEntry>[];
      final out = <ToolboxEntry>[];
      for (final item in raw) {
        if (item is! Map<String, Object?>) continue;
        final name = item['name'];
        final code = item['code'];
        final at = item['savedAt'];
        if (name is String && code is String) {
          out.add(
            ToolboxEntry(
              name: name,
              code: code,
              savedAt:
                  (at is String ? DateTime.tryParse(at) : null) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
        }
      }
      return out;
    } on Object {
      return <ToolboxEntry>[];
    }
  }

  Future<void> _store(List<ToolboxEntry> all) async {
    final file = await _storage.toolboxFile();
    // Written beside the file and moved over it, so a kill in the middle leaves the old list, never half of a new one
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(
      jsonEncode(<Object?>[
        for (final e in all)
          <String, Object?>{
            'name': e.name,
            'code': e.code,
            'savedAt': e.savedAt.toUtc().toIso8601String(),
          },
      ]),
      flush: true,
    );
    temp.renameSync(file.path);
  }

  /// Changes run one after another, so two at once (the screen and the assistant) cannot overwrite each other.
  Future<void> _turn = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() work) {
    final done = _turn.then((_) => work());
    _turn = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  String _cleanName(String raw) {
    final name = raw.trim();
    if (name.isEmpty || name.length > toolboxMaxNameChars) {
      throw const ToolboxException('A script name has 1 to 60 characters.');
    }
    if (name.codeUnits.any((c) => c < 32)) {
      throw const ToolboxException('A script name is plain text on one line.');
    }
    return name;
  }

  bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  /// The scripts by name.
  Future<List<ToolboxEntry>> list() async =>
      (await _load())
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<ToolboxEntry?> read(String name) async {
    for (final e in await _load()) {
      if (_same(e.name, name.trim())) return e;
    }
    return null;
  }

  /// Saves under [name]; the same name (any case) replaces the older one.
  Future<ToolboxEntry> save(String name, String code, {DateTime? now}) =>
      _exclusive(() => _save(name, code, now));

  Future<ToolboxEntry> _save(String name, String code, DateTime? now) async {
    final clean = _cleanName(name);
    if (code.trim().isEmpty || code.length > toolboxMaxCodeChars) {
      throw const ToolboxException('A script has 1 to 20000 characters.');
    }
    final all = await _load();
    final at = all.indexWhere((e) => _same(e.name, clean));
    if (at < 0 && all.length >= toolboxMaxScripts) {
      throw const ToolboxException(
        'The toolbox is full (30 scripts). Delete one first.',
      );
    }
    final entry = ToolboxEntry(
      name: clean,
      code: code,
      savedAt: now ?? DateTime.now(),
    );
    if (at < 0) {
      all.add(entry);
    } else {
      all[at] = entry;
    }
    await _store(all);
    return entry;
  }

  /// True when a script was removed.
  Future<bool> delete(String name) => _exclusive(() => _delete(name));

  Future<bool> _delete(String name) async {
    final all = await _load();
    final before = all.length;
    all.removeWhere((e) => _same(e.name, name.trim()));
    if (all.length == before) return false;
    await _store(all);
    return true;
  }
}
