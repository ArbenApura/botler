// -- DEP-MODULES -- //
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/core/clipboard_image.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('paste_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes the bytes to a file named for their type', () async {
    final png = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final path = await imageBytesToFile(png, folder: dir);
    expect(path, isNotNull);
    expect(path, endsWith('.png'));
    expect(File(path!).readAsBytesSync(), png);
  });

  test('falls back to jpg and makes a new file each time', () async {
    final data = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final a = await imageBytesToFile(data, folder: dir);
    final b = await imageBytesToFile(data, folder: dir);
    expect(a, endsWith('.jpg'));
    expect(a, isNot(b));
  });

  test('refuses nothing and anything past the size cap', () async {
    expect(await imageBytesToFile(Uint8List(0), folder: dir), isNull);
    expect(
      await imageBytesToFile(Uint8List(maxPastedBytes + 1), folder: dir),
      isNull,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('dropPastedFile deletes the file and never throws', () async {
    final path = await imageBytesToFile(
      Uint8List.fromList(<int>[1]),
      folder: dir,
    );
    await dropPastedFile(path!);
    expect(File(path).existsSync(), isFalse);
    await dropPastedFile(path);
  });
}
