// HOW THE SERVER COUNTS THE PHOTOS OF A TURN (BTL-20261031-1011): "PHOTO 2" ON A CARD MUST BE THE SAME FILE THE SERVER MEANT, NEVER ANOTHER

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'package:botler/core/chat_photos.dart';

// -- FUNCTIONS -- //

String name(String path) => path.split(Platform.pathSeparator).last;

void main() {
  test('the index keeps the numbering with the turn and reads old saves', () {
    final index = PhotoIndex(<String, List<String>>{
      't1': <String>['a.jpg', 'b.jpg', 'c.jpg'],
    })..putNumbered('t1', <String>['a.jpg', 'c.jpg']);
    final back = PhotoIndex.decode(index.encode());
    expect(back.numberedOf('t1'), <String>['a.jpg', 'c.jpg']);
    expect(back.of('t1'), <String>['a.jpg', 'b.jpg', 'c.jpg']);
    // An older save is a plain list: the files in order are the numbering
    final old = PhotoIndex.decode('{"t0":["x.jpg","y.jpg"]}');
    expect(old.numberedOf('t0'), <String>['x.jpg', 'y.jpg']);
  });

  test(
    'a numbered photo that is gone empties the numbering, it never shifts',
    () {
      final index = PhotoIndex(<String, List<String>>{
        't1': <String>['a.jpg', 'b.jpg', 'c.jpg'],
      })..putNumbered('t1', <String>['a.jpg', 'b.jpg', 'c.jpg']);
      index.keepOnly((n) => n != 'b.jpg');
      expect(index.numberedOf('t1'), isEmpty);
      expect(index.of('t1'), <String>['a.jpg', 'c.jpg']);
    },
  );

  test('a store files the photos in the server numbering', () async {
    final dir = await Directory.systemTemp.createTemp('photo_numbering');
    addTearDown(() => dir.delete(recursive: true));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = ChatPhotoStore(
      prefs: await SharedPreferences.getInstance(),
      owner: 'a@b.c',
      baseDir: () async => dir,
    );
    final staged = <String>[];
    for (var i = 0; i < 3; i++) {
      final f = File('${dir.path}${Platform.pathSeparator}src$i.jpg')
        ..writeAsBytesSync(<int>[i]);
      staged.add((await store.stage(f.path))!);
    }
    // Photo 1 had no picture made, so the server's photos are the second and third copies
    await store.promote('t1', staged, numbered: <String>[staged[1], staged[2]]);
    final all = store.photosOf('t1');
    final numbered = store.numberedPhotosOf('t1');
    expect(all, hasLength(3));
    expect(numbered.map(name), <String>[name(all[1]), name(all[2])]);
    // A turn filed without a numbering falls back to the files in order
    final more = <String>[
      (await store.stage(
        (File(
          '${dir.path}${Platform.pathSeparator}z.jpg',
        )..writeAsBytesSync(<int>[9])).path,
      ))!,
    ];
    await store.promote('t2', more);
    expect(store.numberedPhotosOf('t2'), store.photosOf('t2'));
  });
}
