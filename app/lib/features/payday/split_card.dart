// THE PAYDAY SPLIT AS A CARD: WHERE EVERY PESO OF THE PAY GOES, THE TRANSFERS TO MAKE (TAP TO COPY THE AMOUNT, TAP WHEN SENT), AND ONE BUTTON TO APPROVE.
// When the pay cannot cover everything the card shows the gap and what could be cut, and there is nothing to approve: the person decides.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart' show tabular;
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'payday_actions.dart';

// -- TYPES -- //

class SplitCard extends ConsumerStatefulWidget {
  const SplitCard({
    required this.plan,
    this.onChanged,
    this.onPlanAgain,
    super.key,
  });

  /// A split plan as the server sends it.
  final Json plan;
  final VoidCallback? onChanged;

  /// Asks for a new split for the same payday. Offered only while the split is not approved yet.
  final VoidCallback? onPlanAgain;

  @override
  ConsumerState<SplitCard> createState() => _SplitCardState();
}

class _SplitCardState extends ConsumerState<SplitCard> {
  late Json _plan = widget.plan;
  bool _busy = false;

  Json get _result => asJson(_plan['result']);
  bool get _short => str(_plan['status']) == 'shortfall';
  bool get _approved => str(_plan['status']) == 'approved';

  Future<void> _call(String verb, Json args, {required String done}) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).verb(verb, args);
      if (!mounted) return;
      // Approve returns the plan; mark-sent returns the transfer and the plan with it
      if (verb == 'split_approve') _plan = asJson(r);
      if (verb == 'split_mark_sent') _plan = asJson(asJson(r)['plan']);
      if (!mounted) return;
      say(context, done);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = asJson(_result['accountNames']);
    final lines = asJsonList(_result['lines']);
    final transfers = asJsonList(_result['transfers']);
    final sent = asJsonList(_plan['sentTransfers'])
        .map((s) => intOf(s['index']))
        .toSet();
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t.splitPayday(str(_plan['payday'])),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: context.t.splitMenu,
                enabled: !_busy,
                onSelected: (_) async {
                  if (await deleteSplitSheet(context, ref, plan: _plan)) {
                    widget.onChanged?.call();
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(context.t.splitDeleteButton),
                  ),
                ],
              ),
            ],
          ),
          Amount(
            intOf(_plan['pay']),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (_short) ...<Widget>[
            Text(
              context.t.splitShort(context.moneyMain(intOf(_plan['gap']))),
              style: TextStyle(color: c.warning),
            ),
            const SizedBox(height: 8),
            Text(context.t.splitCutOrMove, style: TextStyle(color: c.muted)),
            for (final o in asJsonList(_result['cutOptions']))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(str(o['label']))),
                    Text(context.moneyMain(intOf(o['amount']))),
                  ],
                ),
              ),
          ] else ...<Widget>[
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${str(l['label'])}  ·  ${str(names[str(l['accountId'])], context.t.splitAccountFallback)}',
                      ),
                    ),
                    Text(context.moneyMain(intOf(l['amount']))),
                  ],
                ),
              ),
          ],
          // A rule left out of this split (its goal is off, or its account is hidden) is said, so the pay is never moved without a reason
          if (!_short)
            for (final r in asJsonList(_result['skippedRules']))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(str(r['note']), style: TextStyle(color: c.warning)),
              ),
          // What of the bills did not come from this pay: money already in their account, and what a rule saved for them (BTL-20261029-0119)
          if (!_short) _FromElsewhere(result: _result, names: names),
          // Bills in another currency were counted at the rate of the day the split was made, and the split keeps that rate
          if (!_short &&
              asJsonList(_result['foreignBills']).isNotEmpty) ...<Widget>[
            SectionTitle(context.t.splitForeignTitle),
            for (final f in asJsonList(_result['foreignBills']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  context.t.splitForeignLine(
                    str(f['name']),
                    context.moneyIn(intOf(f['amount']), str(f['currency'])),
                    context.moneyMain(intOf(f['converted'])),
                    '1 ${str(f['currency'])} = ${str(f['rate'])} ${context.currencyCode}',
                  ),
                  style: TextStyle(color: c.muted),
                ),
              ),
          ],
          if (!_short && transfers.isNotEmpty) ...<Widget>[
            SectionTitle(context.t.splitTransfers),
            for (final (i, t) in transfers.indexed)
              _TransferRow(
                from: str(
                  names[str(t['fromAccountId'])],
                  context.t.splitAccountFallback,
                ),
                to: str(
                  names[str(t['toAccountId'])],
                  context.t.splitAccountFallback,
                ),
                amount: intOf(t['amount']),
                sent: sent.contains(i),
                enabled: _approved && !_busy,
                onSent: () => _call('split_mark_sent', <String, Object?>{
                  'splitId': str(_plan['id']),
                  'index': i,
                }, done: context.t.splitMarkedSent),
              ),
          ],
          if (_short && widget.onPlanAgain != null) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : widget.onPlanAgain,
                child: Text(context.t.splitPlanAgain),
              ),
            ),
          ],
          if (!_short && !_approved) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _call('split_approve', <String, Object?>{
                        'splitId': str(_plan['id']),
                      }, done: context.t.splitApprovedDone),
                child: Text(context.t.splitApproveButton),
              ),
            ),
            if (widget.onPlanAgain != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : widget.onPlanAgain,
                  child: Text(context.t.splitPlanAgain),
                ),
              ),
          ],
          if (_approved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.t.splitApproved,
                style: TextStyle(color: c.success),
              ),
            ),
        ],
      ),
    );
  }
}

/// The parts of the bills the split did not take from the pay, in muted rows below the lines: covered by money already in the account,
/// saved by a rule, still needed beyond the rule's savings, and rules that cannot save for their bill. Nothing when there are none.
class _FromElsewhere extends StatelessWidget {
  const _FromElsewhere({required this.result, required this.names});

  final Json result;
  final Json names;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final covered = asJsonList(result['covered']);
    final funded = asJsonList(result['funded']);
    final unfunded = asJsonList(result['unfunded']);
    final broken = asJsonList(result['brokenLinks']);
    if (covered.isEmpty &&
        funded.isEmpty &&
        unfunded.isEmpty &&
        broken.isEmpty) {
      return const SizedBox.shrink();
    }
    final muted = TextStyle(color: c.muted);
    Widget row(String text, int amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: muted)),
          Text(
            context.moneyMain(amount),
            style: muted.copyWith(fontFeatures: tabular),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(t.splitFromElsewhereTitle),
        for (final x in covered)
          row(
            t.splitCoveredLine(
              str(x['label']),
              str(names[str(x['accountId'])], t.splitAccountFallback),
            ),
            intOf(x['amount']),
          ),
        for (final x in funded)
          row(
            t.splitFundedLine(str(x['label']), str(x['ruleLabel'])),
            intOf(x['amount']),
          ),
        for (final x in unfunded)
          row(t.splitUnfundedLine(str(x['label'])), intOf(x['amount'])),
        for (final b in broken)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              t.splitBrokenLink(
                str(b['ruleLabel']),
                str(b['billName'], t.splitBillFallback),
                str(b['reason']),
              ),
              style: TextStyle(color: c.warning),
            ),
          ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.from,
    required this.to,
    required this.amount,
    required this.sent,
    required this.enabled,
    required this.onSent,
  });

  final String from;
  final String to;
  final int amount;
  final bool sent;
  final bool enabled;
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('$from → $to'),
                Text(
                  context.moneyMain(amount),
                  style: TextStyle(color: c.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.t.splitCopyTooltip,
            onPressed: () async {
              final copied = context.t.splitCopied(
                context.plainAmountMain(amount),
              );
              await Clipboard.setData(
                ClipboardData(text: context.plainAmountMain(amount)),
              );
              if (context.mounted) say(context, copied);
            },
            icon: const Icon(Icons.copy_outlined),
          ),
          sent
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    context.t.splitSent,
                    style: TextStyle(color: c.success),
                  ),
                )
              : TextButton(
                  onPressed: enabled ? onSent : null,
                  child: Text(context.t.splitMarkSent),
                ),
        ],
      ),
    );
  }
}
