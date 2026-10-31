// CUTTING A PHOTO FROM THE ASSISTANT'S BOX (BTL-20261031-1011): THE BOX MATHS STAYS INSIDE THE PHOTO, AND THE CUT IS A SMALL SQUARE JPEG

// -- DEP-MODULES -- //
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// -- MODULES -- //
import 'package:botler/core/marks.dart';
import 'package:botler/core/photo_crop.dart';

// -- FUNCTIONS -- //

/// A 400 by 200 picture: the left half red, the right half blue.
Uint8List twoColours() {
  final image = img.Image(width: 400, height: 200);
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 199,
    y2: 199,
    color: img.ColorRgb8(255, 0, 0),
  );
  return Uint8List.fromList(img.encodePng(image));
}

img.Image decode(Uint8List bytes) => img.decodeJpg(bytes)!;

void main() {
  group('reading the plan', () {
    test('forces a box inside the photo', () {
      final p = CropPlan.fromJson(<String, Object?>{
        'x': 0.8,
        'y': -3,
        'width': 0.6,
        'height': 9,
        'fit': 'contain',
      });
      expect(p.width, 0.6);
      expect(p.height, 1.0);
      expect(p.x, closeTo(0.4, 1e-9));
      expect(p.y, 0.0);
      expect(p.fit, CropFit.contain);
    });

    test('a missing or odd value falls back to the whole photo', () {
      final p = CropPlan.fromJson(<String, Object?>{'x': 'a', 'width': null});
      expect(p, CropPlan.whole);
      expect(CropPlan.fromJson(null), CropPlan.whole);
    });
  });

  group('zoom and move', () {
    test(
      'zooming keeps the centre and never leaves the photo or goes tiny',
      () {
        const p = CropPlan(x: 0.25, y: 0.25, width: 0.5, height: 0.5);
        final z = p.zoomed(2);
        expect(z.width, 0.25);
        expect(z.x + z.width / 2, closeTo(0.5, 1e-9));
        var tiny = p;
        for (var i = 0; i < 40; i++) {
          tiny = tiny.zoomed(2);
        }
        expect(tiny.width, minCropShare);
        var wide = p;
        for (var i = 0; i < 40; i++) {
          wide = wide.zoomed(0.5);
        }
        expect(wide.x, 0.0);
        expect(wide.width, 1.0);
        expect(p.zoomed(0), p);
        expect(p.zoomed(double.nan), p);
      },
    );

    test('moving is by the box size and stops at the edges', () {
      const p = CropPlan(x: 0.4, y: 0.4, width: 0.2, height: 0.2);
      final m = p.moved(1, 0);
      expect(m.x, closeTo(0.6, 1e-9));
      expect(p.moved(100, 100).x, closeTo(0.8, 1e-9));
      expect(p.moved(-100, -100).y, 0.0);
    });
  });

  group('the part of the photo that is kept', () {
    test('cover takes the square in the middle of the box', () {
      const p = CropPlan(x: 0, y: 0, width: 1, height: 1);
      final r = sourceRect(p, 400, 200);
      expect((r.width, r.height), (200, 200));
      expect(r.x, 100);
    });

    test('contain takes the whole box', () {
      const p = CropPlan(
        x: 0.5,
        y: 0,
        width: 0.5,
        height: 1,
        fit: CropFit.contain,
      );
      final r = sourceRect(p, 400, 200);
      expect((r.x, r.y, r.width, r.height), (200, 0, 200, 200));
    });

    test('never empty and never outside', () {
      const p = CropPlan(x: 0.99, y: 0.99, width: 0.05, height: 0.05);
      final r = sourceRect(p, 10, 10);
      expect(r.width, greaterThanOrEqualTo(1));
      expect(r.x + r.width, lessThanOrEqualTo(10));
      expect(r.y + r.height, lessThanOrEqualTo(10));
    });
  });

  group('the cut', () {
    test('cover is a small square of the chosen side', () {
      const left = CropPlan(x: 0, y: 0, width: 0.5, height: 1);
      final out = encodeCropped(twoColours(), left)!;
      expect(out.length, lessThanOrEqualTo(markMaxBytes));
      final image = decode(out);
      expect((image.width, image.height), (markEdge, markEdge));
      final centre = image.getPixel(markEdge ~/ 2, markEdge ~/ 2);
      expect(centre.r, greaterThan(180));
      expect(centre.b, lessThan(80));
      const right = CropPlan(x: 0.5, y: 0, width: 0.5, height: 1);
      final blue = decode(encodeCropped(twoColours(), right)!);
      expect(blue.getPixel(10, 10).b, greaterThan(180));
    });

    test('contain keeps a wide box whole on a square with a margin', () {
      const whole = CropPlan(
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        fit: CropFit.contain,
      );
      final out = encodeCropped(twoColours(), whole)!;
      final image = decode(out);
      expect((image.width, image.height), (markEdge, markEdge));
      // Both halves are there, red on the left and blue on the right, in the middle band
      expect(image.getPixel(20, markEdge ~/ 2).r, greaterThan(150));
      expect(image.getPixel(markEdge - 20, markEdge ~/ 2).b, greaterThan(150));
      // The margin above the band is not black
      final margin = image.getPixel(markEdge ~/ 2, 2);
      expect(margin.r + margin.g + margin.b, greaterThan(60));
    });

    test('something that is not a picture gives null', () {
      expect(
        encodeCropped(Uint8List.fromList(<int>[1, 2, 3]), CropPlan.whole),
        isNull,
      );
      expect(cropSourceOf(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    });

    test('a photo turned by the camera is cut as the person sees it', () {
      // 400 by 200 on disk, marked "rotate 90 degrees": the person sees it 200 by 400 (red half on top after the turn)
      final image = img.Image(width: 400, height: 200);
      img.fill(image, color: img.ColorRgb8(0, 0, 255));
      img.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 199,
        y2: 199,
        color: img.ColorRgb8(255, 0, 0),
      );
      image.exif.imageIfd.orientation = 6;
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      final source = cropSourceOf(bytes)!;
      expect((source.width, source.height), (200, 400));
      // Rotating 90 degrees clockwise puts the left (red) half on top
      const top = CropPlan(x: 0, y: 0, width: 1, height: 0.5);
      final out = decode(source.cut(top)!);
      expect(out.getPixel(markEdge ~/ 2, markEdge ~/ 2).r, greaterThan(180));
      const bottom = CropPlan(x: 0, y: 0.5, width: 1, height: 0.5);
      final blue = decode(source.cut(bottom)!);
      expect(blue.getPixel(markEdge ~/ 2, markEdge ~/ 2).b, greaterThan(180));
    });

    test('a big photo is read once at a working size and still cuts', () {
      final big = img.Image(width: cropWorkingEdge + 800, height: 600);
      img.fill(big, color: img.ColorRgb8(10, 200, 10));
      final source = cropSourceOf(Uint8List.fromList(img.encodePng(big)))!;
      expect(source.width, cropWorkingEdge);
      expect(source.height, lessThan(600));
      expect(source.cut(CropPlan.whole), isNotNull);
    });

    test(
      'a picture too large for the mark limit gives null, not a bad file',
      () {
        // Noise does not compress: even the lowest quality is over the limit
        final noise = img.Image(width: 192, height: 192);
        var v = 12345;
        for (final p in noise) {
          v = (v * 1103515245 + 12345) & 0x7fffffff;
          p
            ..r = v & 255
            ..g = (v >> 8) & 255
            ..b = (v >> 16) & 255;
        }
        final source = cropSourceOf(Uint8List.fromList(img.encodePng(noise)))!;
        expect(source.cut(CropPlan.whole), isNull);
      },
    );

    test('a header that claims too many pixels is refused before decoding', () {
      final tiny = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      // The IHDR width and height sit at bytes 16 to 23 of a PNG
      final data = ByteData.sublistView(tiny);
      data.setUint32(16, 20000);
      data.setUint32(20, 20000);
      expect(cropSourceOf(tiny), isNull);
      expect(encodeCropped(tiny, CropPlan.whole), isNull);
    });
  });
}
