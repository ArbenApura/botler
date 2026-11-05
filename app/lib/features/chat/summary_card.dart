// THE SUMMARY CARD AT THE TOP OF THE CHAT: THREE QUIET LINES (THE TOTAL ACROSS ACCOUNTS, THE NEXT BILL, TODAY'S FIRST EVENT). IT SCROLLS AWAY WITH THE CHAT,
// AND A SMALL CHIP WITH THE TOTAL TAKES ITS PLACE AT THE TOP OF A LONG CHAT.
// With no connection it shows the last answer that worked and says so.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/marks.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';
import '../money/accounts_screen.dart' show walletsOf;
import '../money/money_parts.dart';
import '../money/net_parts.dart';
import '../../core/clock.dart';

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
              // The same light figure as every other balance in the app, shrunk to fit rather than wrapped
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Amount(
                  netTotal ?? intOf(summary['total']),
                  currency: str(summary['currency'], context.currencyCode),
                ),
              ),
              // The balance counted, smaller, what the bills due before payday still lack, and any currency left out: small badges
              if (netTotal != null ||
                  intOf(summary['totalMissing']) > 0) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    if (netTotal != null) ...<Widget>[
                      InfoPill(
                        text: context.t.netGross(
                          context.moneyIn(
                            intOf(summary['total']),
                            str(summary['currency'], context.currencyCode),
                          ),
                        ),
                        color: c.muted,
                      ),
                      if (shortTotal > 0)
                        InfoPill(
                          text: context.t.netShortfall(
                            context.moneyIn(
                              shortTotal,
                              str(summary['currency'], context.currencyCode),
                            ),
                          ),
                          color: c.warning,
                          icon: Icons.warning_amber_rounded,
                        ),
                    ],
                    if (intOf(summary['totalMissing']) > 0)
                      InfoPill(
                        text: context.t.summaryMissingRates(
                          intOf(summary['totalMissing']),
                        ),
                        color: c.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                  ],
                ),
              ],
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
          // The badges under the figure: two rows at most
          const SizedBox(height: 8),
          const SkeletonLine(widthFactor: 0.45, height: 28),
          const SizedBox(height: 6),
          const SkeletonLine(widthFactor: 0.6, height: 28),
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
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: c.warning),
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
    // The net lines come only with the net on; the accounts themselves are always listed, each with its mark
    final net = ref.watch(settingsProvider.select((s) => s.showNetBalance));
    final balances = ref.watch(balancesProvider);
    // While they load, rows of the same kind hold the place, so the sheet does not jump up when they arrive
    if (balances.isLoading && !balances.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            context.t.drawerAccounts,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: c.muted),
          ),
        ),
        PaperCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: <Widget>[
              for (var i = 0; i < accounts.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                _SheetRow(account: accounts[i], net: net),
              ],
            ],
          ),
        ),
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
    final own = str(account['currency'], context.currencyCode);
    // Every wallet of the account, like the Accounts screen: a Wise with pesos and dollars shows both
    final wallets = walletsOf(account);
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The account's own logo, icon or first letter, like the Accounts screen
                    MarkBadge(
                      name: str(account['name']),
                      mark: markOf(account),
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          str(account['name']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (final w in wallets)
                          // The net leads only when the server sent one for this wallet: never a net of zero for a missing figure
                          if (net && netInt(w, 'netBalance') != null)
                            NetAmount(
                              wallet: w,
                              currency: str(w['currency'], own),
                              style: Theme.of(context).textTheme.titleMedium,
                            )
                          else
                            Amount(
                              intOf(w['balance']),
                              currency: str(w['currency'], own),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                      ],
                    ),
                  ],
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
  return d == null ? iso : fmtDate(d, DateKind.monthDay);
}

String _time(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : fmtTime(manilaWall(d));
}
