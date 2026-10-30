// WHICH LINES OF A PAGE ARE NEW SINCE AN EARLIER VERSION OF IT. PURE, NO NETWORK AND NO WIDGETS.
// A line counts as added when the new text has more copies of it than the old text had (a multiset, so a line moved to another place is not new, and
// a line written twice where it stood once is new once). Blank lines are never added, and trailing spaces and line ends are not part of a line.

// -- FUNCTIONS -- //

String _key(String line) => line.trimRight();

List<String> _lines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

/// The numbers (from 0) of the lines of [current] that [before] does not have.
Set<int> addedLines(String before, String current) {
  final left = <String, int>{};
  for (final l in _lines(before)) {
    final k = _key(l);
    if (k.isNotEmpty) left[k] = (left[k] ?? 0) + 1;
  }
  final added = <int>{};
  final now = _lines(current);
  for (var i = 0; i < now.length; i++) {
    final k = _key(now[i]);
    if (k.isEmpty) continue;
    final have = left[k] ?? 0;
    if (have > 0) {
      left[k] = have - 1;
    } else {
      added.add(i);
    }
  }
  return added;
}

/// True when any line from [first] for [count] lines is in [added].
bool touchesAdded(Set<int> added, int first, int count) {
  if (added.isEmpty) return false;
  for (var i = first; i < first + count; i++) {
    if (added.contains(i)) return true;
  }
  return false;
}
