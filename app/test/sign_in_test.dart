// THE SIGN-IN SCREEN AT START: ONLY THE NAME WHILE THE SAVED SIGN-IN IS READ (NO BUTTON, NO SPINNER), AND THE BUSY BUTTON DURING A REAL SIGN-IN.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/auth.dart';
import 'package:botler/features/auth/sign_in_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

class FakeSession extends SessionNotifier {
  FakeSession(this.start);

  final Future<Session?> start;

  @override
  Future<Session?> build() => start;

  void failed() => state = AsyncError<Session?>('x', StackTrace.empty);

  void signingIn() => state = const AsyncLoading<Session?>();
}

Future<FakeSession> show(WidgetTester tester, Future<Session?> start) async {
  final notifier = FakeSession(start);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: const SignInScreen(),
      ),
    ),
  );
  return notifier;
}

void main() {
  testWidgets('while the saved sign-in is read there is no button or spinner', (
    tester,
  ) async {
    await show(tester, Completer<Session?>().future);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The button keeps its space but is hidden (and out of the screen reader's way)
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isFalse);
    expect(find.textContaining('otler'), findsOneWidget);
  });

  testWidgets('with nobody signed in the button shows', (tester) async {
    await show(tester, Future<Session?>.value());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a real sign-in keeps its busy button', (tester) async {
    final notifier = await show(tester, Future<Session?>.value());
    await tester.pump(const Duration(milliseconds: 100));
    notifier.signingIn();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('trying again after a failure shows the busy button', (
    tester,
  ) async {
    final notifier = await show(tester, Future<Session?>.value());
    await tester.pump(const Duration(milliseconds: 100));
    notifier.failed();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.signingIn();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
