// WHERE SCRIPTS KEEP THEIR FILES (BTL-20261031-1334): ONE FOLDER FOR EACH PERSON, WITH A SCRATCH FOLDER FOR EACH CHAT AND THE TOOLBOX OF SAVED SCRIPTS.
// Another person signing in never finds these, and signing out removes them. A scratch folder lives as long as its chat; chats are never deleted here,
// so a folder that has not been used for 30 days is swept when the sandbox is next used (a safety net for the phone's storage).

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// -- MODULES -- //
import 'scratch.dart';

// -- CONSTANTS -- //

const String _folder = 'script_data';
const String _scratchFolder = 'scratch';
const String _toolboxFile = 'toolbox.json';

/// A scratch folder not touched for this long is removed.
const Duration scratchIdleLimit = Duration(days: 30);

final RegExp _chatKey = RegExp(r'^[A-Za-z0-9\-]{1,64}$');

// -- TYPES -- //

class ScriptStorage {
  ScriptStorage({required this.owner, Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationSupportDirectory;

  /// Whose files these are (the signed-in email).
  final String owner;
  final Future<Directory> Function() _baseDir;

  Directory? _root;

  // -- FUNCTIONS -- //

  Future<Directory> root() async {
    final cached = _root;
    if (cached != null) return cached;
    final base = await _baseDir();
    final who = base64Url.encode(utf8.encode(owner)).replaceAll('=', '');
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_folder${Platform.pathSeparator}$who',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _root = dir;
  }

  /// The scratch folder of a chat. A chat id that is not plain letters, digits and dashes gets the shared "new" folder, never a path of its own.
  Future<Directory> scratchFor(String? chatId) async {
    final key = chatId != null && _chatKey.hasMatch(chatId) ? chatId : 'new';
    final dir = Directory(
      '${(await root()).path}${Platform.pathSeparator}$_scratchFolder${Platform.pathSeparator}$key',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  String _key(String? chatId) =>
      chatId != null && _chatKey.hasMatch(chatId) ? chatId : 'new';

  Future<File> _marker(String? chatId) async => File(
    '${(await root()).path}${Platform.pathSeparator}$_scratchFolder${Platform.pathSeparator}${_key(chatId)}.untrusted',
  );

  /// Notes that this chat's scratch folder holds something written while untrusted text (a web page, a photo's text) was in a message.
  /// Kept beside the folder, never inside it where a script could see or remove it.
  Future<void> markUntrusted(String? chatId) async {
    final f = await _marker(chatId);
    if (!f.existsSync()) {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('1');
    }
  }

  Future<bool> isUntrusted(String? chatId) async =>
      (await _marker(chatId)).existsSync();

  Future<File> toolboxFile() async =>
      File('${(await root()).path}${Platform.pathSeparator}$_toolboxFile');

  /// When a scratch folder last changed: its newest file, or the folder itself when it is empty.
  DateTime _lastUsed(Directory dir) {
    var latest = dir.statSync().modified;
    for (final f in dir.listSync(followLinks: false)) {
      final at = f.statSync().modified;
      if (at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  /// Removes the scratch folders nobody used for [scratchIdleLimit]. Never throws.
  Future<void> sweep({DateTime? now}) async {
    try {
      final base = Directory(
        '${(await root()).path}${Platform.pathSeparator}$_scratchFolder',
      );
      if (!base.existsSync()) return;
      final cutoff = (now ?? DateTime.now()).subtract(scratchIdleLimit);
      for (final e in base.listSync(followLinks: false)) {
        if (e is Directory && _lastUsed(e).isBefore(cutoff)) {
          ScratchFolder(e).clear();
          final marker = File('${e.path}.untrusted');
          if (marker.existsSync()) marker.deleteSync();
        }
      }
    } on Object {
      // A sweep that fails leaves the folders for the next time
    }
  }

  /// Everything of this person's: the scratch folders and the toolbox.
  Future<void> wipe() async {
    try {
      final dir = await root();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      _root = null;
    } on Object {
      // Signing out never waits on this
    }
  }
}
