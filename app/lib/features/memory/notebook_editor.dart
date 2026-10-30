// THE NOTEBOOK EDITOR: THE WHOLE TEXT IN ONE FIELD, A COUNTER, AND SAVE. SAVING NEEDS THE NETWORK AND IS CHECKED AGAINST THE VERSION THAT WAS OPENED.
// Whatever happens, the text typed here is never lost to a failed save: a lost connection or a newer version leaves it in the field, and the
// person chooses what to do. A retry of the same text with the same version reuses its request id, so a save whose answer was lost is not made twice.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'markdown_edit.dart';
import 'markdown_toolbar.dart';
import 'notebook_text.dart';

// -- TYPES -- //

enum _Conflict { copy, overwrite, keepEditing }

class NotebookEditor extends ConsumerStatefulWidget {
  const NotebookEditor({
    required this.initial,
    required this.version,
    this.notebookId,
    this.title,
    this.pageId,
    this.maxChars = notebookMaxChars,
    super.key,
  });

  /// The text the editor opens with, and the version it was read at.
  final String initial;
  final int version;

  /// The notebook being edited: none is the main notebook. [title] names an extra one in the app bar.
  final String? notebookId;
  final String? title;

  /// A page of a notebook with pages: the text is read and saved with the page verbs, checked against the page's own version. Without it
  /// this is the main notebook (or an older one-page notebook) and nothing changes.
  final String? pageId;

  /// The longest text the server accepts here: a page takes more than the main notebook.
  final int maxChars;

  @override
  ConsumerState<NotebookEditor> createState() => _NotebookEditorState();
}

class _NotebookEditorState extends ConsumerState<NotebookEditor> {
  // -- STATES -- //

  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focus = FocusNode();
  late int _version = widget.version;
  bool _saving = false;
  String? _key;
  String _keyText = '';
  int _keyVersion = -1;

  // -- FUNCTIONS -- //

  bool get _changed => _controller.text != widget.initial;

  int get _count => _controller.text.length;

  /// Names the notebook to the server; the main notebook needs no name.
  Map<String, Object?> get _target => widget.pageId != null
      ? <String, Object?>{'pageId': widget.pageId}
      : <String, Object?>{'notebookId': ?widget.notebookId};

  bool get _isPage => widget.pageId != null;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A toolbar button: the text changes where the cursor is, and the field keeps the keyboard.
  void _edit(MarkdownEdit edit) {
    _controller.value = applyMarkdownEdit(_controller.value, edit);
    _focus.requestFocus();
    setState(() {});
  }

  /// The request id of this text at this version: a repeat of the same save carries the same one.
  String _requestId() {
    if (_key == null ||
        _keyText != _controller.text ||
        _keyVersion != _version) {
      _key = newRequestId();
      _keyText = _controller.text;
      _keyVersion = _version;
    }
    return _key!;
  }

  Future<void> _save({bool overwrite = false}) async {
    final api = ref.read(apiProvider);
    final words = context.t;
    setState(() => _saving = true);
    var conflict = false;
    try {
      if (overwrite) {
        // The newest version is read first, so this save is made from it: what it replaces stays in the changes
        final latest = await api.verbJson(
          _isPage ? 'page_get' : 'notebook_get',
          _target,
        );
        _version = intOf(latest['version']);
      }
      await api.verb(_isPage ? 'page_save' : 'notebook_save', <String, Object?>{
        ..._target,
        'text': _controller.text,
        'expectVersion': _version,
      }, _requestId());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'CONFLICT') {
        conflict = true;
      } else if (e.isNetwork) {
        say(context, words.notebookOffline);
      } else {
        say(context, errorWords(e, context));
      }
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // The choice is asked after the save has ended, so nothing spins behind the dialog
    if (conflict && mounted) await _conflict();
  }

  Future<void> _conflict() async {
    final words = context.t;
    final choice = await showDialog<_Conflict>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(words.notebookConflictTitle),
        content: Text(words.notebookConflictBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(_Conflict.keepEditing),
            child: Text(words.notebookKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(_Conflict.copy),
            child: Text(words.notebookConflictCopy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(_Conflict.overwrite),
            child: Text(words.notebookConflictSave),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _Conflict.copy) {
      await Clipboard.setData(ClipboardData(text: _controller.text));
      if (mounted) say(context, words.notebookCopiedText);
    } else if (choice == _Conflict.overwrite) {
      await _save(overwrite: true);
    }
  }

  Future<void> _leave() async {
    final leave = await confirm(
      context,
      title: context.t.notebookDiscardTitle,
      body: context.t.notebookDiscardBody,
      yes: context.t.notebookDiscardYes,
      danger: true,
    );
    if (leave && mounted) Navigator.of(context).pop(false);
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final over = _count > widget.maxChars;
    return PopScope(
      // Typed words are asked about before they are thrown away
      canPop: !_changed || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? context.t.notebookEditTitle),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving || over || !_changed ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.onAccent,
                        ),
                      )
                    : Text(context.t.save),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    label: context.t.notebookEditTitle,
                    textField: true,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      readOnly: _saving,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: context.t.notebookEditHint,
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Only a page has the Markdown buttons; the main notebook is edited as before
                if (_isPage && !_saving) MarkdownToolbar(onEdit: _edit),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    context.t.notebookCount(
                      _count.toString(),
                      widget.maxChars.toString(),
                    ),
                    style: TextStyle(
                      color: over ? c.danger : c.muted,
                      fontFeatures: tabular,
                    ),
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
