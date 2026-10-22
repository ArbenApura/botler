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
import 'features/expense/expense_screen.dart';
import 'features/history/history_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/money/account_detail_screen.dart';
import 'features/money/accounts_screen.dart';
import 'features/money/bills_screen.dart';
import 'features/money/goals_screen.dart';
import 'features/payday/payday_screen.dart';
import 'features/settings/reset_screen.dart';
import 'features/settings/settings_screen.dart';
import 'state/providers.dart';
import 'theme/theme.dart';

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
      GoRoute(path: '/', builder: (_, _) => const ChatScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/menu', builder: (_, _) => const MenuScreen()),
      GoRoute(
        path: '/expense',
        builder: (_, state) {
          // "Fix this" in the history opens the form with the entry's values
          final extra = state.extra;
          final values = extra is Map<String, Object?>
              ? extra
              : const <String, Object?>{};
          return ExpenseScreen(
            amount: values['amount'] is String
                ? values['amount']! as String
                : null,
            note: values['note'] is String ? values['note']! as String : null,
          );
        },
      ),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/account/:id',
        builder: (_, state) =>
            AccountDetailScreen(accountId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(path: '/bills', builder: (_, _) => const BillsScreen()),
      GoRoute(path: '/goals', builder: (_, _) => const GoalsScreen()),
      GoRoute(path: '/payday', builder: (_, _) => const PaydayScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(path: '/agenda', builder: (_, _) => const AgendaScreen()),
      GoRoute(path: '/memory', builder: (_, _) => const MemoryScreen()),
      GoRoute(path: '/settings/reset', builder: (_, _) => const ResetScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
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
      }
    });
    if (ref.read(sessionProvider).value != null) {
      unawaited(ref.read(settingsProvider.notifier).pullFromServer());
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
        child: LockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
