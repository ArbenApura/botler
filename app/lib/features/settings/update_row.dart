// THE APP VERSION ROW IN SETTINGS: THE BUILD THAT RUNS, WHAT THE LAST CHECK FOUND, THE RUNNING UPDATE AND HOW MANY WRITES ARE STILL WAITING TO SYNC.
// One primary action: "Update now" when a build is ready (or "Try again" after a failure), else a quiet "Check for updates".

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../state/update.dart';
import '../../theme/tokens.dart';
import '../update/update_gate.dart';

// -- FUNCTIONS -- //

class UpdateRow extends ConsumerWidget {
  const UpdateRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.t;
    final u = ref.watch(updateProvider);
    final pending = ref.watch(outboxCountProvider);
    final notifier = ref.read(updateProvider.notifier);
    final offer = u.offer;
    final working = updateWorking(u);
    final checking = u.phase == UpdatePhase.checking;
    final failed = u.phase == UpdatePhase.failed && u.failure != null;
    final bad = failed || (u.checkFailed && offer == null);
    final String status;
    if (checking) {
      status = t.updRowChecking;
    } else if (failed) {
      status = updateFailureWords(t, u.failure!);
    } else if (offer != null) {
      status = t.updRowAvailable(offer.versionName);
    } else if (u.checkFailed) {
      status = t.updRowFailed;
    } else {
      status = t.updRowUpToDate;
    }
    final IconData statusIcon = bad
        ? Icons.error_outline
        : offer != null
        ? Icons.new_releases_outlined
        : Icons.check_circle_outline;
    final Color statusColor = bad
        ? c.danger
        : offer != null
        ? c.accentText
        : c.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.system_update_alt, color: c.accentText),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.updRowTitle,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      t.updRowLine(u.installedName, u.installedCode),
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 8),
                    if (working)
                      UpdateProgressView(u: u)
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(right: 8, top: 2),
                            child: checking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    statusIcon,
                                    size: 18,
                                    color: statusColor,
                                  ),
                          ),
                          Expanded(
                            child: Text(
                              status,
                              style: TextStyle(color: bad ? c.danger : c.ink),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      pending == 0
                          ? t.updRowPendingNone
                          : t.updRowPending(pending),
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!working && !checking) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: offer != null
                  ? FilledButton(
                      onPressed: () => unawaited(notifier.start()),
                      child: Text(failed ? t.updRetry : t.updNow),
                    )
                  : OutlinedButton(
                      onPressed: () => unawaited(notifier.checkNow()),
                      child: Text(t.updCheckNow),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
