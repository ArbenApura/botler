// NET BALANCE PIECES THE ACCOUNTS SCREEN AND THE ACCOUNT DETAIL SHARE (BTL-20261030-0546)
// The server always sends gross and net; the setting `showNetBalance` only chooses which one leads. A net that is missing (an older server, an
// answer cached before this version) or null (the server could not work it out) means the gross view, never a net of zero and never a shortfall.
// All money goes through Amount and context.moneyIn (core/money.dart), colours through context.colors.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'money_parts.dart';
import '../../core/clock.dart' show DateKind, fmtDate;

// -- FUNCTIONS -- //

/// A whole number the server sent, or null when it is missing, null or not a number.
int? netInt(Json? j, String key) {
  final v = j?[key];
  return v is int ? v : null;
}

/// The wallet of an account in one currency, or null.
Json? walletIn(Json account, String currency) {
  for (final w in asJsonList(account['wallets'])) {
    if (str(w['currency']) == currency) return w;
  }
  return null;
}

/// A date the server sent (YYYY-MM-DD) as the person reads it.
String _day(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return fmtDate(d, DateKind.monthDay);
}

/// Saves the choice on the server, then here. A failure says so in words and the old value stays; settings are not queued, so offline it is refused.
Future<void> setShowNet(BuildContext context, WidgetRef ref, bool on) async {
  try {
    await ref.read(settingsProvider.notifier).saveToServer(showNetBalance: on);
  } catch (e) {
    if (context.mounted) say(context, errorWords(e, context));
  }
}

/// One hold in words: the bill with its date, the rule saving for a bill, the goal.
String holdWords(BuildContext context, Json h) {
  final t = context.t;
  final label = str(h['label']);
  final date = h['dueDate'] is String ? _day(context, str(h['dueDate'])) : '';
  return switch (str(h['kind'])) {
    'goal' => t.netHeldGoal(label),
    'rule' => t.netHeldRule(label, date),
    _ => t.netHeldBill(label, date),
  };
}

/// Every hold of every wallet of an account, each with the currency of its own wallet, in the order the server sent them. Only wallets that
/// have a net count: an older answer or one the server could not work out has no holds to show.
List<({Json hold, String currency})> accountHolds(Json account) =>
    <({Json hold, String currency})>[
      for (final w in asJsonList(account['wallets']))
        if (netInt(w, 'netBalance') != null)
          for (final h in asJsonList(w['holds']))
            (hold: h, currency: str(w['currency'], str(account['currency']))),
    ];

// -- WIDGETS -- //

/// One wallet with the net leading: the net, then the balance counted smaller, then what a due bill still lacks. A wallet with no net shows
/// the balance as counted: never a net of zero.
class NetAmount extends StatelessWidget {
  const NetAmount({
    required this.wallet,
    required this.currency,
    this.style,
    this.lead = true,
    super.key,
  });

  final Json wallet;
  final String currency;
  final TextStyle? style;

  /// False when the person chose the balance as counted: only the balance shows, whatever net the server sent.
  final bool lead;

  /// The shortfall line wraps inside this width, so it never squeezes the name next to it on a narrow phone.
  static const double _shortWidth = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final net = lead ? netInt(wallet, 'netBalance') : null;
    // One line each, shrunk to the room it has: an amount never wraps onto a second line
    Widget line(Widget child) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: child,
    );
    if (net == null) {
      return line(
        Amount(intOf(wallet['balance']), currency: currency, style: style),
      );
    }
    final short = netInt(wallet, 'shortfall') ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        line(Amount(net, currency: currency, style: style)),
        // The counted balance shows only when it differs from the net: the same number twice says nothing
        if (net != intOf(wallet['balance']))
          line(
            Text(
              context.t.netGross(
                context.moneyIn(intOf(wallet['balance']), currency),
              ),
              maxLines: 1,
              style: TextStyle(color: c.muted, fontFeatures: tabular),
            ),
          ),
        if (short > 0)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _shortWidth),
            child: Text(
              context.t.netShortfall(context.moneyIn(short, currency)),
              textAlign: TextAlign.end,
              style: TextStyle(color: c.warning, fontFeatures: tabular),
            ),
          ),
      ],
    );
  }
}

/// The line under the total that flips the setting: a muted 48 dp line like the rates and time travel lines, not a second button. A tap while
/// the server is saving is ignored, so a second tap cannot send the opposite value.
class NetToggleLine extends ConsumerStatefulWidget {
  const NetToggleLine({super.key});

  @override
  ConsumerState<NetToggleLine> createState() => _NetToggleLineState();
}

class _NetToggleLineState extends ConsumerState<NetToggleLine> {
  // -- STATES -- //

  bool _saving = false;

  // -- FUNCTIONS -- //

  Future<void> _flip(bool on) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await setShowNet(context, ref, on);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(settingsProvider).showNetBalance;
    final label = on ? context.t.netShowGross : context.t.netShowNet;
    return ActionRow(
      icon: on ? Icons.account_balance_wallet_outlined : Icons.savings_outlined,
      label: label,
      onTap: () => _flip(!on),
    );
  }
}

/// What a wallet holds back, one line each: the bill and its date, the rule saving for a bill, the goal. One line (the net now) until the
/// person opens it, and the list inside is bounded and scrolls, so it never pushes the entries off a small screen.
class NetHolds extends StatelessWidget {
  const NetHolds({required this.wallet, required this.currency, super.key});

  final Json wallet;
  final String currency;

  /// The most height the opened list takes.
  static const double _maxListHeight = 160;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final net = netInt(wallet, 'netBalance');
    if (net == null) return const SizedBox.shrink();
    final holds = asJsonList(wallet['holds']);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      shape: const Border(),
      collapsedShape: const Border(),
      minTileHeight: 48,
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(t.netNetNow, style: TextStyle(color: c.muted)),
          ),
          Amount(
            net,
            currency: currency,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: Text(t.netHeldTitle, style: TextStyle(color: c.muted)),
        ),
        if (holds.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(t.netHeldNothing, style: TextStyle(color: c.muted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxListHeight),
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final h in holds)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: Text(holdWords(context, h))),
                          const SizedBox(width: 8),
                          Text(
                            context.moneyIn(intOf(h['amount']), currency),
                            style: TextStyle(fontFeatures: tabular),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// What consumed an account, right on its card: the first few holds (bill with date, rule, goal) with their amounts, then "+N more". Nothing
/// when the account holds nothing or has no net.
class NetHoldLines extends StatelessWidget {
  const NetHoldLines({required this.account, super.key});

  final Json account;

  /// More than this many lines are folded into a "+N more" line (the whole list is on the account's own screen).
  static const int maxLines = 3;

  @override
  Widget build(BuildContext context) {
    final holds = accountHolds(account);
    if (holds.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final shown = holds.take(maxLines).toList();
    final more = holds.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(context.t.netTakenBy, style: TextStyle(color: c.muted)),
          for (final h in shown)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      holdWords(context, h.hold),
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-${context.moneyIn(intOf(h.hold['amount']), h.currency)}',
                    style: TextStyle(color: c.muted, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                context.t.netTakenMore(more),
                style: TextStyle(color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}
