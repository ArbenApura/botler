// THE SCRIPT CARD IN THE CHAT: RUNNING, DONE WITH FOLDED OUTPUT THAT OPENS, AND DID NOT FINISH.

// -- DEP-MODULES -- //
import 'package:botler/features/chat/script_card.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Widget app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('running says what it is doing', (tester) async {
    await tester.pumpWidget(app(const ScriptCard(stage: ScriptStage.running)));
    expect(find.text('Running a script on your phone'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the toolbox has its own words', (tester) async {
    await tester.pumpWidget(
      app(const ScriptCard(stage: ScriptStage.done, toolbox: true)),
    );
    expect(find.text('Used your toolbox'), findsOneWidget);
  });

  testWidgets('done folds long output and opens it on a tap', (tester) async {
    final out = List<String>.generate(12, (i) => 'line $i').join('\n');
    await tester.pumpWidget(
      app(ScriptCard(stage: ScriptStage.done, output: out)),
    );
    expect(find.text('Ran a script on your phone'), findsOneWidget);
    expect(find.text('Show all of it'), findsOneWidget);
    await tester.tap(find.text('Show all of it'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
    expect(find.textContaining('line 11'), findsOneWidget);
  });

  testWidgets('short output has nothing to open', (tester) async {
    await tester.pumpWidget(
      app(const ScriptCard(stage: ScriptStage.done, output: '42')),
    );
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Show all of it'), findsNothing);
  });

  testWidgets('failed gives the reason and no output', (tester) async {
    await tester.pumpWidget(
      app(
        const ScriptCard(
          stage: ScriptStage.failed,
          message: 'It took too long.',
          output: 'hidden',
        ),
      ),
    );
    expect(find.text('The script did not finish'), findsOneWidget);
    expect(find.text('It took too long.'), findsOneWidget);
    expect(find.text('hidden'), findsNothing);
  });
}
