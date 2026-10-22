// THE UPDATE GATE, THE REQUIRED-UPDATE SCREEN AND THE OPTIONAL BANNER.
// The gate sits inside the app lock and shows the blocking screen only after the server said, in a good answer, that this build is too old.
// Offline, a server fault or a strange answer never blocks anything. After a failed attempt the screen offers a way back into the app for
// this start, so a broken update can never lock the person out of their own data.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/app_update.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../state/update.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// The plain words for why an update did not happen.
String updateFailureWords(AppLocalizations t, UpdateFailure f) => switch (f) {
  UpdateFailure.network => t.updFailNetwork,
  UpdateFailure.server => t.updFailServer,
  UpdateFailure.space => t.updFailSpace,
  UpdateFailure.damaged => t.updFailDamaged,
  UpdateFailure.wrongBuild => t.updFailWrongBuild,
  UpdateFailure.permission => t.updFailPermission,
  UpdateFailure.installer => t.updFailInstaller,
};

String _megabytes(int bytes) => (bytes / 1048576).round().toString();

class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Once per start, and again whenever somebody signs in
    ref.listenManual(sessionProvider.select((s) => s.value != null), (
      _,
      signedIn,
    ) {
      if (signedIn) unawaited(ref.read(updateProvider.notifier).checkOnStart());
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (ref.read(sessionProvider).value == null) return;
    unawaited(ref.read(updateProvider.notifier).onResumed());
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.value != null));
    final offer = ref.watch(updateProvider.select((u) => u.offer));
    final bypass = ref.watch(updateProvider.select((u) => u.bypass));
    if (signedIn && offer != null && offer.isRequired && !bypass) {
      return const UpdateRequiredScreen();
    }
    return widget.child;
  }
}

/// The blocking screen: one primary action, and in a failure the reason, a retry and a way back into the app.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.t;
    final u = ref.watch(updateProvider);
    final offer = u.offer;
    if (offer == null) return const SizedBox.shrink();
    final notifier = ref.read(updateProvider.notifier);
    final percent = (u.progress * 100).floor().clamp(0, 100);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.system_update_alt, size: 40, color: c.muted),
                  const SizedBox(height: 16),
                  Text(
                    t.updRequiredTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.updRequiredBody(
                      offer.versionName,
                      _megabytes(offer.size),
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                  const SizedBox(height: 24),
                  if (u.phase == UpdatePhase.downloading)
                    Semantics(
                      label: t.updDownloading(percent),
                      child: LinearProgressIndicator(value: u.progress),
                    )
                  else if (u.phase == UpdatePhase.verifying)
                    Text(t.updVerifying, style: TextStyle(color: c.muted))
                  else if (u.phase == UpdatePhase.installing)
                    Text(
                      t.updInstalling,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    )
                  else ...<Widget>[
                    if (u.phase == UpdatePhase.failed &&
                        u.failure != null) ...<Widget>[
                      Text(
                        updateFailureWords(t, u.failure!),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.danger),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: () => unawaited(notifier.start()),
                      child: Text(
                        u.phase == UpdatePhase.failed ? t.updRetry : t.updNow,
                      ),
                    ),
                    if (u.failure == UpdateFailure.permission)
                      TextButton(
                        onPressed: () =>
                            unawaited(notifier.openInstallSettings()),
                        child: Text(t.updOpenSettings),
                      ),
                    if (u.phase == UpdatePhase.failed)
                      TextButton(
                        onPressed: notifier.useAppForNow,
                        child: Text(t.updUseForNow),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The optional update, a quiet card at the top of the home screen. It disappears for the build the person dismissed.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.t;
    final u = ref.watch(updateProvider);
    final offer = u.offer;
    if (offer == null || offer.isRequired) return const SizedBox.shrink();
    final working =
        u.phase == UpdatePhase.downloading ||
        u.phase == UpdatePhase.verifying ||
        u.phase == UpdatePhase.installing;
    // Dismissed for this build: hidden, unless a download is running
    if (!working && u.dismissedCode == offer.versionCode) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(updateProvider.notifier);
    final percent = (u.progress * 100).floor().clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.system_update_alt, color: c.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.updBannerTitle(offer.versionName),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (u.phase == UpdatePhase.downloading)
                        Semantics(
                          label: t.updDownloading(percent),
                          child: LinearProgressIndicator(value: u.progress),
                        )
                      else if (u.phase == UpdatePhase.verifying)
                        Text(t.updVerifying, style: TextStyle(color: c.muted))
                      else if (u.phase == UpdatePhase.installing)
                        Text(t.updInstalling, style: TextStyle(color: c.muted))
                      else if (u.phase == UpdatePhase.failed &&
                          u.failure != null)
                        Text(
                          updateFailureWords(t, u.failure!),
                          style: TextStyle(color: c.danger),
                        )
                      else
                        Text(
                          t.updBannerSize(_megabytes(offer.size)),
                          style: TextStyle(color: c.muted),
                        ),
                    ],
                  ),
                ),
                if (!working)
                  IconButton(
                    tooltip: t.updDismiss,
                    icon: const Icon(Icons.close),
                    onPressed: () => unawaited(notifier.dismiss()),
                  ),
              ],
            ),
            // The actions sit under the text, so a narrow phone never squeezes the words
            if (!working)
              Wrap(
                alignment: WrapAlignment.end,
                children: <Widget>[
                  if (u.failure == UpdateFailure.permission)
                    TextButton(
                      onPressed: () =>
                          unawaited(notifier.openInstallSettings()),
                      child: Text(t.updOpenSettings),
                    ),
                  TextButton(
                    onPressed: () => unawaited(notifier.start()),
                    child: Text(
                      u.phase == UpdatePhase.failed ? t.updRetry : t.updNow,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
