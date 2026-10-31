// WHAT THE PERSON CAN DO WITH A FILE A SCRIPT MADE (BTL-20261031-1334): SAVE IT TO THE PHONE (THE SYSTEM'S "SAVE AS" SCREEN, THEIR CHOICE OF FOLDER) OR SHARE / OPEN IT WITH ANOTHER APP.
// The seam is an interface so a test can stand in for the system screens. Nothing here reads a file's content or sends it anywhere by itself: the person taps, and the system asks them.

// -- DEP-MODULES -- //
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:share_plus/share_plus.dart';

// -- TYPES -- //

abstract class FileActions {
  /// Asks the system where to save a copy and writes it there. True when saved, false when the person cancelled or it failed.
  Future<bool> save(String path, String name);

  /// Opens the system share sheet for the file (it can be opened, sent, or saved to a drive from there).
  Future<void> share(String path, String name);
}

class PlatformFileActions implements FileActions {
  const PlatformFileActions();

  @override
  Future<bool> save(String path, String name) async {
    try {
      final saved = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(sourceFilePath: path, fileName: name),
      );
      return saved != null;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> share(String path, String name) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, name: name, mimeType: mimeOf(name))],
      ),
    );
  }
}

// -- FUNCTIONS -- //

/// The kind of a file by its name's ending, for the share sheet and for choosing its icon.
String mimeOf(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'pdf' => 'application/pdf',
    'csv' => 'text/csv',
    'txt' || 'md' || 'log' => 'text/plain',
    'json' => 'application/json',
    'html' || 'htm' => 'text/html',
    'zip' => 'application/zip',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => 'application/octet-stream',
  };
}

/// Pictures the chat can show in place.
bool isPictureName(String name) => mimeOf(name).startsWith('image/');
