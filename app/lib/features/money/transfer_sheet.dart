// MOVE MONEY BETWEEN TWO WALLETS: FROM ONE ACCOUNT'S CURRENCY TO ANOTHER (OR THE SAME ACCOUNT'S OTHER CURRENCY, LIKE A CONVERSION INSIDE WISE).
// When the two wallets are in different currencies the person types what was sent AND what really arrived: the rate is theirs, and the
// balances then match the statement. Today's rate is only a suggestion for the second box. It works with no connection: the move is kept on
// the phone under one request id and sent when the phone is back online, exactly once.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'accounts_screen.dart';

// -- FUNCTIONS -- //

/// The sheet. [from] is a row of `accounts_balances`, [fromCurrency] the wallet the money leaves.
Future<void> showMoveSheet(
  BuildContext context,
  WidgetRef ref, {
  required Json from,
  required String fromCurrency,
}) async {
  final accounts = ref.read(balancesProvider).value ?? <Json>[];
  final done = await showFormSheet<bool>(
    context,
    title: context.t.transferMove,
    builder: (sheet, close) => _MoveForm(
      from: from,
      fromCurrency: fromCurrency,
      accounts: accounts,
      close: close,
    ),
  );
  if (done == true) {
    ref
      ..invalidate(balancesProvider)
      ..invalidate(assetsProvider)
      ..invalidate(syncProvider);
  }
}

/// "1 USD = 56.1 PHP" from what was sent and what arrived. Shown to the person only; nothing is computed from it.
String impliedRate(int sent, String from, int arrived, String to) {
  if (sent <= 0 || arrived <= 0) return '';
  final perFrom = minorPerMajor(from);
  final perTo = minorPerMajor(to);
  final rate = (arrived / perTo) / (sent / perFrom);
  final text = rate >= 100
      ? rate.toStringAsFixed(2)
      : rate >= 1
      ? rate.toStringAsFixed(4)
      : rate.toStringAsPrecision(4);
  return '1 $from = $text $to';
}

// -- TYPES -- //

class _MoveForm extends ConsumerStatefulWidget {
  const _MoveForm({
    required this.from,
    required this.fromCurrency,
    required this.accounts,
    required this.close,
  });

  final Json from;
  final String fromCurrency;
  final List<Json> accounts;
  final void Function(bool? result) close;

  @override
  ConsumerState<_MoveForm> createState() => _MoveFormState();
}

class _MoveFormState extends ConsumerState<_MoveForm> {
  // -- STATES -- //

  final TextEditingController _sent = TextEditingController();
  final TextEditingController _arrived = TextEditingController();
  final TextEditingController _fee = TextEditingController();
  String _toAccount = '';
  String _toCurrency = '';
  bool _arrivedEdited = false;
  bool _busy = false;
  final Once _once = Once();
  String _suggest = '';
  int _ticket = 0;

  // -- FUNCTIONS -- //

  /// Every wallet the money can go to: all of them but the one it leaves.
  List<(Json, String)> get _targets => <(Json, String)>[
    for (final a in widget.accounts)
      for (final w in walletsOf(a))
        if (!(str(a['id']) == str(widget.from['id']) &&
            str(w['currency']) == widget.fromCurrency))
          (a, str(w['currency'])),
  ];

  bool get _crossing =>
      _toCurrency.isNotEmpty && _toCurrency != widget.fromCurrency;

  @override
  void initState() {
    super.initState();
    final first = _targets.firstOrNull;
    if (first != null) {
      _toAccount = str(first.$1['id']);
      _toCurrency = first.$2;
    }
  }

  @override
  void dispose() {
    _sent.dispose();
    _arrived.dispose();
    _fee.dispose();
    super.dispose();
  }

  /// Asks the server what today's rate gives for the amount typed, and fills the second box until the person types in it.
  Future<void> _suggestFor(String text) async {
    final ticket = ++_ticket;
    final sent = parseMoney(text, widget.fromCurrency);
    if (!_crossing || sent == null || sent <= 0) {
      if (mounted) {
        setState(() {
          _suggest = '';
          if (!_arrivedEdited) _arrived.clear();
        });
      }
      return;
    }
    try {
      final r = await ref.read(apiProvider).verbJson(
        'fx_convert',
        <String, Object?>{
          'amount': sent,
          'from': widget.fromCurrency,
          'to': _toCurrency,
        },
      );
      if (!mounted || ticket != _ticket) return;
      if (str(r['status']) != 'ok') {
        // No rate: the person types what arrived, and an old suggestion is not left looking like an answer
        setState(() {
          _suggest = '';
          if (!_arrivedEdited) _arrived.clear();
        });
        return;
      }
      final converted = intOf(r['converted']);
      setState(() {
        _suggest = context.moneyIn(converted, _toCurrency);
        if (!_arrivedEdited) {
          _arrived.text = plainAmount(converted, _toCurrency);
        }
      });
    } on ApiException {
      // No rate or no connection: the person types what arrived
      if (mounted && ticket == _ticket) {
        setState(() {
          _suggest = '';
          if (!_arrivedEdited) _arrived.clear();
        });
      }
    }
  }

  Future<void> _send() async {
    final t = context.t;
    final sent = parseMoney(_sent.text, widget.fromCurrency);
    final arrived = _crossing ? parseMoney(_arrived.text, _toCurrency) : null;
    final fee = _fee.text.trim().isEmpty
        ? 0
        : parseMoney(_fee.text, widget.fromCurrency);
    if (_toAccount.isEmpty) {
      say(context, t.transferSame);
      return;
    }
    if (sent == null ||
        sent <= 0 ||
        fee == null ||
        (_crossing && (arrived == null || arrived <= 0))) {
      say(context, t.transferInvalid);
      return;
    }
    final args = <String, Object?>{
      'fromAccountId': str(widget.from['id']),
      'toAccountId': _toAccount,
      'currency': widget.fromCurrency,
      'toCurrency': _toCurrency,
      'amount': sent,
      'toAmount': ?arrived,
      if (fee > 0) 'fee': fee,
    };
    // One key per request (the intent is the whole body): a retry after a timeout is the same transfer, a changed amount is a new one
    final intent = jsonEncode(args);
    final key = _once.key(intent);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).verb('transfer_record', args, key);
      _once.done(intent);
      if (!mounted) return;
      say(context, t.transferDone);
      widget.close(true);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Kept on the phone under the same id: if the first try did arrive, the server knows the id and does not double it
        await ref.read(outboxProvider).add('transfer_record', args, key: key);
        ref.read(outboxCountProvider.notifier).refresh();
        _once.done(intent);
        if (!mounted) return;
        say(context, t.transferQueued);
        widget.close(true);
      } else if (mounted) {
        say(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final sent = parseMoney(_sent.text, widget.fromCurrency);
    final arrived = _crossing ? parseMoney(_arrived.text, _toCurrency) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.transferFrom, style: TextStyle(color: c.muted)),
        Text(
          '${str(widget.from['name'])} · ${widget.fromCurrency}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(t.transferTo, style: TextStyle(color: c.muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final (a, currency) in _targets)
              ChoiceChip(
                avatar: AccountBadge(
                  accountId: str(a['id']),
                  name: str(a['name']),
                  size: 24,
                ),
                label: Text('${str(a['name'])} · $currency'),
                selected: str(a['id']) == _toAccount && currency == _toCurrency,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() {
                          _toAccount = str(a['id']);
                          _toCurrency = currency;
                          _arrivedEdited = false;
                        });
                        _suggestFor(_sent.text);
                      },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Field(
          controller: _sent,
          label: t.transferSentLabel(widget.fromCurrency),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            setState(() {});
            _suggestFor(v);
          },
        ),
        if (_crossing) ...<Widget>[
          Field(
            controller: _arrived,
            label: t.transferArrivedLabel(_toCurrency),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _arrivedEdited = true),
          ),
          if (sent != null && arrived != null)
            Text(
              t.transferRate(
                impliedRate(sent, widget.fromCurrency, arrived, _toCurrency),
              ),
              style: TextStyle(color: c.muted),
            ),
          if (_suggest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t.transferSuggest(_suggest),
                style: TextStyle(color: c.muted),
              ),
            ),
          const SizedBox(height: 8),
        ],
        Field(
          controller: _fee,
          label: t.transferFeeLabel(widget.fromCurrency),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: Text(t.transferMove),
        ),
      ],
    );
  }
}
