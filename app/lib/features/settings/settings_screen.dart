// SETTINGS: WHO IS SIGNED IN, THE APP LOCK, WHAT NOTIFICATIONS SHOW, HOW EARLY REMINDERS COME, WHICH LANGUAGE TO LISTEN FOR, GOOGLE CALENDAR, AND THE LOOK.
// The lock is only turned on after it has worked once, so a phone with no fingerprint set up cannot lock the person out.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/reminders.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../auth/lock_gate.dart';

// -- TYPES -- //

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final session = ref.watch(sessionProvider).value;
    final sync = ref.watch(syncProvider);
    final cal = asJson(sync.value?['calendar']);
    final status = str(cal['status'], 'off');
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PaperCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session?.name.isNotEmpty ?? false
                            ? session!.name
                            : 'Signed in',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        session?.email ?? '',
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (await confirm(
                      context,
                      title: 'Sign out?',
                      body: 'Botler stays on the server. You can sign in again any time.',
                      yes: 'Sign out',
                    )) {
                      await ref.read(sessionProvider.notifier).signOut();
                    }
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
          const SectionTitle('Privacy'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ask for my fingerprint or face to open Botler'),
            value: s.lockOn,
            onChanged: (on) async {
              if (on && !await ref.read(authenticateProvider)()) {
                if (context.mounted)
                  say(
                    context,
                    'The lock needs a fingerprint or face set up on this phone.',
                  );
                return;
              }
              await notifier.update(s.copyWith(lockOn: on));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide the details in notifications'),
            subtitle: Text(
              'A reminder says only “Botler”, so nobody sees it on your lock screen.',
              style: TextStyle(color: c.muted),
            ),
            value: s.hideDetails,
            onChanged: (on) async {
              await notifier.update(s.copyWith(hideDetails: on));
              await flushAndSync(ref.container);
            },
          ),
          const SectionTitle('Reminders'),
          DropdownButtonFormField<int>(
            // ignore: deprecated_member_use
            value: s.leadMinutes,
            decoration: const InputDecoration(
              labelText: 'Remind me this long before',
            ),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(value: 0, child: Text('At the time')),
              DropdownMenuItem<int>(
                value: 15,
                child: Text('15 minutes before'),
              ),
              DropdownMenuItem<int>(value: 60, child: Text('1 hour before')),
              DropdownMenuItem<int>(value: 180, child: Text('3 hours before')),
              DropdownMenuItem<int>(value: 1440, child: Text('1 day before')),
            ],
            onChanged: (m) async {
              if (m == null) return;
              await notifier.update(s.copyWith(leadMinutes: m));
              await flushAndSync(ref.container);
            },
          ),
          const SectionTitle('Voice'),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: s.speechLocale,
            decoration: const InputDecoration(labelText: 'Listen for'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'en_PH',
                child: Text('English (Philippines)'),
              ),
              DropdownMenuItem<String>(
                value: 'fil_PH',
                child: Text('Filipino and Taglish'),
              ),
            ],
            onChanged: (l) =>
                l == null ? null : notifier.update(s.copyWith(speechLocale: l)),
          ),
          const SectionTitle('Google Calendar'),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  switch (status) {
                    'ok' => 'Syncing both ways',
                    'error' => 'Stopped: Google needs you to connect again',
                    _ => 'Off',
                  },
                  style: TextStyle(
                    color: status == 'error' ? c.warning : c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Events made in Botler appear in Google Calendar, and events made there appear here. Bills and paydays that need action are added too, without amounts.',
                  style: TextStyle(color: c.muted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    if (status != 'ok')
                      FilledButton(
                        onPressed: () async {
                          try {
                            final r = await ref
                                .read(apiProvider)
                                .post(
                                  '/api/v1/calendar/connect',
                                  <String, Object?>{},
                                );
                            final url = Uri.tryParse(str(r['url']));
                            if (url != null)
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            if (context.mounted)
                              say(
                                context,
                                'Finish in the browser, then come back and tap “I connected”.',
                              );
                          } catch (e) {
                            if (context.mounted) say(context, errorWords(e));
                          }
                        },
                        child: const Text('Connect Google Calendar'),
                      ),
                    if (status != 'ok')
                      TextButton(
                        onPressed: () =>
                            _switch(context, ref, 'calendar_enable'),
                        child: const Text('I connected'),
                      ),
                    if (status == 'ok')
                      TextButton(
                        onPressed: () =>
                            _switch(context, ref, 'calendar_disable'),
                        child: const Text('Turn off'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('Look'),
          SegmentedButton<ThemeMode>(
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('Phone'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('Light'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('Dark'),
              ),
            ],
            selected: <ThemeMode>{s.themeMode},
            onSelectionChanged: (m) =>
                notifier.update(s.copyWith(themeMode: m.first)),
          ),
        ],
      ),
    );
  }

  Future<void> _switch(BuildContext context, WidgetRef ref, String verb) async {
    try {
      await ref.read(apiProvider).verb(verb);
      ref.invalidate(syncProvider);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e));
    }
  }
}
