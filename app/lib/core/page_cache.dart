// THE COPY OF THE NOTEBOOKS KEPT ON THE PHONE: THE OUTLINE, THE TEXT OF THE LAST PAGES OPENED OR PINNED, AND THE RECENTLY OPENED LIST.
// So a manual can be read on a train. The copy is marked stale ("Offline copy") whenever it is shown instead of the server's answer. It is bounded:
// at most [maxCachedPages] page texts, the oldest used going first. Notebook text is the person's own, not a secret, but it is removed when
// signing out and after a data reset, like the photos of sent messages.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'json.dart';
import 'library.dart';

// -- CONSTANTS -- //

/// Page texts kept on the phone, the one used longest ago dropped first.
const int maxCachedPages = 50;

/// Pages remembered in the "recently opened" list.
const int maxRecents = 12;

const String _prefix = 'library.';
const String _outlineKey = 'library.outline.v1';
const String _indexKey = 'library.pages.v1';
const String _pagePrefix = 'library.page.v1.';
const String _recentsKey = 'library.recents.v1';

// -- FUNCTIONS -- //

class PageCache {
  PageCache(this._prefs);

  final SharedPreferences _prefs;

  int _generation = 0;

  /// Goes up with every [wipe]. A background fetch that began before a wipe compares it and drops what it brought, so a wipe is not undone.
  int get generation => _generation;

  Json _readJson(String key) {
    final raw = _prefs.getString(key);
    return raw == null ? <String, Object?>{} : decodeJson(raw);
  }

  /// The last outline that was fetched, marked offline, or null when there is none.
  Library? library() {
    final j = _readJson(_outlineKey);
    return j.isEmpty ? null : Library.fromCache(j);
  }

  Future<void> saveLibrary(Library library) =>
      _prefs.setString(_outlineKey, jsonEncode(library.toJson()));

  /// The ids of the saved pages, the one used longest ago first.
  List<String> _index() {
    final raw = _prefs.getString(_indexKey);
    if (raw == null) return <String>[];
    try {
      return <String>[
        for (final e in asList(jsonDecode(raw)))
          if (e is String) e,
      ];
    } on FormatException {
      return <String>[];
    }
  }

  Future<void> _saveIndex(List<String> ids) =>
      _prefs.setString(_indexKey, jsonEncode(ids));

  /// The ids of the pages whose text is on the phone.
  List<String> cachedIds() => _index();

  /// The saved page marked offline, or null when it was never saved.
  PageDoc? page(String id) {
    final j = _readJson('$_pagePrefix$id');
    return j.isEmpty ? null : PageDoc.fromJson(j).asOffline();
  }

  /// The version of the saved copy, or null.
  int? cachedVersion(String id) {
    final j = _readJson('$_pagePrefix$id');
    return j.isEmpty ? null : intOf(j['version']);
  }

  /// Keeps this page as the newest used, and drops the oldest ones past the bound.
  Future<void> savePage(PageDoc doc) async {
    await _prefs.setString('$_pagePrefix${doc.id}', jsonEncode(doc.toJson()));
    final ids = _index()
      ..remove(doc.id)
      ..add(doc.id);
    while (ids.length > maxCachedPages) {
      final old = ids.removeAt(0);
      await _prefs.remove('$_pagePrefix$old');
    }
    await _saveIndex(ids);
  }

  Future<void> forgetPage(String id) async {
    await _prefs.remove('$_pagePrefix$id');
    final ids = _index();
    if (ids.remove(id)) await _saveIndex(ids);
  }

  /// The pages opened lately, newest first.
  List<RecentPage> recents() {
    final raw = _prefs.getString(_recentsKey);
    if (raw == null) return <RecentPage>[];
    try {
      return asJsonList(jsonDecode(raw)).map(RecentPage.fromJson).toList();
    } on FormatException {
      return <RecentPage>[];
    }
  }

  Future<void> saveRecents(List<RecentPage> list) => _prefs.setString(
    _recentsKey,
    jsonEncode(<Json>[for (final r in list.take(maxRecents)) r.toJson()]),
  );

  /// Removes everything of the library from the phone.
  Future<void> wipe() async {
    _generation++;
    for (final key in _prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await _prefs.remove(key);
    }
  }
}
