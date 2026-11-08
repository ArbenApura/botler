// THE LIVE PARTS OF THE CHAT: THE "WORKING ON IT" ROW, THE ASSISTANT'S THINKING, AND A TOOL THAT IS STILL RUNNING.
// Everything here is quiet: soft dots in the accent colour, muted small text, nothing that jumps. With "remove animations" on the dots stand still.
// The thinking is the model's own words and untrusted, so it is drawn as plain text, never as markdown.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'chat_state.dart';
import 'notebook_rows.dart';
import 'tool_words.dart';

// -- CONSTANTS -- //

/// The thinking panel never grows taller than this; while it streams it shows the newest lines.
const double _thinkingMaxHeight = 180;

// -- FUNCTIONS -- //

/// A tool's name as plain words, for "Checking accounts list".
String toolWords(String name) => name.replaceAll('_', ' ');

/// The words for one stage of the turn.
String phaseWords(BuildContext context, TurnPhase phase, String? tool) =>
    switch (phase) {
      TurnPhase.waiting || TurnPhase.idle => context.t.chatWaiting,
      TurnPhase.thinking => context.t.chatThinking,
      TurnPhase.writing => context.t.chatWriting,
      TurnPhase.tool => switch (tool) {
        'script_run' => context.t.chatRunningScript,
        'toolbox' => context.t.chatUsingToolbox,
        final name when isNotebookWrite(name ?? '') =>
          context.t.chatSavingNotebook,
        _ => context.t.chatChecking(toolWords(tool ?? '')),
      },
    };

// -- TYPES -- //

/// Three soft dots that take turns to brighten. Still when the phone is set to remove animations.
class PulsingDots extends StatefulWidget {
  const PulsingDots({super.key});

  @override
  State<PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // -- LIFECYCLES -- //

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reads the phone's setting each time it can change
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.accent;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                child: Opacity(
                  // Each dot is a third of a turn behind the one before it
                  opacity: _controller.isAnimating
                      ? 0.3 + 0.7 * _wave((_controller.value - i / 3) % 1)
                      : 0.7,
                  child: SizedBox.square(
                    dimension: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 0 to 1 and back to 0 over one turn.
  double _wave(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}

/// The labelled Stop that floats over the bottom of the conversation while a turn runs. It carries no dots or words of its own: the
/// conversation already shows what is happening. Once pressed it waits, reading "Stopping...", until the turn ends and it leaves.
/// Stop is ink on paper, never danger red (red is for recording).
class StopChip extends StatefulWidget {
  const StopChip({required this.onStop, super.key});

  final VoidCallback onStop;

  @override
  State<StopChip> createState() => _StopChipState();
}

class _StopChipState extends State<StopChip> {
  // -- STATES -- //

  bool _stopping = false;

  // -- FUNCTIONS -- //

  void _press() {
    if (_stopping) return;
    setState(() => _stopping = true);
    widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    return Semantics(
      button: true,
      enabled: !_stopping,
      label: _stopping ? t.chatStopping : t.chatStop,
      excludeSemantics: true,
      onTap: _stopping ? null : _press,
      child: Material(
        color: c.surface,
        elevation: 2,
        shadowColor: c.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _stopping ? null : _press,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (!_stopping) ...<Widget>[
                    Icon(Icons.stop_rounded, size: 20, color: c.ink),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _stopping ? t.chatStopping : t.chatStop,
                    style: TextStyle(
                      color: _stopping ? c.muted : c.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Working on it", "Thinking" or "Writing" with the soft dots, under the conversation while the assistant has not started its answer.
class WorkingRow extends StatelessWidget {
  const WorkingRow({required this.phase, this.tool, super.key});

  final TurnPhase phase;
  final String? tool;

  @override
  Widget build(BuildContext context) {
    final label = phaseWords(context, phase, tool);
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            const PulsingDots(),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the assistant thought. Open and streaming while it thinks, then one line, "Thought for 4 s", that opens to the full text on a tap.
class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel(this.item, {super.key});

  final ThinkingItem item;

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  // -- STATES -- //

  /// The person's choice once they tap; until then it follows the item (open while thinking, folded after).
  bool? _chosen;

  bool get _expanded => _chosen ?? widget.item.open;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    // Nothing was thought out loud: no line that opens onto nothing
    if (!item.open && item.text.trim().isEmpty) return const SizedBox.shrink();
    final title = item.open
        ? context.t.chatThinking
        : context.t.chatThoughtFor(item.seconds < 1 ? 1 : item.seconds);
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _expanded,
            label: '${context.t.chatThoughtToggle}. $title',
            // The tap lives here: the InkWell below is left out of the semantics, so a screen reader would find no action without it
            onTap: () => setState(() => _chosen = !_expanded),
            child: ExcludeSemantics(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _chosen = !_expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (item.open) ...<Widget>[
                        const PulsingDots(),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        title,
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: c.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded && item.text.trim().isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.line, width: 3)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: _thinkingMaxHeight,
                  ),
                  child: SingleChildScrollView(
                    // Newest lines stay in view while it streams
                    reverse: item.open,
                    child: Text(
                      item.text.trim(),
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A soft block at the end of the words while they are still arriving. Drawn apart from the text so a screen reader never reads it.
class StreamCaret extends StatelessWidget {
  const StreamCaret({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: 8,
        height: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    ),
  );
}

/// The small spinner of a running tool. With animations removed a spinner would still spin, so a still mark stands in.
class ToolSpinner extends StatelessWidget {
  const ToolSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Icon(Icons.more_horiz, size: 14, color: c.muted);
    }
    return SizedBox.square(
      dimension: 14,
      child: CircularProgressIndicator(strokeWidth: 2, color: c.muted),
    );
  }
}

/// A tool that has started and has not answered yet: a small spinner and what it is doing ("Reading page Trip plan").
/// With no label from the server it says "Checking ..." from the tool's name, as before.
class RunningToolRow extends StatelessWidget {
  const RunningToolRow(this.name, {this.family, this.subject, super.key});

  final String name;

  /// The kind and the subject the server labelled the call with. Both null from an older server.
  final String? family;
  final String? subject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fromLabel = family == null
        ? null
        : runningWords(
            context,
            ToolItem(
              0,
              name: name,
              status: 'running',
              family: family,
              subject: subject,
            ),
          );
    final label =
        fromLabel ??
        switch (name) {
          'script_run' => context.t.chatRunningScript,
          'toolbox' => context.t.chatUsingToolbox,
          _ when isNotebookWrite(name) => context.t.chatSavingNotebook,
          _ => context.t.chatChecking(toolWords(name)),
        };
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            const ToolSpinner(),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
