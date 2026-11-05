// SEARCH THE NOTEBOOKS: A FIELD THAT SEARCHES AS YOU PAUSE, AND THE PAGES THAT MATCH, EACH LABELLED "NOTEBOOK > PAGE" WITH THE LINE AROUND THE MATCH.
// The words found are marked in the title and the line. A tap opens the page scrolled to the first block that holds them. Search needs a
// connection (it asks the server, notebook_search) and says so when it cannot, with a way to try again. Only the newest question's answer is
// shown, so a slow answer never replaces a newer one.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/library_extras.dart';
import '../../l10n/l10n.dart';
import '../../state/library_extras.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import '../../ui/ui.dart';
import 'page_reader.dart';
import 'term_highlight.dart';

// -- CONSTANTS -- //

/// The shortest search the server accepts.
const int searchMin = 2;

/// How long after the last key the search starts by itself.
const Duration searchPause = Duration(milliseconds: 350);

// -- TYPES -- //

enum _Phase { idle, loading, done, failed, offline }

// -- WIDGETS -- //

class LibrarySearchScreen extends ConsumerStatefulWidget {
  const LibrarySearchScreen({super.key});

  @override
  ConsumerState<LibrarySearchScreen> createState() =>
      _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends ConsumerState<LibrarySearchScreen> {
  // -- STATES -- //

  final TextEditingController _query = TextEditingController();
  Timer? _pause;
  _Phase _phase = _Phase.idle;
  SearchAnswer _answer = const SearchAnswer(hits: <SearchHit>[], more: false);

  /// The words the shown answer was asked for (the marks use them, not what is typed now).
  String _asked = '';
  int _ticket = 0;

  // -- FUNCTIONS -- //

  @override
  void dispose() {
    _pause?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _typed(String _) {
    _pause?.cancel();
    final q = _query.text.trim();
    if (q.length < searchMin) {
      _ticket++;
      setState(() => _phase = _Phase.idle);
      return;
    }
    setState(() {});
    _pause = Timer(searchPause, _search);
  }

  Future<void> _search() async {
    _pause?.cancel();
    final q = _query.text.trim();
    if (q.length < searchMin) return;
    final mine = ++_ticket;
    setState(() => _phase = _Phase.loading);
    try {
      final answer = await searchNotebooks(ref.read(apiProvider), q);
      if (!mounted || mine != _ticket) return;
      setState(() {
        _answer = answer;
        _asked = q;
        _phase = _Phase.done;
      });
    } on ApiException catch (e) {
      if (!mounted || mine != _ticket) return;
      setState(() => _phase = e.isNetwork ? _Phase.offline : _Phase.failed);
    } catch (_) {
      if (mounted && mine == _ticket) setState(() => _phase = _Phase.failed);
    }
  }

  void _clear() {
    _pause?.cancel();
    _ticket++;
    _query.clear();
    setState(() => _phase = _Phase.idle);
  }

  // -- WIDGETS -- //

  Widget _problem(BuildContext context, String words) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, color: c.muted),
            const SizedBox(height: 8),
            Text(
              words,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _search, child: Text(context.t.retry)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, SearchHit hit) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    void open() => openPage(
      context,
      hit.pageId,
      title: hit.page,
      match: hit.matchIn == 'text' ? _asked : null,
    );
    return Semantics(
      button: true,
      label:
          '${context.t.libraryOpenPage(hit.page)}, ${hit.trail.take(hit.trail.length - 1).join(' > ')}',
      onTap: open,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('result.${hit.pageId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTap + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hit.trail.take(hit.trail.length - 1).join(' > '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(color: c.muted),
                ),
                HighlightedText(
                  hit.page,
                  term: hit.matchIn == 'title' ? _asked : '',
                  style: theme.titleSmall,
                  maxLines: 2,
                ),
                if (hit.snippet.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: HighlightedText(
                      plainFromMarkdown(hit.snippet),
                      term: _asked,
                      style: theme.bodyMedium?.copyWith(color: c.ink),
                      maxLines: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final hits = _answer.hits;
    if (hits.isEmpty) return Note(context.t.librarySearchNone);
    final c = context.colors;
    return ListView.builder(
      padding: pagePadding(context),
      itemCount: hits.length + (_answer.more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == hits.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              context.t.librarySearchMore,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
          );
        }
        return _row(context, hits[i]);
      },
    );
  }

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.idle:
        return Note(context.t.librarySearchPrompt);
      case _Phase.loading:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        );
      case _Phase.done:
        return _results(context);
      case _Phase.offline:
        return _problem(context, context.t.librarySearchOffline);
      case _Phase.failed:
        return _problem(context, context.t.librarySearchFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          textField: true,
          label: context.t.librarySearchHint,
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.none,
            onChanged: _typed,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: context.t.librarySearchHint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        actions: <Widget>[
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: context.t.librarySearchClear,
              onPressed: _clear,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: _body(context),
    );
  }
}
