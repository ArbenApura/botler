// WHAT THE PERSON CAN DO TO A NOTEBOOK OR A PAGE FROM A LONG-PRESS SHEET OR AN OVERFLOW MENU: PIN, RENAME, MOVE, DELETE.
// Pin, rename and move wait in the outbox when there is no connection; delete and create need the network and say so. Every action reports in
// plain words through a snack bar. The sheet is the app's one kind of bottom sheet (showFormSheet).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/library.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../memory/notebook_list.dart';
import 'move_sheet.dart';

// -- CONSTANTS -- //

/// The longest page title the server accepts.
const int pageTitleMax = 80;

// -- TYPES -- //

/// What the sheet of a page can do. [move] asks for a place; [moveUp] and [moveDown] change the place among its neighbours.
enum PageAction { rename, pin, move, moveUp, moveDown, delete }

enum NotebookAction { pin, describe, delete }

// -- FUNCTIONS -- //

/// Says what a write did: nothing when it went through, a note when it was kept for later, the server's words when it was refused.
void reportWrite(BuildContext context, WriteResult result) {
  if (result == WriteResult.queued) say(context, context.t.libraryQueued);
}

/// The words for a failure of a write that needs the network.
String needsNetworkWords(BuildContext context, Object e) =>
    e is ApiException && e.isNetwork
    ? context.t.libraryNeedsConnection
    : errorWords(e, context);

/// One row of an action sheet: an icon and a plain action, at least 56 dp tall.
class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : c.ink;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: 56,
        leading: Icon(icon, color: danger ? c.danger : c.muted),
        title: Text(label, style: TextStyle(color: color)),
        onTap: onTap,
      ),
    );
  }
}

// -- PAGES -- //

/// The sheet of a page: rename, pin or unpin, move, delete. Returns what was chosen (the caller runs it with [runPageAction]). Move up and
/// down are offered when the page has a neighbour on that side.
Future<PageAction?> showPageActions(
  BuildContext context, {
  required String title,
  required bool pinned,
  bool canMoveUp = false,
  bool canMoveDown = false,
}) {
  return showFormSheet<PageAction>(
    context,
    title: title,
    builder: (sheet, close) => Column(
      children: <Widget>[
        ActionTile(
          icon: Icons.drive_file_rename_outline,
          label: sheet.t.pageRename,
          onTap: () => close(PageAction.rename),
        ),
        ActionTile(
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: pinned ? sheet.t.pageUnpin : sheet.t.pagePin,
          onTap: () => close(PageAction.pin),
        ),
        ActionTile(
          icon: Icons.drive_file_move_outline,
          label: sheet.t.pageMove,
          onTap: () => close(PageAction.move),
        ),
        if (canMoveUp)
          ActionTile(
            icon: Icons.arrow_upward,
            label: sheet.t.pageMoveUp,
            onTap: () => close(PageAction.moveUp),
          ),
        if (canMoveDown)
          ActionTile(
            icon: Icons.arrow_downward,
            label: sheet.t.pageMoveDown,
            onTap: () => close(PageAction.moveDown),
          ),
        ActionTile(
          icon: Icons.delete_outline,
          label: sheet.t.pageDelete,
          danger: true,
          onTap: () => close(PageAction.delete),
        ),
      ],
    ),
  );
}

/// Does what the page sheet chose. [onDeleted] runs after a delete went through (the reader closes itself there).
Future<void> runPageAction(
  BuildContext context,
  WidgetRef ref,
  PageAction action, {
  required String pageId,
  required String title,
  required bool pinned,
  VoidCallback? onDeleted,
}) async {
  final actions = ref.read(libraryActionsProvider);
  switch (action) {
    case PageAction.pin:
      try {
        final result = await actions.pinPage(pageId, pinned: !pinned);
        if (context.mounted) reportWrite(context, result);
      } catch (e) {
        if (context.mounted) say(context, errorWords(e, context));
      }
    case PageAction.move:
      final library = ref.read(libraryProvider).asData?.value;
      final page = library?.page(pageId);
      if (library == null || page == null) return;
      final target = await pickMoveTarget(context, library, page);
      if (target == null || !context.mounted) return;
      final sameBook = target.notebookId == page.notebookId;
      if (sameBook && target.parentPageId == page.parentPageId) return;
      await _moved(
        context,
        () => actions.movePage(
          pageId,
          toNotebookId: sameBook ? null : target.notebookId,
          toParentPageId: target.parentPageId,
        ),
      );
    case PageAction.moveUp:
    case PageAction.moveDown:
      final library = ref.read(libraryProvider).asData?.value;
      final page = library?.page(pageId);
      if (library == null || page == null) return;
      final mates = library.siblings(page);
      final at = mates.indexWhere((p) => p.id == pageId);
      final to = action == PageAction.moveUp ? at - 1 : at + 1;
      if (at < 0 || to < 0 || to >= mates.length) return;
      // The parent is named again so a sub-page stays under it while it changes place
      await _moved(
        context,
        () => actions.movePage(
          pageId,
          toParentPageId: page.parentPageId,
          position: to,
        ),
      );
    case PageAction.rename:
      final renamed = context.t.pageRenamed;
      final result = await showFormSheet<WriteResult>(
        context,
        title: context.t.pageRename,
        builder: (sheet, close) => PageTitleForm(
          initial: title,
          label: sheet.t.save,
          onSubmit: (text) async =>
              close(await actions.renamePage(pageId, text)),
        ),
      );
      if (result != null && context.mounted) {
        if (result == WriteResult.queued) {
          say(context, context.t.libraryQueued);
        } else {
          say(context, renamed);
        }
      }
    case PageAction.delete:
      final gone = context.t.pageDeleted;
      final ok = await confirm(
        context,
        title: context.t.pageDeleteTitle,
        body: context.t.pageDeleteBody,
        yes: context.t.pageDelete,
        danger: true,
      );
      if (!ok || !context.mounted) return;
      try {
        await actions.deletePage(pageId);
        if (!context.mounted) return;
        say(context, gone);
        onDeleted?.call();
      } catch (e) {
        if (context.mounted) say(context, needsNetworkWords(context, e));
      }
  }
}

/// Runs a move and says what happened: moved, kept for later, or the server's words.
Future<void> _moved(
  BuildContext context,
  Future<WriteResult> Function() move,
) async {
  final done = context.t.pageMoved;
  try {
    final result = await move();
    if (!context.mounted) return;
    say(context, result == WriteResult.queued ? context.t.libraryQueued : done);
  } catch (e) {
    if (context.mounted) say(context, errorWords(e, context));
  }
}

/// A one-line form for a page title: used to rename a page and to name a new one. [onSubmit] does the work and closes the sheet; an error it
/// throws is shown here and the sheet stays open.
class PageTitleForm extends StatefulWidget {
  const PageTitleForm({
    required this.label,
    required this.onSubmit,
    this.initial = '',
    super.key,
  });

  final String initial;

  /// The words on the one button.
  final String label;
  final Future<void> Function(String title) onSubmit;

  @override
  State<PageTitleForm> createState() => _PageTitleFormState();
}

class _PageTitleFormState extends State<PageTitleForm> {
  // -- STATES -- //

  late final TextEditingController _title = TextEditingController(
    text: widget.initial,
  );
  bool _busy = false;

  // -- FUNCTIONS -- //

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _title.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(text);
    } catch (e) {
      if (mounted) say(context, needsNetworkWords(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Field(
          controller: _title,
          label: context.t.pageTitleLabel,
          hint: context.t.pageTitleHint,
          maxLength: pageTitleMax,
          onChanged: (_) => setState(() {}),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy || _title.text.trim().isEmpty ? null : _submit,
            child: Text(widget.label),
          ),
        ),
      ],
    );
  }
}

// -- NOTEBOOKS -- //

/// The sheet of a notebook: pin or unpin, name and summary, delete.
Future<NotebookAction?> showNotebookActions(
  BuildContext context, {
  required LibraryNotebook notebook,
}) {
  return showFormSheet<NotebookAction>(
    context,
    title: notebook.title,
    builder: (sheet, close) => Column(
      children: <Widget>[
        ActionTile(
          icon: notebook.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: notebook.pinned ? sheet.t.pageUnpin : sheet.t.pagePin,
          onTap: () => close(NotebookAction.pin),
        ),
        ActionTile(
          icon: Icons.edit_outlined,
          label: sheet.t.notebookDescribe,
          onTap: () => close(NotebookAction.describe),
        ),
        ActionTile(
          icon: Icons.delete_outline,
          label: sheet.t.notebookDelete,
          danger: true,
          onTap: () => close(NotebookAction.delete),
        ),
      ],
    ),
  );
}

/// Does what the notebook sheet chose. [onDeleted] runs after the notebook was deleted (its own screen closes itself there).
Future<void> runNotebookAction(
  BuildContext context,
  WidgetRef ref,
  NotebookAction action,
  LibraryNotebook notebook, {
  VoidCallback? onDeleted,
}) async {
  switch (action) {
    case NotebookAction.pin:
      try {
        final result = await ref
            .read(libraryActionsProvider)
            .pinNotebook(notebook.id, pinned: !notebook.pinned);
        if (context.mounted) reportWrite(context, result);
      } catch (e) {
        if (context.mounted) say(context, errorWords(e, context));
      }
    case NotebookAction.describe:
      final saved = context.t.memorySaved;
      final form = <String, Object?>{
        'id': notebook.id,
        'title': notebook.title,
        'summary': notebook.summary,
      };
      final done = await showFormSheet<Json>(
        context,
        title: context.t.notebookDescribe,
        builder: (sheet, close) =>
            NotebookInfoForm(notebook: form, onDone: close),
      );
      if (done != null) {
        ref.read(libraryActionsProvider).refresh();
        if (context.mounted) say(context, saved);
      }
    case NotebookAction.delete:
      final gone = context.t.notebookDeletedDone;
      final ok = await confirm(
        context,
        title: context.t.notebookDeleteTitle,
        body: context.t.notebookDeleteBody,
        yes: context.t.notebookDelete,
        danger: true,
      );
      if (!ok || !context.mounted) return;
      try {
        await ref.read(apiProvider).verb('notebook_delete', <String, Object?>{
          'notebookId': notebook.id,
        });
        ref.read(libraryActionsProvider).refresh();
        if (!context.mounted) return;
        say(context, gone);
        onDeleted?.call();
      } catch (e) {
        if (context.mounted) say(context, needsNetworkWords(context, e));
      }
  }
}
