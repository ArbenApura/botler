// BOTLER'S RECENT CHANGES: THE PAGES BOTLER WROTE IN THE LAST 14 DAYS, NEWEST FIRST, A FEW AT A TIME. A TAP OPENS THE PAGE. UNDO IS OFFERED ONLY WHEN THE
// CHANGE IS STILL THE NEWEST VERSION OF THE PAGE (nobody wrote on it since): it puts back the text Botler replaced, or, for a page Botler made,
// deletes the page after asking. Any other entry is view-only, and so is a page Botler only renamed or moved. Without a connection the section is not there.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/library_extras.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/library_extras.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'library_actions.dart';
import 'library_widgets.dart';

// -- FUNCTIONS -- //

/// A time that has passed, in words ("5 minutes ago").
String agoWords(BuildContext context, DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final ago = agoOf(at, now ?? DateTime.now());
  return switch (ago.unit) {
    'minutes' => context.t.libraryAgoMinutes(ago.count),
    'hours' => context.t.libraryAgoHours(ago.count),
    'days' => context.t.libraryAgoDays(ago.count),
    _ => context.t.libraryAgoNow,
  };
}

// -- WIDGETS -- //

class ActivityFeed extends ConsumerStatefulWidget {
  const ActivityFeed({required this.onOpen, super.key});

  final void Function(ActivityEntry entry) onOpen;

  @override
  ConsumerState<ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends ConsumerState<ActivityFeed> {
  // -- STATES -- //

  bool _all = false;
  bool _busy = false;

  // -- FUNCTIONS -- //

  Future<void> _undo(ActivityEntry entry) async {
    if (_busy) return;
    final words = context.t;
    if (entry.created) {
      final ok = await confirm(
        context,
        title: words.activityUndoCreatedTitle,
        body: words.activityUndoCreatedBody(entry.page),
        yes: words.pageDelete,
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(changeActionsProvider).undo(entry);
      if (!mounted) return;
      say(
        context,
        result == UndoResult.deleted
            ? words.activityUndoneDeleted
            : words.activityUndoneRestored,
      );
    } on UndoUnavailable {
      if (mounted) say(context, words.activityUndoUnavailable);
    } catch (e) {
      if (mounted) say(context, needsNetworkWords(context, e));
    } finally {
      // The screen may be gone by now: using ref then would throw, and its providers are gone with it
      if (mounted) {
        setState(() => _busy = false);
        ref
          ..invalidate(activityProvider)
          ..invalidate(libraryProvider);
      }
    }
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(activityProvider).asData?.value;
    if (entries == null || entries.isEmpty) return const SizedBox.shrink();
    final library = ref.watch(libraryProvider).asData?.value;
    final shown = _all ? entries : entries.take(activityShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(context.t.libraryActivity),
        for (final e in shown)
          ActivityRow(
            key: ValueKey<String>('activity.${e.pageId}'),
            entry: e,
            canUndo: !_busy && canUndoChange(e, library),
            onOpen: () => widget.onOpen(e),
            onUndo: () => _undo(e),
          ),
        if (entries.length > activityShown)
          Semantics(
            button: true,
            label: _all
                ? context.t.libraryActivityFewer
                : context.t.libraryActivityAll(entries.length),
            excludeSemantics: true,
            onTap: () => setState(() => _all = !_all),
            child: TextButton(
              key: const ValueKey<String>('activity.toggle'),
              style: TextButton.styleFrom(
                minimumSize: const Size(minTap, minTap),
              ),
              onPressed: () => setState(() => _all = !_all),
              child: Text(
                _all
                    ? context.t.libraryActivityFewer
                    : context.t.libraryActivityAll(entries.length),
              ),
            ),
          ),
      ],
    );
  }
}

class ActivityRow extends StatelessWidget {
  const ActivityRow({
    required this.entry,
    required this.canUndo,
    required this.onOpen,
    required this.onUndo,
    super.key,
  });

  final ActivityEntry entry;
  final bool canUndo;
  final VoidCallback onOpen;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = agoWords(context, entry.updatedAt);
    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            button: true,
            label:
                '${context.t.libraryActivityLine(entry.page, entry.notebook)}, $when',
            onTap: onOpen,
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey<String>('activity.open.${entry.pageId}'),
              borderRadius: BorderRadius.circular(12),
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: libraryRowHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.auto_fix_high_outlined,
                        size: 20,
                        color: c.muted,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.t.libraryActivityLine(
                                entry.page,
                                entry.notebook,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(when, style: TextStyle(color: c.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (canUndo)
          Semantics(
            button: true,
            label: context.t.libraryUndoFor(entry.page),
            excludeSemantics: true,
            onTap: onUndo,
            child: TextButton(
              key: ValueKey<String>('activity.undo.${entry.pageId}'),
              style: TextButton.styleFrom(
                minimumSize: const Size(minTap, minTap),
              ),
              onPressed: onUndo,
              child: Text(context.t.libraryUndo),
            ),
          ),
      ],
    );
  }
}
