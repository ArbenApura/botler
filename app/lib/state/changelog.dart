// THE "WHAT IS NEW" STATE: WHICH BUILDS THE PERSON HAS NOT SEEN THE NOTES OF. THE RULES LIVE IN core/changelog.dart.
// Nothing here can fail loudly: an unknown build, a missing asset or a platform error just means no sheet.

// -- DEP-MODULES -- //
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/changelog.dart';
import 'providers.dart';
import 'update.dart';

// -- CONSTANTS -- //

/// The versionCode of the running build; 0 when Android cannot say. Tests override it.
final FutureProvider<int> installedBuildProvider = FutureProvider<int>((
  ref,
) async {
  try {
    return await ref.read(updateHostProvider).installedCode();
  } on PlatformException {
    return 0;
  } on MissingPluginException {
    return 0;
  }
});

/// The bundled notes. Tests override it.
final FutureProvider<List<ChangelogEntry>> changelogEntriesProvider =
    FutureProvider<List<ChangelogEntry>>((ref) => loadChangelog());

/// The notes the sheet already opened for in this run, so a rebuilt screen or a return from the lock never opens it twice.
final NotifierProvider<ChangelogShown, bool> changelogShownProvider =
    NotifierProvider<ChangelogShown, bool>(ChangelogShown.new);

class ChangelogShown extends Notifier<bool> {
  @override
  bool build() => false;

  void markShown() => state = true;
}

/// The builds not seen yet, newest first. Empty when nothing was decided yet (the first-run rule did not run), the build is unknown or
/// nothing is newer than what was seen. The seen value is read first, so a phone with nothing to announce never asks Android anything.
final FutureProvider<List<ChangelogEntry>> pendingChangelogProvider =
    FutureProvider<List<ChangelogEntry>>((ref) async {
      final seen = seenCode(ref.read(prefsProvider));
      if (seen == null) return <ChangelogEntry>[];
      final installed = await ref.read(installedBuildProvider.future);
      if (installed <= seen) return <ChangelogEntry>[];
      return selectUnseen(
        await ref.read(changelogEntriesProvider.future),
        seen,
        installed,
      );
    });

/// The notes of the running build, for the Settings row. Null when there is no entry for it.
final FutureProvider<ChangelogEntry?> installedChangelogProvider =
    FutureProvider<ChangelogEntry?>((ref) async {
      final installed = await ref.read(installedBuildProvider.future);
      return selectFor(
        await ref.read(changelogEntriesProvider.future),
        installed,
      );
    });
