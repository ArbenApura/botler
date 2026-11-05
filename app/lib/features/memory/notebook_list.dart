// THE OTHER NOTEBOOKS: THE FORM THAT MAKES OR RENAMES ONE, AND THE DELETED ONES THAT CAN BE PUT BACK. (THE LIST OF THEM IS THE LIBRARY SCREEN.)
// The main notebook keeps the essentials; Botler (or you) keeps other information in notebooks of their own. Each has a title and a one-line
// summary, which is also how Botler finds it. A deleted notebook is only hidden for 30 days.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

/// The longest title and summary the server accepts.
const int notebookTitleMax = 80;
const int notebookSummaryMax = 200;

/// The other notebooks (not the main one), by title.
final FutureProvider<List<Json>> notebookListProvider =
    FutureProvider.autoDispose<List<Json>>((ref) async {
      final answer = await ref.watch(apiProvider).verbJson('notebook_list');
      return asJsonList(answer['notebooks'])
          .where((n) => str(n['kind']) == 'extra')
          .toList();
    });

/// The deleted notebooks that can still be restored.
final FutureProvider<List<Json>> _deletedProvider =
    FutureProvider.autoDispose<List<Json>>((ref) async {
      final answer = await ref.watch(apiProvider).verbJson(
        'notebook_list',
        <String, Object?>{'deleted': true},
      );
      return asJsonList(answer['notebooks']);
    });

// -- WIDGETS -- //

/// Makes a new notebook (no [notebook]) or renames and describes one. [onDone] gets the notebook the server answered with.
class NotebookInfoForm extends ConsumerStatefulWidget {
  const NotebookInfoForm({required this.onDone, this.notebook, super.key});

  final Json? notebook;
  final void Function(Json notebook) onDone;

  @override
  ConsumerState<NotebookInfoForm> createState() => _NotebookInfoFormState();
}

class _NotebookInfoFormState extends ConsumerState<NotebookInfoForm> {
  // -- STATES -- //

  late final TextEditingController _title = TextEditingController(
    text: str(widget.notebook?['title']),
  );
  late final TextEditingController _summary = TextEditingController(
    text: str(widget.notebook?['summary']),
  );
  bool _saving = false;
  // The intent is the title and the summary: the same form again is the same request, a changed form is a new one
  final Once _once = Once();

  // -- FUNCTIONS -- //

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final existing = widget.notebook;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      final summary = _summary.text.trim();
      final intent =
          '${existing == null ? 'new' : str(existing['id'])}:$title:$summary';
      final answer = await _once.run((key) async {
        if (existing == null) {
          return api.verb('notebook_create', <String, Object?>{
            'title': title,
            'summary': summary,
          }, key);
        }
        return api.verb('notebook_update', <String, Object?>{
          'notebookId': str(existing['id']),
          'newTitle': title,
          'summary': summary,
        }, key);
      }, intent: intent);
      if (answer == null) return;
      final made = asJson(answer);
      ref
        ..invalidate(notebookListProvider)
        ..invalidate(libraryProvider);
      widget.onDone(made);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
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
          label: context.t.notebookFieldTitle,
          capitalization: TextCapitalization.sentences,
          maxLength: notebookTitleMax,
          onChanged: (_) => setState(() {}),
        ),
        Field(
          controller: _summary,
          label: context.t.notebookFieldSummary,
          hint: context.t.notebookFieldSummaryHint,
          maxLength: notebookSummaryMax,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
            child: Text(
              widget.notebook == null
                  ? context.t.notebookCreate
                  : context.t.save,
            ),
          ),
        ),
      ],
    );
  }
}

/// One key per notebook put back, until it works, and no second call of the same one while it runs.
final Once _undeleteOnce = Once();

/// The deleted notebooks, each with a way back.
class DeletedNotebooks extends ConsumerWidget {
  const DeletedNotebooks({required this.onRestored, super.key});

  final VoidCallback onRestored;

  Future<void> _restore(BuildContext context, WidgetRef ref, Json n) async {
    final restored = context.t.notebookRestored;
    try {
      final id = str(n['id']);
      final ran = await _undeleteOnce.ok((key) async {
        await ref.read(apiProvider).verb('notebook_undelete', <String, Object?>{
          'notebookId': id,
        }, key);
      }, intent: id);
      if (!ran) return;
      ref
        ..invalidate(notebookListProvider)
        ..invalidate(libraryProvider);
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
      value: ref.watch(_deletedProvider),
      skeleton: const SkeletonRows(count: 3),
      onRetry: () => ref.invalidate(_deletedProvider),
      data: (list) {
        if (list.isEmpty) return Note(context.t.notebookDeletedEmpty);
        return Column(
          children: <Widget>[
            for (final n in list)
              ListTile(
                key: ValueKey<String>('deleted.${str(n['id'])}'),
                contentPadding: EdgeInsets.zero,
                title: Text(str(n['title'])),
                subtitle: str(n['summary']).isEmpty
                    ? null
                    : Text(
                        plainFromMarkdown(str(n['summary'])),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted),
                      ),
                trailing: TextButton(
                  onPressed: () => _restore(context, ref, n),
                  child: Text(context.t.notebookRestore),
                ),
              ),
          ],
        );
      },
    );
  }
}
