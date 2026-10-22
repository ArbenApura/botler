// THE ONE LOADER: A SKELETON WHILE THE DATA COMES, THE DATA FADING IN WITHOUT A JUMP, AND WHAT THE PERSON TYPED KEPT THROUGH A RELOAD.
// A skeleton pulses for ever, so a test that holds a loading state pumps for a time and never settles.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/l10n/l10n.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Widget host(Widget body) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildTheme(Brightness.light),
  home: Scaffold(body: body),
);

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: _text);
}

void main() {
  testWidgets('loading shows a skeleton, then the data, and no spinner', (
    tester,
  ) async {
    var value = const AsyncValue<List<String>>.loading();
    late StateSetter set;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (_, setState) {
            set = setState;
            return AsyncBody<List<String>>(
              value: value,
              data: (l) =>
                  Column(children: <Widget>[for (final s in l) Text(s)]),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    set(() => value = const AsyncValue<List<String>>.data(<String>['hello']));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets('it sits in a list, in an Expanded and as a page body', (
    tester,
  ) async {
    const loading = AsyncValue<int>.loading();
    final widgets = <Widget>[
      ListView(
        children: <Widget>[
          AsyncBody<int>(value: loading, data: (_) => const Text('x')),
        ],
      ),
      Column(
        children: <Widget>[
          Expanded(
            child: AsyncBody<int>(value: loading, data: (_) => const Text('x')),
          ),
        ],
      ),
      AsyncBody<int>(
        value: loading,
        skeleton: const SkeletonPage(
          child: SkeletonRows(kind: SkeletonKind.tile),
        ),
        data: (_) => const Text('x'),
      ),
    ];
    for (final w in widgets) {
      await tester.pumpWidget(host(w));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.byType(Skeleton), findsWidgets);
    }
  });

  testWidgets('a reload keeps the data on screen and what was typed', (
    tester,
  ) async {
    var round = 0;
    var gate = Completer<void>();
    final provider = FutureProvider<int>((ref) async {
      round++;
      if (round > 1) await gate.future;
      return round;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: host(
          Consumer(
            builder: (_, ref, _) => AsyncBody<int>(
              value: ref.watch(provider),
              data: (_) => const _Form(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'typed words');
    // The same provider loads again and has not answered yet: the old value stays
    container.invalidate(provider);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('typed words'), findsOneWidget);
    gate.complete();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('typed words'), findsOneWidget);
  });

  testWidgets('a failure shows the words and a retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      host(
        AsyncBody<int>(
          value: AsyncValue<int>.error(Exception('x'), StackTrace.empty),
          onRetry: () => retried = true,
          data: (_) => const Text('x'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });
}
