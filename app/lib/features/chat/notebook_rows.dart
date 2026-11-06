// THE QUIET LINE FOR WHAT THE ASSISTANT WROTE IN THE NOTEBOOKS. A SAVE IS NOT A LOOKUP, SO IT NEVER READS "CHECKED ...".
// The words come only from the tool's own answer (the section, the page and the notebook it names), never from the arguments the model sent, and a
// write that changed nothing says so. A pending approval card and a failed write never reach this file: the row is only drawn for an answer that is ok.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';

// -- CONSTANTS -- //

/// The tools that change a notebook or a page. A read (page_get, notebook_outline, notebook_search) is not one of them.
const Set<String> notebookWriteTools = <String>{
  'notebook_edit',
  'notebook_create',
  'notebook_update',
  'notebook_delete',
  'notebook_undelete',
  'page_edit',
  'page_create',
  'page_rename',
  'page_move',
  'page_merge',
  'page_delete',
  'page_undelete',
};

// -- FUNCTIONS -- //

bool isNotebookWrite(String name) => notebookWriteTools.contains(name);

/// The heading a section starts with ("# Preferences and rules" gives "Preferences and rules"), or empty.
String _headingOf(String section) {
  final first = section.split('\n').first.trim();
  if (!first.startsWith('#')) return '';
  return first.replaceFirst(RegExp(r'^#+\s*'), '').trim();
}

/// A title taken from an answer that holds a page or a notebook, or from the removed one inside it.
String _titleOf(Json data) {
  final own = str(data['title']);
  if (own.isNotEmpty) return own;
  final inner = asJson(data['removed']);
  if (inner.isNotEmpty) return str(inner['title']);
  return str(asJson(data['page'])['title']);
}

/// The words for a finished notebook write, or null when [name] is not one. An answer that is missing (an older stored one) gives the plain words.
String? notebookWriteLine(BuildContext context, String name, Object? raw) {
  if (!isNotebookWrite(name)) return null;
  final t = context.t;
  final data = asJson(raw);
  switch (name) {
    case 'notebook_edit':
      if (data['changed'] == false) return t.chatNotebookAlready;
      final notebook = str(data['notebook']);
      // Another notebook's edit lands on its Overview page
      if (notebook.isNotEmpty && notebook != 'main') {
        return t.chatPageSaved('Overview', notebook);
      }
      final where = _headingOf(str(data['section']));
      return where.isEmpty
          ? t.chatNotebookSavedPlain
          : t.chatNotebookSaved(where);
    case 'page_edit':
      if (data['changed'] == false) return t.chatNotebookAlready;
      final page = str(data['page']);
      final notebook = str(data['notebook']);
      return page.isEmpty || notebook.isEmpty
          ? t.chatNotebookSavedPlain
          : t.chatPageSaved(page, notebook);
    case 'notebook_create' || 'page_create':
      final title = _titleOf(data);
      return title.isEmpty
          ? t.chatNotebookChangedPlain
          : t.chatNotebookMade(title);
    case 'notebook_delete' || 'page_delete':
      final title = _titleOf(data);
      return title.isEmpty
          ? t.chatNotebookChangedPlain
          : t.chatNotebookRemoved(title);
    case 'notebook_undelete' || 'page_undelete':
      final title = _titleOf(data);
      return title.isEmpty
          ? t.chatNotebookChangedPlain
          : t.chatNotebookRestored(title);
    default:
      // Rename, move, merge, update
      final title = _titleOf(data);
      return title.isEmpty
          ? t.chatNotebookChangedPlain
          : t.chatNotebookChanged(title);
  }
}
