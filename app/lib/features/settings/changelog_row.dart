// THE "WHAT IS NEW IN THIS VERSION" ROW IN SETTINGS: REOPENS THE NOTES OF THE BUILD THAT RUNS. HIDDEN WHEN THAT BUILD HAS NO ENTRY.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/changelog.dart';
import '../../l10n/l10n.dart';
import '../../state/changelog.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../update/changelog_sheet.dart';

// -- FUNCTIONS -- //

class ChangelogRow extends ConsumerWidget {
  const ChangelogRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(installedChangelogProvider).value;
    if (entry == null) return const SizedBox.shrink();
    final c = context.colors;
    final t = context.t;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Icon(Icons.new_releases_outlined, color: c.accentText),
      title: Text(t.changelogRowTitle),
      subtitle: Text(t.changelogRowHint, style: TextStyle(color: c.muted)),
      onTap: () => unawaited(
        showChangelogSheet(context, <ChangelogEntry>[
          entry,
        ], ref.read(settingsProvider).language),
      ),
    );
  }
}
