// HOW EACH THING IN THE CHAT LOOKS. THE ASSISTANT'S WORDS ARE PLAIN TEXT, THE PERSON'S ARE SMALL SOFT CHIPS, WHAT IT DID IS ONE QUIET LINE,
// AND ANYTHING THAT NEEDS A DECISION (A CONFIRMATION, A CARD, A SPLIT) IS A CARD WITH ONE CLEAR BUTTON.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../payday/split_card.dart';
import 'agent_text.dart';
import 'chat_state.dart';
import 'live_parts.dart';

// -- FUNCTIONS -- //

String _name(BuildContext context, Object? accounts, String id) {
  for (final a in asJsonList(accounts)) {
    if (str(a['id']) == id) return str(a['name']);
  }
  return context.t.chatYourAccount;
}

/// Undoes a created entry: finds its place in the recent changes, then undoes it.
Future<void> undoEntry(
  ApiClient api,
  String entityId, {
  String gone = 'That entry can no longer be undone.',
}) async {
  final recent = await api.verbList('ledger_undoable', <String, Object?>{
    'limit': 20,
  });
  for (final r in recent) {
    if (str(asJson(r['after'])['id']) == entityId) {
      await api.verb('undo', <String, Object?>{'journalId': str(r['id'])});
      return;
    }
  }
  throw ApiException('NOT_FOUND', gone, 404);
}

class ChatItemView extends ConsumerWidget {
  const ChatItemView(this.item, {super.key});

  final ChatItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return switch (item) {
      UserItem(:final text, :final photo) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(photo ? context.t.chatWithPhoto(text) : text),
            ),
          ),
        ),
      ),
      AgentItem(:final text, :final streaming) => Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AgentText(text),
            if (streaming) const StreamCaret(),
          ],
        ),
      ),
      ThinkingItem() => ThinkingPanel(item as ThinkingItem),
      ToolItem() => _ToolView(item as ToolItem),
      CardItem() => _CardView(item as CardItem),
      FallbackItem() => PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.t.chatAssistantDown, style: text.titleSmall),
            const SizedBox(height: 4),
            Text(
              context.t.chatAddExpenseHint,
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/expense'),
              child: Text(context.t.chatAddExpense),
            ),
          ],
        ),
      ),
      NoticeItem(:final text) => Text(text, style: TextStyle(color: c.muted)),
    };
  }
}

class _ToolView extends ConsumerWidget {
  const _ToolView(this.item);

  final ToolItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Started and not answered yet: a spinner and what it is doing, never the "failed" words below
    if (item.running) return RunningToolRow(item.name);
    if (item.status == 'needs_approval') return const SizedBox.shrink();
    if (item.status != 'ok') {
      return Text(
        item.message ?? context.t.chatToolFailed,
        style: TextStyle(color: c.muted),
      );
    }
    final data = asJson(item.data);
    final accounts = ref.watch(balancesProvider).value;
    final notifier = ref.read(chatProvider.notifier);
    final api = ref.read(apiProvider);

    switch (item.name) {
      case 'expense_from_text' || 'expense_log':
        switch (str(data['status'])) {
          case 'saved':
            final txn = asJson(data['txn']);
            return _Logged(
              line: context.t.chatLogged(
                context.money(intOf(txn['amount'])),
                _name(context, accounts, str(txn['accountId'])),
              ),
              undoable: !item.resolved,
              undone: item.resolved,
              onUndo: () => _undo(context, ref, str(txn['id'])),
            );
          case 'needs_confirmation':
            final chip = asJson(data['chip']);
            return _Ask(
              question: context.t.chatConfirmQuestion(
                context.money(intOf(chip['amount'])),
                str(chip['accountName']),
              ),
              resolved: item.resolved,
              yes: context.t.chatYesLogIt,
              onYes: () async {
                await api.verb('expense_log', <String, Object?>{
                  'accountId': str(chip['accountId']),
                  'amount': intOf(chip['amount']),
                  'note': str(chip['note']),
                  'confirmed': true,
                });
                notifier.answer(item.id);
                ref
                  ..invalidate(balancesProvider)
                  ..invalidate(syncProvider);
              },
              onNo: () async => notifier.answer(item.id),
            );
          case 'needs_account':
            return _Choose(
              question: context.t.chatWhichAccount(
                context.money(intOf(data['amount'])),
              ),
              names: asList(data['accounts']).whereType<String>().toList(),
              resolved: item.resolved,
              onPick: (name) async {
                final match = asJsonList(accounts)
                    .where((a) => str(a['name']) == name);
                if (match.isEmpty) return;
                await api.verb('expense_log', <String, Object?>{
                  'accountId': str(match.first['id']),
                  'amount': intOf(data['amount']),
                  'note': str(data['note']),
                });
                notifier.answer(item.id);
                ref
                  ..invalidate(balancesProvider)
                  ..invalidate(syncProvider);
              },
            );
          case 'needs_amount':
            return Text(
              context.t.chatHowMuch,
              style: TextStyle(color: c.muted),
            );
        }
        return const SizedBox.shrink();
      case 'income_record' || 'refund_record' || 'transfer_record':
        return _Logged(
          line: context.t.chatRecorded(context.money(intOf(data['amount']))),
          undoable: !item.resolved,
          undone: item.resolved,
          onUndo: () => _undo(context, ref, str(data['id'])),
        );
      case 'split_propose':
        if (str(data['status']) == 'needs_amounts') {
          final names = asJsonList(data['bills'])
              .map((b) => str(b['name']))
              .join(', ');
          return Text(
            context.t.chatNeedsAmounts(names),
            style: TextStyle(color: c.muted),
          );
        }
        return SplitCard(
          plan: data,
          onChanged: () => ref
            ..invalidate(balancesProvider)
            ..invalidate(syncProvider),
        );
      case 'rule_from_text' || 'rule_propose':
        return _RuleCard(rule: data);
      case 'bill_mark_paid':
        return Text(
          context.t.chatMarkedPaid(context.money(intOf(data['amount']))),
          style: TextStyle(color: c.muted),
        );
      default:
        // A read the assistant did: one small quiet line, never a block
        return Row(
          children: <Widget>[
            Icon(Icons.search, size: 14, color: c.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _humanize(context, item.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
          ],
        );
    }
  }

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    String entityId,
  ) async {
    try {
      await undoEntry(
        ref.read(apiProvider),
        entityId,
        gone: context.t.chatUndoGone,
      );
      ref.read(chatProvider.notifier).answer(item.id, data: item.data);
      ref
        ..invalidate(balancesProvider)
        ..invalidate(syncProvider);
      if (context.mounted) say(context, context.t.chatUndoneSnack);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }
}

String _humanize(BuildContext context, String name) {
  final words = name.replaceAll('_', ' ');
  return context.t.chatChecked(words);
}

class _Logged extends StatelessWidget {
  const _Logged({
    required this.line,
    required this.undoable,
    required this.undone,
    required this.onUndo,
  });

  final String line;
  final bool undoable;
  final bool undone;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: <Widget>[
        Icon(
          undone ? Icons.undo : Icons.check_circle_outline,
          size: 16,
          color: undone ? c.muted : c.success,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            undone ? context.t.chatUndoneLine : line,
            style: TextStyle(color: c.muted, fontSize: 14),
          ),
        ),
        if (undoable)
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(context.t.undo),
          ),
      ],
    );
  }
}

class _Ask extends StatelessWidget {
  const _Ask({
    required this.question,
    required this.yes,
    required this.onYes,
    required this.onNo,
    required this.resolved,
  });

  final String question;
  final String yes;
  final Future<void> Function() onYes;
  final Future<void> Function() onNo;
  final bool resolved;

  @override
  Widget build(BuildContext context) {
    if (resolved)
      return Text(question, style: TextStyle(color: context.colors.muted));
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(question),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              FilledButton(onPressed: onYes, child: Text(yes)),
              const SizedBox(width: 8),
              TextButton(onPressed: onNo, child: Text(context.t.no)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Choose extends StatelessWidget {
  const _Choose({
    required this.question,
    required this.names,
    required this.onPick,
    required this.resolved,
  });

  final String question;
  final List<String> names;
  final Future<void> Function(String name) onPick;
  final bool resolved;

  @override
  Widget build(BuildContext context) {
    if (resolved)
      return Text(question, style: TextStyle(color: context.colors.muted));
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(question),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final n in names)
                ActionChip(label: Text(n), onPressed: () => onPick(n)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends ConsumerStatefulWidget {
  const _RuleCard({required this.rule});

  final Json rule;

  @override
  ConsumerState<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends ConsumerState<_RuleCard> {
  String _status = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final status = _status.isEmpty ? str(widget.rule['status']) : _status;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(str(widget.rule['summary'])),
          const SizedBox(height: 8),
          if (status == 'proposed')
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await ref.read(apiProvider).verb(
                          'rule_approve',
                          <String, Object?>{'ruleId': str(widget.rule['id'])},
                        );
                        if (mounted) setState(() => _status = 'active');
                      } catch (e) {
                        if (context.mounted)
                          say(context, errorWords(e, context));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text(context.t.chatApproveRule),
            )
          else
            Text(
              status == 'active' ? context.t.chatInForce : status,
              style: TextStyle(color: context.colors.success),
            ),
        ],
      ),
    );
  }
}

class _CardView extends ConsumerWidget {
  const _CardView(this.item);

  final CardItem item;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final notifier = ref.read(chatProvider.notifier);
    try {
      final r = await ref
          .read(apiProvider)
          .decideCard(item.actionId, approve: approve);
      final status = str(asJson(r['action'])['status']);
      final failed = status == 'failed';
      notifier.setCard(
        item.id,
        approve
            ? (failed ? CardState.failed : CardState.approved)
            : CardState.declined,
        note: failed
            ? str(asJson(asJson(r['action'])['result'])['error'])
            : null,
      );
      ref
        ..invalidate(balancesProvider)
        ..invalidate(syncProvider);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.t.chatPleaseCheck, style: TextStyle(color: c.muted)),
          const SizedBox(height: 4),
          Text(item.summary, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          switch (item.state) {
            CardState.waiting => Row(
              children: <Widget>[
                FilledButton(
                  onPressed: () => _decide(context, ref, approve: true),
                  child: Text(context.t.chatApprove),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _decide(context, ref, approve: false),
                  child: Text(context.t.chatNotNow),
                ),
              ],
            ),
            CardState.approved => Text(
              context.t.done,
              style: TextStyle(color: c.success),
            ),
            CardState.declined => Text(
              context.t.chatNotDone,
              style: TextStyle(color: c.muted),
            ),
            CardState.failed => Text(
              item.note ?? context.t.chatCardFailed,
              style: TextStyle(color: c.danger),
            ),
          },
        ],
      ),
    );
  }
}
