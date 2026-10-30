// THE PICTURE SENT TO THE ASSISTANT: THE RIGHT SIZE AND SHAPE, ITS TURN BAKED IN, NOTHING ELSE KEPT BESIDE THE PIXELS, AND NEVER A CRASH FOR A FILE THAT IS
// NOT A PICTURE

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:botler/core/photo_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// -- FUNCTIONS -- //

/// A picture of the given size with some detail in it (a flat colour would shrink to nothing and prove little).
img.Image sample(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 5) % 256, (x + y) % 256);
    }
  }
  return image;
}

void main() {
  group('fitWithin', () {
    test(
      'keeps what is small enough, and shrinks the longest side to the edge',
      () {
        expect(fitWithin(800, 600), (width: 800, height: 600));
        expect(fitWithin(3136, 1568), (width: 1568, height: 784));
        expect(fitWithin(1000, 4000), (width: 392, height: 1568));
        expect(fitWithin(0, 0), (width: 0, height: 0));
      },
    );
  });

  group('encodeForUpload', () {
    test('makes a JPEG no larger than the limits from a large picture', () {
      final big = Uint8List.fromList(img.encodePng(sample(2400, 1800)));
      final out = encodeForUpload(big)!;
      expect(out[0], 0xff);
      expect(out[1], 0xd8);
      expect(out.length, lessThanOrEqualTo(uploadMaxBytes));
      final back = img.decodeJpg(out)!;
      expect(back.width > back.height ? back.width : back.height, 1568);
    });

    test(
      'applies the camera turn to the pixels and keeps no details beside them',
      () {
        final turned = sample(40, 20);
        turned.exif.imageIfd.orientation = 6;
        final out = encodeForUpload(Uint8List.fromList(img.encodeJpg(turned)))!;
        final back = img.decodeJpg(out)!;
        // Turned a quarter: wide became tall
        expect((back.width, back.height), (20, 40));
        expect(back.exif.imageIfd.hasOrientation, isFalse);
        expect(back.exif.isEmpty, isTrue);
      },
    );

    test('is null for what is not a picture, empty, or cut short', () {
      expect(
        encodeForUpload(Uint8List.fromList(utf8.encode('just some words'))),
        isNull,
      );
      expect(encodeForUpload(Uint8List(0)), isNull);
      final whole = Uint8List.fromList(img.encodePng(sample(200, 200)));
      expect(encodeForUpload(whole.sublist(0, 40)), isNull);
    });

    test('is null for a picture with too many pixels, without opening it', () {
      // A PNG header that claims 10000 x 10000 and nothing else
      final header = BytesBuilder()
        ..add(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ..add(<int>[0, 0, 0, 13])
        ..add(utf8.encode('IHDR'))
        ..add(<int>[0, 0, 0x27, 0x10, 0, 0, 0x27, 0x10, 8, 2, 0, 0, 0])
        ..add(<int>[0, 0, 0, 0]);
      expect(encodeForUpload(header.toBytes()), isNull);
    });
  });

  group('prepareUpload', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('botler_upload'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, List<int> bytes) =>
        File('${dir.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(bytes);

    test(
      'reads a file in another isolate and answers base64 with its size',
      () async {
        final f = write('a.png', img.encodePng(sample(300, 200)));
        final one = await prepareUpload(f.path);
        expect(one, isNotNull);
        expect(base64Decode(one!.data).length, one.bytes);
      },
    );

    test(
      'is null for a file that is gone or not a picture, never a throw',
      () async {
        expect(
          await prepareUpload('${dir.path}${Platform.pathSeparator}none.png'),
          isNull,
        );
        expect(
          await prepareUpload(write('x.png', utf8.encode('words')).path),
          isNull,
        );
      },
    );

    test('keeps one entry for each path, in order, with null where one could not be made', () async {
      final a = write('a.png', img.encodePng(sample(120, 80)));
      final bad = write('b.png', utf8.encode('words'));
      final c = write('c.png', img.encodePng(sample(100, 100)));
      final out = await prepareUploads(<String>[a.path, bad.path, c.path]);
      expect(out.map((e) => e != null), <bool>[true, false, true]);
    });

    test('skips what is asked to stop', () async {
      final a = write('a.png', img.encodePng(sample(120, 80)));
      var asked = 0;
      final out = await prepareUploads(<String>[
        a.path,
        a.path,
      ], cancelled: () => ++asked > 1);
      expect(out.map((e) => e != null), <bool>[true, false]);
    });
  });
}
