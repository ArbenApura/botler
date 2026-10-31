// THE READER: ONE PAGE OF A NOTEBOOK, MADE TO BE READ ON A PHONE WITH ONE HAND. THE ONE PRIMARY ACTION IS EDIT; CONTENTS IS NEXT TO IT IN THE BOTTOM BAR.
// The text is Markdown drawn lazily in blocks (reader_view.dart). A breadcrumb says where the page lives. Opening a page marks it as looked at
// (page_seen, fire and forget) and puts it in the recent list. Without a connection the copy kept on the phone is shown with an "Offline copy"
// note; Edit then waits for a connection. A page that was deleted meanwhile says so and leaves the recent list. [[Links]] are tappable, lines Botler
// added since the person last read are marked, and the pages that link here are listed at the end (reader_body.dart).

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../memory/notebook_editor.dart';
import 'library_actions.dart';
import 'library_widgets.dart';
import 'reader_blocks.dart';
import 'reader_body.dart';
import 'reader_contents.dart';
import 'reader_view.dart';

// -- TYPES -- //

enum _More { pin, rename, move, copy, delete }

// -- FUNCTIONS -- //

/// Opens a page in the reader. [heading] scrolls to the first heading with those words once it is shown; [match] scrolls to the first block
/// that holds those words (a search result uses it).
Future<void> openPage(
  BuildContext context,
  String pageId, {
  String? title,
  String? heading,
  String? match,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => PageReaderScreen(
      pageId: pageId,
      title: title,
      initialHeading: heading,
      initialMatch: match,
    ),
  ),
);

// -- WIDGETS -- //

class PageReaderScreen extends ConsumerStatefulWidget {
  const PageReaderScreen({
    required this.pageId,
    this.title,
    this.initialHeading,
    this.initialMatch,
    super.key,
  });

  final String pageId;

  /// The title to show in the bar while the page loads.
  final String? title;
  final String? initialHeading;
  final String? initialMatch;

  @override
  ConsumerState<PageReaderScreen> createState() => _PageReaderScreenState();
}

class _PageReaderScreenState extends ConsumerState<PageReaderScreen> {
  // -- STATES -- //

  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();
  final ReaderController _reader = ReaderController();
  bool _gone = false;
  bool _jumped = false;
  String _noted = '';

  // The newest version looked at before this opening: taken once, before page_seen moves it, so the marks stay for as long as the page is open
  int? _seenAtOpen;

  // The headings of the text on screen, worked out once per text
  String _headingsOf = '';
  List<ReaderBlock> _headings = const <ReaderBlock>[];

  // -- FUNCTIONS -- //

  @override
  void initState() {
    super.initState();
    // A page already loaded (kept alive by another screen) never fires the listener, so it is noted here
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final doc = ref.read(pageProvider(widget.pageId)).asData?.value;
      if (doc != null) _arrived(doc);
    });
  }

  List<ReaderBlock> _headingsFor(PageDoc doc) {
    if (_headingsOf != doc.text) {
      _headingsOf = doc.text;
      _headings = extractHeadings(splitBlocks(doc.text));
    }
    return _headings;
  }

  /// The person's own save makes the version they wrote a seen one (the server marks it so): what they wrote is not "added since you last read".
  void _ownEdit(PageDoc doc) {
    if (!doc.offline && doc.updatedBy == 'user') {
      _seenAtOpen = doc.seenVersion;
    }
  }

  /// The page has been shown: it is a recent one, it counts as looked at, and a search result scrolls to its heading.
  void _arrived(PageDoc doc) {
    final tag = '${doc.id}:${doc.version}:${doc.offline}';
    if (_seenAtOpen == null && !doc.offline) _seenAtOpen = doc.seenVersion;
    _ownEdit(doc);
    if (_noted != tag) {
      _noted = tag;
      unawaited(ref.read(recentsProvider.notifier).touch(doc));
      if (!doc.offline) {
        unawaited(ref.read(libraryActionsProvider).markSeen(doc));
      }
    }
    final want = widget.initialHeading;
    if (want != null && !_jumped) {
      _jumped = true;
      for (final h in _headingsFor(doc)) {
        if ((h.heading ?? '').toLowerCase() == want.toLowerCase()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_reader.jumpToBlock(h.index));
          });
          break;
        }
      }
    }
    final term = widget.initialMatch?.trim().toLowerCase();
    if (term != null && term.isNotEmpty && !_jumped) {
      _jumped = true;
      // Headings are blocks too, so a match in a heading lands on it
      for (final b in splitBlocks(doc.text)) {
        if (b.markdown.toLowerCase().contains(term)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_reader.jumpToBlock(b.index));
          });
          break;
        }
      }
    }
  }

  void _lost() {
    unawaited(ref.read(recentsProvider.notifier).forget(widget.pageId));
    if (!_gone && mounted) setState(() => _gone = true);
  }

  Future<void> _edit(PageDoc doc) async {
    final saved = context.t.memorySaved;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => NotebookEditor(
          initial: doc.text,
          version: doc.version,
          pageId: doc.id,
          title: doc.title,
          maxChars: doc.maxChars,
        ),
      ),
    );
    if (done == true) {
      ref.read(libraryActionsProvider).refresh(doc.id);
      if (mounted) say(context, saved);
    }
  }

  Future<void> _copy(PageDoc doc) async {
    final copied = context.t.pageCopied;
    await Clipboard.setData(ClipboardData(text: doc.text));
    if (mounted) say(context, copied);
  }

  Future<void> _more(_More what, PageDoc doc) async {
    switch (what) {
      case _More.copy:
        await _copy(doc);
      case _More.move:
        await runPageAction(
          context,
          ref,
          PageAction.move,
          pageId: doc.id,
          title: doc.title,
          pinned: doc.pinned,
        );
      case _More.pin:
        await runPageAction(
          context,
          ref,
          PageAction.pin,
          pageId: doc.id,
          title: doc.title,
          pinned: doc.pinned,
        );
      case _More.rename:
        await runPageAction(
          context,
          ref,
          PageAction.rename,
          pageId: doc.id,
          title: doc.title,
          pinned: doc.pinned,
        );
      case _More.delete:
        await runPageAction(
          context,
          ref,
          PageAction.delete,
          pageId: doc.id,
          title: doc.title,
          pinned: doc.pinned,
          onDeleted: () {
            if (mounted) Navigator.of(context).pop();
          },
        );
    }
  }

  // -- WIDGETS -- //

  Widget _header(BuildContext context, PageDoc doc) {
    final c = context.colors;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: c.muted);
    final who = switch (doc.updatedBy) {
      'agent' => context.t.notebookByBotler,
      'seed' => context.t.notebookBySeed,
      _ => context.t.notebookByYou,
    };
    final trail = doc.trail;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (doc.offline) OfflineCopyNote(since: doc.cachedAt),
          Semantics(
            label: context.t.pageBreadcrumb(trail.join(' > ')),
            excludeSemantics: true,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (var i = 0; i < trail.length; i++) ...<Widget>[
                  if (i > 0)
                    Icon(Icons.chevron_right, size: 16, color: c.muted),
                  Text(trail[i], style: small),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(doc.title, style: Theme.of(context).textTheme.headlineSmall),
          if (doc.updatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  // Botler wrote a version the person had not looked at when the page was opened
                  if (doc.updatedBy == 'agent' &&
                      (_seenAtOpen ?? doc.version) < doc.version) ...<Widget>[
                    const UpdatedDot(),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      context.t.pageUpdatedBy(
                        who,
                        libraryWhen(context, doc.updatedAt),
                      ),
                      style: small,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (doc.text.trim().isEmpty) Note(context.t.pageEmpty),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, PageDoc doc) {
    if (doc.subpages.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(context.t.pageSubpages),
        for (final s in doc.subpages)
          PageShortcut(
            pageId: s.id,
            title: s.title,
            notebook: doc.title,
            onOpen: () => openPage(context, s.id, title: s.title),
          ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, PageDoc doc) {
    final c = context.colors;
    return Material(
      color: c.paper,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                Semantics(
                  button: true,
                  label: context.t.pageContents,
                  excludeSemantics: true,
                  onTap: () => _scaffold.currentState?.openEndDrawer(),
                  child: TextButton.icon(
                    onPressed: () => _scaffold.currentState?.openEndDrawer(),
                    icon: const Icon(Icons.format_list_bulleted),
                    label: Text(context.t.pageContents),
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: doc.offline
                      ? context.t.pageEditOffline
                      : context.t.notebookEdit,
                  excludeSemantics: true,
                  onTap: doc.offline ? null : () => _edit(doc),
                  child: FilledButton.icon(
                    onPressed: doc.offline ? null : () => _edit(doc),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.t.notebookEdit),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.pageId;
    final page = ref.watch(pageProvider(id));
    // The page was shown (or has gone) after the first answer or a later reload
    ref.listen<AsyncValue<PageDoc>>(pageProvider(id), (_, next) {
      next.whenData(_arrived);
      if (next.error is PageGone) _lost();
    });
    // The outline came from the server and the page is not in it: Botler (or another phone) deleted it while this screen was open
    ref.listen<AsyncValue<Library>>(libraryProvider, (_, next) {
      final library = next.asData?.value;
      if (library != null && !library.offline && library.page(id) == null) {
        _lost();
      }
    });
    final doc = page.asData?.value;
    final gone = _gone || page.error is PageGone;
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(doc?.title ?? widget.title ?? ''),
        actions: <Widget>[
          if (doc != null && !gone)
            PopupMenuButton<_More>(
              tooltip: context.t.memoryMore,
              onSelected: (what) => _more(what, doc),
              itemBuilder: (_) => <PopupMenuEntry<_More>>[
                PopupMenuItem<_More>(
                  value: _More.pin,
                  child: Text(
                    doc.pinned ? context.t.pageUnpin : context.t.pagePin,
                  ),
                ),
                PopupMenuItem<_More>(
                  value: _More.rename,
                  child: Text(context.t.pageRename),
                ),
                PopupMenuItem<_More>(
                  value: _More.move,
                  child: Text(context.t.pageMove),
                ),
                PopupMenuItem<_More>(
                  value: _More.copy,
                  child: Text(context.t.pageCopyText),
                ),
                PopupMenuItem<_More>(
                  value: _More.delete,
                  child: Text(
                    context.t.pageDelete,
                    style: TextStyle(color: context.colors.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      endDrawer: doc == null || gone
          ? null
          : ReaderContents(
              headings: _headingsFor(doc),
              onPick: (i) => unawaited(_reader.jumpToBlock(i)),
            ),
      bottomNavigationBar: doc == null || gone
          ? null
          : _bottomBar(context, doc),
      body: gone
          ? GoneNote(
              title: context.t.pageGone,
              body: context.t.pageGoneBody,
              onBack: () => Navigator.of(context).maybePop(),
            )
          : AsyncBody<PageDoc>(
              value: page,
              skeleton: const SkeletonPage(
                child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
              ),
              onRetry: () => ref.invalidate(pageProvider(id)),
              data: (d) {
                // Taken here as well as in _arrived, so the first drawing already knows it (the answer was read before page_seen moved it)
                if (_seenAtOpen == null && !d.offline) {
                  _seenAtOpen = d.seenVersion;
                }
                _ownEdit(d);
                return ReaderBody(
                  doc: d,
                  controller: _reader,
                  // The newest version is the person's own: there is nothing of Botler's to mark
                  seenAtOpen: d.updatedBy == 'user' ? null : _seenAtOpen,
                  header: _header(context, d),
                  footer: _footer(context, d),
                  onOpenPage: (pageId, title) =>
                      openPage(context, pageId, title: title),
                );
              },
            ),
    );
  }
}
