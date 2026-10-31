// HISTORY: EVERYTHING YOU SPENT OR MOVED, THE MONTH SO FAR, SEARCH, UNDO, AND "FIX THIS" (UNDOES THE ENTRY AND OPENS THE FORM WITH ITS VALUES).
// A transfer between your own accounts is shown as a move, not as spending. Undone entries stay in the list, struck through, so nothing disappears.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/money.dart' show defaultCurrency;
import '../../core/money_scope.dart';
import '../../core/json.dart';
import '../../core/manila.dart' show manilaToday;
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';
import '../chat/chat_items.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _entriesProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('ledger_list', <String, Object?>{
        'limit': 200,
      }),
    );

final FutureProvider<Json> _monthProvider = FutureProvider.autoDispose<Json>((
  ref,
) {
  // The month so far, by Manila dates
  final today = manilaToday();
  return ref.watch(apiProvider).verbJson('ledger_spending', <String, Object?>{
    'from': '${today.substring(0, 8)}01',
    'to': today,
  });
});

/// How many entries one read brings; the server's own ceiling.
const int _pageSize = 200;

/// How long after the last key the search runs.
const Duration _searchPause = Duration(milliseconds: 300);

// -- TYPES -- //

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  // -- STATES -- //

  String _query = '';
  Timer? _pause;
  // Entries older than the first read, brought by "Load more" (the first 200 come from the provider)
  final List<Json> _older = <Json>[];
  bool _loadingMore = false;
  bool _noMore = false;
  // One key per undo, until it works, and no second tap of the same one while it runs
  final Once _once = Once();

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _pause?.cancel();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  void _refresh() {
    _older.clear();
    _noMore = false;
    ref
      ..invalidate(_entriesProvider)
      ..invalidate(_monthProvider)
      ..invalidate(balancesProvider)
      ..invalidate(syncProvider);
  }

  void _typed(String words) {
    _pause?.cancel();
    _pause = Timer(_searchPause, () {
      if (mounted) setState(() => _query = words.trim().toLowerCase());
    });
  }

  /// Reads the next 200 entries older than what is loaded. The server pages by date, so the read starts at the oldest loaded day and the
  /// entries already held are dropped by id; when nothing new comes the end is reached.
  Future<void> _loadMore(List<Json> held) async {
    if (_loadingMore || held.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final oldest = dateOf(held.last['occurredAt']);
      final found = await ref.read(apiProvider).verbList(
        'ledger_list',
        <String, Object?>{
          'limit': _pageSize,
          if (oldest != null) 'to': manilaToday(oldest),
        },
      );
      final have = <String>{for (final e in held) str(e['id'])};
      final fresh = <Json>[
        for (final e in found)
          if (have.add(str(e['id']))) e,
      ];
      if (!mounted) return;
      setState(() {
        _older.addAll(fresh);
        if (fresh.isEmpty || found.length < _pageSize) _noMore = true;
      });
    } catch (err) {
      if (mounted) say(context, errorWords(err, context));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _undo(Json e) async {
    final id = str(e['id']);
    try {
      final ran = await _once.ok(
        (key) => undoEntry(ref.read(apiProvider), id, key: key),
        intent: 'undo:$id',
      );
      if (!ran) return;
      _refresh();
      if (mounted) say(context, context.t.historyUndoneSaid);
    } catch (err) {
      if (mounted) say(context, errorWords(err));
    }
  }

  /// Opens the form with the entry's values. The entry is undone only after the form has saved the new one, so backing out changes nothing.
  Future<void> _fix(Json e) async {
    final id = str(e['id']);
    final saved = await context.push<Object>(
      '/expense',
      extra: <String, Object?>{
        'amount': plainAmountIn(intOf(e['amount']), _currencyOf(e)),
        'note': str(e['note']),
        'currency': _currencyOf(e),
      },
    );
    if (saved == 'queued') {
      // The new entry waits for a connection and the old one cannot be undone offline: say so, so it is not counted twice unseen
      if (mounted) say(context, context.t.fixQueued);
      return;
    }
    if (saved != true) return;
    try {
      await _once.ok(
        (key) => undoEntry(ref.read(apiProvider), id, key: key),
        intent: 'undo:$id',
      );
    } catch (err) {
      if (mounted) say(context, errorWords(err));
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = <String, String>{
      for (final a in ref.watch(balancesProvider).value ?? <Json>[])
        str(a['id']): str(a['name']),
    };
    // One date format for every row, in the app's language
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_jm();
    final entries = ref.watch(_entriesProvider);
    final first = entries.value;
    final held = first == null
        ? const <Json>[]
        : <Json>[
            ...first,
            for (final e in _older)
              if (!first.any((f) => str(f['id']) == str(e['id']))) e,
          ];
    final list = <Json>[
      for (final e in held)
        if (_query.isEmpty ||
            '${str(e['note'])} ${str(e['category'])} ${plainAmountIn(intOf(e['amount']), _currencyOf(e))} ${str(e['type'])} ${_currencyOf(e)}'
                .toLowerCase()
                .contains(_query))
          e,
    ];
    // More may exist when the last read was full; it also shows during a search, so a search can reach further back
    final canMore = first != null && !_noMore && held.length >= _pageSize;
    const lead = 4;
    final body = first == null
        ? 1
        : (list.isEmpty ? 1 : list.length) + (canMore ? 1 : 0);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.historyTitle)),
      body: ListView.builder(
        padding: pagePadding(context),
        itemCount: lead + body,
        itemBuilder: (_, i) {
          switch (i) {
            case 0:
              return AsyncBody<Json>(
                value: ref.watch(_monthProvider),
                skeleton: const SkeletonRows(count: 1, kind: SkeletonKind.card),
                onRetry: () => ref.invalidate(_monthProvider),
                data: (m) => _MonthCard(month: m, muted: c.muted),
              );
            case 1:
              return const SizedBox(height: 12);
            case 2:
              return TextField(
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.t.historySearchHint,
                ),
                onChanged: _typed,
              );
            case 3:
              return const SizedBox(height: 8);
          }
          final n = i - lead;
          if (first == null) {
            return AsyncBody<List<Json>>(
              value: entries,
              skeleton: const SkeletonRows(count: 4),
              onRetry: () => ref.invalidate(_entriesProvider),
              data: (_) => const SizedBox.shrink(),
            );
          }
          if (list.isEmpty && n == 0) {
            return Column(
              children: <Widget>[
                Note(context.t.historyEmpty),
                if (canMore)
                  _MoreButton(
                    loading: _loadingMore,
                    onTap: () => _loadMore(held),
                  ),
              ],
            );
          }
          if (n >= list.length) {
            return _MoreButton(
              loading: _loadingMore,
              onTap: () => _loadMore(held),
            );
          }
          final e = list[n];
          return _Row(
            entry: e,
            format: format,
            account:
                names[str(e['accountId'])] ?? context.t.historyAccountFallback,
            to: names[str(e['toAccountId'])],
            onUndo: () => _undo(e),
            onFix: () => _fix(e),
          );
        },
      ),
    );
  }
}

/// The month so far, as a card.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month, required this.muted});

  final Json month;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = month;
    final others = asList(m['otherCurrencies']).whereType<String>();
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.t.historySpentThisMonth, style: TextStyle(color: muted)),
          Amount(
            intOf(m['spending']),
            currency: str(m['currency'], context.currencyCode),
          ),
          if (others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.t.historyOtherCurrencies(others.join(', ')),
                style: TextStyle(color: muted),
              ),
            ),
          if (intOf(m['untracked']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.t.historyUntracked(
                  context.moneyIn(
                    intOf(m['untracked']),
                    str(m['currency'], context.currencyCode),
                  ),
                ),
                style: TextStyle(color: c.warning),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Load more" under the list, at least 48 dp tall.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: loading ? null : onTap,
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      child: Text(context.t.acctLoadMore),
    );
  }
}

/// The currency of a ledger row: its own, else the main one (an older server sends none).
String _currencyOf(Json e) => str(e['currency'], defaultCurrency);

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.format,
    required this.account,
    required this.to,
    required this.onUndo,
    required this.onFix,
  });

  final Json entry;

  /// The date format of the whole list, made once by the screen.
  final DateFormat format;
  final String account;
  final String? to;
  final VoidCallback onUndo;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final type = str(entry['type']);
    final voided = entry['voidedAt'] != null;
    final amount = intOf(entry['amount']);
    final sign = switch (type) {
      'income' || 'refund' => 1,
      'expense' => -1,
      _ => 0,
    };
    final at = dateOf(entry['occurredAt']);
    final when = at == null ? null : manilaWall(at);
    final title = str(entry['note']).isNotEmpty
        ? str(entry['note'])
        : (str(entry['category']).isNotEmpty ? str(entry['category']) : type);
    final style = TextStyle(
      decoration: voided ? TextDecoration.lineThrough : null,
      color: voided ? c.muted : null,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        type == 'transfer'
            ? context.t.historyMoved(
                account,
                to ?? context.t.historyAccountFallback,
              )
            : title,
        style: style,
      ),
      subtitle: Text(
        '${type == 'transfer' ? '' : '$account · '}${when == null ? '' : format.format(when)}${voided ? ' · ${context.t.historyUndoneTag}' : ''}',
        style: TextStyle(color: c.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${sign > 0
                ? '+'
                : sign < 0
                ? '-'
                : ''}${context.moneyIn(amount, _currencyOf(entry))}',
            style: Theme.of(context).textTheme.titleMedium
                ?.merge(style)
                .copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
          ),
          if (!voided && type != 'adjustment')
            PopupMenuButton<String>(
              tooltip: context.t.historyMore,
              onSelected: (v) => v == 'undo' ? onUndo() : onFix(),
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'undo',
                  child: Text(context.t.undo),
                ),
                if (type == 'expense')
                  PopupMenuItem<String>(
                    value: 'fix',
                    child: Text(context.t.historyFixThis),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
