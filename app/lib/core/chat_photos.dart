// THE PHOTOS OF SENT MESSAGES, KEPT ON THE PHONE ONLY SO THEY CAN BE SHOWN AGAIN: COPIED INTO THE APP'S PRIVATE FOLDER, LISTED BY TURN, CAPPED.
// The server never gets a picture (see device.dart): it keeps the words read from it. These copies are for the person's own eyes, they are
// removed when signing out or after a data reset, and the oldest go first once there are more than [maxStoredPhotos].

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- CONSTANTS -- //

/// Photos kept on the phone, all messages together.
const int maxStoredPhotos = 150;

/// Where the index lives in the preferences: this prefix, then the owner.
const String photoIndexPrefix = 'chatphotos.v1.';

const String _folder = 'chat_photos';
const String _staging = 'staging';

/// A staged copy nobody promoted within this long is a leftover of a send that never started.
const Duration _stagingLife = Duration(hours: 1);

// -- TYPES -- //

/// Which file names belong to which turn, oldest turn first. Pure data: no files, no platform.
class PhotoIndex {
  PhotoIndex([Map<String, List<String>>? turns])
    : _turns = <String, List<String>>{...?turns};

  /// Reads the saved JSON; anything unreadable is an empty index.
  factory PhotoIndex.decode(String? raw) {
    if (raw == null) return PhotoIndex();
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return PhotoIndex();
      return PhotoIndex(<String, List<String>>{
        for (final e in data.entries)
          if (e.value is List<dynamic>)
            e.key: <String>[
              for (final n in e.value as List<dynamic>)
                if (n is String) n,
            ],
      });
    } on FormatException {
      return PhotoIndex();
    }
  }

  final Map<String, List<String>> _turns;

  String encode() => jsonEncode(_turns);

  /// The file names of [turnId], empty when it had none.
  List<String> of(String turnId) => _turns[turnId] ?? const <String>[];

  /// Every file name in the index.
  Set<String> get names => <String>{for (final l in _turns.values) ...l};

  int get count => _turns.values.fold<int>(0, (a, l) => a + l.length);

  /// Records the files of a turn. A repeat for the same turn (a retried send) replaces the earlier entry instead of adding to it.
  void put(String turnId, List<String> files) {
    _turns.remove(turnId);
    if (files.isNotEmpty) _turns[turnId] = List<String>.of(files);
  }

  /// Drops the oldest turns until at most [limit] photos remain; returns the file names that were dropped.
  List<String> evict(int limit) {
    final gone = <String>[];
    while (count > limit && _turns.isNotEmpty) {
      gone.addAll(_turns.remove(_turns.keys.first) ?? const <String>[]);
    }
    return gone;
  }

  /// Forgets file names that no longer exist; returns whether anything changed.
  bool keepOnly(bool Function(String name) exists) {
    var changed = false;
    for (final entry in _turns.entries.toList()) {
      final key = entry.key;
      final kept = <String>[
        for (final n in entry.value)
          if (exists(n)) n,
      ];
      if (kept.length != entry.value.length) changed = true;
      if (kept.isEmpty) {
        _turns.remove(key);
      } else {
        _turns[key] = kept;
      }
    }
    return changed;
  }
}

/// The photo folder and its index. [baseDir] is the app's private documents folder; tests give a temporary one.
class ChatPhotoStore {
  ChatPhotoStore({
    required this.prefs,
    required this.owner,
    Future<Directory> Function()? baseDir,
  }) : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final SharedPreferences prefs;

  /// Whose photos these are (the signed-in email); another owner's index is never read.
  final String owner;
  final Future<Directory> Function() _baseDir;

  Directory? _root;
  PhotoIndex? _index;
  Future<void>? _opening;
  int _serial = 0;

  /// Counts wipes, so work that started before one can tell and drop its result.
  int _wipes = 0;

  String get _key => '$photoIndexPrefix$owner';

  Future<Directory> _folderDir([String? sub]) async {
    // One folder for each person, so one person's sweep can never touch another's photos
    final base = _root ??= Directory(
      '${(await _baseDir()).path}${Platform.pathSeparator}$_folder'
      '${Platform.pathSeparator}${base64Url.encode(utf8.encode(owner)).replaceAll('=', '')}',
    );
    final dir = sub == null
        ? base
        : Directory('${base.path}${Platform.pathSeparator}$sub');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Opens the folder, forgets what is gone and sweeps files nothing points at. Call before the first lookup.
  Future<void> ready() {
    // One opening at a time: two callers must not each build an index and sweep the other's new files
    final opening = _opening ??= _open();
    return opening.catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  Future<void> _open() async {
    final index = PhotoIndex.decode(prefs.getString(_key));
    final dir = await _folderDir();
    final sep = Platform.pathSeparator;
    if (index.keepOnly((n) => File('${dir.path}$sep$n').existsSync())) {
      await prefs.setString(_key, index.encode());
    }
    _index = index;
    // Files in the folder that no turn names, and staged copies from a send that never reached the server
    final named = index.names;
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (f is File && !named.contains(name)) {
        await _quietDelete(f);
      } else if (f is Directory && name == _staging) {
        for (final s in f.listSync()) {
          if (s is File &&
              DateTime.now().difference(s.statSync().modified) > _stagingLife) {
            await _quietDelete(s);
          }
        }
      }
    }
  }

  /// The files of a turn as full paths, in the order they were sent. Needs [ready] first.
  List<String> photosOf(String turnId) {
    final index = _index;
    final root = _root;
    if (index == null || root == null) return const <String>[];
    return <String>[
      for (final n in index.of(turnId))
        '${root.path}${Platform.pathSeparator}$n',
    ];
  }

  /// Copies a picked photo into the staging folder (the picker's own copy can be cleared by the phone at any time).
  /// Null when the copy failed: the message then goes without a thumbnail.
  Future<String?> stage(String source) async {
    try {
      final dir = await _folderDir(_staging);
      final dot = source.lastIndexOf('.');
      final ext =
          dot > source.lastIndexOf(Platform.pathSeparator) &&
              source.length - dot <= 5
          ? source.substring(dot)
          : '.jpg';
      final name = '${DateTime.now().microsecondsSinceEpoch}_${_serial++}$ext';
      final copy = await File(source)
          .copy('${dir.path}${Platform.pathSeparator}$name');
      return copy.path;
    } on Object {
      return null;
    }
  }

  /// Moves staged copies into the folder and files them under [turnId]. Returns the final paths; the oldest photos beyond the cap are deleted.
  Future<List<String>> promote(String turnId, List<String> staged) async {
    if (staged.isEmpty) return const <String>[];
    final wipes = _wipes;
    await ready();
    final index = _index;
    // Wiped while it was opening: nothing is kept
    if (wipes != _wipes || index == null) {
      await discard(staged);
      return const <String>[];
    }
    final dir = await _folderDir();
    final names = <String>[];
    for (final path in staged) {
      try {
        final name = path.split(Platform.pathSeparator).last;
        await File(path).rename('${dir.path}${Platform.pathSeparator}$name');
        names.add(name);
      } on Object {
        // One file that cannot move is left out
      }
    }
    // Signed out or reset while the files were moving: nothing is kept, and no index is written back
    if (wipes != _wipes) {
      await discard(<String>[
        for (final n in names) '${dir.path}${Platform.pathSeparator}$n',
      ]);
      return const <String>[];
    }
    // A retried send files the same turn again: its earlier files are replaced
    final before = index.of(turnId);
    index.put(turnId, names);
    final stale = before.where((n) => !names.contains(n)).toList();
    for (final gone in <String>[...stale, ...index.evict(maxStoredPhotos)]) {
      await _quietDelete(File('${dir.path}${Platform.pathSeparator}$gone'));
    }
    try {
      await prefs.setString(_key, index.encode());
    } on Object {
      // The files stay; they are swept at the next start
    }
    return photosOf(turnId);
  }

  /// Deletes staged copies that will not be filed (the send never reached the server, or was stopped).
  Future<void> discard(List<String> staged) async {
    for (final path in staged) {
      await _quietDelete(File(path));
    }
  }

  /// Removes every photo and every index, whoever they belong to. For signing out and after a data reset.
  Future<void> wipe() async {
    _wipes++;
    _index = null;
    _opening = null;
    for (final k in prefs.getKeys().where(
      (k) => k.startsWith(photoIndexPrefix),
    )) {
      await prefs.remove(k);
    }
    try {
      final dir = Directory(
        '${(await _baseDir()).path}${Platform.pathSeparator}$_folder',
      );
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Nothing more can be done for a folder that will not go
    }
    _root = null;
  }

  Future<void> _quietDelete(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } on Object {
      // A file that is in use goes at the next sweep
    }
  }
}
