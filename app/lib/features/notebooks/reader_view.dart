// THE READER'S TEXT: A PAGE DRAWN AS A LAZY LIST OF TOP-LEVEL BLOCKS, EACH HEADING WITH A KEY OF ITS OWN SO THE CONTENTS LIST CAN SCROLL TO IT.
// A page can be 30,000 characters, so only the blocks near the screen are built. A block that is not built has no key to scroll to; jumping
// moves the list a screen at a time towards the target until it is built, then lands on it. Motion is short and stands still when the phone
// removes animations. A later phase (search, [[links]]) jumps with the same controller.

// -- DEP-MODULES -- //
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// Needed to name the inline syntax type; see reader_links.dart
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

// -- MODULES -- //
import '../../core/library.dart';
import '../../core/library_extras.dart';
import '../../core/line_diff.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import '../../ui/ui.dart';
import 'reader_blocks.dart';
import 'reader_links.dart';

// -- CONSTANTS -- //

const Duration _jumpTime = Duration(milliseconds: 250);

/// The most screens a jump travels before it gives up (a page holds at most about a dozen screens of text).
const int _jumpTries = 60;

// -- TYPES -- //

/// Lets the screen around the reader (the contents drawer, later a search result) scroll the reader to a block.
class ReaderController {
  Future<void> Function(int blockIndex)? _jump;

  /// Scrolls so that block [blockIndex] is near the top. Does nothing before the reader is built.
  Future<void> jumpToBlock(int blockIndex) async => _jump?.call(blockIndex);

  bool get attached => _jump != null;
}

// -- WIDGETS -- //

class ReaderView extends StatefulWidget {
  const ReaderView({
    required this.doc,
    required this.controller,
    this.header,
    this.footer,
    this.onTapLink,
    this.library,
    this.changes = PageChanges.none,
    super.key,
  });

  final PageDoc doc;
  final ReaderController controller;

  /// Shown above the text and below it, scrolling with it.
  final Widget? header;
  final Widget? footer;
  final void Function(String text, String? href)? onTapLink;

  /// The library the [[links]] are looked up in; without it they stay as written.
  final Library? library;

  /// The lines new since the person last read: their blocks are tinted and marked.
  final PageChanges changes;

  @override
  State<ReaderView> createState() => ReaderViewState();
}

class ReaderViewState extends State<ReaderView> {
  // -- STATES -- //

  final ScrollController _scroll = ScrollController();
  late List<ReaderBlock> _blocks = splitBlocks(widget.doc.text);
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  /// The blocks that are built right now, with how many hosts hold each: after the text changes a new host of a block can start before the old one
  /// of the same index is disposed, and the old one must not take the new one's entry with it.
  final Map<int, int> _built = <int, int>{};
  bool _jumping = false;
  final Map<String, MarkdownElementBuilder> _builders =
      <String, MarkdownElementBuilder>{missingTag: MissingLinkBuilder()};
  final List<md.InlineSyntax> _syntaxes = <md.InlineSyntax>[
    MissingLinkSyntax(),
  ];

  // -- FUNCTIONS -- //

  /// The blocks of the text on screen, for tests and for the contents list.
  List<ReaderBlock> get blocks => _blocks;

  @override
  void initState() {
    super.initState();
    widget.controller._jump = _jump;
  }

  @override
  void didUpdateWidget(ReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._jump = null;
      widget.controller._jump = _jump;
    }
    if (oldWidget.doc.text != widget.doc.text) {
      _blocks = splitBlocks(widget.doc.text);
      _keys.clear();
    }
  }

  @override
  void dispose() {
    widget.controller._jump = null;
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) =>
      _keys.putIfAbsent(index, () => GlobalKey(debugLabel: 'heading.$index'));

  Future<void> _jump(int target) async {
    if (_jumping || !_scroll.hasClients) return;
    _jumping = true;
    try {
      final still = MediaQuery.disableAnimationsOf(context);
      for (var tries = 0; tries < _jumpTries; tries++) {
        if (!mounted) return;
        final built = _keys[target]?.currentContext;
        if (built != null && built.mounted) {
          await Scrollable.ensureVisible(
            built,
            alignment: 0.04,
            duration: still ? Duration.zero : _jumpTime,
            curve: Curves.easeOutCubic,
          );
          return;
        }
        final position = _scroll.position;
        if (_built.isNotEmpty) {
          final low = _built.keys.reduce(math.min);
          final high = _built.keys.reduce(math.max);
          // Towards the target, a screen at a time; a target between two built blocks has not been laid out yet, so wait for it
          final step = position.viewportDimension * 0.9;
          final to = target < low
              ? position.pixels - step
              : (target > high ? position.pixels + step : position.pixels);
          _scroll.jumpTo(
            to.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
        }
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _jumping = false;
    }
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    // The header is item 0 and the footer the last item, so they scroll with the text
    final count = blocks.length + 2;
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: pagePadding(context),
        itemCount: count,
        itemBuilder: (context, i) {
          if (i == 0) return widget.header ?? const SizedBox.shrink();
          if (i == count - 1) return widget.footer ?? const SizedBox.shrink();
          final block = blocks[i - 1];
          final lib = widget.library;
          final source = lib == null
              ? block.markdown
              : linkifyPages(block.markdown, lib, widget.doc.notebookId);
          Widget body = Semantics(
            header: block.isHeading,
            child: BotlerMarkdown(
              source,
              levels: true,
              onTapLink: widget.onTapLink,
              builders: _builders,
              inlineSyntaxes: _syntaxes,
            ),
          );
          if (widget.changes.marksLines &&
              touchesAdded(widget.changes.added, block.line, block.lineCount)) {
            body = ChangedBlock(child: body);
          }
          return _BlockHost(
            // Every block has a key, so a search result can scroll to the one that holds the match
            key: _keyFor(block.index),
            index: block.index,
            built: _built,
            child: Padding(
              padding: EdgeInsets.only(
                top: block.isHeading ? 12 : 0,
                bottom: 8,
              ),
              child: body,
            ),
          );
        },
      ),
    );
  }
}

/// A block with lines added since the person last read: a soft tint and a bar at its edge, and a spoken label (the tint is never the only sign).
class ChangedBlock extends StatelessWidget {
  const ChangedBlock({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: context.t.pageAddedMark,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: c.accent, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
          child: child,
        ),
      ),
    );
  }
}

/// Tells the reader which blocks are built, so a jump knows which way the target lies.
class _BlockHost extends StatefulWidget {
  const _BlockHost({
    required this.index,
    required this.built,
    required this.child,
    super.key,
  });

  final int index;
  final Map<int, int> built;
  final Widget child;

  @override
  State<_BlockHost> createState() => _BlockHostState();
}

class _BlockHostState extends State<_BlockHost> {
  @override
  void initState() {
    super.initState();
    widget.built.update(widget.index, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    final left = (widget.built[widget.index] ?? 1) - 1;
    if (left <= 0) {
      widget.built.remove(widget.index);
    } else {
      widget.built[widget.index] = left;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
