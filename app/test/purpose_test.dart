// THE PURPOSE LABEL OF AN ACCOUNT: THE CHIP, THE PICKER (PRESET, CUSTOM, NONE), AND THE RULES THE SERVER ALSO CHECKS.

// -- DEP-MODULES -- //
import 'package:botler/features/money/purpose.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildTheme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  test('reads the label of an account map, an older server sends none', () {
    expect(purposeOf(<String, Object?>{'purpose': ' Bills '}), 'Bills');
    expect(purposeOf(<String, Object?>{'purpose': null}), isNull);
    expect(purposeOf(<String, Object?>{'purpose': '  '}), isNull);
    expect(purposeOf(<String, Object?>{'name': 'GCash'}), isNull);
    expect(purposeOf(null), isNull);
  });

  test('a blank typed label becomes null so it clears, and the rules match the server', () {
    expect(cleanPurpose('  '), isNull);
    expect(cleanPurpose(' Gadgets '), 'Gadgets');
    expect(purposeValid(null), isTrue);
    expect(purposeValid('x' * kPurposeMax), isTrue);
    expect(purposeValid('x' * (kPurposeMax + 1)), isFalse);
    expect(purposeValid('GCash 0917 123 4567'), isFalse);
    expect(purposeValid('Plan 2027'), isFalse);
    expect(purposeValid('0917.123.4567'), isFalse);
    expect(purposeValid('Rent 12'), isTrue);
  });

  testWidgets('the chip shows the label, and nothing for none', (tester) async {
    await tester.pumpWidget(host(const PurposeChip('Emergency')));
    expect(find.text('Emergency'), findsOneWidget);
    await tester.pumpWidget(host(const PurposeChip(null)));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a long label stays on one line at a large text size', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 140,
          child: PurposeChip('A very long label of 24 ch'),
        ),
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picks a preset, switches to custom text, and clears', (
    tester,
  ) async {
    String? latest = 'unset';
    await tester.pumpWidget(
      host(PurposeField(value: null, onChanged: (v) => latest = v)),
    );
    await tester.tap(find.text('Emergency'));
    await tester.pump();
    expect(latest, 'Emergency');

    await tester.tap(find.text('Custom'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  School fund ');
    expect(latest, 'School fund');
    // The field stops at the limit
    await tester.enterText(find.byType(TextField), 'y' * 40);
    expect(latest!.length, kPurposeMax);

    await tester.tap(find.text('No label'));
    await tester.pump();
    expect(latest, isNull);
  });

  testWidgets('opens on the label the account already has', (tester) async {
    await tester.pumpWidget(
      host(PurposeField(value: 'Travel', onChanged: (_) {})),
    );
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Travel'),
    );
    expect(chip.selected, isTrue);
    await tester.pumpWidget(
      host(
        PurposeField(key: UniqueKey(), value: 'School fund', onChanged: (_) {}),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('School fund'), findsOneWidget);
  });
}
