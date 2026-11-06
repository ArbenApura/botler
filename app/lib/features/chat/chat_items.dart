// HOW EACH THING IN THE CHAT LOOKS. THE ASSISTANT'S WORDS ARE PLAIN TEXT, THE PERSON'S ARE SMALL SOFT CHIPS, WHAT IT DID IS ONE QUIET LINE,
// AND ANYTHING THAT NEEDS A DECISION (A CONFIRMATION, A CARD, A SPLIT) IS A CARD WITH ONE CLEAR BUTTON.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'web_mark_card.dart';
import 'message_actions.dart';
import 'notebook_rows.dart';
import 'photo_mark_card.dart';
import 'shown_files.dart';
import 'photo_widgets.dart';
import 'script_card.dart';

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
  String? key,
}) async {
  final recent = await api.verbList('ledger_undoable', <String, Object?>{
    'limit': 20,
  });
  for (final r in recent) {
    if (str(asJson(r['after'])['id']) == entityId) {
      await api.verb('undo', <String, Object?>{'journalId': str(r['id'])}, key);
      return;
    }
  }
  throw ApiException('NOT_FOUND', gone, 404);
}

class ChatItemView extends ConsumerWidget {
  const ChatItemView(this.item, {this.more = 0, super.key});

  final ChatItem item;

  /// How many identical quiet tool lines were folded into this one.
  final int more;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return switch (item) {
      UserItem(:final text, :final photos, :final photoPaths, :final turnId) =>
        Align(
          alignment: Alignment.centerRight,
          child: _Actionable(
            text: text,
            turnId: turnId,
            itemId: item.id,
            mine: true,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The pictures themselves when this phone still has them, otherwise just the count of photos in words
                      if (photoPaths.isNotEmpty) ...<Widget>[
                        PhotoGrid(paths: photoPaths),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        photos > 0 && photoPaths.isEmpty
                            ? context.t.chatWithPhotos(text, photos)
                            : text,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      AgentItem(:final text, :final streaming, :final turnId) => Padding(
        padding: const EdgeInsets.only(right: 24),
        child: _Actionable(
          text: text,
          turnId: streaming ? null : turnId,
          mine: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AgentText(text, streaming: streaming),
              if (streaming) const StreamCaret(),
            ],
          ),
        ),
      ),
      ThinkingItem() => ThinkingPanel(item as ThinkingItem),
      ToolItem() => _ToolView(item as ToolItem, more: more),
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
      DividerItem() => const _EarlierDivider(),
    };
  }
}

/// A message that opens its action sheet on a long press (and by the screen reader's own action list).
class _Actionable extends ConsumerWidget {
  const _Actionable({
    required this.text,
    required this.turnId,
    required this.mine,
    required this.child,
    this.itemId,
  });

  final String text;
  final String? turnId;
  final int? itemId;
  final bool mine;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => unawaited(
      showMessageSheet(
        context,
        ref,
        text: text,
        turnId: turnId,
        mine: mine,
        itemId: itemId,
      ),
    );
    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: context.t.chatMsgActions): open,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: open,
        child: child,
      ),
    );
  }
}

class _ToolView extends ConsumerWidget {
  const _ToolView(this.item, {this.more = 0});

  final ToolItem item;
  final int more;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Started and not answered yet: a spinner and what it is doing, never the "failed" words below
    if (item.running) {
      if (item.name == 'script_run' || item.name == 'toolbox') {
        return ScriptCard(
          stage: ScriptStage.running,
          toolbox: item.name == 'toolbox',
        );
      }
      return RunningToolRow(item.name);
    }
    // From an earlier session: one quiet read-only line, never a chip or Undo
    if (item.restored) return _RestoredToolLine(item, more: more);
    if (item.status == 'needs_approval') return const SizedBox.shrink();
    if (item.status != 'ok') {
      if (item.name == 'script_run' || item.name == 'toolbox') {
        return ScriptCard(
          stage: ScriptStage.failed,
          toolbox: item.name == 'toolbox',
          message: item.message,
        );
      }
      return Text(
        item.message ?? context.t.chatToolFailed,
        style: TextStyle(color: c.muted),
      );
    }
    // A save in a notebook is one quiet line of its own, never "Checked ...": it names what the answer says was written
    if (isNotebookWrite(item.name)) {
      return _QuietRow(
        icon: Icons.menu_book_outlined,
        text: notebookWriteLine(context, item.name, item.data) ?? '',
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted) ??
            TextStyle(color: c.muted),
        maxLines: 2,
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
                context.moneyIn(
                  intOf(txn['amount']),
                  str(txn['currency'], context.currencyCode),
                ),
                _name(context, accounts, str(txn['accountId'])),
              ),
              undoable: !item.resolved,
              undone: item.resolved,
              onUndo: (key) => _undo(context, ref, str(txn['id']), key),
            );
          case 'needs_confirmation':
            final chip = asJson(data['chip']);
            return _Ask(
              question: context.t.chatConfirmQuestion(
                context.moneyIn(
                  intOf(chip['amount']),
                  str(chip['currency'], context.currencyCode),
                ),
                str(chip['accountName']),
              ),
              resolved: item.resolved,
              yes: context.t.chatYesLogIt,
              onYes: (key) async {
                await api.verb('expense_log', <String, Object?>{
                  'accountId': str(chip['accountId']),
                  'amount': intOf(chip['amount']),
                  if (str(chip['currency']).isNotEmpty)
                    'currency': str(chip['currency']),
                  'note': str(chip['note']),
                  'confirmed': true,
                }, key);
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
                context.moneyIn(
                  intOf(data['amount']),
                  str(data['currency'], context.currencyCode),
                ),
              ),
              names: asList(data['accounts']).whereType<String>().toList(),
              resolved: item.resolved,
              onPick: (name, key) async {
                final match = asJsonList(accounts)
                    .where((a) => str(a['name']) == name);
                if (match.isEmpty) return;
                await api.verb('expense_log', <String, Object?>{
                  'accountId': str(match.first['id']),
                  'amount': intOf(data['amount']),
                  if (str(data['currency']).isNotEmpty)
                    'currency': str(data['currency']),
                  'note': str(data['note']),
                }, key);
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
          line: context.t.chatRecorded(
            context.moneyIn(
              intOf(data['amount']),
              str(data['currency'], context.currencyCode),
            ),
          ),
          undoable: !item.resolved,
          undone: item.resolved,
          onUndo: (key) => _undo(context, ref, str(data['id']), key),
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
        // A bill's amount is in the bill's own currency
        return Text(
          context.t.chatMarkedPaid(
            context.moneyIn(
              intOf(data['amount']),
              str(data['currency'], context.currencyCode),
            ),
          ),
          style: TextStyle(color: c.muted),
        );
      case 'script_run' || 'toolbox':
        // A script the phone ran for the assistant (or the toolbox it opened): a card with the start of what it printed and the files it showed
        final shown = shownOf(data);
        return ScriptCard(
          stage: ScriptStage.done,
          toolbox: item.name == 'toolbox',
          output: item.name == 'toolbox' ? '' : str(data['output']),
          files: shown.isEmpty
              ? null
              : ShownFiles(files: shown, chatId: ref.read(chatProvider).chatId),
        );
      default:
        // A read the assistant did: one small quiet line, never a block
        return _QuietRow(
          icon: Icons.search,
          text: _humanize(context, item.name),
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted) ??
              TextStyle(color: c.muted),
          more: more,
        );
    }
  }

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    String entityId,
    String key,
  ) async {
    try {
      await undoEntry(
        ref.read(apiProvider),
        entityId,
        gone: context.t.chatUndoGone,
        key: key,
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

/// One quiet line for something the assistant looked up. [more] is how many identical lines were folded into it: it shows as "+5" and is read out in words.
class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.icon,
    required this.text,
    required this.style,
    this.more = 0,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;
  final TextStyle style;
  final int more;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: <Widget>[
        Icon(icon, size: 14, color: style.color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              context.t.chatCheckedMore(more),
              // Tabular figures so the count does not shift as it grows
              style: style.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
    if (more == 0) return row;
    return Semantics(
      label: context.t.chatCheckedMany(text, more),
      excludeSemantics: true,
      child: row,
    );
  }
}

/// A tool result from an earlier session as one quiet line. It shows an amount only when the stored answer really holds it, never a made up one.
class _RestoredToolLine extends ConsumerWidget {
  const _RestoredToolLine(this.item, {this.more = 0});

  final ToolItem item;
  final int more;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final muted = TextStyle(color: c.muted, fontSize: 13);
    if (item.status != 'ok') {
      return Text(item.message ?? context.t.chatToolFailed, style: muted);
    }
    // The same words as the live line, from the stored answer
    if (isNotebookWrite(item.name)) {
      return _QuietRow(
        icon: Icons.menu_book_outlined,
        text: notebookWriteLine(context, item.name, item.data) ?? '',
        style: muted,
        maxLines: 2,
      );
    }
    final data = asJson(item.data);
    String? line;
    switch (item.name) {
      case 'expense_from_text' || 'expense_log':
        final txn = asJson(data['txn']);
        if (str(data['status']) == 'saved' && txn['amount'] is int) {
          final accounts = ref.watch(balancesProvider).value;
          line = context.t.chatLogged(
            context.moneyIn(
              intOf(txn['amount']),
              str(txn['currency'], context.currencyCode),
            ),
            _name(context, accounts, str(txn['accountId'])),
          );
        }
      case 'income_record' || 'refund_record' || 'transfer_record':
        if (data['amount'] is int) {
          line = context.t.chatRecorded(
            context.moneyIn(
              intOf(data['amount']),
              str(data['currency'], context.currencyCode),
            ),
          );
        }
      case 'bill_mark_paid':
        if (data['amount'] is int) {
          line = context.t.chatMarkedPaid(
            context.moneyIn(
              intOf(data['amount']),
              str(data['currency'], context.currencyCode),
            ),
          );
        }
    }
    if (item.name == 'script_run' || item.name == 'toolbox') {
      final row = _QuietRow(
        icon: item.name == 'toolbox' ? Icons.build_outlined : Icons.code,
        text: item.name == 'toolbox'
            ? context.t.chatUsedToolbox
            : context.t.chatRanScriptQuiet,
        style: muted,
        more: more,
        maxLines: 2,
      );
      final shown = shownOf(item.data);
      if (shown.isEmpty) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          row,
          ShownFiles(files: shown, chatId: ref.read(chatProvider).chatId),
        ],
      );
    }
    return _QuietRow(
      icon: line == null ? Icons.search : Icons.check_circle_outline,
      text: line ?? _humanize(context, item.name),
      style: muted,
      more: more,
      maxLines: 2,
    );
  }
}

/// The line between the conversation from before and the one happening now.
class _EarlierDivider extends StatelessWidget {
  const _EarlierDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: context.t.chatEarlier,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Expanded(child: Divider(color: c.line, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                context.t.chatEarlier,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: c.muted),
              ),
            ),
            Expanded(child: Divider(color: c.line, height: 1)),
          ],
        ),
      ),
    );
  }
}

class _Logged extends StatefulWidget {
  const _Logged({
    required this.line,
    required this.undoable,
    required this.undone,
    required this.onUndo,
  });

  final String line;
  final bool undoable;
  final bool undone;

  /// Gets the request key of this undo: the same one for a second tap.
  final Future<void> Function(String key) onUndo;

  @override
  State<_Logged> createState() => _LoggedState();
}

class _LoggedState extends State<_Logged> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  String get line => widget.line;
  bool get undoable => widget.undoable;
  bool get undone => widget.undone;

  Future<void> _run() async {
    await _once.run(widget.onUndo);
  }

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
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: c.muted),
          ),
        ),
        if (undoable)
          TextButton(
            onPressed: _once.running() ? null : _run,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(48, 48),
            ),
            child: Text(context.t.undo),
          ),
      ],
    );
  }
}

class _Ask extends StatefulWidget {
  const _Ask({
    required this.question,
    required this.yes,
    required this.onYes,
    required this.onNo,
    required this.resolved,
  });

  final String question;
  final String yes;

  /// Gets the request key of this answer: the same one for a second tap.
  final Future<void> Function(String key) onYes;
  final Future<void> Function() onNo;
  final bool resolved;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  String get question => widget.question;
  String get yes => widget.yes;
  bool get resolved => widget.resolved;

  Future<void> _answer(Future<void> Function(String key) body) async {
    try {
      await _once.run(body);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

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
              FilledButton(
                onPressed: _once.running() ? null : () => _answer(widget.onYes),
                child: Text(yes),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _once.running()
                    ? null
                    : () => _answer((_) => widget.onNo()),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(context.t.no),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Choose extends StatefulWidget {
  const _Choose({
    required this.question,
    required this.names,
    required this.onPick,
    required this.resolved,
  });

  final String question;
  final List<String> names;

  /// Gets the picked name and the request key of this pick.
  final Future<void> Function(String name, String key) onPick;
  final bool resolved;

  @override
  State<_Choose> createState() => _ChooseState();
}

class _ChooseState extends State<_Choose> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  String get question => widget.question;
  List<String> get names => widget.names;
  bool get resolved => widget.resolved;

  Future<void> _pick(String name) async {
    try {
      // One intent for the whole card: a second chip is not a second entry
      await _once.run((key) => widget.onPick(name, key));
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

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
                ActionChip(
                  label: Text(n),
                  onPressed: _once.running() ? null : () => _pick(n),
                ),
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
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final status = _status.isEmpty ? str(widget.rule['status']) : _status;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (str(widget.rule['label']).isNotEmpty)
            Text(
              str(widget.rule['label']),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          Text(ruleSentence(widget.rule)),
          const SizedBox(height: 8),
          if (status == 'proposed')
            FilledButton(
              onPressed: _once.running()
                  ? null
                  : () async {
                      try {
                        await _once.run((key) async {
                          await ref.read(apiProvider).verb(
                            'rule_approve',
                            <String, Object?>{'ruleId': str(widget.rule['id'])},
                            key,
                          );
                        });
                        if (mounted) setState(() => _status = 'active');
                      } catch (e) {
                        if (context.mounted) {
                          say(context, errorWords(e, context));
                        }
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

class _CardView extends ConsumerStatefulWidget {
  const _CardView(this.item);

  final CardItem item;

  @override
  ConsumerState<_CardView> createState() => _CardViewState();
}

class _CardViewState extends ConsumerState<_CardView> {
  // -- STATES -- //
  // The action id is the stable key of a card decision (the server takes no request key for it), so only the in-flight guard is needed
  bool _deciding = false;

  CardItem get item => widget.item;

  Future<void> _decide({required bool approve, Uint8List? picture}) async {
    if (_deciding) return;
    setState(() => _deciding = true);
    final notifier = ref.read(chatProvider.notifier);
    try {
      final r = await ref
          .read(apiProvider)
          .decideCard(
            item.actionId,
            approve: approve,
            imageData: picture == null ? null : base64Encode(picture),
          );
      final status = str(asJson(r['action'])['status']);
      final failed = status == 'failed';
      // Only an action that was really applied is "done": an expired or any other answer is never shown as approved
      notifier.setCard(
        item.id,
        !approve
            ? CardState.declined
            : switch (status) {
                'applied' => CardState.approved,
                'expired' => CardState.expired,
                _ => CardState.failed,
              },
        note: failed
            ? str(asJson(asJson(r['action'])['result'])['error'])
            : null,
      );
      ref
        ..invalidate(balancesProvider)
        ..invalidate(syncProvider)
        ..invalidate(pendingCardProvider(item.actionId))
        ..invalidate(webCandidatesProvider(item.actionId));
    } catch (e) {
      // "Already answered" (or gone) means this card is out of date: show how it really stands instead of an error on a live button
      if (e is ApiException &&
          (e.code == 'CONFLICT' || e.code == 'NOT_FOUND')) {
        await notifier.syncCards();
      } else if (mounted) {
        say(context, errorWords(e, context));
      }
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A card that uses a photo for a mark is drawn with its preview; every other card keeps the two buttons
    final photoCard =
        item.state == CardState.waiting &&
        !item.readOnly &&
        (item.verb == photoMarkVerb || item.verb == webMarkVerb);
    final pending = photoCard
        ? ref.watch(pendingCardProvider(item.actionId))
        : null;
    final photo = photoMarkOf(pending?.value);
    final web = webMarkOf(pending?.value);
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.t.chatPleaseCheck, style: TextStyle(color: c.muted)),
          const SizedBox(height: 4),
          Text(item.summary, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          switch (item.state) {
            CardState.waiting when item.readOnly => Text(
              context.t.chatCardElsewhere,
              style: TextStyle(color: c.muted),
            ),
            CardState.waiting when photo != null => PhotoMarkEditor(
              key: ValueKey<String>('photo.${item.actionId}'),
              actionId: item.actionId,
              turnId: item.turnId,
              photo: photo.photo,
              name: photo.name,
              plan: photo.plan,
              deciding: _deciding,
              onApprove: (bytes) => _decide(approve: true, picture: bytes),
              onReject: () => _decide(approve: false),
            ),
            CardState.waiting when web != null => WebMarkEditor(
              key: ValueKey<String>('web.${item.actionId}'),
              actionId: item.actionId,
              name: web.name,
              fit: web.fit,
              deciding: _deciding,
              onApprove: (bytes) => _decide(approve: true, picture: bytes),
              onReject: () => _decide(approve: false),
            ),
            // A photo card has no plain Approve: without its plan and its cut there is no picture to approve
            CardState.waiting when photoCard => Row(
              children: <Widget>[
                if (pending != null && pending.isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(pendingCardProvider(item.actionId)),
                    child: Text(context.t.photoMarkRetry),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _deciding ? null : () => _decide(approve: false),
                  child: Text(context.t.chatNotNow),
                ),
              ],
            ),
            CardState.waiting => Row(
              children: <Widget>[
                FilledButton(
                  onPressed: _deciding ? null : () => _decide(approve: true),
                  child: Text(context.t.chatApprove),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _deciding ? null : () => _decide(approve: false),
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
            CardState.expired => Text(
              context.t.chatCardExpired,
              style: TextStyle(color: c.muted),
            ),
          },
        ],
      ),
    );
  }
}
