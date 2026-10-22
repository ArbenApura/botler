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
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

class SplitCard extends ConsumerStatefulWidget {
  const SplitCard({required this.plan, this.onChanged, super.key});

  /// A split plan as the server sends it.
  final Json plan;
  final VoidCallback? onChanged;

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
      // Approve returns the plan; mark-sent returns the transfer, so the plan is read again after it
      if (verb == 'split_approve') _plan = asJson(r);
      if (verb == 'split_mark_sent') {
        final plans = await ref.read(apiProvider).verbList(
          'split_list',
          <String, Object?>{'limit': 10},
        );
        _plan = plans.firstWhere(
          (p) => str(p['id']) == str(_plan['id']),
          orElse: () => _plan,
        );
      }
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
          Text(
            context.t.splitPayday(str(_plan['payday'])),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Amount(
            intOf(_plan['pay']),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (_short) ...<Widget>[
            Text(
              context.t.splitShort(context.money(intOf(_plan['gap']))),
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
                    Text(context.money(intOf(o['amount']))),
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
                    Text(context.money(intOf(l['amount']))),
                  ],
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
                Text(context.money(amount), style: TextStyle(color: c.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: context.t.splitCopyTooltip,
            onPressed: () async {
              final copied = context.t.splitCopied(context.plainAmount(amount));
              await Clipboard.setData(
                ClipboardData(text: context.plainAmount(amount)),
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
