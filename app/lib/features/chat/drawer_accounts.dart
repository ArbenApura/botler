// THE ACCOUNTS SHORTCUT AT THE BOTTOM OF THE CHAT DRAWER (BTL-20261030-0632): A ROW THAT OPENS ALL ACCOUNTS, AND A COMPACT ROW PER ACCOUNT.
// Each row shows what the person chose to lead with (the net when the setting is on and the server sent one, else the balance as counted) and a
// shortfall line in the warning colour when a due bill is not covered. The list is bounded and scrolls, so the chats above keep their room.
// It reads the same balancesProvider as the Accounts screen; a failure is said in words and the chats still work.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../money/net_parts.dart';

// -- CONSTANTS -- //

/// The most height the account rows take before they scroll.
const double _maxRowsHeight = 168;

// -- TYPES -- //

class DrawerAccounts extends ConsumerWidget {
  const DrawerAccounts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final accounts = ref.watch(balancesProvider);
    final net = ref.watch(settingsProvider.select((s) => s.showNetBalance));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Divider(height: 1),
        ListTile(
          minTileHeight: 52,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(t.drawerAccounts),
          trailing: Icon(Icons.chevron_right, color: c.muted),
          onTap: () => _open(context, '/accounts'),
        ),
        accounts.when(
          loading: () => const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SkeletonRows(count: 2),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              t.drawerAccountsError,
              style: TextStyle(color: c.muted),
            ),
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    t.drawerAccountsEmpty,
                    style: TextStyle(color: c.muted),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _maxRowsHeight),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      for (final a in list) _Row(account: a, net: net),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.account, required this.net});

  final Json account;
  final bool net;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currency = str(account['currency'], context.currencyCode);
    // The net leads only when the server sent one: never a net of zero for a missing figure
    final netValue = net ? netInt(account, 'netBalance') : null;
    final shown = netValue ?? intOf(account['balance']);
    final short = netValue == null ? 0 : (netInt(account, 'shortfall') ?? 0);
    return ListTile(
      dense: true,
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        str(account['name']),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: short > 0
          ? Text(
              context.t.drawerAccountShort(context.moneyIn(short, currency)),
              style: TextStyle(color: c.warning, fontFeatures: tabular),
            )
          : null,
      trailing: Text(
        context.moneyIn(shown, currency),
        style: TextStyle(fontFeatures: tabular),
      ),
      onTap: () => _open(context, '/account/${str(account['id'])}'),
    );
  }
}

// -- FUNCTIONS -- //

/// Closes the drawer, then opens the screen on top of the chat.
void _open(BuildContext context, String path) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push(path);
}
