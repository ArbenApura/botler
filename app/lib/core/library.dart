// THE LIBRARY OF NOTEBOOKS AS THE APP HOLDS IT: NOTEBOOKS WITH PAGES, A PAGE WITH ITS TEXT, THE TREE OF A NOTEBOOK FLATTENED FOR A LAZY LIST.
// Pure data, no network and no widgets. The server answers notebook_outline (every notebook with its pages in tree order) and page_get (one page);
// the same shapes are saved on the phone for reading without a connection, so every class here can be written back to JSON.
// The Main notebook is not part of the library: it stays one special page of its own (features/memory/notebook_screen.dart).

// -- MODULES -- //
import 'json.dart';

// -- TYPES -- //

/// One line of a notebook's outline: a page without its text.
class LibraryPage {
  const LibraryPage({
    required this.id,
    required this.notebookId,
    required this.title,
    this.parentPageId,
    this.position = 0,
    this.chars = 0,
    this.version = 1,
    this.seenVersion = 0,
    this.pinnedAt,
    this.updatedBy = 'user',
    this.updatedAt,
    this.deletedAt,
  });

  /// [notebookId] is not in the outline line itself: the notebook that holds the line gives it.
  factory LibraryPage.fromJson(Json j, {required String notebookId}) =>
      LibraryPage(
        id: str(j['id']),
        notebookId: str(j['notebookId'], notebookId),
        parentPageId: j['parentPageId'] is String
            ? j['parentPageId']! as String
            : null,
        title: str(j['title']),
        position: intOf(j['position']),
        chars: intOf(j['chars']),
        version: intOf(j['version'], 1),
        seenVersion: intOf(j['seenVersion']),
        pinnedAt: j['pinnedAt'] is String ? j['pinnedAt']! as String : null,
        updatedBy: str(j['updatedBy'], 'user'),
        updatedAt: j['updatedAt'] is String ? j['updatedAt']! as String : null,
        deletedAt: j['deletedAt'] is String ? j['deletedAt']! as String : null,
      );

  final String id;
  final String notebookId;

  /// The top-level page this one sits under, or null for a top-level page. The tree is one level deep.
  final String? parentPageId;
  final String title;
  final int position;
  final int chars;
  final int version;

  /// The newest version the person has looked at.
  final int seenVersion;

  /// When it was pinned (an ISO time), or null.
  final String? pinnedAt;

  /// 'user', 'agent' or 'seed'.
  final String updatedBy;
  final String? updatedAt;

  /// When it was deleted (an ISO time): only the list of deleted pages has it.
  final String? deletedAt;

  bool get pinned => pinnedAt != null;

  /// Botler wrote it and the person has not looked at that version yet.
  bool get botlerUpdated => updatedBy == 'agent' && version > seenVersion;

  Json toJson() => <String, Object?>{
    'id': id,
    'notebookId': notebookId,
    'parentPageId': parentPageId,
    'title': title,
    'position': position,
    'chars': chars,
    'version': version,
    'seenVersion': seenVersion,
    'pinnedAt': pinnedAt,
    'updatedBy': updatedBy,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  /// [pinnedAt] can be set back to null, so [clearPin] says that; [parentPageId] likewise with [clearParent].
  LibraryPage copyWith({
    String? notebookId,
    String? parentPageId,
    bool clearParent = false,
    String? title,
    String? pinnedAt,
    bool clearPin = false,
    int? seenVersion,
  }) => LibraryPage(
    id: id,
    notebookId: notebookId ?? this.notebookId,
    parentPageId: clearParent ? null : (parentPageId ?? this.parentPageId),
    title: title ?? this.title,
    position: position,
    chars: chars,
    version: version,
    seenVersion: seenVersion ?? this.seenVersion,
    pinnedAt: clearPin ? null : (pinnedAt ?? this.pinnedAt),
    updatedBy: updatedBy,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

/// A notebook of the library with its pages in tree order (a page, then its sub-pages).
class LibraryNotebook {
  const LibraryNotebook({
    required this.id,
    required this.title,
    this.summary = '',
    this.pinnedAt,
    this.pages = const <LibraryPage>[],
  });

  factory LibraryNotebook.fromJson(Json j) {
    final id = str(j['id']);
    return LibraryNotebook(
      id: id,
      title: str(j['title']),
      summary: str(j['summary']),
      pinnedAt: j['pinnedAt'] is String ? j['pinnedAt']! as String : null,
      pages: <LibraryPage>[
        for (final p in asJsonList(j['pages']))
          LibraryPage.fromJson(p, notebookId: id),
      ],
    );
  }

  final String id;
  final String title;
  final String summary;
  final String? pinnedAt;
  final List<LibraryPage> pages;

  int get pageCount => pages.length;
  bool get pinned => pinnedAt != null;

  /// Some page was written by Botler and not looked at yet.
  bool get botlerUpdated => pages.any((p) => p.botlerUpdated);

  Json toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'summary': summary,
    'pinnedAt': pinnedAt,
    'pages': <Json>[for (final p in pages) p.toJson()],
  };

  LibraryNotebook copyWith({
    String? title,
    String? summary,
    String? pinnedAt,
    bool clearPin = false,
    List<LibraryPage>? pages,
  }) => LibraryNotebook(
    id: id,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    pinnedAt: clearPin ? null : (pinnedAt ?? this.pinnedAt),
    pages: pages ?? this.pages,
  );
}

/// The whole library: every notebook but the main one. [offline] says this is the copy kept on the phone, taken at [cachedAt].
class Library {
  const Library({
    this.notebooks = const <LibraryNotebook>[],
    this.offline = false,
    this.cachedAt,
  });

  factory Library.fromOutline(Json answer) => Library(
    notebooks: <LibraryNotebook>[
      for (final n in asJsonList(answer['notebooks']))
        LibraryNotebook.fromJson(n),
    ],
  );

  /// Reads the copy saved on the phone (see [toJson]); the result is marked offline.
  factory Library.fromCache(Json j) => Library(
    notebooks: <LibraryNotebook>[
      for (final n in asJsonList(j['notebooks'])) LibraryNotebook.fromJson(n),
    ],
    offline: true,
    cachedAt: dateOf(j['cachedAt']),
  );

  final List<LibraryNotebook> notebooks;
  final bool offline;
  final DateTime? cachedAt;

  bool get isEmpty => notebooks.isEmpty;

  /// Every page of every notebook.
  Iterable<LibraryPage> get pages sync* {
    for (final n in notebooks) {
      yield* n.pages;
    }
  }

  LibraryNotebook? notebook(String id) {
    for (final n in notebooks) {
      if (n.id == id) return n;
    }
    return null;
  }

  LibraryPage? page(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The pages next to [page] (same notebook, same parent), in order, [page] included.
  List<LibraryPage> siblings(LibraryPage page) => <LibraryPage>[
    for (final p in notebook(page.notebookId)?.pages ?? const <LibraryPage>[])
      if (p.parentPageId == page.parentPageId) p,
  ];

  /// The notebooks the way the library lists them: pinned first (newest pin first), then by title.
  List<LibraryNotebook> get sorted {
    final list = <LibraryNotebook>[...notebooks];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.pinned && b.pinned) {
        final byPin = (b.pinnedAt ?? '').compareTo(a.pinnedAt ?? '');
        if (byPin != 0) return byPin;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  }

  /// The pinned pages of all notebooks, the newest pin first.
  List<LibraryPage> get pinnedPages {
    final list = pages.where((p) => p.pinned).toList()
      ..sort((a, b) => (b.pinnedAt ?? '').compareTo(a.pinnedAt ?? ''));
    return list;
  }

  Json toJson() => <String, Object?>{
    'notebooks': <Json>[for (final n in notebooks) n.toJson()],
    'cachedAt': (cachedAt ?? DateTime.now()).toIso8601String(),
  };

  /// The same library with one page changed by [change]; a library where the page is not found is returned as it is.
  Library withPage(
    String pageId,
    LibraryPage Function(LibraryPage page) change,
  ) {
    return Library(
      notebooks: <LibraryNotebook>[
        for (final n in notebooks)
          n.copyWith(
            pages: <LibraryPage>[
              for (final p in n.pages) p.id == pageId ? change(p) : p,
            ],
          ),
      ],
      offline: offline,
      cachedAt: cachedAt,
    );
  }

  Library withNotebook(
    String notebookId,
    LibraryNotebook Function(LibraryNotebook book) change,
  ) => Library(
    notebooks: <LibraryNotebook>[
      for (final n in notebooks) n.id == notebookId ? change(n) : n,
    ],
    offline: offline,
    cachedAt: cachedAt,
  );

  /// A page moved to another notebook or under another parent, put last there, with its own sub-pages going along. A guess made while
  /// offline: the server's own order replaces it as soon as the move is sent.
  Library withMoved(
    String pageId, {
    String? toNotebookId,
    String? toParentPageId,
    int? position,
  }) {
    final moving = page(pageId);
    if (moving == null) return this;
    final target = toNotebookId ?? moving.notebookId;
    final own = <LibraryPage>[
      for (final p in pages)
        if (p.id == pageId || p.parentPageId == pageId) p,
    ];
    final moved = <LibraryPage>[
      for (final p in own)
        if (p.id == pageId)
          p.copyWith(
            notebookId: target,
            parentPageId: toParentPageId,
            clearParent: toParentPageId == null,
          )
        else
          p.copyWith(notebookId: target),
    ];
    return Library(
      notebooks: <LibraryNotebook>[
        for (final n in notebooks)
          n.copyWith(
            pages: n.id == target
                ? _placed(
                    <LibraryPage>[
                      for (final p in n.pages)
                        if (p.id != pageId && p.parentPageId != pageId) p,
                    ],
                    moved,
                    toParentPageId,
                    position,
                  )
                : <LibraryPage>[
                    for (final p in n.pages)
                      if (p.id != pageId && p.parentPageId != pageId) p,
                  ],
          ),
      ],
      offline: offline,
      cachedAt: cachedAt,
    );
  }

  /// [moved] put last among the pages, or last among the sub-pages of [parent].
  static List<LibraryPage> _placed(
    List<LibraryPage> pages,
    List<LibraryPage> moved,
    String? parent,
    int? position,
  ) {
    if (position != null) {
      final next = <LibraryPage>[
        for (final p in pages)
          if (p.parentPageId == parent) p,
      ];
      if (position >= 0 && position < next.length) {
        final at = pages.indexWhere((p) => p.id == next[position].id);
        return <LibraryPage>[
          ...pages.sublist(0, at),
          ...moved,
          ...pages.sublist(at),
        ];
      }
    }
    if (parent == null) return <LibraryPage>[...pages, ...moved];
    var at = pages.indexWhere((p) => p.id == parent);
    if (at < 0) return <LibraryPage>[...pages, ...moved];
    while (at + 1 < pages.length && pages[at + 1].parentPageId == parent) {
      at++;
    }
    return <LibraryPage>[
      ...pages.sublist(0, at + 1),
      ...moved,
      ...pages.sublist(at + 1),
    ];
  }
}

/// A sub-page as page_get lists it under its parent.
class SubPage {
  const SubPage({required this.id, required this.title, this.chars = 0});

  factory SubPage.fromJson(Json j) => SubPage(
    id: str(j['id']),
    title: str(j['title']),
    chars: intOf(j['chars']),
  );

  final String id;
  final String title;
  final int chars;

  Json toJson() => <String, Object?>{'id': id, 'title': title, 'chars': chars};
}

/// One page with its text, as page_get answers. [offline] says this is the copy kept on the phone, saved at [cachedAt].
class PageDoc {
  const PageDoc({
    required this.id,
    required this.notebookId,
    required this.notebook,
    required this.title,
    required this.text,
    this.parentPageId,
    this.parent,
    this.version = 1,
    this.seenVersion = 0,
    this.pinnedAt,
    this.updatedBy = 'user',
    this.updatedAt,
    this.maxChars = 30000,
    this.subpages = const <SubPage>[],
    this.offline = false,
    this.cachedAt,
  });

  factory PageDoc.fromJson(Json j) => PageDoc(
    id: str(j['id']),
    notebookId: str(j['notebookId']),
    notebook: str(j['notebook']),
    parentPageId: j['parentPageId'] is String
        ? j['parentPageId']! as String
        : null,
    parent: j['parent'] is String ? j['parent']! as String : null,
    title: str(j['title']),
    text: str(j['text']),
    version: intOf(j['version'], 1),
    seenVersion: intOf(j['seenVersion']),
    pinnedAt: j['pinnedAt'] is String ? j['pinnedAt']! as String : null,
    updatedBy: str(j['updatedBy'], 'user'),
    updatedAt: dateOf(j['updatedAt']),
    maxChars: intOf(j['maxChars'], 30000),
    subpages: <SubPage>[
      for (final s in asJsonList(j['subpages'])) SubPage.fromJson(s),
    ],
    offline: boolOf(j['offline']),
    cachedAt: dateOf(j['cachedAt']),
  );

  final String id;
  final String notebookId;
  final String notebook;
  final String? parentPageId;
  final String? parent;
  final String title;
  final String text;
  final int version;

  /// The newest version the person had looked at when the page was read (0 when never).
  final int seenVersion;
  final String? pinnedAt;
  final String updatedBy;
  final DateTime? updatedAt;
  final int maxChars;
  final List<SubPage> subpages;
  final bool offline;
  final DateTime? cachedAt;

  bool get pinned => pinnedAt != null;

  /// 'Notebook > Page' or 'Notebook > Parent > Page', as the reader's breadcrumb lists it.
  List<String> get trail => <String>[notebook, ?parent, title];

  Json toJson() => <String, Object?>{
    'id': id,
    'notebookId': notebookId,
    'notebook': notebook,
    'parentPageId': parentPageId,
    'parent': parent,
    'title': title,
    'text': text,
    'version': version,
    'seenVersion': seenVersion,
    'pinnedAt': pinnedAt,
    'updatedBy': updatedBy,
    'updatedAt': updatedAt?.toIso8601String(),
    'maxChars': maxChars,
    'subpages': <Json>[for (final s in subpages) s.toJson()],
    'cachedAt': (cachedAt ?? DateTime.now()).toIso8601String(),
  };

  /// The same page with another title or pin; [clearPin] takes the pin away.
  PageDoc copyWith({String? title, String? pinnedAt, bool clearPin = false}) =>
      PageDoc(
        id: id,
        notebookId: notebookId,
        notebook: notebook,
        parentPageId: parentPageId,
        parent: parent,
        title: title ?? this.title,
        text: text,
        version: version,
        seenVersion: seenVersion,
        pinnedAt: clearPin ? null : (pinnedAt ?? this.pinnedAt),
        updatedBy: updatedBy,
        updatedAt: updatedAt,
        maxChars: maxChars,
        subpages: subpages,
        offline: offline,
        cachedAt: cachedAt,
      );

  /// This copy marked as the one kept on the phone.
  PageDoc asOffline() => PageDoc(
    id: id,
    notebookId: notebookId,
    notebook: notebook,
    parentPageId: parentPageId,
    parent: parent,
    title: title,
    text: text,
    version: version,
    seenVersion: seenVersion,
    pinnedAt: pinnedAt,
    updatedBy: updatedBy,
    updatedAt: updatedAt,
    maxChars: maxChars,
    subpages: subpages,
    offline: true,
    cachedAt: cachedAt,
  );
}

/// A page the person opened lately, kept on the phone only.
class RecentPage {
  const RecentPage({
    required this.id,
    required this.title,
    required this.notebook,
    required this.at,
  });

  factory RecentPage.fromJson(Json j) => RecentPage(
    id: str(j['id']),
    title: str(j['title']),
    notebook: str(j['notebook']),
    at: dateOf(j['at']) ?? DateTime.now(),
  );

  final String id;
  final String title;
  final String notebook;
  final DateTime at;

  Json toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'notebook': notebook,
    'at': at.toIso8601String(),
  };
}

/// A page that was open and is not on the server any more (deleted by Botler, or by another phone).
class PageGone implements Exception {
  const PageGone(this.pageId);

  final String pageId;

  @override
  String toString() => 'PageGone($pageId)';
}

/// One row of a notebook's page list: a page, how deep it sits, and whether it can be folded.
class TreeRow {
  const TreeRow({
    required this.page,
    required this.depth,
    required this.hasChildren,
    required this.collapsed,
  });

  final LibraryPage page;

  /// 0 for a top-level page, 1 for a sub-page.
  final int depth;
  final bool hasChildren;
  final bool collapsed;
}

// -- FUNCTIONS -- //

/// The rows to draw for a notebook's pages (already in tree order): the sub-pages of a folded page are left out. A sub-page whose parent is
/// not in the list is shown as a top-level page, so nothing is ever hidden by a mismatch.
List<TreeRow> flattenTree(List<LibraryPage> pages, Set<String> collapsed) {
  final ids = <String>{for (final p in pages) p.id};
  final kids = <String, int>{};
  for (final p in pages) {
    final parent = p.parentPageId;
    if (parent != null && ids.contains(parent)) {
      kids[parent] = (kids[parent] ?? 0) + 1;
    }
  }
  final rows = <TreeRow>[];
  for (final p in pages) {
    final parent = p.parentPageId;
    final sub = parent != null && ids.contains(parent);
    if (sub && collapsed.contains(parent)) continue;
    rows.add(
      TreeRow(
        page: p,
        depth: sub ? 1 : 0,
        hasChildren: (kids[p.id] ?? 0) > 0,
        collapsed: collapsed.contains(p.id),
      ),
    );
  }
  return rows;
}
