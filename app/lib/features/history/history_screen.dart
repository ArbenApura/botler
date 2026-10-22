// HISTORY: EVERYTHING YOU SPENT OR MOVED, THE MONTH SO FAR, SEARCH, UNDO, AND "FIX THIS" (UNDOES THE ENTRY AND OPENS THE FORM WITH ITS VALUES).
// A transfer between your own accounts is shown as a move, not as spending. Undone entries stay in the list, struck through, so nothing disappears.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
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
  final now = DateTime.now();
  final f = DateFormat('yyyy-MM-dd');
  return ref.watch(apiProvider).verbJson('ledger_spending', <String, Object?>{
    'from': f.format(DateTime(now.year, now.month)),
    'to': f.format(now),
  });
});

// -- TYPES -- //

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _query = '';

  void _refresh() {
    ref
      ..invalidate(_entriesProvider)
      ..invalidate(_monthProvider)
      ..invalidate(balancesProvider)
      ..invalidate(syncProvider);
  }

  Future<void> _undo(Json e) async {
    try {
      await undoEntry(ref.read(apiProvider), str(e['id']));
      _refresh();
      if (mounted) say(context, 'Undone.');
    } catch (err) {
      if (mounted) say(context, errorWords(err));
    }
  }

  Future<void> _fix(Json e) async {
    try {
      await undoEntry(ref.read(apiProvider), str(e['id']));
      _refresh();
      if (!mounted) return;
      await context.push(
        '/expense',
        extra: <String, Object?>{
          'amount': pesosText(intOf(e['amount'])),
          'note': str(e['note']),
        },
      );
    } catch (err) {
      if (mounted) say(context, errorWords(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = <String, String>{
      for (final a in ref.watch(balancesProvider).value ?? <Json>[])
        str(a['id']): str(a['name']),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AsyncBody<Json>(
            value: ref.watch(_monthProvider),
            onRetry: () => ref.invalidate(_monthProvider),
            data: (m) => PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Spent this month', style: TextStyle(color: c.muted)),
                  Amount(intOf(m['spending'])),
                  if (intOf(m['untracked']) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${formatPhp(intOf(m['untracked']))} went untracked (found when you counted an account).',
                        style: TextStyle(color: c.warning),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by note, category or amount',
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          AsyncBody<List<Json>>(
            value: ref.watch(_entriesProvider),
            onRetry: () => ref.invalidate(_entriesProvider),
            data: (all) {
              final list = all
                  .where(
                    (e) =>
                        _query.isEmpty ||
                        '${str(e['note'])} ${str(e['category'])} ${pesosText(intOf(e['amount']))} ${str(e['type'])}'
                            .toLowerCase()
                            .contains(_query),
                  )
                  .toList();
              if (list.isEmpty) return const Note('Nothing here yet.');
              return Column(
                children: <Widget>[
                  for (final e in list)
                    _Row(
                      entry: e,
                      account: names[str(e['accountId'])] ?? 'account',
                      to: names[str(e['toAccountId'])],
                      onUndo: () => _undo(e),
                      onFix: () => _fix(e),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.account,
    required this.to,
    required this.onUndo,
    required this.onFix,
  });

  final Json entry;
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
    final when = dateOf(entry['occurredAt'])?.toLocal();
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
        type == 'transfer' ? 'Moved $account → ${to ?? 'account'}' : title,
        style: style,
      ),
      subtitle: Text(
        '${type == 'transfer' ? '' : '$account · '}${when == null ? '' : DateFormat('MMM d, h:mm a').format(when)}${voided ? ' · undone' : ''}',
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
                : ''}${formatPhp(amount)}',
            style: style.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          if (!voided && type != 'adjustment')
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'undo' ? onUndo() : onFix(),
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(value: 'undo', child: Text('Undo')),
                if (type == 'expense')
                  const PopupMenuItem<String>(
                    value: 'fix',
                    child: Text('Fix this'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
