// PICTURE WORK FOR SCRIPTS (BTL-20261031-1334): INFO, RESIZE, CROP, ROTATE AND GRAYSCALE ON BYTES. PLAIN FUNCTIONS WITH NO FILES AND NO ENGINE, SO THEY RUN THE SAME IN A TEST.
// A picture with too many pixels is never opened (decoding it could run the phone out of memory), and no result is larger than 4096 on a side.

// -- DEP-MODULES -- //
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// -- MODULES -- //
import '../photo_upload.dart';
import 'scratch.dart';

// -- CONSTANTS -- //

/// The longest side a script may make, and the most pixels a made picture may hold (decoded, four bytes each).
const int imageMaxEdge = 4096;
const int imageMaxPixels = 16 * 1024 * 1024;

// -- FUNCTIONS -- //

img.Image open(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) {
    throw const ScratchException(
      'That file is not a picture this phone can read.',
    );
  }
  final info = decoder.startDecode(bytes);
  if (info == null) {
    throw const ScratchException(
      'That file is not a picture this phone can read.',
    );
  }
  if (info.width * info.height > uploadMaxPixels) {
    throw const ScratchException('That picture has too many pixels to open.');
  }
  final decoded = decoder.decode(bytes);
  if (decoded == null) {
    throw const ScratchException(
      'That file is not a picture this phone can read.',
    );
  }
  return img.bakeOrientation(decoded)..exif.clear();
}

({int width, int height}) info(Uint8List bytes) {
  final image = open(bytes);
  return (width: image.width, height: image.height);
}

/// The picture in the format its destination name asks for (png, jpg, jpeg, gif or bmp; png when the name says nothing).
Uint8List encode(img.Image image, String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? 'png' : name.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return Uint8List.fromList(img.encodeJpg(image, quality: 88));
    case 'gif':
      return Uint8List.fromList(img.encodeGif(image));
    case 'bmp':
      return Uint8List.fromList(img.encodeBmp(image));
    default:
      return Uint8List.fromList(img.encodePng(image));
  }
}

int _edge(Object? v, String what) {
  if (v is! num || !v.isFinite) {
    throw ScratchException('$what must be a number.');
  }
  final n = v.round();
  if (n < 1 || n > imageMaxEdge) {
    throw ScratchException('$what must be between 1 and $imageMaxEdge.');
  }
  return n;
}

/// Refuses a size outside the limits before any pixel is made, so a thin picture stretched on one side cannot ask for a gigabyte.
void _checkSize(int w, int h, {int limit = imageMaxPixels}) {
  if (w < 1 || h < 1 || w > imageMaxEdge * 2 || h > imageMaxEdge * 2) {
    throw const ScratchException(
      'That size is out of range: a side is between 1 and 4096 pixels.',
    );
  }
  if (w * h > limit) {
    throw const ScratchException(
      'That size would make a picture with too many pixels.',
    );
  }
}

/// Resizes to fit inside width by height ("contain", the default, keeps the whole picture and its shape) or to fill it exactly, cutting
/// the overflow from the middle ("cover"). With only one of width and height, the other follows the shape.
img.Image resize(
  img.Image image, {
  Object? width,
  Object? height,
  String fit = 'contain',
}) {
  if (width == null && height == null) {
    throw const ScratchException('Give a width, a height or both.');
  }
  if (fit != 'contain' && fit != 'cover') {
    throw const ScratchException('fit is "contain" or "cover".');
  }
  var w = width == null ? null : _edge(width, 'width');
  var h = height == null ? null : _edge(height, 'height');
  if (w == null || h == null) {
    // The side that is not given follows the shape, so it is worked out here and held to the same limits
    if (w != null) h = (image.height * w / image.width).round();
    if (h != null && w == null) w = (image.width * h / image.height).round();
    _checkSize(w!, h!);
    return img.copyResize(
      image,
      width: w,
      height: h,
      interpolation: img.Interpolation.average,
    );
  }
  _checkSize(w, h);
  if (fit == 'cover') {
    final scale = (w / image.width) > (h / image.height)
        ? w / image.width
        : h / image.height;
    final bigW = (image.width * scale).ceil().clamp(w, imageMaxEdge * 2);
    final bigH = (image.height * scale).ceil().clamp(h, imageMaxEdge * 2);
    _checkSize(bigW, bigH, limit: imageMaxPixels * 2);
    final big = img.copyResize(
      image,
      width: bigW,
      height: bigH,
      interpolation: img.Interpolation.average,
    );
    return img.copyCrop(
      big,
      x: ((big.width - w) / 2).floor(),
      y: ((big.height - h) / 2).floor(),
      width: w,
      height: h,
    );
  }
  final scale = (w / image.width) < (h / image.height)
      ? w / image.width
      : h / image.height;
  return img.copyResize(
    image,
    width: (image.width * scale).round().clamp(1, imageMaxEdge),
    height: (image.height * scale).round().clamp(1, imageMaxEdge),
    interpolation: img.Interpolation.average,
  );
}

/// The part from (x, y) of the given size, in pixels. It has to lie inside the picture.
img.Image crop(
  img.Image image, {
  required Object? x,
  required Object? y,
  required Object? width,
  required Object? height,
}) {
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
    throw const ScratchException('x and y must be numbers.');
  }
  final w = _edge(width, 'width');
  final h = _edge(height, 'height');
  final left = x.round();
  final top = y.round();
  if (left < 0 || top < 0 || left + w > image.width || top + h > image.height) {
    throw ScratchException(
      'The box must lie inside the picture (${image.width} by ${image.height}).',
    );
  }
  return img.copyCrop(image, x: left, y: top, width: w, height: h);
}

/// Turns the picture clockwise by degrees; only multiples of 90 are exact, any other angle grows the canvas.
img.Image rotate(img.Image image, Object? degrees) {
  if (degrees is! num || !degrees.isFinite) {
    throw const ScratchException('degrees must be a number.');
  }
  final d = degrees.toDouble() % 360;
  if (d == 0) return image;
  // The canvas a turn by d degrees needs, worked out before it is made
  final rad = d * math.pi / 180;
  final c = math.cos(rad).abs();
  final s = math.sin(rad).abs();
  _checkSize(
    (image.width * c + image.height * s).ceil(),
    (image.width * s + image.height * c).ceil(),
  );
  return img.copyRotate(image, angle: d);
}

img.Image grayscale(img.Image image) => img.grayscale(image);
