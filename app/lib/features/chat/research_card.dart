// THE CARD OF A WEB RESEARCH CALL: A SPINNER ROW WITH THE QUESTION AND LIVE COUNTS WHILE IT RUNS, ONE FOLDED LINE "RESEARCHED, 14 SOURCES" WHEN DONE.
// Built from the parts that already exist (docs/DESIGN.md): the running tool row, the quiet panel with a left rule, and the fold line of the thinking panel.
// Several calls make several cards, each counting on its own. A stopped or failed call says what it found so far in words. Approved mockup of 2026-11-08.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import 'chat_state.dart';
import 'live_parts.dart';

// -- TYPES -- //

/// One source the server built in code: a plain title, the site, and the address a tap opens in the browser.
class ResearchSource {
  const ResearchSource({
    required this.title,
    required this.host,
    required this.url,
  });

  final String title;
  final String host;
  final String url;
}

/// The sources of a finished research call's answer. Anything that is not a title, a site and a web address is left out.
List<ResearchSource> researchSources(Object? data) {
  final out = <ResearchSource>[];
  for (final s in asList(asJson(data)['sources'])) {
    final m = asJson(s);
    final url = str(m['url']);
    final host = str(m['host']);
    if (host.isEmpty ||
        !(url.startsWith('https://') || url.startsWith('http://'))) {
      continue;
    }
    final title = str(m['title']);
    out.add(
      ResearchSource(title: title.isEmpty ? host : title, host: host, url: url),
    );
  }
  return out;
}

class ResearchCard extends StatefulWidget {
  const ResearchCard(this.item, {super.key});

  final ToolItem item;

  @override
  State<ResearchCard> createState() => _ResearchCardState();
}

class _ResearchCardState extends State<ResearchCard> {
  // -- STATES -- //

  bool _open = false;

  // -- FUNCTIONS -- //

  /// The page storage key of this card, so its open state survives the list rebuilding.
  String get _key => 'research-${widget.item.callId ?? widget.item.id}';

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
    final item = widget.item;
    if (item.running) return _running(context, item);
    if (item.status != 'ok') return _failed(context);
    return _done(context, item);
  }

  // -- PARTS -- //

  Widget _running(BuildContext context, ToolItem item) {
    final c = context.colors;
    final t = context.t;
    final live = item.live;
    final question = item.subject;
    final title = question == null
        ? t.researchRunningNone
        : t.researchRunning(question);
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: c.muted);
    final searches = live?.searches ?? 0;
    final reads = live?.reads ?? 0;
    final hosts = live?.hosts ?? const <String>[];
    final counts = searches > 0 || reads > 0
        ? t.researchCounts(searches, reads)
        : null;
    return Semantics(
      liveRegion: true,
      label: counts == null ? title : '$title. $counts',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const ToolSpinner(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ),
              ],
            ),
            if (counts != null)
              _Panel(
                children: <Widget>[
                  Text(
                    counts,
                    style: small?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (hosts.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[for (final h in hosts) _HostChip(h)],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: context.t.researchFailed,
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 14, color: c.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              context.t.researchFailed,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _done(BuildContext context, ToolItem item) {
    final c = context.colors;
    final t = context.t;
    final sources = researchSources(item.data);
    final stopped = str(asJson(item.data)['stopped']);
    final label = sources.isEmpty
        ? t.researchDoneNone
        : t.researchDone(sources.length);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: c.muted);
    final note = switch (stopped) {
      '' => null,
      'time' => t.researchStoppedTime,
      'cancelled' => t.researchStoppedCancelled,
      _ => t.researchStoppedOther,
    };
    final canOpen = sources.isNotEmpty;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check, size: 14, color: c.muted),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: style)),
          if (canOpen) ...<Widget>[
            const SizedBox(width: 4),
            Icon(
              _open ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: c.muted,
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (canOpen)
          Semantics(
            button: true,
            expanded: _open,
            label: _open
                ? t.researchOpenLabel(label)
                : t.researchClosedLabel(label),
            excludeSemantics: true,
            onTap: _toggle,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _toggle,
              child: row,
            ),
          )
        else
          Semantics(label: label, excludeSemantics: true, child: row),
        if (note != null)
          _Panel(
            children: <Widget>[
              Text(note, style: style?.copyWith(color: c.warning)),
            ],
          ),
        if (_open && canOpen)
          _Panel(children: <Widget>[for (final s in sources) _SourceRow(s)]),
      ],
    );
  }
}

/// The quiet panel with a left rule, as the thinking panel is drawn.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: context.colors.line, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HostChip extends StatelessWidget {
  const _HostChip(this.host);

  final String host;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(host, style: TextStyle(color: c.muted, fontSize: 12)),
      ),
    );
  }
}

/// A source: its title and site; a tap opens the page in the browser. At least 48 dp high.
class _SourceRow extends StatelessWidget {
  const _SourceRow(this.source);

  final ResearchSource source;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.t.researchOpenSource(source.title, source.host),
      excludeSemantics: true,
      onTap: () => openWebLink(source.url),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openWebLink(source.url),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink, fontSize: 14),
                    ),
                    Text(
                      source.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.open_in_new, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}
