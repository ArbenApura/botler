// A PICTURE MADE READY TO SEND TO THE ASSISTANT: A JPEG WITH ITS TURN BAKED IN, NO LOCATION OR CAMERA DETAILS, NO LARGER THAN THE ASSISTANT NEEDS.
// It is made when the message is sent, one picture at a time, in another isolate, from the copy kept on this phone. A picture that cannot be made
// (a format this phone cannot read, too many pixels, still too large after the smallest try) is simply left out: its text still goes.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// -- CONSTANTS -- //

/// The longest side of what is sent. The assistant's host shrinks anything larger itself, so more would only cost upload.
const int uploadLongEdge = 1568;

/// The most one picture may weigh, and all of a message's pictures together.
const int uploadMaxBytes = 1200000;
const int uploadTotalBytes = 6000000;

/// A picture with more pixels than this is not opened: decoding it could run the phone out of memory.
const int uploadMaxPixels = 24000000;

/// The sizes tried in turn, each at the qualities below, until one fits uploadMaxBytes.
const List<int> _edges = <int>[uploadLongEdge, 1200, 900];
const List<int> _qualities = <int>[80, 70, 60, 50];

// -- TYPES -- //

/// A picture ready to go in the body of a message: its base64 and its size in bytes.
class UploadPicture {
  const UploadPicture(this.data, this.bytes);

  final String data;
  final int bytes;
}

// -- FUNCTIONS -- //

/// The size a picture is drawn at: the same shape, its longest side at most [edge], never larger than it is.
({int width, int height}) fitWithin(
  int width,
  int height, {
  int edge = uploadLongEdge,
}) {
  final longest = width > height ? width : height;
  if (longest <= edge || longest == 0) return (width: width, height: height);
  final scale = edge / longest;
  return (
    width: (width * scale).round().clamp(1, edge),
    height: (height * scale).round().clamp(1, edge),
  );
}

/// The JPEG for [bytes], or null when they are not a picture this phone can open, have too many pixels, or stay too large at the smallest try.
/// Runs in the calling isolate; [prepareUpload] puts it in another.
Uint8List? encodeForUpload(Uint8List bytes) {
  try {
    return _encode(bytes);
  } on Object {
    // A file that is cut short, or a format this phone only half reads, is not a picture it can send
    return null;
  }
}

Uint8List? _encode(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) return null;
  // The size is read from the header first, so a huge picture is refused before anything is decoded
  final info = decoder.startDecode(bytes);
  if (info == null || info.width * info.height > uploadMaxPixels) return null;
  final decoded = decoder.decode(bytes);
  if (decoded == null) return null;
  // The turn the camera recorded is applied to the pixels, then every detail kept beside them (place, camera, time) is dropped
  final upright = img.bakeOrientation(decoded)..exif.clear();
  for (final edge in _edges) {
    final size = fitWithin(upright.width, upright.height, edge: edge);
    final fitted = size.width == upright.width && size.height == upright.height
        ? upright
        : img.copyResize(
            upright,
            width: size.width,
            height: size.height,
            interpolation: img.Interpolation.average,
          );
    for (final quality in _qualities) {
      final out = img.encodeJpg(fitted, quality: quality);
      if (out.length <= uploadMaxBytes) return out;
    }
  }
  return null;
}

/// Reads the file and makes its JPEG. A top-level function, so another isolate can run it.
Uint8List? _fromFile(String path) =>
    encodeForUpload(File(path).readAsBytesSync());

/// Makes the picture at [path] ready to send, off the main isolate. Null when it cannot be made (see [encodeForUpload]) or the file is gone.
Future<UploadPicture?> prepareUpload(String path) async {
  try {
    final bytes = await Isolate.run(() => _fromFile(path));
    return bytes == null
        ? null
        : UploadPicture(base64Encode(bytes), bytes.length);
  } on Object {
    return null;
  }
}

/// The pictures for a message, one after another so only one is ever open in memory. The answer has one entry for each path, in order: null
/// where the picture could not be made or would take the message past [uploadTotalBytes]. [cancelled] is asked between pictures.
Future<List<UploadPicture?>> prepareUploads(
  List<String> paths, {
  bool Function()? cancelled,
}) async {
  final out = <UploadPicture?>[];
  var total = 0;
  for (final path in paths) {
    if (cancelled?.call() ?? false) {
      out.add(null);
      continue;
    }
    final one = await prepareUpload(path);
    if (one == null || total + one.bytes > uploadTotalBytes) {
      out.add(null);
    } else {
      total += one.bytes;
      out.add(one);
    }
  }
  return out;
}
