// THE SCRATCH FOLDER OF ONE CHAT (BTL-20261031-1334): THE ONLY PLACE A SCRIPT CAN READ OR WRITE FILES. FLAT NAMES (NO FOLDERS, NO DOTS AT THE START), A CAP ON THE WHOLE FOLDER
// AND ON EACH FILE, AND NOTHING OUTSIDE IT IS EVER REACHABLE: a name is checked as text first, so "../x" or "a/b" never touches the disk.

// -- DEP-MODULES -- //
import 'dart:io';
import 'dart:typed_data';

// -- CONSTANTS -- //

/// All the files of one chat together.
const int scratchMaxTotalBytes = 50 * 1024 * 1024;

/// One file.
const int scratchMaxFileBytes = 25 * 1024 * 1024;

/// How many files one chat may keep.
const int scratchMaxFiles = 200;

/// The longest file name.
const int scratchMaxNameLength = 64;

final RegExp _flatName = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.\- ]*$');

// -- TYPES -- //

/// A refusal a script can read: it is thrown as text inside the sandbox.
class ScratchException implements Exception {
  const ScratchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScratchFolder {
  ScratchFolder(this.dir);

  final Directory dir;

  // -- FUNCTIONS -- //

  /// The name as text, or throws. Only letters, digits, space, dot, dash and underscore; no slash, no leading dot, at most 64 characters.
  String check(String name) {
    if (name.isEmpty || name.length > scratchMaxNameLength) {
      throw const ScratchException(
        'A file name has 1 to 64 characters, with no folders.',
      );
    }
    if (!_flatName.hasMatch(name) || name.contains('..')) {
      throw const ScratchException(
        'A file name may only use letters, digits, space, dot, dash and underscore, with no folders and no dot at the start.',
      );
    }
    return name;
  }

  File _file(String name) =>
      File('${dir.path}${Platform.pathSeparator}${check(name)}');

  List<File> _files() {
    if (!dir.existsSync()) return const <File>[];
    return dir.listSync(followLinks: false).whereType<File>().toList();
  }

  /// The files with their sizes, by name.
  List<({String name, int size})> list() {
    final out = <({String name, int size})>[
      for (final f in _files())
        (
          name: f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last,
          size: f.lengthSync(),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  int totalBytes() => _files().fold<int>(0, (n, f) => n + f.lengthSync());

  bool exists(String name) => _file(name).existsSync();

  Uint8List read(String name) {
    final f = _file(name);
    if (!f.existsSync()) throw ScratchException('There is no file "$name".');
    return f.readAsBytesSync();
  }

  /// Writes (or replaces) a file, within the caps.
  void write(String name, List<int> bytes) {
    final f = _file(name);
    if (bytes.length > scratchMaxFileBytes) {
      throw const ScratchException('That file is larger than 25 MB.');
    }
    final existing = f.existsSync() ? f.lengthSync() : 0;
    if (!f.existsSync() && _files().length >= scratchMaxFiles) {
      throw const ScratchException('This chat already has 200 files.');
    }
    if (totalBytes() - existing + bytes.length > scratchMaxTotalBytes) {
      throw const ScratchException(
        'The files of this chat would be larger than 50 MB together.',
      );
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    f.writeAsBytesSync(bytes, flush: true);
  }

  void remove(String name) {
    final f = _file(name);
    if (f.existsSync()) f.deleteSync();
  }

  /// Deletes the whole folder.
  void clear() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
