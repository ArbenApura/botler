// THE MENU: THE PLACES BEYOND THE CHAT, EACH WITH ONE PLAIN LINE SAYING WHAT IT IS FOR.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  /// The places beyond the chat: where it goes, its name, one plain line, its icon.
  List<(String, String, String, IconData)> _items(BuildContext context) {
    final t = context.t;
    return <(String, String, String, IconData)>[
      ('/health', t.menuHealth, t.menuHealthLine, Icons.favorite_border),
      (
        '/calendar',
        t.menuCalendar,
        t.menuCalendarLine,
        Icons.calendar_month_outlined,
      ),
      (
        '/accounts',
        t.menuAccounts,
        t.menuAccountsLine,
        Icons.account_balance_wallet_outlined,
      ),
      ('/simulate', t.menuSimulate, t.menuSimulateLine, Icons.auto_graph),
      ('/bills', t.menuBills, t.menuBillsLine, Icons.receipt_long_outlined),
      ('/payday', t.menuPayday, t.menuPaydayLine, Icons.payments_outlined),
      ('/goals', t.menuGoals, t.menuGoalsLine, Icons.savings_outlined),
      ('/history', t.menuHistory, t.menuHistoryLine, Icons.history),
      ('/agenda', t.menuAgenda, t.menuAgendaLine, Icons.event_note_outlined),
      (
        '/memory',
        t.menuNotebook,
        t.menuNotebookLine,
        Icons.psychology_alt_outlined,
      ),
      ('/settings', t.menuSettings, t.menuSettingsLine, Icons.tune),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(context.t.menuTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          for (final (path, title, line, icon) in _items(context))
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
