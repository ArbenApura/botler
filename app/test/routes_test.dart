// THE ROUTES: EVERY SCREEN ARRIVES THROUGH THE ONE PAGE BUILDER, THE REDIRECT AND THE EXPENSE VALUES STILL WORK, AND REDUCED MOTION ONLY FADES.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/app.dart';
import 'package:botler/core/api.dart';
import 'package:botler/features/auth/sign_in_screen.dart';
import 'package:botler/features/expense/expense_screen.dart';
import 'package:botler/core/auth.dart';
import 'package:botler/core/json.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer;

// -- FUNCTIONS -- //

/// The app's own routes, built the way the app builds them, with a person signed in or not.
class _Routed extends ConsumerStatefulWidget {
  const _Routed();

  @override
  ConsumerState<_Routed> createState() => _RoutedState();
}

class _RoutedState extends ConsumerState<_Routed> {
  late final GoRouter router = buildRouter(ref);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
  );
}

Future<ProviderContainer> start(
  WidgetTester tester, {
  required Session? session,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final server = RestoreServer();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(() => _Fixed(session)),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: server.client,
        ),
      ),
      syncProvider.overrideWith((ref) => Completer<Never>().future),
      balancesProvider.overrideWith(
        (ref) async => <Json>[
          <String, Object?>{'id': 'a1', 'name': 'Cash', 'balance': 1000},
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const _Routed()),
  );
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

class _Fixed extends SessionNotifier {
  _Fixed(this.session);

  final Session? session;

  @override
  Future<Session?> build() async => session;
}

void main() {
  testWidgets(
    'a pushed screen slides a little and fades, and only fades with animations off',
    (tester) async {
      for (final still in <bool>[false, true]) {
        final router = GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              pageBuilder: (_, state) => botlerPage(
                state,
                Scaffold(
                  body: Builder(
                    builder: (c) => TextButton(
                      onPressed: () => c.push('/next'),
                      child: const Text('go'),
                    ),
                  ),
                ),
                fadeOnly: true,
              ),
            ),
            GoRoute(
              path: '/next',
              pageBuilder: (_, state) =>
                  botlerPage(state, const Scaffold(body: Text('next page'))),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            theme: buildTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQueryData(disableAnimations: still),
              child: child!,
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('next page'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text('next page'),
            matching: find.byType(SlideTransition),
          ),
          still ? findsNothing : findsWidgets,
        );
        await tester.pumpAndSettle();
        expect(find.text('next page'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('go'), findsOneWidget);
      }
    },
  );

  testWidgets('with nobody signed in every route lands on the sign-in', (
    tester,
  ) async {
    await start(tester, session: null);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('the expense route still takes the values "fix this" passes', (
    tester,
  ) async {
    await start(
      tester,
      session: const Session(token: 't', email: 'a@b.c', name: 'A'),
    );
    final router = tester.state<_RoutedState>(find.byType(_Routed)).router;
    unawaited(
      router.push(
        '/expense',
        extra: <String, Object?>{'amount': '180', 'note': 'rice'},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ExpenseScreen), findsOneWidget);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller?.text)
        .toList();
    expect(fields, <String?>['180', 'rice']);
  });
}
