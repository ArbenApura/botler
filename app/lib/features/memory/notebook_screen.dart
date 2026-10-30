// THE NOTEBOOK: WHAT BOTLER KEEPS IN MIND ABOUT YOU, AS A SHORT PAGE OF SECTIONS. ONE PRIMARY ACTION, EDIT. THE CHANGES, THE PRIVATE NAMES, COPYING
// EVERYTHING AND WIPING ARE IN THE MENU. Botler writes lasting things in it while you talk; you can change any word, and every change keeps the
// text it replaced, so nothing is lost to an edit. The route stays /memory so an older link still opens it.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'notebook_editor.dart';
import 'notebook_list.dart';
import 'notebook_text.dart';

// -- CONSTANTS -- //

/// A notebook by id; no id is the main notebook.
Json _target(String? id) => <String, Object?>{'notebookId': ?id};

final _notebook = FutureProvider.autoDispose.family<Json, String?>(
  (ref, id) => ref.watch(apiProvider).verbJson('notebook_get', _target(id)),
);

final _revisions = FutureProvider.autoDispose.family<List<Json>, String?>((
  ref,
  id,
) async {
  final answer = await ref
      .watch(apiProvider)
      .verbJson('notebook_revisions', _target(id));
  return asJsonList(answer['revisions']);
});

final DateFormat _when = DateFormat('d MMM, HH:mm');

// -- TYPES -- //

enum _More { changes, names, copy, wipe, describe, delete }

/// The main notebook (no [notebookId]), opened from the top of the library. A notebook id still opens an older one-page notebook by its text.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({this.notebookId, this.title, super.key});

  final String? notebookId;
  final String? title;

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  // -- FUNCTIONS -- //

  String? get _id => widget.notebookId;

  bool get _main => _id == null;

  void _refresh() => ref
    ..invalidate(_notebook(_id))
    ..invalidate(_revisions(_id))
    ..invalidate(notebookListProvider)
    ..invalidate(libraryProvider);

  Future<void> _edit(Json book) async {
    final saved = context.t.memorySaved;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => NotebookEditor(
          initial: str(book['text']),
          version: intOf(book['version'], 1),
          notebookId: _id,
          title: _main ? null : str(book['title']),
        ),
      ),
    );
    if (done == true) {
      _refresh();
      if (mounted) say(context, saved);
    }
  }

  Future<void> _changes() async {
    await showFormSheet<void>(
      context,
      title: context.t.notebookChanges,
      builder: (sheet, close) => _Changes(
        notebookId: _id,
        onRestored: () {
          _refresh();
          close(null);
        },
      ),
    );
  }

  Future<void> _names() async {
    final Json profile;
    try {
      profile = await ref.read(apiProvider).verbJson('profile_get');
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
      return;
    }
    if (!mounted) return;
    final names = asList(profile['people']).whereType<String>().toList();
    final saved = await showFormSheet<bool>(
      context,
      title: context.t.notebookNames,
      builder: (sheet, close) =>
          _Names(initial: names, onSaved: () => close(true)),
    );
    if (saved == true && mounted) say(context, context.t.memorySaved);
  }

  Future<void> _wipe() async {
    final typed = TextEditingController();
    final wipeWord = context.t.memoryWipeWord;
    final wiped = context.t.memoryWiped;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(context.t.memoryWipeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.t.memoryWipeBody),
            const SizedBox(height: 12),
            TextField(
              controller: typed,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: context.t.memoryWipeType),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(context.t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: context.colors.paper,
            ),
            onPressed: () => Navigator.of(d).pop(typed.text.trim() == wipeWord),
            child: Text(context.t.memoryWipe),
          ),
        ],
      ),
    );
    // The field is not disposed here: the dialog is still fading out and builds it once more
    if (ok != true) return;
    try {
      await ref.read(apiProvider).verb('memory_wipe', <String, Object?>{
        'confirm': true,
      });
      // The wipe took the library's pages with it: the copies kept on the phone and the recently opened list are old now
      await ref.read(pageCacheProvider).wipe();
      ref
        ..invalidate(recentsProvider)
        ..invalidate(libraryProvider);
      _refresh();
      if (mounted) say(context, wiped);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _export() async {
    final copied = context.t.memoryCopied;
    try {
      final all = await ref.read(apiProvider).verb('memory_export');
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(all)),
      );
      if (mounted) say(context, copied);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _describe(Json book) async {
    final saved = context.t.memorySaved;
    final done = await showFormSheet<Json>(
      context,
      title: context.t.notebookDescribe,
      builder: (sheet, close) =>
          NotebookInfoForm(notebook: book, onDone: close),
    );
    if (done != null) {
      _refresh();
      if (mounted) say(context, saved);
    }
  }

  Future<void> _delete(Json book) async {
    final gone = context.t.notebookDeletedDone;
    final ok = await confirm(
      context,
      title: context.t.notebookDeleteTitle,
      body: context.t.notebookDeleteBody,
      yes: context.t.notebookDelete,
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(apiProvider).verb('notebook_delete', <String, Object?>{
        'notebookId': str(book['id']),
      });
      ref
        ..invalidate(notebookListProvider)
        ..invalidate(libraryProvider);
      if (!mounted) return;
      say(context, gone);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  void _more(_More what, Json? book) {
    switch (what) {
      case _More.describe:
        if (book != null) _describe(book);
      case _More.delete:
        if (book != null) _delete(book);
      case _More.changes:
        _changes();
      case _More.names:
        _names();
      case _More.copy:
        _export();
      case _More.wipe:
        _wipe();
    }
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final book = ref.watch(_notebook(_id));
    final loaded = book.asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _main
              ? context.t.notebookTitle
              : (loaded == null ? widget.title : str(loaded['title'])) ?? '',
        ),
        actions: <Widget>[
          PopupMenuButton<_More>(
            tooltip: context.t.memoryMore,
            onSelected: (what) => _more(what, loaded),
            itemBuilder: (_) => <PopupMenuEntry<_More>>[
              PopupMenuItem<_More>(
                value: _More.changes,
                child: Text(context.t.notebookChanges),
              ),
              if (_main) ...<PopupMenuEntry<_More>>[
                PopupMenuItem<_More>(
                  value: _More.names,
                  child: Text(context.t.notebookNames),
                ),
                PopupMenuItem<_More>(
                  value: _More.copy,
                  child: Text(context.t.memoryCopyAll),
                ),
                PopupMenuItem<_More>(
                  value: _More.wipe,
                  child: Text(
                    context.t.memoryWipeButton,
                    style: TextStyle(color: c.danger),
                  ),
                ),
              ] else ...<PopupMenuEntry<_More>>[
                PopupMenuItem<_More>(
                  value: _More.describe,
                  child: Text(context.t.notebookDescribe),
                ),
                PopupMenuItem<_More>(
                  value: _More.delete,
                  child: Text(
                    context.t.notebookDelete,
                    style: TextStyle(color: c.danger),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: AsyncBody<Json>(
        value: book,
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        onRetry: () => ref.invalidate(_notebook(_id)),
        data: (b) => _Page(book: b, onEdit: () => _edit(b)),
      ),
    );
  }
}

/// The notebook as a page: Edit, a note while it is still the first draft, then the sections.
class _Page extends StatelessWidget {
  const _Page({required this.book, required this.onEdit});

  final Json book;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = str(book['text']);
    final empty = isEmptyNotebook(text);
    final draft =
        intOf(book['version'], 1) == 1 && str(book['updatedBy']) == 'seed';
    final sections = parseNotebook(text);
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: Text(context.t.notebookEdit),
        ),
        if (str(book['summary']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(str(book['summary']), style: TextStyle(color: c.muted)),
          ),
        if (draft && !empty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              context.t.notebookSeeding,
              style: TextStyle(color: c.muted),
            ),
          ),
        if (empty)
          Note(context.t.notebookEmpty)
        else
          for (final s in sections) ...<Widget>[
            if (s.heading.isNotEmpty) SectionTitle(s.heading),
            PaperCard(
              child: s.lines.isEmpty
                  ? Text(
                      context.t.notebookSectionEmpty,
                      style: TextStyle(color: c.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final l in s.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (l.bullet)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      '•',
                                      style: TextStyle(color: c.muted),
                                    ),
                                  ),
                                Expanded(child: Text(l.text)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              context.t.notebookCount(
                text.length.toString(),
                notebookMaxChars.toString(),
              ),
              style: TextStyle(color: c.muted, fontFeatures: tabular),
            ),
          ),
        ),
      ],
    );
  }
}

/// The changes made to the notebook, newest first, each with a way back.
class _Changes extends ConsumerWidget {
  const _Changes({required this.onRestored, this.notebookId});

  final VoidCallback onRestored;
  final String? notebookId;

  String _who(BuildContext context, String actor) => switch (actor) {
    'agent' => context.t.notebookByBotler,
    'seed' => context.t.notebookBySeed,
    _ => context.t.notebookByYou,
  };

  Future<void> _restore(BuildContext context, WidgetRef ref, Json r) async {
    final restored = context.t.notebookRestored;
    final ok = await confirm(
      context,
      title: context.t.notebookRestoreTitle,
      body: '${context.t.notebookRestoreBody}\n\n${str(r['preview'])}',
      yes: context.t.notebookRestore,
    );
    if (!ok) return;
    try {
      await ref.read(apiProvider).verb('notebook_restore', <String, Object?>{
        'revisionId': str(r['id']),
      });
      if (context.mounted) {
        say(context, restored);
        onRestored();
      }
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return AsyncBody<List<Json>>(
      value: ref.watch(_revisions(notebookId)),
      skeleton: const SkeletonRows(count: 3),
      onRetry: () => ref.invalidate(_revisions(notebookId)),
      data: (list) {
        if (list.isEmpty) return Note(context.t.notebookChangesEmpty);
        return Column(
          children: <Widget>[
            for (final r in list)
              ListTile(
                key: ValueKey<String>('revision.${str(r['id'])}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${_who(context, str(r['actor']))} · ${_formatWhen(dateOf(r['at']))}',
                ),
                subtitle: Text(
                  str(r['preview']),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted),
                ),
                trailing: TextButton(
                  onPressed: () => _restore(context, ref, r),
                  child: Text(context.t.notebookRestore),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _formatWhen(DateTime? at) =>
    at == null ? '' : _when.format(at.toLocal());

/// The private names: chips with a way to add one and to take one away. Saved as the whole list.
class _Names extends ConsumerStatefulWidget {
  const _Names({required this.initial, required this.onSaved});

  final List<String> initial;
  final VoidCallback onSaved;

  @override
  ConsumerState<_Names> createState() => _NamesState();
}

class _NamesState extends ConsumerState<_Names> {
  late final List<String> _names = <String>[...widget.initial];
  final TextEditingController _add = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _addName() {
    final name = _add.text.trim();
    if (name.isEmpty || _names.contains(name)) return;
    setState(() {
      _names.add(name);
      _add.clear();
    });
  }

  Future<void> _save() async {
    // A name typed but not added yet is added, so Save never drops what was written
    _addName();
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).verb('profile_set', <String, Object?>{
        'people': _names,
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.t.memoryPeopleNote,
          style: TextStyle(color: context.colors.muted),
        ),
        const SizedBox(height: 12),
        if (_names.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final n in _names)
                  InputChip(
                    key: ValueKey<String>('name.$n'),
                    label: Text(n),
                    deleteButtonTooltipMessage: context.t.notebookNameRemove(n),
                    onDeleted: () => setState(() => _names.remove(n)),
                  ),
              ],
            ),
          ),
        Field(
          controller: _add,
          label: context.t.notebookNamesAdd,
          hint: context.t.memoryPeopleHint,
          capitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        Row(
          children: <Widget>[
            TextButton(
              onPressed: _addName,
              child: Text(context.t.notebookNamesAddButton),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(context.t.save),
            ),
          ],
        ),
      ],
    );
  }
}
