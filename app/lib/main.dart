// START: THE PREFERENCES, THE REMINDER MACHINERY (NOTIFICATIONS AND THE BACKGROUND SYNC), THEN THE APP.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'app.dart';
import 'core/reminders.dart';
import 'state/providers.dart';

// -- FUNCTIONS -- //

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Month and weekday names for the two languages the app has, not every language intl knows: that is a slow start for nothing
  await Future.wait<void>(<Future<void>>[
    initializeDateFormatting('en'),
    initializeDateFormatting('fil'),
  ]);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const BotlerApp(),
    ),
  );
  // The permission dialog and the background task setup must not hold up the first frame
  unawaited(initReminders().catchError((Object _) {}));
}
