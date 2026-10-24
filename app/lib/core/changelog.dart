// WHAT IS NEW AFTER AN UPDATE: THE CHANGELOG SHIPS INSIDE THE APP (assets/changelog.json), SO IT ALWAYS MATCHES THE BUILD THAT RUNS AND NEEDS NO NETWORK.
// Every entry is keyed by versionCode and holds plain lines in English and Filipino. The rules are pure functions (tested without a phone).
// 'changelog.seen' is the last build code the person has seen the notes of. It belongs to the phone: signing out or resetting never touches it.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'json.dart';

// -- TYPES -- //

class ChangelogEntry {
  const ChangelogEntry({
    required this.versionCode,
    required this.versionName,
    required this.en,
    required this.fil,
  });

  final int versionCode;
  final String versionName;
  final List<String> en;
  final List<String> fil;

  /// The lines in the app language. A missing or empty Filipino list falls back to English, so a person never sees an empty entry.
  List<String> lines(String language) =>
      language == 'fil' && fil.isNotEmpty ? fil : en;
}

// -- CONSTANTS -- //

const String changelogAsset = 'assets/changelog.json';
const String changelogSeenKey = 'changelog.seen';

/// Written by every build that has the in-app update, after its first good check (core/app_update.dart).
const String _updateLastCheckKey = 'update.lastCheck';

/// The sheet lists at most this many builds, so a phone that skipped many updates still gets a short list.
const int maxShown = 5;

// -- FUNCTIONS -- //

/// Reads the changelog text. A text that is not the expected list, or an entry without a version or English lines, is skipped; nothing throws.
List<ChangelogEntry> parseChangelog(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    debugPrint('changelog: the file is not JSON');
    return <ChangelogEntry>[];
  }
  final entries = <ChangelogEntry>[];
  for (final e in asJsonList(decoded)) {
    final code = intOf(e['versionCode']);
    final en = _lines(e['en']);
    if (code <= 0 || en.isEmpty) continue;
    entries.add(
      ChangelogEntry(
        versionCode: code,
        versionName: str(e['versionName']),
        en: en,
        fil: _lines(e['fil']),
      ),
    );
  }
  entries.sort((a, b) => b.versionCode.compareTo(a.versionCode));
  return entries;
}

List<String> _lines(Object? v) => <String>[
  for (final l in asList(v))
    if (l is String && l.trim().isNotEmpty) l.trim(),
];

/// The builds the person has not seen yet: above [seen] and up to [installed], newest first, at most [maxShown].
/// Nothing when the installed build is unknown (<= 0) or not above [seen].
List<ChangelogEntry> selectUnseen(
  List<ChangelogEntry> entries,
  int seen,
  int installed,
) {
  if (installed <= 0 || installed <= seen) return <ChangelogEntry>[];
  final unseen = entries
      .where((e) => e.versionCode > seen && e.versionCode <= installed)
      .toList();
  return unseen.length > maxShown ? unseen.sublist(0, maxShown) : unseen;
}

/// The one entry of the installed build, or null (Settings hides its row then).
ChangelogEntry? selectFor(List<ChangelogEntry> entries, int installed) {
  for (final e in entries) {
    if (e.versionCode == installed) return e;
  }
  return null;
}

/// Runs once at start, before any update check can write 'update.lastCheck'. A phone with no 'changelog.seen' is either a fresh install
/// (no update check ever ran: nothing to announce, so the current build counts as seen) or an upgrade from a build that predates this
/// feature (an update check ran: seen is 0, so the notes of this build show once). Unknown installed build (<= 0): nothing is written.
Future<void> decideFirstRun(SharedPreferences prefs, int installed) async {
  if (prefs.containsKey(changelogSeenKey) || installed <= 0) return;
  final upgrade = prefs.containsKey(_updateLastCheckKey);
  await prefs.setInt(changelogSeenKey, upgrade ? 0 : installed);
}

/// The build code whose notes the person has seen, or null when it was never decided.
int? seenCode(SharedPreferences prefs) => prefs.getInt(changelogSeenKey);

/// Loads the bundled changelog. A missing asset is an empty list, never a crash.
Future<List<ChangelogEntry>> loadChangelog([AssetBundle? bundle]) async {
  try {
    return parseChangelog(
      await (bundle ?? rootBundle).loadString(changelogAsset),
    );
  } on FlutterError {
    debugPrint('changelog: the asset is missing');
    return <ChangelogEntry>[];
  }
}
