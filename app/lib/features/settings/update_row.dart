// THE APP VERSION ROW IN SETTINGS: THE BUILD THAT RUNS, WHAT THE LAST CHECK FOUND AND HOW MANY WRITES ARE STILL WAITING TO SYNC.
// Tapping it asks the server for a newer build; "Update now" appears when one is ready.

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
    final String status;
    if (u.phase == UpdatePhase.checking) {
      status = t.updRowChecking;
    } else if (u.phase == UpdatePhase.failed && u.failure != null) {
      status = updateFailureWords(t, u.failure!);
    } else if (offer != null) {
      status = t.updRowAvailable(offer.versionName);
    } else if (u.checkFailed) {
      status = t.updRowFailed;
    } else {
      status = t.updRowUpToDate;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Icon(Icons.system_update_alt, color: c.accentText),
      title: Text(t.updRowTitle),
      subtitle: Text(
        '${t.updRowLine(u.installedName, u.installedCode)}\n$status\n${pending == 0 ? t.updRowPendingNone : t.updRowPending(pending)}',
        style: TextStyle(color: c.muted),
      ),
      isThreeLine: true,
      trailing: offer != null && !u.busy
          ? FilledButton(
              onPressed: () => unawaited(notifier.start()),
              child: Text(t.updNow),
            )
          : null,
      onTap: u.busy ? null : () => unawaited(notifier.checkNow()),
    );
  }
}
