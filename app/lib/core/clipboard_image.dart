// A PICTURE FROM THE CLIPBOARD OR THE KEYBOARD, MADE INTO A FILE THE PHOTO FLOW CAN TAKE LIKE ANY PICKED PHOTO.
// The file lives in the cache "paste" folder only until the chat has copied it into its own staging folder; then it is deleted. The
// folder is also swept when the chat opens, so a picture pasted and never sent does not stay behind.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// -- CONSTANTS -- //

/// A picture bigger than this is left out.
const int maxPastedBytes = 12 * 1024 * 1024;

/// The picture types the photo reader and the server can take; anything else (a sticker pack, a video) is not pasted.
const List<String> pastableMimeTypes = <String>[
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
];

const MethodChannel _channel = MethodChannel('com.arbenger.botler/clipboard');

int _serial = 0;

// -- FUNCTIONS -- //

/// Whether the clipboard holds a picture right now. False when it cannot be read.
Future<bool> clipboardHasImage() async {
  try {
    return await _channel.invokeMethod<bool>('hasImage') ?? false;
  } on Object {
    return false;
  }
}

/// Copies the picture on the clipboard to a file and returns its path; null when there is none, it is too big, or it cannot be read.
Future<String?> clipboardImageFile() async {
  try {
    return await _channel.invokeMethod<String>('saveImage', <String, Object>{
      'maxBytes': maxPastedBytes,
    });
  } on Object {
    return null;
  }
}

/// Writes [bytes] (a picture the keyboard inserted) to a new cache file and returns its path. Null for nothing or a picture past
/// [maxPastedBytes].
Future<String?> imageBytesToFile(Uint8List bytes, {Directory? folder}) async {
  if (bytes.isEmpty || bytes.length > maxPastedBytes) return null;
  try {
    final base =
        folder ?? Directory('${(await getTemporaryDirectory()).path}/paste');
    await base.create(recursive: true);
    final name = 'paste_${DateTime.now().microsecondsSinceEpoch}_${_serial++}';
    final file = File(
      '${base.path}${Platform.pathSeparator}$name${_extension(bytes)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}

/// The file ending the bytes call for, from their first bytes (PNG, GIF, WebP, else JPEG).
String _extension(Uint8List b) {
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return '.png';
  }
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return '.gif';
  }
  if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
    return '.webp';
  }
  return '.jpg';
}

/// Deletes a file made here; never throws.
Future<void> dropPastedFile(String path) async {
  try {
    await File(path).delete();
  } on Object {
    // Already gone
  }
}

/// Deletes every leftover pasted file. Never throws.
Future<void> sweepPastedFiles() async {
  try {
    await _channel.invokeMethod<bool>('sweep');
  } on Object {
    // No channel (a test): nothing to sweep
  }
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/paste');
    if (await dir.exists()) await dir.delete(recursive: true);
  } on Object {
    // Nothing to sweep
  }
}
