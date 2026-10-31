// EVERYTHING THE PHONE KEEPS ABOUT ONE PERSON, IN ONE PLACE TO SWEEP. SIGNING OUT AND A DATA RESET CALL clearPersonData, SO THE NEXT PERSON ON THIS
// PHONE (OR THE EMPTY ACCOUNT AFTER A RESET) NEVER FINDS THE LAST ONE'S BALANCES, CALENDAR, PAGES OR REMINDER BOOKKEEPING.
// The waiting writes (outbox) are not here: they carry their owner's id and stay for that person after a sign out; a data reset clears them itself.

// -- DEP-MODULES -- //
import 'package:shared_preferences/shared_preferences.dart';

// -- CONSTANTS -- //

/// Single keys that hold a person's data. The names are the real keys of the screens that write them.
const List<String> personDataKeys = <String>[
  'accounts.cache',
  'assets.cache',
  'summary.cache',
  'calendar.range.v1',
  'expense.last_account',
  'sync.cursor',
  'sync.shown',
  'sync.clock_handled',
  'reminders.last_error',
  'reminders.last_sync',
];

/// Families of keys, removed by their beginning: the saved time travel answers (simulate.overview.v1.DATE), the notebook outline, pages and
/// recents (library.), and the index of the photos of sent messages (chatphotos.v1.).
const List<String> personDataPrefixes = <String>[
  'simulate.overview.v1.',
  'library.',
  'chatphotos.v1.',
];

// -- FUNCTIONS -- //

/// Removes every per-person key from the preferences. Settings (language, theme, lock) belong to the phone and stay. The photo files on disk
/// are removed by ChatPhotoStore.wipe, which the callers also run.
///
/// A data reset of money only leaves the notebook pages ([notebooks]) and the photos of sent messages ([photos]) where they are; signing out removes all.
Future<void> clearPersonData(
  SharedPreferences prefs, {
  bool notebooks = true,
  bool photos = true,
}) async {
  // Another isolate (the background sync) may have written since this one read
  await prefs.reload();
  for (final key in personDataKeys) {
    await prefs.remove(key);
  }
  for (final key in prefs.getKeys().toList()) {
    if (!notebooks && key.startsWith('library.')) continue;
    if (!photos && key.startsWith('chatphotos.v1.')) continue;
    if (personDataPrefixes.any(key.startsWith)) await prefs.remove(key);
  }
}
