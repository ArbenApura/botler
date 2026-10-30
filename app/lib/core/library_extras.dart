// THE SMALLER SHAPES AROUND A PAGE: A SEARCH HIT, A LINK BACK TO THE PAGE, A CHANGE BOTLER MADE, AND WHAT CHANGED SINCE THE PERSON LAST READ.
// Pure data, no network and no widgets; each class reads the answer of one server operation (notebook_search, page_backlinks, page_activity).

// -- MODULES -- //
import 'json.dart';

// -- TYPES -- //

/// One page that matches a search, with the line around the match.
class SearchHit {
  const SearchHit({
    required this.pageId,
    required this.notebook,
    required this.page,
    required this.matchIn,
    required this.snippet,
    this.parent,
  });

  factory SearchHit.fromJson(Json j) => SearchHit(
    pageId: str(j['pageId']),
    notebook: str(j['notebook']),
    page: str(j['page']),
    parent: j['parent'] is String ? j['parent']! as String : null,
    matchIn: str(j['matchIn'], 'text'),
    snippet: str(j['snippet']),
  );

  final String pageId;
  final String notebook;
  final String page;
  final String? parent;

  /// 'title' or 'text'.
  final String matchIn;
  final String snippet;

  /// 'Notebook > Page' or 'Notebook > Parent > Page'.
  List<String> get trail => <String>[notebook, ?parent, page];
}

class SearchAnswer {
  const SearchAnswer({required this.hits, required this.more});

  factory SearchAnswer.fromJson(Json j) => SearchAnswer(
    hits: <SearchHit>[
      for (final r in asJsonList(j['results'])) SearchHit.fromJson(r),
    ],
    more: boolOf(j['more']),
  );

  final List<SearchHit> hits;

  /// There are more matches than are listed.
  final bool more;
}

/// A page that links to the page being read.
class Backlink {
  const Backlink({
    required this.pageId,
    required this.notebook,
    required this.page,
    required this.snippet,
  });

  factory Backlink.fromJson(Json j) => Backlink(
    pageId: str(j['pageId']),
    notebook: str(j['notebook']),
    page: str(j['page']),
    snippet: str(j['snippet']),
  );

  final String pageId;
  final String notebook;
  final String page;
  final String snippet;
}

/// A page Botler changed lately, at the version it left it.
class ActivityEntry {
  const ActivityEntry({
    required this.pageId,
    required this.notebookId,
    required this.notebook,
    required this.page,
    required this.version,
    required this.updatedAt,
    this.created = false,
    this.textChanged = false,
  });

  factory ActivityEntry.fromJson(Json j) => ActivityEntry(
    pageId: str(j['pageId']),
    notebookId: str(j['notebookId']),
    notebook: str(j['notebook']),
    page: str(j['page']),
    version: intOf(j['version'], 1),
    updatedAt: dateOf(j['updatedAt']),
    created: boolOf(j['created']),
    textChanged: boolOf(j['textChanged']),
  );

  final String pageId;
  final String notebookId;
  final String notebook;
  final String page;
  final int version;
  final DateTime? updatedAt;

  /// Botler made the page and nothing touched it since: undoing it means deleting the page. The server says so; an older server does not, and
  /// then the entry is only for looking at.
  final bool created;

  /// Botler made the latest change to the text, so there is an earlier text to put back. A rename or a move is neither this nor [created].
  final bool textChanged;

  /// Undo may be offered: Botler made the page, or changed its text.
  bool get undoable => created || textChanged;
}

/// What is known about the change since the version the person last read.
enum ChangeKind {
  /// Nothing to show: nothing new, never read here, or no connection.
  none,

  /// The lines in [PageChanges.added] are new.
  lines,

  /// The version that was read is older than the kept changes, so it cannot be compared.
  tooMuch,
}

class PageChanges {
  const PageChanges(this.kind, [this.added = const <int>{}]);

  static const PageChanges none = PageChanges(ChangeKind.none);

  final ChangeKind kind;

  /// Numbers (from 0) of the lines of the page that are new.
  final Set<int> added;

  bool get marksLines => kind == ChangeKind.lines && added.isNotEmpty;
}

/// The words of a time that has passed, as a number and a unit, so the screen can say it in the app's language.
class Ago {
  const Ago(this.unit, this.count);

  /// 'now', 'minutes', 'hours' or 'days'.
  final String unit;
  final int count;
}

// -- FUNCTIONS -- //

/// How long ago [at] was, in the largest whole unit.
Ago agoOf(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return const Ago('now', 0);
  if (d.inHours < 1) return Ago('minutes', d.inMinutes);
  if (d.inDays < 1) return Ago('hours', d.inHours);
  return Ago('days', d.inDays);
}

/// Days left of the 30 a deleted page is kept, never below 0.
int daysLeftToRestore(DateTime deletedAt, DateTime now, {int keptDays = 30}) {
  final left = keptDays - now.difference(deletedAt).inDays;
  return left < 0 ? 0 : left;
}
