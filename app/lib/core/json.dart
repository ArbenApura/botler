// SAFE READING OF JSON: THE DECODER GIVES Object?, THESE TURN IT INTO TYPES WITHOUT dynamic AND WITHOUT A CRASH ON A SURPRISE

// -- DEP-MODULES -- //
import 'dart:convert';

// -- TYPES -- //

typedef Json = Map<String, Object?>;

// -- FUNCTIONS -- //

/// The object, or an empty one when the value is not an object.
Json asJson(Object? v) {
  if (v is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final e in v.entries)
        if (e.key is String) e.key! as String: e.value,
    };
  }
  return <String, Object?>{};
}

/// The list of objects, skipping anything that is not one.
List<Json> asJsonList(Object? v) => v is List<Object?>
    ? <Json>[
        for (final e in v)
          if (e is Map<Object?, Object?>) asJson(e),
      ]
    : <Json>[];

List<Object?> asList(Object? v) => v is List<Object?> ? v : <Object?>[];

String str(Object? v, [String fallback = '']) => v is String ? v : fallback;

/// A payday rule's sentence without the name the server puts in front of it (the name is drawn on its own line), and without the bill it
/// saves for at the end (the "Saves for" row under it says so).
String ruleSentence(Json rule) {
  final summary = str(rule['summary']);
  final label = str(rule['label']);
  final bill = str(rule['fundsBillName']);
  var out = label.isNotEmpty && summary.startsWith('$label: ')
      ? summary.substring(label.length + 2)
      : summary;
  final tail = ' It saves for $bill.';
  if (bill.isNotEmpty && out.endsWith(tail)) {
    out = out.substring(0, out.length - tail.length);
  }
  return out;
}

int intOf(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

bool boolOf(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

DateTime? dateOf(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Decodes a JSON text into an object, or an empty one if it is not JSON.
Json decodeJson(String text) {
  try {
    return asJson(jsonDecode(text));
  } on FormatException {
    return <String, Object?>{};
  }
}
