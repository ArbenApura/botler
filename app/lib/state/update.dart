// THE APP UPDATE STATE (RIVERPOD): WHAT IS OFFERED, WHERE THE DOWNLOAD IS AND WHY IT FAILED. THE RULES LIVE IN core/app_update.dart.
// A check only runs for a signed in person. A failed check is quiet (the app keeps working offline); only a good answer from the server
// can ever make the blocking screen appear.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/app_update.dart';
import '../core/reminders.dart';
import 'providers.dart';

// -- TYPES -- //

enum UpdatePhase { idle, checking, downloading, verifying, installing, failed }

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.offer,
    this.progress = 0,
    this.failure,
    this.bypass = false,
    this.dismissedCode = 0,
    this.checkFailed = false,
    this.checkedOnce = false,
    this.installedName = '',
    this.installedCode = 0,
  });

  final UpdatePhase phase;
  final UpdateOffer? offer;

  /// 0..1 while downloading.
  final double progress;
  final UpdateFailure? failure;

  /// The person chose "use the app for now" after a failed required update. Until the next start.
  final bool bypass;

  /// The offer the person dismissed in the banner.
  final int dismissedCode;
  final bool checkFailed;
  final bool checkedOnce;
  final String installedName;
  final int installedCode;

  bool get busy =>
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.verifying ||
      phase == UpdatePhase.installing ||
      phase == UpdatePhase.checking;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateOffer? offer,
    bool clearOffer = false,
    double? progress,
    UpdateFailure? failure,
    bool clearFailure = false,
    bool? bypass,
    int? dismissedCode,
    bool? checkFailed,
    bool? checkedOnce,
    String? installedName,
    int? installedCode,
  }) => UpdateState(
    phase: phase ?? this.phase,
    offer: clearOffer ? null : (offer ?? this.offer),
    progress: progress ?? this.progress,
    failure: clearFailure ? null : (failure ?? this.failure),
    bypass: bypass ?? this.bypass,
    dismissedCode: dismissedCode ?? this.dismissedCode,
    checkFailed: checkFailed ?? this.checkFailed,
    checkedOnce: checkedOnce ?? this.checkedOnce,
    installedName: installedName ?? this.installedName,
    installedCode: installedCode ?? this.installedCode,
  );
}

// -- CONSTANTS -- //

/// The seam to Android. Tests override it.
final Provider<UpdateHost> updateHostProvider = Provider<UpdateHost>(
  (ref) => const MethodChannelUpdateHost(),
);

final Provider<AppUpdater> appUpdaterProvider = Provider<AppUpdater>(
  (ref) => AppUpdater(
    api: ref.watch(apiProvider),
    host: ref.watch(updateHostProvider),
    prefs: ref.watch(prefsProvider),
  ),
);

// -- NOTIFIER -- //

class UpdateNotifier extends Notifier<UpdateState> {
  // -- STATES -- //

  /// A downloaded file that passed every check and is waiting for the installer (kept so "try again" does not download it twice).
  String? _readyPath;
  bool _started = false;

  /// An update is running (set before the first await, so two taps can never start two).
  bool _running = false;

  @override
  UpdateState build() =>
      UpdateState(dismissedCode: ref.read(appUpdaterProvider).dismissedCode);

  // -- FUNCTIONS -- //

  /// Runs once per start of the app (and is not repeated by a later sign in): removes old downloads, learns the installed build and asks the server.
  Future<void> checkOnStart() async {
    if (_started) return;
    _started = true;
    final updater = ref.read(appUpdaterProvider);
    await updater.sweep();
    await _learnInstalled();
    // A start always asks (one small request), so a required update that was not installed shows again at once
    await _check(force: true);
  }

  /// The app came back to the front: asks again only when 12 hours have passed since the last good answer.
  Future<void> checkIfDue() => _check(force: false);

  /// The Settings button: always asks.
  Future<void> checkNow() async {
    await _learnInstalled();
    await _check(force: true);
  }

  Future<void> _learnInstalled() async {
    try {
      final host = ref.read(updateHostProvider);
      state = state.copyWith(
        installedCode: await host.installedCode(),
        installedName: await host.installedName(),
      );
    } on Exception {
      // The build is shown as unknown; checks then fail quietly
    }
  }

  Future<void> _check({required bool force}) async {
    if (state.busy || _running) return;
    final updater = ref.read(appUpdaterProvider);
    // A check that is not due touches nothing: a failure on screen, or a known offer, stays as it is
    if (!updater.isDue(force: force)) return;
    // A quiet check never replaces the reason of a failed update; only the person asking (the Settings button) does
    if (!force && state.phase != UpdatePhase.idle) return;
    state = state.copyWith(phase: UpdatePhase.checking);
    final offer = await updater.check(force: force);
    // Whatever started meanwhile (a download) keeps its own phase
    if (state.phase != UpdatePhase.checking) return;
    final failed = updater.lastCheckFailed;
    state = state.copyWith(
      phase: UpdatePhase.idle,
      offer: offer,
      // A good answer of "nothing newer" clears the offer; a failed check keeps what was known
      clearOffer: offer == null && !failed,
      clearFailure: true,
      checkFailed: failed,
      checkedOnce: true,
    );
  }

  /// Dismisses the banner for this build only. A later build shows it again.
  Future<void> dismiss() async {
    final offer = state.offer;
    if (offer == null || offer.isRequired) return;
    await ref.read(appUpdaterProvider).dismiss(offer.versionCode);
    state = state.copyWith(dismissedCode: offer.versionCode);
  }

  /// After a failed required update: back to the app for this start, so a broken update can never lock the person out.
  void useAppForNow() {
    if (state.phase == UpdatePhase.failed) {
      state = state.copyWith(bypass: true);
    }
  }

  Future<void> openInstallSettings() =>
      ref.read(updateHostProvider).openInstallSettings();

  /// The person tapped Update: allowed to install, download, check, flush what is waiting, then open Android's installer.
  Future<void> start() async {
    final offer = state.offer;
    if (offer == null || state.busy || _running) return;
    _running = true;
    final updater = ref.read(appUpdaterProvider);
    final host = ref.read(updateHostProvider);
    try {
      // Ask about the permission first, so a 100 MB download is not wasted on a phone that will refuse the install
      if (!await host.canInstall()) {
        state = state.copyWith(
          phase: UpdatePhase.failed,
          failure: UpdateFailure.permission,
        );
        return;
      }
      var path = _readyPath;
      if (path == null ||
          !File(path).existsSync() ||
          await host.archiveCheck(path, offer.versionCode) != 'ok') {
        _readyPath = null;
        state = state.copyWith(
          phase: UpdatePhase.downloading,
          progress: 0,
          clearFailure: true,
        );
        var shown = -1;
        path = await updater.download(
          offer,
          (p) {
            // Whole percents only, so the screen is not rebuilt for every chunk
            final pct = (p * 100).floor();
            if (pct == shown) return;
            shown = pct;
            state = state.copyWith(progress: p);
          },
          verifying: () => state = state.copyWith(phase: UpdatePhase.verifying),
        );
        _readyPath = path;
      }
      // What is waiting goes out first: the installer ends the app
      try {
        await flushAndSync(ref.container);
      } on Exception {
        // Offline: the outbox is kept on the phone and survives the update
      }
      state = state.copyWith(phase: UpdatePhase.installing, clearFailure: true);
      await updater.install(path);
    } on UpdateException catch (e) {
      state = state.copyWith(phase: UpdatePhase.failed, failure: e.failure);
    } on Object {
      // Any other failure (a platform error from Android, a file error) must never leave the screen stuck in a busy phase
      state = state.copyWith(
        phase: UpdatePhase.failed,
        failure: UpdateFailure.installer,
      );
    } finally {
      _running = false;
    }
  }

  /// The app is back in front. If the installer was open and this build is still the one running, the update did not happen.
  Future<void> onResumed() async {
    if (state.phase != UpdatePhase.installing) {
      await checkIfDue();
      return;
    }
    try {
      final now = await ref.read(updateHostProvider).installedCode();
      final offer = state.offer;
      if (offer != null && now >= offer.versionCode) {
        // Installed after all (the process normally ends first)
        state = state.copyWith(phase: UpdatePhase.idle, clearOffer: true);
        return;
      }
    } on Exception {
      // Treated as not finished
    }
    state = state.copyWith(
      phase: UpdatePhase.failed,
      failure: UpdateFailure.installer,
    );
  }
}

final NotifierProvider<UpdateNotifier, UpdateState> updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
