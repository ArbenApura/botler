// THE APP SHELL: THEME, ROUTES, THE SIGN-IN GATE AND THE APP LOCK. THE LINK botler://quickadd (FROM THE HOME SCREEN WIDGET) OPENS THE EXPENSE BOX.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import 'core/money_scope.dart';
import 'l10n/l10n.dart';
import 'core/reminders.dart';
import 'features/agenda/agenda_screen.dart';
import 'features/auth/lock_gate.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_state.dart';
import 'features/expense/expense_screen.dart';
import 'features/history/history_screen.dart';
import 'features/notebooks/library_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/money/account_detail_screen.dart';
import 'features/money/accounts_screen.dart';
import 'features/money/bills_screen.dart';
import 'features/money/goals_screen.dart';
import 'features/payday/payday_screen.dart';
import 'features/settings/reset_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/toolbox_screen.dart';
import 'features/simulate/simulate_screen.dart';
import 'features/update/update_gate.dart';
import 'state/providers.dart';
import 'theme/theme.dart';
import 'ui/transitions.dart';

// -- FUNCTIONS -- //

GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // The widget opens botler://quickadd: the host is "quickadd"
      if (state.uri.host == 'quickadd') return '/expense';
      final session = ref.read(sessionProvider);
      final signedIn = session.value != null;
      if (!signedIn && state.matchedLocation != '/sign-in') return '/sign-in';
      if (signedIn && state.matchedLocation == '/sign-in') return '/';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        pageBuilder: (_, state) =>
            botlerPage(state, const ChatScreen(), fadeOnly: true),
      ),
      GoRoute(
        path: '/sign-in',
        pageBuilder: (_, state) =>
            botlerPage(state, const SignInScreen(), fadeOnly: true),
      ),
      GoRoute(
        path: '/menu',
        pageBuilder: (_, state) => botlerPage(state, const MenuScreen()),
      ),
      GoRoute(
        path: '/expense',
        pageBuilder: (_, state) {
          // "Fix this" in the history opens the form with the entry's values
          final extra = state.extra;
          final values = extra is Map<String, Object?>
              ? extra
              : const <String, Object?>{};
          return botlerPage(
            state,
            ExpenseScreen(
              amount: values['amount'] is String
                  ? values['amount']! as String
                  : null,
              note: values['note'] is String ? values['note']! as String : null,
              currency: values['currency'] is String
                  ? values['currency']! as String
                  : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/accounts',
        pageBuilder: (_, state) => botlerPage(state, const AccountsScreen()),
      ),
      GoRoute(
        path: '/account/:id',
        pageBuilder: (_, state) => botlerPage(
          state,
          AccountDetailScreen(accountId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/bills',
        pageBuilder: (_, state) => botlerPage(state, const BillsScreen()),
      ),
      GoRoute(
        path: '/goals',
        pageBuilder: (_, state) => botlerPage(state, const GoalsScreen()),
      ),
      GoRoute(
        path: '/payday',
        pageBuilder: (_, state) => botlerPage(state, const PaydayScreen()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (_, state) => botlerPage(state, const HistoryScreen()),
      ),
      GoRoute(
        path: '/calendar',
        pageBuilder: (_, state) => botlerPage(state, const CalendarScreen()),
      ),
      GoRoute(
        path: '/simulate',
        pageBuilder: (_, state) => botlerPage(
          state,
          SimulateScreen(initialDate: state.uri.queryParameters['date']),
        ),
      ),
      GoRoute(
        path: '/agenda',
        pageBuilder: (_, state) => botlerPage(state, const AgendaScreen()),
      ),
      GoRoute(
        path: '/memory',
        pageBuilder: (_, state) => botlerPage(state, const LibraryScreen()),
      ),
      GoRoute(
        path: '/settings/reset',
        pageBuilder: (_, state) => botlerPage(state, const ResetScreen()),
      ),
      GoRoute(
        path: '/settings/toolbox',
        pageBuilder: (_, state) => botlerPage(state, const ToolboxScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, state) => botlerPage(state, const SettingsScreen()),
      ),
    ],
  );
}

class BotlerApp extends ConsumerStatefulWidget {
  const BotlerApp({super.key});

  @override
  ConsumerState<BotlerApp> createState() => _BotlerAppState();
}

class _BotlerAppState extends ConsumerState<BotlerApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(ref);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-evaluate the redirect when the session changes (signing in or out)
    ref.listenManual(sessionProvider, (_, next) {
      _router.refresh();
      // Signed in: take the currency and languages the server has
      if (next.value != null) {
        unawaited(ref.read(settingsProvider.notifier).pullFromServer());
        unawaited(ref.read(pushServiceProvider).register());
      }
    });
    // A silent push while the app is open: send what waits and bring the alarms in line, like coming back to the front
    ref.read(pushServiceProvider).onSync = () {
      ref.invalidate(syncProvider);
      unawaited(flushAndSync(ref.container));
    };
    if (ref.read(sessionProvider).value != null) {
      unawaited(ref.read(settingsProvider.notifier).pullFromServer());
      unawaited(ref.read(pushServiceProvider).register());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the app comes back to the front: send what was waiting, and bring the alarms in line with the server.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (ref.read(sessionProvider).value == null) return;
    ref.invalidate(syncProvider);
    unawaited(flushAndSync(ref.container));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // A different person signing in must never see the last person's conversation, nor skip loading their own
    ref.listen<String?>(sessionProvider.select((s) => s.value?.email), (
      prev,
      next,
    ) {
      if (prev != next) ref.invalidate(chatProvider);
    });
    return MaterialApp.router(
      title: 'Botler',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: Locale(settings.language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
      builder: (context, child) => MoneyScope(
        currency: settings.currency,
        child: LockGate(
          child: UpdateGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
