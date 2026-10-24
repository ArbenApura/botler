// CHANGES MADE OFFLINE THAT THE SERVER REFUSED: SHOWN IN SETTINGS UNTIL THE PERSON LOOKS AT THEM. HIDDEN WHEN THERE ARE NONE.
// A payment or a move that did not go through must not vanish quietly: this row says how many, and the sheet says which and why.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

class FailedWritesRow extends ConsumerStatefulWidget {
  const FailedWritesRow({super.key});

  @override
  ConsumerState<FailedWritesRow> createState() => _FailedWritesRowState();
}

class _FailedWritesRowState extends ConsumerState<FailedWritesRow> {
  Future<void> _show() async {
    final box = ref.read(outboxProvider);
    final list = box.failed();
    await showFormSheet<void>(
      context,
      title: context.t.outboxFailedTitle,
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final f in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    f.verb.replaceAll('_', ' '),
                    style: Theme.of(sheet).textTheme.titleSmall,
                  ),
                  Text(f.reason, style: TextStyle(color: sheet.colors.muted)),
                ],
              ),
            ),
          FilledButton(
            onPressed: () async {
              await box.dismissFailed();
              close(null);
            },
            child: Text(sheet.t.outboxFailedDismiss),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(outboxProvider).failed();
    if (list.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Icon(Icons.error_outline, color: c.warning),
      title: Text(context.t.outboxFailedTitle),
      subtitle: Text(
        context.t.outboxFailedLine(list.length),
        style: TextStyle(color: c.muted),
      ),
      onTap: () => unawaited(_show()),
    );
  }
}
