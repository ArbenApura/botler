// SEVERAL PHOTOS IN ONE MESSAGE: THE BUDGET OF THEIR TEXT, WHAT THE PHONE SENDS, AND WHAT THE USER BUBBLE SAYS.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/photo_budget.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

int total(List<String> texts) => texts.fold(0, (n, t) => n + t.length);

/// A server that keeps the body of the one chat request it gets and answers with a finished turn.
class Capture {
  Json? body;

  MockClient get client => MockClient.streaming((req, stream) async {
    body =
        jsonDecode(utf8.decode(await stream.expand((c) => c).toList())) as Json;
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode('data: {"type":"done","reply":"ok","toolsRun":[]}\n\n'),
      ),
      200,
    );
  });
}

void main() {
  group('the budget of the photo text', () {
    test('keeps every text when together they fit', () {
      final b = fitPhotoTexts(<String>['a' * 100, 'b' * 5000, 'c' * 7000]);
      expect(b.trimmed, false);
      expect(b.texts.map((t) => t.length), <int>[100, 5000, 7000]);
    });

    test('cuts one photo at the most one photo may send', () {
      final b = fitPhotoTexts(<String>['a' * (maxPhotoChars + 500)]);
      expect(b.texts.single.length, maxPhotoChars);
      expect(b.trimmed, true);
    });

    test('shares what is left when six long photos pass the total', () {
      final b = fitPhotoTexts(List<String>.filled(6, 'x' * 8000));
      expect(total(b.texts) <= maxPhotosTotalChars, true);
      expect(b.texts.every((t) => t.length == maxPhotosTotalChars ~/ 6), true);
      expect(b.trimmed, true);
    });

    test(
      'lets a short photo keep all of its text while the long ones are cut',
      () {
        final b = fitPhotoTexts(<String>[
          'a' * 100,
          'b' * 8000,
          'c' * 8000,
          'd' * 8000,
          'e' * 8000,
        ]);
        expect(b.texts.first.length, 100);
        expect(total(b.texts) <= maxPhotosTotalChars, true);
        // The long ones are cut to the same length, and the budget is used up
        expect(b.texts[1].length, b.texts[2].length);
        expect(total(b.texts) > maxPhotosTotalChars - 5, true);
      },
    );

    test(
      'sits exactly on the boundary: 24000 passes whole, one more is cut',
      () {
        final whole = fitPhotoTexts(List<String>.filled(3, 'x' * 8000));
        expect(whole.trimmed, false);
        expect(total(whole.texts), maxPhotosTotalChars);
        final over = fitPhotoTexts(<String>[
          'x' * 8000,
          'x' * 8000,
          'x' * 8000,
          'y',
        ]);
        expect(over.trimmed, true);
        expect(total(over.texts) <= maxPhotosTotalChars, true);
      },
    );

    test('has nothing to do for no photos', () {
      final b = fitPhotoTexts(<String>[]);
      expect(b.texts, isEmpty);
      expect(b.trimmed, false);
    });
  });

  group('sending the photos', () {
    Future<(ProviderContainer, Capture)> open() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final p = await SharedPreferences.getInstance();
      final cap = Capture();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(p),
          apiProvider.overrideWithValue(
            ApiClient(
              base: 'https://botler.test',
              token: () async => 'tok',
              client: cap.client,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return (c, cap);
    }

    test(
      'sends each photo text in ocrTexts, and never the old single field',
      () async {
        final (c, cap) = await open();
        await c
            .read(chatProvider.notifier)
            .send('receipts', photoTexts: <String>['coffee 120', 'taxi 300']);
        expect(cap.body?['ocrTexts'], <String>['coffee 120', 'taxi 300']);
        expect(cap.body?.containsKey('ocrText'), false);
      },
    );

    test('leaves the field out when there are no photos', () async {
      final (c, cap) = await open();
      await c.read(chatProvider.notifier).send('hello');
      expect(cap.body?.containsKey('ocrTexts'), false);
      expect(cap.body?.containsKey('ocrText'), false);
    });

    test('keeps how many photos went along on the user item', () async {
      final (c, _) = await open();
      await c
          .read(chatProvider.notifier)
          .send('receipts', photoTexts: <String>['a', 'b', 'c']);
      final mine = c.read(chatProvider).items.whereType<UserItem>().single;
      expect(mine.photos, 3);
      await c.read(chatProvider.notifier).send('no photo');
      final last = c.read(chatProvider).items.whereType<UserItem>().last;
      expect(last.photos, 0);
    });
  });

  group('the words on the bubble', () {
    test('say one photo or the number of photos, in both languages', () async {
      final en = lookupAppLocalizations(const Locale('en'));
      final fil = lookupAppLocalizations(const Locale('fil'));
      expect(en.chatWithPhotos('hi', 1), 'hi\n(1 photo attached)');
      expect(en.chatWithPhotos('hi', 3), 'hi\n(3 photos attached)');
      expect(fil.chatWithPhotos('hi', 1), 'hi\n(1 litrato)');
      expect(fil.chatWithPhotos('hi', 3), 'hi\n(3 litrato)');
      expect(en.chatPhotosLimit(6), contains('6'));
      expect(fil.chatPhotoRemove(2), contains('2'));
      expect(en.chatPhotoItem(2, 1), 'Photo 2 (1 character)');
    });
  });
}
