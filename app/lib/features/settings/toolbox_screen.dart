// THE TOOLBOX SCREEN (BTL-20261031-1334): THE SCRIPTS BOTLER SAVED ON THIS PHONE, EACH WITH ITS CODE TO READ AND A DELETE. Nothing here can run a script or change data:
// scripts only run when the assistant calls them in a chat, in the sandbox, and a script can never change money or other data.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/script/toolbox.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

/// The saved scripts, read fresh each time the screen opens and after a delete.
final toolboxListProvider = FutureProvider.autoDispose<List<ToolboxEntry>>(
  (ref) => ref.watch(toolboxProvider).list(),
);

class ToolboxScreen extends ConsumerWidget {
  const ToolboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final list = ref.watch(toolboxListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.toolboxTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          Text(t.toolboxNote, style: TextStyle(color: c.muted)),
          const SizedBox(height: 12),
          switch (list) {
            AsyncData(:final value) when value.isEmpty => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(t.toolboxEmpty, style: TextStyle(color: c.muted)),
            ),
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.toolboxCount(value.length, toolboxMaxScripts),
                  style: TextStyle(color: c.muted),
                ),
                const SizedBox(height: 8),
                for (final e in value) _Script(entry: e),
              ],
            ),
            AsyncError() => Text(
              t.toolboxFailed,
              style: TextStyle(color: c.danger),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ],
      ),
    );
  }
}

class _Script extends ConsumerWidget {
  const _Script({required this.entry});

  final ToolboxEntry entry;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    if (!await confirm(
      context,
      title: t.toolboxDeleteTitle,
      body: t.toolboxDeleteBody(entry.name),
      yes: t.toolboxDelete,
    )) {
      return;
    }
    await ref.read(toolboxProvider).delete(entry.name);
    ref.invalidate(toolboxListProvider);
    if (context.mounted) say(context, t.toolboxDeleted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    return PaperCard(
      child: ExpansionTile(
        // No outline lines inside the card
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(entry.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          t.toolboxChars(entry.code.length),
          style: TextStyle(color: c.muted),
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              entry.code,
              style: TextStyle(
                fontFamily: 'monospace',
                color: c.ink,
                fontSize: 12,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: Text(t.toolboxDelete),
            ),
          ),
        ],
      ),
    );
  }
}
