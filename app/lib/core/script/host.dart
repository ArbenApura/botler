// WHAT A SCRIPT CAN ASK THE PHONE FOR (BTL-20261031-1334): THE HOST SIDE OF THE SANDBOX. A SCRIPT NEVER TOUCHES THE PHONE ITSELF; IT CALLS THESE OPERATIONS BY NAME, AND EACH ONE ONLY REACHES
// THE CHAT'S SCRATCH FOLDER, THE PHOTOS OF THIS MESSAGE (COPIED IN), AND PICTURE MATHS ON BYTES. No network, no other file, no Botler data. The engine is not here, so all of it is testable.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// -- MODULES -- //
import 'image_ops.dart' as pic;
import 'scratch.dart';

// -- CONSTANTS -- //

/// The most text one read gives back to a script, and the most bytes of a file that can be turned into base64 text.
const int hostMaxReadBytes = 8 * 1024 * 1024;

// -- TYPES -- //

typedef Args = Map<String, Object?>;

class ScriptHost {
  ScriptHost({
    required this.scratch,
    this.photos = const <String>[],
    this.outputChars = 6000,
  });

  final ScratchFolder scratch;

  /// The files of the photos of the message the script runs in, numbered from 1 in the order the assistant counts them.
  final List<String> photos;
  final int outputChars;

  final StringBuffer _out = StringBuffer();
  bool _cut = false;

  // -- FUNCTIONS -- //

  /// What the script printed, cut at the cap with a note.
  String get output =>
      _cut ? '${_out.toString()}\n[output cut]' : _out.toString();

  /// Every operation a script may name. Anything else is refused.
  static const Set<String> operations = <String>{
    'print',
    'fs.write',
    'fs.read',
    'fs.list',
    'fs.remove',
    'fs.writeBase64',
    'fs.readBase64',
    'fs.photo',
    'image.info',
    'image.resize',
    'image.crop',
    'image.rotate',
    'image.grayscale',
    'base64.encode',
    'base64.decode',
  };

  String _text(Args a, String key) {
    final v = a[key];
    if (v is! String) throw ScratchException('$key must be text.');
    return v;
  }

  /// Runs one operation and returns the JSON the script's side reads: {"v": value}, or {"e": message} when it was refused.
  String call(String op, Object? raw) {
    try {
      if (!operations.contains(op)) {
        throw ScratchException('There is no operation "$op".');
      }
      final a = raw is Map ? raw.cast<String, Object?>() : <String, Object?>{};
      return jsonEncode(<String, Object?>{'v': _run(op, a)});
    } on ScratchException catch (e) {
      return jsonEncode(<String, Object?>{'e': e.message});
    } on FileSystemException {
      return jsonEncode(<String, Object?>{'e': 'The file could not be used.'});
    } on FormatException catch (e) {
      return jsonEncode(<String, Object?>{'e': e.message});
    } on Object {
      return jsonEncode(<String, Object?>{'e': 'That did not work.'});
    }
  }

  Object? _run(String op, Args a) {
    switch (op) {
      case 'print':
        _print(_text(a, 't'));
        return null;
      case 'fs.write':
        scratch.write(_text(a, 'name'), utf8.encode(_text(a, 'text')));
        return null;
      case 'fs.read':
        {
          final bytes = scratch.read(_text(a, 'name'));
          if (bytes.length > hostMaxReadBytes) {
            throw const ScratchException(
              'That file is too large to read as text.',
            );
          }
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'fs.list':
        return <Object?>[
          for (final f in scratch.list())
            <String, Object?>{'name': f.name, 'size': f.size},
        ];
      case 'fs.remove':
        scratch.remove(_text(a, 'name'));
        return null;
      case 'fs.writeBase64':
        scratch.write(_text(a, 'name'), base64Decode(_text(a, 'b64')));
        return null;
      case 'fs.readBase64':
        {
          final bytes = scratch.read(_text(a, 'name'));
          if (bytes.length > hostMaxReadBytes) {
            throw const ScratchException(
              'That file is too large to read as base64 text.',
            );
          }
          return base64Encode(bytes);
        }
      case 'fs.photo':
        return _photo(a);
      case 'image.info':
        {
          final i = pic.info(scratch.read(_text(a, 'src')));
          return <String, Object?>{'width': i.width, 'height': i.height};
        }
      case 'image.resize':
        return _make(
          a,
          (image) => pic.resize(
            image,
            width: a['width'],
            height: a['height'],
            fit: switch (a['fit']) {
              final String f => f,
              _ => 'contain',
            },
          ),
        );
      case 'image.crop':
        return _make(
          a,
          (image) => pic.crop(
            image,
            x: a['x'],
            y: a['y'],
            width: a['width'],
            height: a['height'],
          ),
        );
      case 'image.rotate':
        return _make(a, (image) => pic.rotate(image, a['degrees']));
      case 'image.grayscale':
        return _make(a, pic.grayscale);
      case 'base64.encode':
        return base64Encode(utf8.encode(_text(a, 't')));
      case 'base64.decode':
        return utf8.decode(base64Decode(_text(a, 'b')), allowMalformed: true);
    }
    throw ScratchException('There is no operation "$op".');
  }

  void _print(String text) {
    if (_cut) return;
    if (_out.length + text.length + 1 > outputChars) {
      final room = outputChars - _out.length;
      if (room > 0) _out.write(text.substring(0, room.clamp(0, text.length)));
      _cut = true;
      return;
    }
    if (_out.isNotEmpty) _out.write('\n');
    _out.write(text);
  }

  /// Copies photo [n] of the message into the scratch folder under [name], and tells the script its size.
  Object? _photo(Args a) {
    final n = a['n'];
    if (n is! int || n < 1 || n > photos.length) {
      throw ScratchException(
        photos.isEmpty
            ? 'There is no photo in this message.'
            : 'Photo n must be between 1 and ${photos.length}.',
      );
    }
    final file = File(photos[n - 1]);
    if (!file.existsSync()) {
      throw const ScratchException('That photo is no longer on this phone.');
    }
    final bytes = file.readAsBytesSync();
    scratch.write(_text(a, 'name'), bytes);
    final i = pic.info(Uint8List.fromList(bytes));
    return <String, Object?>{
      'width': i.width,
      'height': i.height,
      'size': bytes.length,
    };
  }

  /// Reads the picture src, applies [work], writes the result to dst in the format dst's name asks for, and returns its size.
  Object? _make(Args a, img.Image Function(img.Image image) work) {
    final src = _text(a, 'src');
    final dst = _text(a, 'dst');
    scratch.check(dst);
    final image = pic.open(scratch.read(src));
    final made = work(image);
    final bytes = pic.encode(made, dst);
    scratch.write(dst, bytes);
    return <String, Object?>{
      'width': made.width,
      'height': made.height,
      'size': bytes.length,
    };
  }
}
