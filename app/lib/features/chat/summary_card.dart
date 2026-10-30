// THE SUMMARY CARD AT THE TOP OF THE CHAT: THREE QUIET LINES (THE TOTAL ACROSS ACCOUNTS, THE NEXT BILL, TODAY'S FIRST EVENT). IT SCROLLS AWAY WITH THE CHAT,
// AND A SMALL CHIP WITH THE TOTAL TAKES ITS PLACE AT THE TOP OF A LONG CHAT.
// With no connection it shows the last answer that worked and says so.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../money/net_parts.dart';

// -- TYPES -- //

class SummaryCard extends ConsumerWidget {
  const SummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sync = ref.watch(syncProvider);
    // The net total comes from assets_summary (the sync answer stays gross): only read when the person leads with the net
    final net = ref.watch(settingsProvider.select((s) => s.showNetBalance));
    final assetsAsync = net ? ref.watch(assetsProvider) : null;
    final assets = assetsAsync?.value;
    // With the net on the card waits for its figures, so it does not grow when they arrive
    final waiting =
        assetsAsync != null && assetsAsync.isLoading && !assetsAsync.hasValue;
    final netTotal = netInt(assets, 'netTotal');
    final shortTotal = netInt(assets, 'shortfallTotal') ?? 0;
    return PaperCard(
      // A refresh keeps the last answer on screen instead of flashing the card empty
      child: sync.when(
        skipLoadingOnReload: true,
        loading: () => _SummarySkeleton(net: net),
        error: (e, _) =>
            Text(errorWords(e, context), style: TextStyle(color: c.muted)),
        data: (s) {
          if (waiting) return _SummarySkeleton(net: net);
          final summary = asJson(s['summary']);
          final bill = summary['nextBill'] is Map<Object?, Object?>
              ? asJson(summary['nextBill'])
              : null;
          final event = summary['firstEventToday'] is Map<Object?, Object?>
              ? asJson(summary['firstEventToday'])
              : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      netTotal == null
                          ? context.t.chatAcrossAccounts
                          : context.t.netTotalTitle,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                  if (boolOf(s['offline'])) const _OfflineChip(),
                ],
              ),
              const SizedBox(height: 2),
              // The same light figure as every other balance in the app
              Amount(
                netTotal ?? intOf(summary['total']),
                currency: str(summary['currency'], context.currencyCode),
              ),
              // The balance counted, smaller, and what the bills due before payday still lack
              if (netTotal != null) ...<Widget>[
                Text(
                  context.t.netGross(
                    context.moneyIn(
                      intOf(summary['total']),
                      str(summary['currency'], context.currencyCode),
                    ),
                  ),
                  style: TextStyle(color: c.muted, fontFeatures: tabular),
                ),
                if (shortTotal > 0)
                  Text(
                    context.t.netShortfall(
                      context.moneyIn(
                        shortTotal,
                        str(summary['currency'], context.currencyCode),
                      ),
                    ),
                    style: TextStyle(color: c.warning, fontFeatures: tabular),
                  ),
              ],
              if (intOf(summary['totalMissing']) > 0)
                Text(
                  context.t.summaryMissingRates(intOf(summary['totalMissing'])),
                  style: TextStyle(color: context.colors.warning),
                ),
              const SizedBox(height: 14),
              _Line(
                icon: Icons.receipt_long_outlined,
                text: bill == null
                    ? context.t.chatNoBill
                    : context.t.chatNextBill(
                        str(bill['name']),
                        _day(context, str(bill['dueDate'])),
                      ),
              ),
              const SizedBox(height: 8),
              _Line(
                icon: Icons.event_outlined,
                text: event == null
                    ? context.t.chatNoEvent
                    : '${_time(context, str(event['startsAt']))}  ${str(event['title'])}',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The card while it loads: the same lines in the same places, so it does not change height when the answer comes.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton({required this.net});

  /// With the net on the loaded card has two more lines (the balance counted, and what a due bill lacks), so the skeleton has them too.
  final bool net;

  @override
  Widget build(BuildContext context) => SkeletonGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SkeletonLine(widthFactor: 0.4, height: 20),
        const SizedBox(height: 2),
        const SkeletonLine(widthFactor: 0.55, height: 36),
        if (net) ...<Widget>[
          const SizedBox(height: 2),
          const SkeletonLine(widthFactor: 0.35, height: 22),
          const SizedBox(height: 2),
          const SkeletonLine(widthFactor: 0.6, height: 22),
        ],
        const SizedBox(height: 14),
        const SkeletonLine(widthFactor: 0.75, height: 20),
        const SizedBox(height: 8),
        const SkeletonLine(widthFactor: 0.65, height: 20),
      ],
    ),
  );
}

/// "Offline" as a small outlined chip in the warning colour (outlined, so no tinted background is needed in either mode).
class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.warning),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.t.chatOffline,
        style: TextStyle(color: c.warning, fontSize: 12),
      ),
    );
  }
}

/// Opens the summary in a sheet, from the app bar, so the person never has to scroll a long chat back to its top to see the money.
void showSummarySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.paper,
    builder: (_) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[SummaryCard(), _SheetAccounts()],
        ),
      ),
    ),
  );
}

/// The accounts under the summary in the wallet sheet: one row each with what the person leads with, and, with the net on, the lines that
/// consumed it. A row opens the account on top of the chat. The sheet scrolls, so a long list needs no cap of its own.
class _SheetAccounts extends ConsumerWidget {
  const _SheetAccounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Only with the net on: the sheet is the summary as it always was for a person who leads with the balance counted
    final net = ref.watch(settingsProvider.select((s) => s.showNetBalance));
    if (!net) return const SizedBox.shrink();
    final balances = ref.watch(balancesProvider);
    // While they load, rows of the same kind hold the place, so the sheet does not jump up when they arrive
    if (balances.isLoading && !balances.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 12),
          Text(context.t.drawerAccounts, style: TextStyle(color: c.muted)),
          const SkeletonRows(count: 3),
        ],
      );
    }
    final accounts = balances.value;
    if (accounts == null || accounts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The gap is here, so a sheet with no accounts is exactly as tall as its card
        const SizedBox(height: 12),
        Text(context.t.drawerAccounts, style: TextStyle(color: c.muted)),
        for (final a in accounts) _SheetRow(account: a, net: net),
      ],
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.account, required this.net});

  final Json account;
  final bool net;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currency = str(account['currency'], context.currencyCode);
    // The net leads only when the server sent one: never a net of zero for a missing figure
    final netValue = net ? netInt(account, 'netBalance') : null;
    final short = netValue == null ? 0 : (netInt(account, 'shortfall') ?? 0);
    return Semantics(
      button: true,
      label: str(account['name']),
      child: InkWell(
        onTap: () {
          final router = GoRouter.of(context);
          Navigator.of(context).pop();
          router.push('/account/${str(account['id'])}');
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        str(account['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.moneyIn(
                        netValue ?? intOf(account['balance']),
                        currency,
                      ),
                      style: TextStyle(fontFeatures: tabular),
                    ),
                  ],
                ),
                if (short > 0)
                  Text(
                    context.t.drawerAccountShort(
                      context.moneyIn(short, currency),
                    ),
                    style: TextStyle(color: c.warning, fontFeatures: tabular),
                  ),
                if (net) NetHoldLines(account: account),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 18, color: context.colors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}

// -- FUNCTIONS -- //

String _day(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  return d == null
      ? iso
      : DateFormat(
          'MMM d',
          Localizations.localeOf(context).toString(),
        ).format(d);
}

String _time(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  return d == null
      ? ''
      : DateFormat(
          'h:mm a',
          Localizations.localeOf(context).toString(),
        ).format(d.toLocal());
}
