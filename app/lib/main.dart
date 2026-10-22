// START: THE PREFERENCES, THE REMINDER MACHINERY (NOTIFICATIONS AND THE BACKGROUND SYNC), THEN THE APP.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'app.dart';
import 'core/reminders.dart';
import 'state/providers.dart';

// -- FUNCTIONS -- //

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await initReminders();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const BotlerApp(),
    ),
  );
}
