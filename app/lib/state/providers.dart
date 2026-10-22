// THE APP'S SHARED STATE (RIVERPOD): THE SESSION, THE SERVER CLIENT, THE OUTBOX, THE SETTINGS AND THE LISTS EVERY SCREEN READS.
// Business rules are not here and not in widgets: they live on the server and the screens call them through the client.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/json.dart';
import '../core/outbox.dart';

// -- TYPES -- //

/// What the person chose in Settings. Kept on the phone.
class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.lockOn = false,
    this.hideDetails = true,
    this.leadMinutes = 0,
    this.speechLocale = 'en_PH',
  });

  final ThemeMode themeMode;

  /// Ask for a fingerprint or face to open the app.
  final bool lockOn;

  /// Notifications say "Botler reminder" and show nothing else (no names, no amounts).
  final bool hideDetails;

  /// Show a reminder this many minutes before the time the server gave.
  final int leadMinutes;
  final String speechLocale;

  Settings copyWith({
    ThemeMode? themeMode,
    bool? lockOn,
    bool? hideDetails,
    int? leadMinutes,
    String? speechLocale,
  }) => Settings(
    themeMode: themeMode ?? this.themeMode,
    lockOn: lockOn ?? this.lockOn,
    hideDetails: hideDetails ?? this.hideDetails,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    speechLocale: speechLocale ?? this.speechLocale,
  );
}

// -- CONSTANTS -- //

/// The preferences, read once at start in main() and given here.
final Provider<SharedPreferences> prefsProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('prefsProvider must be overridden in main()'),
);

final Provider<SessionStore> sessionStoreProvider = Provider<SessionStore>(
  (ref) => const SecureSessionStore(),
);

final Provider<ApiClient> apiProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final api = ApiClient(
    base: apiBase,
    token: () async => (await store.read())?.token,
  );
  ref.onDispose(api.close);
  return api;
});

final Provider<Outbox> outboxProvider = Provider<Outbox>(
  (ref) => Outbox(ref.watch(prefsProvider)),
);

// -- SESSION -- //

class SessionNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.watch(sessionStoreProvider).read();

  Future<void> signIn() async {
    state = const AsyncLoading<Session?>();
    state = await AsyncValue.guard(() async {
      final idToken = await googleIdToken();
      final session = await exchangeIdToken(idToken, base: apiBase);
      await ref.read(sessionStoreProvider).write(session);
      return session;
    });
  }

  Future<void> signOut() async {
    await ref.read(sessionStoreProvider).clear();
    state = const AsyncData<Session?>(null);
  }
}

final AsyncNotifierProvider<SessionNotifier, Session?> sessionProvider =
    AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

// -- SETTINGS -- //

const String _theme = 'settings.theme';
const String _lock = 'settings.lock';
const String _hide = 'settings.hide';
const String _lead = 'settings.lead';
const String _locale = 'settings.locale';

/// The settings as stored. Also read by the background sync, which has no providers.
Settings readSettings(SharedPreferences p) => Settings(
  themeMode: ThemeMode.values.firstWhere(
    (m) => m.name == p.getString(_theme),
    orElse: () => ThemeMode.system,
  ),
  lockOn: p.getBool(_lock) ?? false,
  hideDetails: p.getBool(_hide) ?? true,
  leadMinutes: p.getInt(_lead) ?? 0,
  speechLocale: p.getString(_locale) ?? 'en_PH',
);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => readSettings(ref.watch(prefsProvider));

  Future<void> update(Settings next) async {
    final p = ref.read(prefsProvider);
    state = next;
    await p.setString(_theme, next.themeMode.name);
    await p.setBool(_lock, next.lockOn);
    await p.setBool(_hide, next.hideDetails);
    await p.setInt(_lead, next.leadMinutes);
    await p.setString(_locale, next.speechLocale);
  }
}

final NotifierProvider<SettingsNotifier, Settings> settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

// -- LISTS THE SCREENS SHARE -- //

/// The accounts with their balances now. Without a connection, the last list that worked (so an expense can still be written down).
final FutureProvider<List<Json>> balancesProvider =
    FutureProvider.autoDispose<List<Json>>((ref) async {
      final prefs = ref.watch(prefsProvider);
      try {
        final list = await ref.watch(apiProvider).verbList('accounts_balances');
        await prefs.setString('accounts.cache', jsonEncode(list));
        return list;
      } on ApiException catch (e) {
        final cached = prefs.getString('accounts.cache');
        if (e.isNetwork && cached != null) {
          final decoded = jsonDecode(cached);
          return asJsonList(decoded);
        }
        rethrow;
      }
    });

/// The home screen summary card and the calendar state, straight from the sync answer. Without a connection the last answer that
/// worked is shown, marked offline, so the card is never empty on a train.
final FutureProvider<Json> syncProvider = FutureProvider.autoDispose<Json>((
  ref,
) async {
  final prefs = ref.watch(prefsProvider);
  try {
    final answer = await ref.watch(apiProvider).sync();
    await prefs.setString('summary.cache', jsonEncode(answer));
    return answer;
  } on ApiException catch (e) {
    final cached = prefs.getString('summary.cache');
    if (e.isNetwork && cached != null)
      return <String, Object?>{...decodeJson(cached), 'offline': true};
    rethrow;
  }
});

/// Writes that are waiting for a connection.
final NotifierProvider<OutboxCount, int> outboxCountProvider =
    NotifierProvider<OutboxCount, int>(OutboxCount.new);

class OutboxCount extends Notifier<int> {
  @override
  int build() => ref.watch(outboxProvider).length;

  void refresh() => state = ref.read(outboxProvider).length;
}
