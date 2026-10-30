// THE LIBRARY'S STATE: A WIPE THAT COMES WHILE A PINNED PAGE IS BEING FETCHED IN THE BACKGROUND IS NOT UNDONE, AND OPENING A PAGE THAT CARRIES NO DOT
// DOES NOT READ THE WHOLE LIBRARY AGAIN.

// -- DEP-MODULES -- //
import 'package:botler/core/library.dart';
import 'package:botler/state/library.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'library_fake.dart';

// -- FUNCTIONS -- //

Future<ProviderContainer> container(FakeLibrary fake) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(fake.api),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test(
    'a wipe during the background fetch of a pinned page keeps nothing',
    () async {
      final fake = sampleLibrary();
      fake.page('p-3')!.pinnedAt = '2026-10-30T02:00:00.000Z';
      fake.pageGetDelay = const Duration(milliseconds: 150);
      final c = await container(fake);
      await c.read(libraryProvider.future);
      final cache = c.read(pageCacheProvider);
      // The fetch of the pinned page is on its way; the person wipes now
      await cache.wipe();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fake.of('page_get'), hasLength(1));
      expect(cache.cachedIds(), isEmpty);
    },
  );

  test('without a wipe the pinned page is kept for offline reading', () async {
    final fake = sampleLibrary();
    fake.page('p-3')!.pinnedAt = '2026-10-30T02:00:00.000Z';
    final c = await container(fake);
    await c.read(libraryProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.read(pageCacheProvider).cachedIds(), <String>['p-3']);
  });

  test(
    'marking a page seen that carries no dot does not read the library again',
    () async {
      final fake = sampleLibrary();
      final c = await container(fake);
      final library = await c.read(libraryProvider.future);
      final page = library.page('p-3')!;
      final doc = PageDoc.fromJson(
        await c.read(apiProvider).verbJson('page_get', <String, Object?>{
          'pageId': page.id,
        }),
      );
      final before = fake.of('notebook_outline').length;
      await c.read(libraryActionsProvider).markSeen(doc);
      expect(fake.of('page_seen'), hasLength(1));
      expect(fake.of('notebook_outline').length, before);
    },
  );

  test('marking a page seen that carries the dot reads the library again and the dot goes', () async {
    final fake = sampleLibrary();
    final c = await container(fake);
    final library = await c.read(libraryProvider.future);
    expect(library.page('p-1')!.botlerUpdated, isTrue);
    final doc = PageDoc.fromJson(
      await c.read(apiProvider).verbJson('page_get', <String, Object?>{
        'pageId': 'p-1',
      }),
    );
    await c.read(libraryActionsProvider).markSeen(doc);
    final fresh = await c.read(libraryProvider.future);
    expect(fresh.page('p-1')!.botlerUpdated, isFalse);
  });
}
