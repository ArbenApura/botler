// THE PAYDAY SPLIT AS A CARD: WHERE EVERY PESO OF THE PAY GOES, THE TRANSFERS TO MAKE (TAP TO COPY THE AMOUNT, TAP WHEN SENT), AND ONE BUTTON TO APPROVE.
// When the pay cannot cover everything the card shows the gap and what could be cut, and there is nothing to approve: the person decides.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
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
      if (mounted) say(context, errorWords(e));
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
            'Payday ${str(_plan['payday'])}',
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
              'This pay is ${formatPhp(intOf(_plan['gap']))} short of what you set aside.',
              style: TextStyle(color: c.warning),
            ),
            const SizedBox(height: 8),
            Text('You could cut or move:', style: TextStyle(color: c.muted)),
            for (final o in asJsonList(_result['cutOptions']))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(str(o['label']))),
                    Text(formatPhp(intOf(o['amount']))),
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
                        '${str(l['label'])}  ·  ${str(names[str(l['accountId'])], 'account')}',
                      ),
                    ),
                    Text(formatPhp(intOf(l['amount']))),
                  ],
                ),
              ),
          ],
          if (!_short && transfers.isNotEmpty) ...<Widget>[
            const SectionTitle('Transfers to make'),
            for (final (i, t) in transfers.indexed)
              _TransferRow(
                from: str(names[str(t['fromAccountId'])], 'account'),
                to: str(names[str(t['toAccountId'])], 'account'),
                amount: intOf(t['amount']),
                sent: sent.contains(i),
                enabled: _approved && !_busy,
                onSent: () => _call('split_mark_sent', <String, Object?>{
                  'splitId': str(_plan['id']),
                  'index': i,
                }, done: 'Marked as sent.'),
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
                      }, done: 'Split approved.'),
                child: const Text('Approve split'),
              ),
            ),
          ],
          if (_approved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Approved', style: TextStyle(color: c.success)),
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
                Text(formatPhp(amount), style: TextStyle(color: c.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy the amount',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: pesosText(amount)));
              if (context.mounted) say(context, 'Copied ${pesosText(amount)}');
            },
            icon: const Icon(Icons.copy_outlined),
          ),
          sent
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Sent', style: TextStyle(color: c.success)),
                )
              : TextButton(
                  onPressed: enabled ? onSent : null,
                  child: const Text('Mark sent'),
                ),
        ],
      ),
    );
  }
}
