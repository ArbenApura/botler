// WHAT THE CHAT SHOWS BEFORE ANYONE HAS SAID ANYTHING: A SKELETON WHILE THE EARLIER CONVERSATION IS COMING, A QUIET RETRY LINE IF IT COULD NOT BE LOADED,
// AND, ONLY WHEN IT LOADED AND THERE WAS NOTHING, A GREETING WITH A FEW THINGS TO TAP.
// A tap only puts words in the message box. Sending stays the person's own press of the one primary button.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'chat_state.dart';

// -- TYPES -- //

class ChatStart extends StatelessWidget {
  const ChatStart({
    required this.status,
    required this.onPick,
    required this.onRetry,
    super.key,
  });

  final RestoreStatus status;

  /// Called with the words to put in the message box.
  final ValueChanged<String> onPick;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    switch (status) {
      // Not asked yet counts as on its way, so the greeting never shows for a blink
      case RestoreStatus.idle:
      case RestoreStatus.loading:
        return const _EarlierSkeleton();
      case RestoreStatus.failed:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: <Widget>[
              Text(
                t.chatRestoreFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
              TextButton(onPressed: onRetry, child: Text(t.retry)),
            ],
          ),
        );
      case RestoreStatus.done:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                t.chatGreeting,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _Suggestion(
                    label: t.chatSuggestExpense,
                    words: t.chatSuggestExpenseText,
                    onPick: onPick,
                  ),
                  _Suggestion(
                    label: t.chatSuggestDue,
                    words: t.chatSuggestDue,
                    onPick: onPick,
                  ),
                  _Suggestion(
                    label: t.chatSuggestToday,
                    words: t.chatSuggestToday,
                    onPick: onPick,
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}

/// A tappable idea. It is 48 dp tall, reads as a button to a screen reader, and only fills the message box.
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.label,
    required this.words,
    required this.onPick,
  });

  final String label;
  final String words;
  final ValueChanged<String> onPick;

  @override
  // The chip is already a labelled button with its own tap action: wrapping it would hide that action from a screen reader
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    onPressed: () => onPick(words),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
  );
}

/// A few quiet lines where the earlier conversation will be: one short on the right (the person), longer ones on the left.
class _EarlierSkeleton extends StatelessWidget {
  const _EarlierSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: SkeletonGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: Skeleton(width: 140, height: 36, radius: 18),
          ),
          SizedBox(height: 16),
          SkeletonLine(widthFactor: 0.9),
          SizedBox(height: 8),
          SkeletonLine(widthFactor: 0.7),
          SizedBox(height: 8),
          SkeletonLine(widthFactor: 0.45),
        ],
      ),
    ),
  );
}
