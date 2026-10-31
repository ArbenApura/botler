// ONE INTENT, ONE KEY, ONE CALL AT A TIME (ui/once.dart), AND THE SHEET SCOPE THAT KEEPS A SHEET'S FIELDS ALIVE UNTIL IT HAS LEFT THE SCREEN.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/core/api.dart';
import 'package:botler/ui/ui.dart';

// -- FUNCTIONS -- //

void main() {
  group('Once', () {
    test(
      'a key the server already holds for another request is dropped',
      () async {
        final once = Once();
        final seen = <String>[];
        await expectLater(
          once.run<void>((key) async {
            seen.add(key);
            throw const ApiException(
              'CONFLICT',
              'used for a different request',
              409,
            );
          }),
          throwsA(isA<ApiException>()),
        );
        await once.run<void>((key) async => seen.add(key));
        expect(seen[0], isNot(seen[1]));
      },
    );

    test('the key is the same until the call works', () async {
      final once = Once();
      final seen = <String>[];
      await expectLater(
        once.run<void>((key) async {
          seen.add(key);
          throw StateError('offline');
        }),
        throwsStateError,
      );
      // A retry after the failure is the same request
      await once.run<void>((key) async => seen.add(key));
      expect(seen[0], seen[1]);
      // After the success it is a new thing
      await once.run<void>((key) async => seen.add(key));
      expect(seen[2], isNot(seen[1]));
      expect(seen[0].length, inInclusiveRange(8, 80));
    });

    test(
      'a second call of the same intent while one runs does nothing',
      () async {
        final once = Once();
        final gate = Completer<void>();
        var calls = 0;
        final first = once.run<void>((_) async {
          calls++;
          await gate.future;
        });
        expect(once.running(), isTrue);
        final second = await once.run<int>((_) async => calls++);
        expect(second, isNull);
        gate.complete();
        await first;
        expect(calls, 1);
        expect(once.running(), isFalse);
      },
    );

    test('different intents run side by side with different keys', () async {
      final once = Once();
      expect(once.key('a'), isNot(once.key('b')));
      expect(once.key('a'), once.key('a'));
      final gate = Completer<void>();
      final a = once.run<void>((_) => gate.future, intent: 'a');
      expect(once.running('a'), isTrue);
      expect(once.running('b'), isFalse);
      final b = await once.ok((_) async {}, intent: 'b');
      expect(b, isTrue);
      gate.complete();
      await a;
    });

    test('ok says false when the call was skipped', () async {
      final once = Once();
      final gate = Completer<void>();
      final first = once.ok((_) => gate.future);
      expect(await once.ok((_) async {}), isFalse);
      gate.complete();
      expect(await first, isTrue);
    });

    test('the change callback fires when a call starts and ends', () async {
      var changes = 0;
      final once = Once(() => changes++);
      await once.run<void>((_) async {});
      expect(changes, 2);
    });
  });

  group('SheetScope', () {
    testWidgets(
      'keeps its fields while the sheet closes and drops them after',
      (tester) async {
        TextEditingController? seen;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showFormSheet<void>(
                    context,
                    title: 'T',
                    builder: (sheet, close) => SheetScope(
                      texts: const <String>['hello'],
                      builder: (_, s) {
                        seen = s.c[0];
                        return Column(
                          children: <Widget>[
                            Field(controller: s.c[0], label: 'L'),
                            FilledButton(
                              onPressed: () => close(null),
                              child: const Text('Close'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('hello'), findsOneWidget);
        final controller = seen!;
        await tester.tap(find.text('Close'));
        // Mid-animation the sheet is still on screen and its field still works
        await tester.pump(const Duration(milliseconds: 50));
        expect(() => controller.text, returnsNormally);
        await tester.pumpAndSettle();
        // Gone: a disposed controller refuses a listener
        expect(
          () => controller.addListener(() {}),
          throwsA(isA<FlutterError>()),
        );
      },
    );
  });
}
