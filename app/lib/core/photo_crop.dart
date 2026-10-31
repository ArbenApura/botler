// CUTTING A PHOTO INTO THE SMALL PICTURE OF AN ACCOUNT OR BILL FROM A BOX THE ASSISTANT PROPOSED (BTL-20261031-1011): THE BOX, ZOOM AND MOVE ARE PURE MATHS; THE CUT RUNS ON THE PHONE FROM ITS OWN COPY
// The box is fractions of the photo as the person sees it (the camera's turn already applied). "cover" fills the square from the middle of
// the box; "contain" keeps the whole box inside the square on a plain margin taken from its corners. Nothing here leaves the phone: the result
// is a small JPEG under the same size limit as any other mark picture.

// -- DEP-MODULES -- //
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// -- MODULES -- //
import 'json.dart';
import 'marks.dart';
import 'photo_upload.dart';

// -- CONSTANTS -- //

/// The smallest share of the photo's width or height a box may keep (the most it can be zoomed in).
const double minCropShare = 0.05;

/// The longest side of the working copy the card cuts from: the photo is read and turned upright once, then every zoom and move cuts from this.
const int cropWorkingEdge = 2048;

/// One tap of the zoom buttons, and of the move buttons as a share of the box.
const double cropZoomStep = 1.25;
const double cropMoveStep = 0.2;

// -- TYPES -- //

enum CropFit { cover, contain }

/// A whole number rectangle in the pixels of the photo.
typedef PixelRect = ({int x, int y, int width, int height});

class CropPlan {
  const CropPlan({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fit = CropFit.cover,
  });

  /// The whole photo, filling the square from its middle: what is shown when nothing better is known.
  static const CropPlan whole = CropPlan(x: 0, y: 0, width: 1, height: 1);

  /// Reads the plan from a card's arguments, forcing every number to be a box inside the photo.
  factory CropPlan.fromJson(Json? j) {
    double n(Object? v, double fallback) =>
        v is num && v.isFinite ? v.toDouble() : fallback;
    final w = n(j?['width'], 1).clamp(minCropShare, 1.0);
    final h = n(j?['height'], 1).clamp(minCropShare, 1.0);
    return CropPlan(
      x: n(j?['x'], 0).clamp(0.0, 1.0 - w),
      y: n(j?['y'], 0).clamp(0.0, 1.0 - h),
      width: w,
      height: h,
      fit: j?['fit'] == 'contain' ? CropFit.contain : CropFit.cover,
    );
  }

  /// Fractions of the photo's width and height.
  final double x;
  final double y;
  final double width;
  final double height;
  final CropFit fit;

  /// The box zoomed about its centre: a [factor] above 1 shows less of the photo, below 1 more. It stays inside the photo.
  CropPlan zoomed(double factor) {
    if (!(factor > 0) || !factor.isFinite) return this;
    final w = (width / factor).clamp(minCropShare, 1.0);
    final h = (height / factor).clamp(minCropShare, 1.0);
    final cx = x + width / 2;
    final cy = y + height / 2;
    return CropPlan(
      x: (cx - w / 2).clamp(0.0, 1.0 - w),
      y: (cy - h / 2).clamp(0.0, 1.0 - h),
      width: w,
      height: h,
      fit: fit,
    );
  }

  /// The box moved by [dx] and [dy] times its own size (positive is right and down). It stays inside the photo.
  CropPlan moved(double dx, double dy) => CropPlan(
    x: (x + dx * width).clamp(0.0, 1.0 - width),
    y: (y + dy * height).clamp(0.0, 1.0 - height),
    width: width,
    height: height,
    fit: fit,
  );

  CropPlan withFit(CropFit next) =>
      CropPlan(x: x, y: y, width: width, height: height, fit: next);

  @override
  bool operator ==(Object other) =>
      other is CropPlan &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(x, y, width, height, fit);
}

// -- FUNCTIONS -- //

/// The part of a photo of [photoWidth] by [photoHeight] pixels that [plan] keeps. For "cover" it is the square in the middle of the box
/// (its shorter side), moved inside the photo if needed; for "contain" it is the whole box. Never empty, never outside the photo.
PixelRect sourceRect(CropPlan plan, int photoWidth, int photoHeight) {
  final bx = plan.x * photoWidth;
  final by = plan.y * photoHeight;
  final bw = plan.width * photoWidth;
  final bh = plan.height * photoHeight;
  double left = bx;
  double top = by;
  double w = bw;
  double h = bh;
  if (plan.fit == CropFit.cover) {
    final side = bw < bh ? bw : bh;
    left = bx + (bw - side) / 2;
    top = by + (bh - side) / 2;
    w = side;
    h = side;
  }
  final width = w.round().clamp(1, photoWidth);
  final height = h.round().clamp(1, photoHeight);
  return (
    x: left.round().clamp(0, photoWidth - width),
    y: top.round().clamp(0, photoHeight - height),
    width: width,
    height: height,
  );
}

/// The small JPEG for the part of [bytes] that [plan] keeps, or null when they are not a picture this phone can open. Runs in the calling isolate.
Uint8List? encodeCropped(Uint8List bytes, CropPlan plan) {
  try {
    final upright = _openUpright(bytes, cropWorkingEdge * 4);
    return upright == null ? null : _cutImage(upright, plan);
  } on Object {
    // A file that is cut short is not a picture it can use
    return null;
  }
}

/// Decodes [bytes], turns them upright and, when the longest side is above [edge], shrinks them to it. Null when they are not a usable picture.
img.Image? _openUpright(Uint8List bytes, int edge) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) return null;
  final info = decoder.startDecode(bytes);
  if (info == null || info.width * info.height > uploadMaxPixels) return null;
  final decoded = decoder.decode(bytes);
  if (decoded == null) return null;
  var upright = img.bakeOrientation(decoded)..exif.clear();
  final longest = upright.width > upright.height
      ? upright.width
      : upright.height;
  if (longest > edge) {
    upright = upright.width >= upright.height
        ? img.copyResize(
            upright,
            width: edge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            upright,
            height: edge,
            interpolation: img.Interpolation.average,
          );
  }
  return upright;
}

/// The small JPEG for the part of an upright picture that [plan] keeps.
Uint8List? _cutImage(img.Image upright, CropPlan plan) {
  final r = sourceRect(plan, upright.width, upright.height);
  final cut = img.copyCrop(
    upright,
    x: r.x,
    y: r.y,
    width: r.width,
    height: r.height,
  );
  final longest = r.width > r.height ? r.width : r.height;
  final edge = longest < markEdge ? longest : markEdge;
  if (plan.fit == CropFit.cover || r.width == r.height) {
    final small = edge == r.width && edge == r.height
        ? cut
        : img.copyResize(
            cut,
            width: edge,
            height: edge,
            interpolation: img.Interpolation.average,
          );
    return encodeMarkImage(small);
  }
  // The whole box inside the square, on a margin the colour of the box's corners
  final scale = edge / longest;
  final w = (r.width * scale).round().clamp(1, edge);
  final h = (r.height * scale).round().clamp(1, edge);
  final inner = img.copyResize(
    cut,
    width: w,
    height: h,
    interpolation: img.Interpolation.average,
  );
  final canvas = img.Image(width: edge, height: edge);
  img.fill(canvas, color: _cornerColour(cut));
  img.compositeImage(
    canvas,
    inner,
    dstX: (edge - w) ~/ 2,
    dstY: (edge - h) ~/ 2,
  );
  return encodeMarkImage(canvas);
}

/// The average of the four corner pixels, as the margin colour.
img.Color _cornerColour(img.Image image) {
  final last = <img.Pixel>[
    image.getPixel(0, 0),
    image.getPixel(image.width - 1, 0),
    image.getPixel(0, image.height - 1),
    image.getPixel(image.width - 1, image.height - 1),
  ];
  num r = 0;
  num g = 0;
  num b = 0;
  for (final p in last) {
    r += p.r;
    g += p.g;
    b += p.b;
  }
  return img.ColorRgb8((r / 4).round(), (g / 4).round(), (b / 4).round());
}

/// A photo read, turned upright and shrunk once, so every zoom and move cuts from memory and never decodes the file again.
class CropSource {
  CropSource._(this._image);

  final img.Image _image;

  int get width => _image.width;
  int get height => _image.height;

  /// The small JPEG for [plan], or null when it cannot be made under the size limit.
  Uint8List? cut(CropPlan plan) {
    try {
      return _cutImage(_image, plan);
    } on Object {
      return null;
    }
  }
}

/// A [CropSource] for already decoded bytes, for the caller's isolate (tests, small pictures). Null when they are not a picture.
CropSource? cropSourceOf(Uint8List bytes) {
  try {
    final upright = _openUpright(bytes, cropWorkingEdge);
    return upright == null ? null : CropSource._(upright);
  } on Object {
    return null;
  }
}

({int width, int height, Uint8List rgba})? _rawFromFile(String path) {
  final upright = _openUpright(File(path).readAsBytesSync(), cropWorkingEdge);
  if (upright == null) return null;
  final rgba = upright.convert(numChannels: 4, alpha: 255);
  return (
    width: rgba.width,
    height: rgba.height,
    rgba: rgba.getBytes(order: img.ChannelOrder.rgba),
  );
}

/// Reads the photo at [path] once, off the main isolate, and keeps a working copy to cut from. Null when the file is gone or is not a picture.
Future<CropSource?> openCropSource(String path) async {
  try {
    final raw = await Isolate.run(() => _rawFromFile(path));
    if (raw == null) return null;
    return CropSource._(
      img.Image.fromBytes(
        width: raw.width,
        height: raw.height,
        bytes: raw.rgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      ),
    );
  } on Object {
    return null;
  }
}
