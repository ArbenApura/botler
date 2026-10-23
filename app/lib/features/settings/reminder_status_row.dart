// THE REMINDER STATUS ROW IN SETTINGS: SHOWN ONLY WHEN SOMETHING STOPS REMINDERS FROM SHOWING (NOTIFICATIONS OFF, NO EXACT ALARMS, OR THE LAST
// ATTEMPT TO SET THEM FAILED). One action opens the system settings. It says nothing when all is well. It never shows a reminder's words.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/reminders.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- STATES -- //

final reminderHealthProvider = FutureProvider.autoDispose<ReminderHealth>(
  (ref) => readReminderHealth(ref.watch(prefsProvider)),
);

// -- FUNCTIONS -- //

class ReminderStatusRow extends ConsumerStatefulWidget {
  const ReminderStatusRow({super.key});

  @override
  ConsumerState<ReminderStatusRow> createState() => _ReminderStatusRowState();
}

class _ReminderStatusRowState extends ConsumerState<ReminderStatusRow>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the system settings: read the phone's state again, so the warning goes away once it is fixed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(reminderHealthProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final health = ref.watch(reminderHealthProvider).value;
    if (health == null || health.ok) return const SizedBox.shrink();
    final String words;
    if (!health.notificationsOn) {
      words = t.remBlockedNotifications;
    } else if (!health.exactOn) {
      words = t.remBlockedExact;
    } else {
      words = t.remBlockedFailed;
    }
    return PaperCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.notifications_off_outlined, color: c.warning),
          const SizedBox(width: 12),
          Expanded(child: Text(words)),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => unawaited(openReminderSettings()),
            child: Text(t.remFix),
          ),
        ],
      ),
    );
  }
}
