// THE ROW FOR A RUN OF TOOL CALLS OF ONE KIND: "READING PAGES  2 OF 3" WHILE THEY RUN, "READ 3 PAGES" WHEN DONE, AND IT OPENS TO ONE LINE PER CALL.
// It is a quiet row like the other tool lines (small muted text, a 14 px icon) with a 48 dp target. The open state is kept by the first call's id.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'chat_state.dart';
import 'live_parts.dart';
import 'tool_words.dart';

// -- TYPES -- //

class ToolGroupRow extends StatefulWidget {
  const ToolGroupRow(this.members, {super.key});

  /// Two or more calls of one kind, in the order they started.
  final List<ToolItem> members;

  @override
  State<ToolGroupRow> createState() => _ToolGroupRowState();
}

class _ToolGroupRowState extends State<ToolGroupRow> {
  // -- STATES -- //

  bool _open = false;

  // -- FUNCTIONS -- //

  /// The page storage key of this group. The first call keeps its id while the group grows, so the open state survives each rebuild.
  String get _key => 'tool-group-${widget.members.first.id}';

  void _toggle() {
    setState(() => _open = !_open);
    PageStorage.maybeOf(context)?.writeState(context, _open, identifier: _key);
  }

  // -- LIFECYCLES -- //

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final kept = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _key);
    if (kept is bool) _open = kept;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final members = widget.members;
    final running = members.any((m) => m.running);
    final finished = members.where((m) => !m.running).length;
    final family = members.first.family ?? 'lookup';
    final label = groupWords(
      context,
      family,
      count: members.length,
      running: running,
    );
    final style =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted) ??
        TextStyle(color: c.muted, fontSize: 13);
    final spoken = _open
        ? context.t.toolGroupOpenLabel(label, members.length)
        : context.t.toolGroupClosedLabel(label, members.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: _open,
          label: spoken,
          excludeSemantics: true,
          onTap: _toggle,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: <Widget>[
                  if (running)
                    const ToolSpinner()
                  else
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: c.success,
                    ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: style)),
                  if (running)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        context.t.toolGroupProgress(finished, members.length),
                        // Tabular figures so the count does not shift as it grows
                        style: style.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 7, bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.line, width: 2)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final m in members) _Member(m, style: style),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One call inside an opened group.
class _Member extends StatelessWidget {
  const _Member(this.item, {required this.style});

  final ToolItem item;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          if (item.running)
            const ToolSpinner()
          else
            Icon(Icons.check_circle_outline, size: 14, color: c.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              memberWords(context, item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
