// THE APP SHELL: THEME, ROUTES, THE SIGN-IN GATE AND THE APP LOCK. THE LINK botler://quickadd (FROM THE HOME SCREEN WIDGET) OPENS THE EXPENSE BOX.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import 'core/clock.dart';
import 'core/clock_picker_l10n.dart';
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
import 'core/json.dart';
import 'core/script/device_tools.dart';
import 'features/health/availability_screen.dart';
import 'features/health/barcode_screen.dart';
import 'features/health/camera_screen.dart';
import 'features/health/meal_detail_screen.dart';
import 'features/health/reading_screen.dart';
import 'features/health/review_screen.dart';
import 'features/health/health_home_screen.dart';
import 'features/health/health_setup_screen.dart';
import 'features/health/session_screen.dart';
import 'features/health/sleep_screen.dart';
import 'features/health/train_screen.dart';
import 'features/health/week_plan_screen.dart';
import 'features/health/weight_screen.dart';
import 'features/health/today_screen.dart';
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
        path: '/health',
        pageBuilder: (_, state) => botlerPage(state, const HealthHomeScreen()),
      ),
      GoRoute(
        path: '/health/setup',
        pageBuilder: (_, state) => botlerPage(state, const HealthSetupScreen()),
      ),
      GoRoute(
        path: '/health/week',
        pageBuilder: (_, state) =>
            botlerPage(state, const AvailabilityScreen()),
      ),
      GoRoute(
        path: '/health/today',
        pageBuilder: (_, state) => botlerPage(state, const TodayScreen()),
      ),
      GoRoute(
        path: '/health/meal/:meal',
        pageBuilder: (_, state) => botlerPage(
          state,
          MealDetailScreen(meal: state.pathParameters['meal'] ?? 'snack'),
        ),
      ),
      GoRoute(
        path: '/health/nutrients',
        pageBuilder: (_, state) => botlerPage(state, const NutrientsScreen()),
      ),
      GoRoute(
        path: '/health/camera',
        pageBuilder: (_, state) => botlerPage(
          state,
          FoodCameraScreen(
            mode: state.uri.queryParameters['mode'] ?? 'meal',
            barcode: state.uri.queryParameters['barcode'],
          ),
        ),
      ),
      GoRoute(
        path: '/health/reading',
        pageBuilder: (_, state) {
          final e = asJson(state.extra);
          return botlerPage(
            state,
            ReadingScreen(
              mode: str(e['mode'], 'meal'),
              paths: <String>[
                for (final p in asList(e['paths']))
                  if (p is String) p,
              ],
              barcode: e['barcode'] is String ? str(e['barcode']) : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/health/review',
        pageBuilder: (_, state) {
          final e = asJson(state.extra);
          return botlerPage(
            state,
            MealReviewScreen(
              actionId: str(e['actionId']),
              args: asJson(e['args']),
              note: e['note'] is String ? str(e['note']) : null,
              photo: e['photo'] is String ? str(e['photo']) : null,
              mode: str(e['mode'], 'meal'),
            ),
          );
        },
      ),
      GoRoute(
        path: '/health/weight',
        pageBuilder: (_, state) => botlerPage(state, const WeightScreen()),
      ),
      GoRoute(
        path: '/health/train',
        pageBuilder: (_, state) => botlerPage(state, const TrainScreen()),
      ),
      GoRoute(
        path: '/health/train/session',
        pageBuilder: (_, state) {
          final e = asJson(state.extra);
          return botlerPage(
            state,
            SessionScreen(
              plannedId: e['plannedId'] is String ? str(e['plannedId']) : null,
              templateKey: e['templateKey'] is String
                  ? str(e['templateKey'])
                  : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/health/train/week',
        pageBuilder: (_, state) => botlerPage(state, const WeekPlanScreen()),
      ),
      GoRoute(
        path: '/health/sleep',
        pageBuilder: (_, state) => botlerPage(state, const SleepScreen()),
      ),
      GoRoute(
        path: '/health/barcode',
        pageBuilder: (_, state) => botlerPage(
          state,
          BarcodeResultScreen(code: str(asJson(state.extra)['code'])),
        ),
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

  void _openHealth() {
    final path = healthOpenSignal.value;
    if (path == null) return;
    healthOpenSignal.value = null;
    unawaited(_router.push(path));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The assistant asked to open a Health screen or the food camera
    healthOpenSignal.addListener(_openHealth);
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
    // A change of zone, clock or date order must reach screens that are already built: they read the clock choices from one place and do not watch them
    ref.listen<ClockPrefs>(
      settingsProvider.select(
        (s) => ClockPrefs(
          zone: s.timeZone,
          timeFormat: s.timeFormat,
          dateStyle: s.dateStyle,
          language: s.language,
        ),
      ),
      (prev, next) {
        if (prev == null || prev == next) return;
        void rebuild(Element el) {
          el.markNeedsBuild();
          el.visitChildren(rebuild);
        }

        (context as Element).visitChildren(rebuild);
        // The reminders and the day's data are worked out again for the new day
        ref.invalidate(syncProvider);
      },
    );
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
      // The date pickers come first, so they write a date in the person's order and not the language's
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        ClockMaterialDelegate(
          ClockPrefs(
            zone: settings.timeZone,
            timeFormat: settings.timeFormat,
            dateStyle: settings.dateStyle,
            language: settings.language,
          ),
        ),
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
      builder: (context, child) => MediaQuery(
        // A very large system font would bloat every screen: text follows the phone's setting up to this much and no further
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: 1, maxScaleFactor: maxTextScale),
          // The time pickers follow the person's 12 or 24 hour choice; on auto they follow the phone
          alwaysUse24HourFormat: switch (settings.timeFormat) {
            '24' => true,
            '12' => false,
            _ => MediaQuery.of(context).alwaysUse24HourFormat,
          },
        ),
        child: MoneyScope(
          currency: settings.currency,
          child: LockGate(
            child: UpdateGate(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
