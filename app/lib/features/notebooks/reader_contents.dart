// THE CONTENTS OF A PAGE: ITS HEADINGS AS A LIST IN A DRAWER, EACH ONE A TAP THAT SCROLLS THE READER THERE.
// It opens from the Contents button in the bottom bar (within thumb reach) or with a swipe from the right edge. Rows are at least 48 dp tall
// and are indented by heading level.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'reader_blocks.dart';

// -- CONSTANTS -- //

/// How far each heading level is indented, and how many levels are indented at all.
const double _indentStep = 16;
const int _indentLevels = 3;

// -- WIDGETS -- //

class ReaderContents extends StatelessWidget {
  const ReaderContents({
    required this.headings,
    required this.onPick,
    super.key,
  });

  final List<ReaderBlock> headings;

  /// Called with the block index of the heading that was tapped; the drawer closes itself first.
  final void Function(int blockIndex) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A page that opens with a level 2 heading is not indented for the level it skipped
    final top = headings.isEmpty
        ? 1
        : headings.map((h) => h.level ?? 1).reduce((a, b) => a < b ? a : b);
    return Drawer(
      backgroundColor: c.paper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                context.t.pageContents,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: headings.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        context.t.pageContentsEmpty,
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: headings.length,
                      itemBuilder: (context, i) {
                        final h = headings[i];
                        final depth = ((h.level ?? 1) - top).clamp(
                          0,
                          _indentLevels,
                        );
                        final text = h.heading ?? '';
                        return Semantics(
                          button: true,
                          label: text,
                          onTap: () => _pick(context, h.index),
                          excludeSemantics: true,
                          child: InkWell(
                            key: ValueKey<String>('contents.${h.index}'),
                            onTap: () => _pick(context, h.index),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  20 + depth * _indentStep,
                                  8,
                                  20,
                                  8,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: depth == 0
                                        ? Theme.of(context).textTheme.titleSmall
                                        : Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _pick(BuildContext context, int blockIndex) {
    Scaffold.of(context).closeEndDrawer();
    onPick(blockIndex);
  }
}
