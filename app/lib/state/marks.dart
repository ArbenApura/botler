// THE PICTURES OF ACCOUNTS AND BILLS, FETCHED ONCE BY ID AND KEPT IN MEMORY, AND THE MARK OF EVERY ACCOUNT BY ITS ID.
// A picture never changes under its id (a new picture is a new id), so nothing is ever refreshed. Two rows that ask for the same id at the same time
// share one request. The cache lives with the signed-in client: signing out drops it, so the next person on the phone never sees these pictures.

// -- DEP-MODULES -- //
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/json.dart';
import '../core/marks.dart';
import 'providers.dart';

// -- CONSTANTS -- //

/// How many pictures are kept; the oldest is dropped past this (each is under 24 KB).
const int _keep = 120;

// -- TYPES -- //

typedef PictureFetch = Future<Json> Function(String imageId);

class MarkImages {
  MarkImages(this._fetch);

  final PictureFetch _fetch;
  final LinkedHashMap<String, Uint8List> _done =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _flight =
      <String, Future<Uint8List?>>{};

  /// The picture if it is already here.
  Uint8List? peek(String imageId) => _done[imageId];

  /// The picture bytes, fetched at most once at a time. Null when the server cannot be reached or has no such picture; a later call tries again.
  Future<Uint8List?> load(String imageId) {
    final have = _done[imageId];
    if (have != null) return Future<Uint8List?>.value(have);
    return _flight[imageId] ??= _get(imageId).whenComplete(() {
      _flight.remove(imageId);
    });
  }

  Future<Uint8List?> _get(String imageId) async {
    try {
      final answer = await _fetch(imageId);
      final data = str(answer['data']);
      if (data.isEmpty) return null;
      final bytes = base64Decode(data);
      _done[imageId] = bytes;
      if (_done.length > _keep) _done.remove(_done.keys.first);
      return bytes;
    } on ApiException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

// -- PROVIDERS -- //

final Provider<MarkImages> markImagesProvider = Provider<MarkImages>((ref) {
  // One cache per signed-in person: a sign-out or another sign-in builds a fresh one, and a fetch still in flight fills the old one
  ref.watch(sessionProvider.select((s) => s.value?.email));
  final api = ref.watch(apiProvider);
  return MarkImages(
    (id) => api.verbJson('picture_get', <String, Object?>{'imageId': id}),
  );
});

/// The mark of each account by its id, from the accounts list the screens already share. Empty until that list is here.
final Provider<Map<String, Mark>> accountMarksProvider =
    Provider<Map<String, Mark>>((ref) {
      final list = ref.watch(balancesProvider).value ?? const <Json>[];
      return <String, Mark>{for (final a in list) str(a['id']): markOf(a)};
    });
