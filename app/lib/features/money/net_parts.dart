// NET BALANCE PIECES THE ACCOUNTS SCREEN AND THE ACCOUNT DETAIL SHARE (BTL-20261030-0546)
// The server always sends gross and net; the setting `showNetBalance` only chooses which one leads. A net that is missing (an older server, an
// answer cached before this version) or null (the server could not work it out) means the gross view, never a net of zero and never a shortfall.
// All money goes through Amount and context.moneyIn (core/money.dart), colours through context.colors.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

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
  return DateFormat.MMMd(Localizations.localeOf(context).toString()).format(d);
}

/// Saves the choice on the server, then here. A failure says so in words and the old value stays; settings are not queued, so offline it is refused.
Future<void> setShowNet(BuildContext context, WidgetRef ref, bool on) async {
  try {
    await ref.read(settingsProvider.notifier).saveToServer(showNetBalance: on);
  } catch (e) {
    if (context.mounted) say(context, errorWords(e, context));
  }
}

// -- WIDGETS -- //

/// One wallet with the net leading: the net, then the balance counted smaller, then what a due bill still lacks. A wallet with no net shows
/// the balance as counted: never a net of zero.
class NetAmount extends StatelessWidget {
  const NetAmount({
    required this.wallet,
    required this.currency,
    this.style,
    super.key,
  });

  final Json wallet;
  final String currency;
  final TextStyle? style;

  /// The shortfall line wraps inside this width, so it never squeezes the name next to it on a narrow phone.
  static const double _shortWidth = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final net = netInt(wallet, 'netBalance');
    if (net == null) {
      return Amount(intOf(wallet['balance']), currency: currency, style: style);
    }
    final short = netInt(wallet, 'shortfall') ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Amount(net, currency: currency, style: style),
        Text(
          context.t.netGross(
            context.moneyIn(intOf(wallet['balance']), currency),
          ),
          style: TextStyle(color: c.muted, fontFeatures: tabular),
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
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () => _flip(!on),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ExcludeSemantics(
              child: Text(label, style: TextStyle(color: context.colors.muted)),
            ),
          ),
        ),
      ),
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
                          Expanded(child: Text(_holdWords(context, h))),
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

  String _holdWords(BuildContext context, Json h) {
    final t = context.t;
    final label = str(h['label']);
    final date = h['dueDate'] is String ? _day(context, str(h['dueDate'])) : '';
    return switch (str(h['kind'])) {
      'goal' => t.netHeldGoal(label),
      'rule' => t.netHeldRule(label, date),
      _ => t.netHeldBill(label, date),
    };
  }
}
