// THE DELETED PAGES OF ONE NOTEBOOK, EACH WITH A WAY BACK AND HOW MANY OF THE 30 DAYS ARE LEFT. Restoring needs a connection and says so when it fails.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../core/library_extras.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/library_extras.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'library_actions.dart';

// -- WIDGETS -- //

class DeletedPages extends ConsumerWidget {
  const DeletedPages({
    required this.notebookId,
    required this.onRestored,
    super.key,
  });

  final String notebookId;
  final VoidCallback onRestored;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    String pageId,
  ) async {
    final restored = context.t.pageRestored;
    try {
      await ref.read(libraryActionsProvider).restorePage(pageId);
      ref.invalidate(deletedPagesProvider(notebookId));
      if (context.mounted) {
        say(context, restored);
        onRestored();
      }
    } catch (e) {
      if (context.mounted) say(context, needsNetworkWords(context, e));
    }
  }

  /// "12 days left", or nothing when the server gave no time.
  String? _left(BuildContext context, LibraryPage p) {
    final at = dateOf(p.deletedAt);
    if (at == null) return null;
    return context.t.pageDaysLeft(daysLeftToRestore(at, DateTime.now()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return AsyncBody<List<LibraryPage>>(
      value: ref.watch(deletedPagesProvider(notebookId)),
      skeleton: const SkeletonRows(count: 3),
      onRetry: () => ref.invalidate(deletedPagesProvider(notebookId)),
      data: (list) {
        if (list.isEmpty) return Note(context.t.pageDeletedEmpty);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (context, i) {
              final p = list[i];
              final left = _left(context, p);
              return ListTile(
                key: ValueKey<String>('deleted.page.${p.id}'),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 56,
                title: Text(p.title, maxLines: 2),
                subtitle: left == null
                    ? null
                    : Text(left, style: TextStyle(color: c.muted)),
                trailing: Semantics(
                  button: true,
                  label: context.t.pageRestoreFor(p.title),
                  excludeSemantics: true,
                  onTap: () => _restore(context, ref, p.id),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(minTap, minTap),
                    ),
                    onPressed: () => _restore(context, ref, p.id),
                    child: Text(context.t.notebookRestore),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
