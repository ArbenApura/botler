// "LINKED FROM": THE PAGES THAT LINK TO THE PAGE BEING READ, AT THE END OF IT. Each row opens that page. Without a connection (or when the server
// cannot say) the section is simply not there: it is an extra, never an error.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/library_extras.dart';
import '../../l10n/l10n.dart';
import '../../state/library_extras.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import '../../ui/ui.dart';

// -- WIDGETS -- //

class BacklinksSection extends ConsumerWidget {
  const BacklinksSection({
    required this.pageId,
    required this.onOpen,
    super.key,
  });

  final String pageId;
  final void Function(Backlink link) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(backlinksProvider(pageId)).asData?.value;
    if (links == null || links.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(context.t.pageLinkedFrom),
        for (final l in links) BacklinkRow(link: l, onOpen: () => onOpen(l)),
      ],
    );
  }
}

class BacklinkRow extends StatelessWidget {
  const BacklinkRow({required this.link, required this.onOpen, super.key});

  final Backlink link;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.t.pageLinkedFromRow(link.page, link.notebook),
      onTap: onOpen,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('backlink.${link.pageId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTap + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.subdirectory_arrow_left, size: 20, color: c.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        link.page,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        link.notebook,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted),
                      ),
                      if (link.snippet.isNotEmpty)
                        Text(
                          plainFromMarkdown(link.snippet, keepPageLinks: true),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: c.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
