// THE MENU: THE PLACES BEYOND THE CHAT, EACH WITH ONE PLAIN LINE SAYING WHAT IT IS FOR.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  static const List<(String, String, String, IconData)> _items =
      <(String, String, String, IconData)>[
        (
          '/accounts',
          'Accounts',
          'What is in RCBC, GCash, Maya and cash',
          Icons.account_balance_wallet_outlined,
        ),
        (
          '/bills',
          'Bills',
          'What is due, and mark it paid',
          Icons.receipt_long_outlined,
        ),
        (
          '/payday',
          'Payday',
          'Split your pay, and the rules for it',
          Icons.payments_outlined,
        ),
        (
          '/goals',
          'Savings goals',
          'What you are saving for',
          Icons.savings_outlined,
        ),
        (
          '/history',
          'History',
          'Everything you spent, and undo',
          Icons.history,
        ),
        (
          '/agenda',
          'Agenda',
          'Tasks, events, routines and reminders',
          Icons.event_note_outlined,
        ),
        (
          '/memory',
          'Memory',
          'What Botler remembers, and how it talks',
          Icons.psychology_alt_outlined,
        ),
        (
          '/settings',
          'Settings',
          'Lock, notifications, calendar, look',
          Icons.tune,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          for (final (path, title, line, icon) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PaperCard(
                onTap: () => context.push(path),
                child: Row(
                  children: <Widget>[
                    Icon(icon, color: c.accentText),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(line, style: TextStyle(color: c.muted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
