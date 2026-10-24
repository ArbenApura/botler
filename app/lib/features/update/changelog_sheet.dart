// THE "WHAT IS NEW" SHEET: THE NOTES OF EVERY BUILD THE PERSON HAS NOT SEEN, SHOWN ONCE AFTER AN UPDATE (AND AGAIN FROM SETTINGS ON REQUEST).
// It opens from the chat screen, which sits below the lock screen and the required-update screen, so it can never appear over either.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/changelog.dart';
import '../../l10n/l10n.dart';
import '../../state/changelog.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// Opens the sheet for [entries], newest first. The title names the newest build; a longer list gets a heading per build.
Future<void> showChangelogSheet(
  BuildContext context,
  List<ChangelogEntry> entries,
  String language,
) {
  if (entries.isEmpty) return Future<void>.value();
  return showFormSheet<void>(
    context,
    title: context.t.changelogTitle(entries.first.versionName),
    builder: (sheet, close) {
      final c = sheet.colors;
      final t = sheet.t;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final entry in entries) ...<Widget>[
            if (entries.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    t.changelogBuildHeader(entry.versionName),
                    style: Theme.of(sheet).textTheme.titleSmall,
                  ),
                ),
              ),
            for (final line in entry.lines(language))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The dot is decoration: a screen reader should not say "bullet" before every line
                    ExcludeSemantics(
                      child: Text('•  ', style: TextStyle(color: c.muted)),
                    ),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => close(null),
              child: Text(t.changelogGotIt),
            ),
          ),
        ],
      );
    },
  );
}

/// Shows the notes the person has not seen, once per run. The seen value is written when the sheet opens, not when it closes: the app
/// lock can take the screen away while it is open and a close that never comes would show the same notes again on every start.
/// Anything unexpected (an unknown build, a missing asset, a platform error) means no sheet, never an error.
Future<void> showPendingChangelog(BuildContext context, WidgetRef ref) async {
  if (ref.read(changelogShownProvider)) return;
  try {
    final entries = await ref.read(pendingChangelogProvider.future);
    if (!context.mounted) return;
    final installed = await ref.read(installedBuildProvider.future);
    if (!context.mounted ||
        entries.isEmpty ||
        ref.read(changelogShownProvider)) {
      return;
    }
    ref.read(changelogShownProvider.notifier).markShown();
    await ref.read(prefsProvider).setInt(changelogSeenKey, installed);
    if (!context.mounted) return;
    await showChangelogSheet(
      context,
      entries,
      ref.read(settingsProvider).language,
    );
  } on Exception {
    // No notes this time; nothing was written unless the sheet was about to open
  }
}
