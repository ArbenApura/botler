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
import '../core/chat_photos.dart';
import '../core/config.dart';
import '../core/json.dart';
import '../core/outbox.dart';
import '../core/page_cache.dart';
import '../core/push.dart';

// -- TYPES -- //

/// What the person chose in Settings. Kept on the phone.
class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.lockOn = false,
    this.hideDetails = true,
    this.leadMinutes = 0,
    this.speechLocale = 'en_PH',
    this.currency = 'PHP',
    this.language = 'en',
    this.replyLanguage = 'auto',
    this.weekStartsOn = 1,
    this.showNetBalance = false,
    this.photoMode = 'text',
    this.photoVision = false,
    this.photoHost,
    this.modelProvider,
    this.modelProviderChoice,
    this.availableProviders = const <String>[],
  });

  final ThemeMode themeMode;

  /// Ask for a fingerprint or face to open the app.
  final bool lockOn;

  /// Notifications say "Botler reminder" and show nothing else (no names, no amounts).
  final bool hideDetails;

  /// Show a reminder this many minutes before the time the server gave.
  final int leadMinutes;
  final String speechLocale;

  /// The next four are the person's choices that the server keeps too (settings_get and settings_set), so the assistant knows them.
  /// The ISO code of the currency amounts are shown in.
  final String currency;

  /// The language of the app: en or fil.
  final String language;

  /// How the assistant replies: auto, en, fil or taglish.
  final String replyLanguage;

  /// The first day of the week: 0 is Sunday, 1 is Monday.
  final int weekStartsOn;

  /// Balances lead with the net (what is left after bills due before the next payday and money kept for goals), the balance counted smaller
  /// beneath. Display only: the server always sends both.
  final bool showNetBalance;

  /// What the assistant gets from a photo: 'image' (the picture itself) or 'text' (only what the phone read from it). Kept on the server too.
  /// Until the server has said, it is 'text': nothing leaves the phone as a picture on a guess.
  final String photoMode;

  /// The server says whether the AI server that will answer reads pictures. False until it says true (an older server never does), and never
  /// kept on the phone as a fact: a stale copy could upload pictures nobody will read.
  final bool photoVision;

  /// The AI server that will look at pictures: the person's own when it can, else another one the server has a key for. Null when none can.
  /// Not kept on the phone, like [photoVision].
  final String? photoHost;

  /// The pictures themselves go with a message: the person chose them AND the server has said its AI server reads them. Anything less, and only text goes.
  bool get usesPictures => photoMode == 'image' && photoVision;

  /// The AI server the assistant will use for this person, as the server says (null: not known yet, or the server has none set up).
  final String? modelProvider;

  /// What the person chose; null means the server default. It can name a server that is no longer available.
  final String? modelProviderChoice;

  /// The servers a person may choose from, by id. Empty from an older server or before the first pull.
  final List<String> availableProviders;

  /// [modelProvider] and [modelProviderChoice] can be set back to null, so they take Object? and the default keeps the old value.
  Settings copyWith({
    ThemeMode? themeMode,
    bool? lockOn,
    bool? hideDetails,
    int? leadMinutes,
    String? speechLocale,
    String? currency,
    String? language,
    String? replyLanguage,
    int? weekStartsOn,
    bool? showNetBalance,
    String? photoMode,
    bool? photoVision,
    Object? photoHost = _keep,
    Object? modelProvider = _keep,
    Object? modelProviderChoice = _keep,
    List<String>? availableProviders,
  }) => Settings(
    themeMode: themeMode ?? this.themeMode,
    lockOn: lockOn ?? this.lockOn,
    hideDetails: hideDetails ?? this.hideDetails,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    speechLocale: speechLocale ?? this.speechLocale,
    currency: currency ?? this.currency,
    language: language ?? this.language,
    replyLanguage: replyLanguage ?? this.replyLanguage,
    weekStartsOn: weekStartsOn ?? this.weekStartsOn,
    showNetBalance: showNetBalance ?? this.showNetBalance,
    photoMode: photoMode ?? this.photoMode,
    photoVision: photoVision ?? this.photoVision,
    photoHost: identical(photoHost, _keep)
        ? this.photoHost
        : photoHost as String?,
    modelProvider: identical(modelProvider, _keep)
        ? this.modelProvider
        : modelProvider as String?,
    modelProviderChoice: identical(modelProviderChoice, _keep)
        ? this.modelProviderChoice
        : modelProviderChoice as String?,
    availableProviders: availableProviders ?? this.availableProviders,
  );
}

/// Marks "leave this field as it is" in copyWith, for the fields that may also be set to null.
const Object _keep = Object();

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

/// The photos of sent messages, kept on this phone for the signed-in person only. Tests override it with a temporary folder.
final Provider<ChatPhotoStore> chatPhotoStoreProvider =
    Provider<ChatPhotoStore>(
      (ref) => ChatPhotoStore(
        prefs: ref.watch(prefsProvider),
        owner: ref.watch(sessionProvider).value?.email ?? 'local',
      ),
    );

/// The seam to Firebase. Tests override it.
final Provider<PushHost> pushHostProvider = Provider<PushHost>(
  (ref) => const FirebasePushHost(),
);

final Provider<PushService> pushServiceProvider = Provider<PushService>(
  (ref) => PushService(
    host: ref.watch(pushHostProvider),
    api: ref.watch(apiProvider),
    prefs: ref.watch(prefsProvider),
  ),
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
    // The server forgets this phone first: the call needs the session that is cleared next
    try {
      await ref
          .read(pushServiceProvider)
          .unregister()
          .timeout(const Duration(seconds: 8));
    } on Exception {
      // Push is optional: signing out never waits on it
    }
    // The next person on this phone must not find these photos
    try {
      await ref.read(chatPhotoStoreProvider).wipe();
    } on Object {
      // Signing out never waits on the photo folder
    }
    // Nor the notebook pages kept for reading offline
    try {
      await PageCache(ref.read(prefsProvider)).wipe();
    } on Object {
      // Signing out never waits on the saved pages
    }
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
const String _currency = 'settings.currency';
const String _language = 'settings.language';
const String _reply = 'settings.reply';
const String _week = 'settings.week';
const String _showNet = 'settings.showNet';
const String _photoMode = 'settings.photoMode';
const String _provider = 'settings.provider';
const String _providerChoice = 'settings.providerChoice';
const String _providers = 'settings.providers';

/// The text of a server id from the answer, or null when it is missing or not text.
String? _providerId(Object? v) => v is String && v.isNotEmpty ? v : null;

/// 'image' or 'text'; anything else (an older server sends nothing) keeps what the phone has.
String _photoModeId(Object? v, String keep) =>
    v is String && (v == 'image' || v == 'text') ? v : keep;

/// The server ids from the answer. A missing field or a wrong type is an empty list, so an older server cannot break the screen.
List<String> _providerIds(Object? v) => <String>[
  for (final e in asList(v))
    if (e is String && e.isNotEmpty) e,
];

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
  currency: p.getString(_currency) ?? 'PHP',
  language: p.getString(_language) ?? 'en',
  replyLanguage: p.getString(_reply) ?? 'auto',
  weekStartsOn: p.getInt(_week) ?? 1,
  showNetBalance: p.getBool(_showNet) ?? false,
  photoMode: p.getString(_photoMode) == 'image' ? 'image' : 'text',
  modelProvider: p.getString(_provider),
  modelProviderChoice: p.getString(_providerChoice),
  availableProviders: p.getStringList(_providers) ?? const <String>[],
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
    await p.setString(_currency, next.currency);
    await p.setString(_language, next.language);
    await p.setString(_reply, next.replyLanguage);
    await p.setInt(_week, next.weekStartsOn);
    await p.setBool(_showNet, next.showNetBalance);
    await p.setString(_photoMode, next.photoMode);
    await _setOrRemove(p, _provider, next.modelProvider);
    await _setOrRemove(p, _providerChoice, next.modelProviderChoice);
    await p.setStringList(_providers, next.availableProviders);
  }

  Future<void> _setOrRemove(SharedPreferences p, String key, String? value) =>
      value == null ? p.remove(key) : p.setString(key, value);

  /// Takes what the server has for the four shared choices, so a second phone or a reinstall shows the same ones. Offline, nothing changes.
  Future<void> pullFromServer() async {
    try {
      final s = await ref.read(apiProvider).verbJson('settings_get');
      await update(
        state.copyWith(
          currency: str(s['currency'], state.currency),
          language: str(s['language'], state.language),
          replyLanguage: str(s['replyLanguage'], state.replyLanguage),
          weekStartsOn: intOf(s['weekStartsOn'], state.weekStartsOn),
          // An older server has no such field: keep what the phone has
          showNetBalance: boolOf(s['showNetBalance'], state.showNetBalance),
          photoMode: _photoModeId(s['photoMode'], state.photoMode),
          // An older server has no such field: nothing is read as pictures
          photoVision: boolOf(s['photoVision'], false),
          photoHost: _providerId(s['photoHost']),
          modelProvider: _providerId(s['modelProvider']),
          modelProviderChoice: _providerId(s['modelProviderChoice']),
          availableProviders: _providerIds(s['availableProviders']),
        ),
      );
    } on ApiException {
      // Keep the stored values: the app starts in the right language and currency without a connection
    }
  }

  /// Saves a change of the shared choices on the server first, then here. Returns the server's notice (for a change of currency) or null.
  /// Throws ApiException when it cannot be saved, so the screen can say so and keep the old value.
  Future<String?> saveToServer({
    String? currency,
    String? language,
    String? replyLanguage,
    int? weekStartsOn,
    bool? showNetBalance,
    String? photoMode,
    String? modelProvider,
  }) async {
    final changes = <String, Object?>{
      'currency': ?currency,
      'language': ?language,
      'replyLanguage': ?replyLanguage,
      'weekStartsOn': ?weekStartsOn,
      'showNetBalance': ?showNetBalance,
      'photoMode': ?photoMode,
      'modelProvider': ?modelProvider,
    };
    final answer = await ref
        .read(apiProvider)
        .verbJson('settings_set', changes);
    final saved = asJson(answer['settings']);
    await update(
      state.copyWith(
        currency: str(saved['currency'], state.currency),
        language: str(saved['language'], state.language),
        replyLanguage: str(saved['replyLanguage'], state.replyLanguage),
        weekStartsOn: intOf(saved['weekStartsOn'], state.weekStartsOn),
        showNetBalance: boolOf(saved['showNetBalance'], state.showNetBalance),
        photoMode: _photoModeId(saved['photoMode'], state.photoMode),
        photoVision: boolOf(saved['photoVision'], state.photoVision),
        photoHost: _providerId(saved['photoHost']),
        modelProvider: _providerId(saved['modelProvider']),
        modelProviderChoice: _providerId(saved['modelProviderChoice']),
        availableProviders: _providerIds(saved['availableProviders']),
        // The voice follows the app's language unless the person chose another
        speechLocale: language == null
            ? state.speechLocale
            : (language == 'fil' ? 'fil_PH' : 'en_PH'),
      ),
    );
    final notice = answer['notice'];
    return notice is String ? notice : null;
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

/// Everything the person has, every wallet converted to the main currency (assets_summary), with the rates used and their date. Without a
/// connection the last answer that worked is shown, marked offline, so the total is never empty on a train.
final FutureProvider<Json> assetsProvider = FutureProvider.autoDispose<Json>((
  ref,
) async {
  final prefs = ref.watch(prefsProvider);
  try {
    final answer = await ref.watch(apiProvider).verbJson('assets_summary');
    await prefs.setString('assets.cache', jsonEncode(answer));
    return answer;
  } on ApiException catch (e) {
    final cached = prefs.getString('assets.cache');
    if (e.isNetwork && cached != null) {
      return <String, Object?>{...decodeJson(cached), 'offline': true};
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
