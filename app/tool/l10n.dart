// BUILDS lib/l10n/app_en.arb AND app_fil.arb FROM THE PARTS IN lib/l10n/parts (ONE PAIR OF FILES PER SCREEN GROUP, NAME.en.arb AND NAME.fil.arb),
// AND REFUSES A KEY THAT ONE LANGUAGE HAS AND THE OTHER DOES NOT. Run from app/:  dart run tool/l10n.dart  then  flutter gen-l10n

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

// -- FUNCTIONS -- //

Map<String, Object?> _read(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, Object?>;

/// The keys of a part without the @ metadata.
Set<String> _keys(Map<String, Object?> m) =>
    m.keys.where((k) => !k.startsWith('@') && k != '@@locale').toSet();

void main() {
  final dir = Directory('lib/l10n/parts');
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final en = <String, Object?>{};
  final fil = <String, Object?>{};
  final problems = <String>[];
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.en.arb')) {
      final m = _read(f);
      for (final e in m.entries) {
        if (en.containsKey(e.key))
          problems.add('Duplicate key ${e.key} in $name');
        en[e.key] = e.value;
      }
    } else if (name.endsWith('.fil.arb')) {
      final m = _read(f);
      for (final e in m.entries) {
        // The Filipino file holds the words only: the metadata (placeholders) is the English file's
        if (e.key.startsWith('@')) continue;
        if (fil.containsKey(e.key))
          problems.add('Duplicate key ${e.key} in $name');
        fil[e.key] = e.value;
      }
    }
  }
  final enKeys = _keys(en);
  final filKeys = _keys(fil);
  for (final k in enKeys.difference(filKeys)) {
    problems.add('Missing in Filipino: $k');
  }
  for (final k in filKeys.difference(enKeys)) {
    problems.add('Missing in English: $k');
  }
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  Map<String, Object?> sorted(Map<String, Object?> m, String locale) {
    final keys = m.keys.where((k) => !k.startsWith('@')).toList()..sort();
    final out = <String, Object?>{'@@locale': locale};
    for (final k in keys) {
      out[k] = m[k];
      if (m.containsKey('@$k')) out['@$k'] = m['@$k'];
    }
    return out;
  }

  const encoder = JsonEncoder.withIndent('  ');
  File('lib/l10n/app_en.arb')
      .writeAsStringSync('${encoder.convert(sorted(en, 'en'))}\n');
  File('lib/l10n/app_fil.arb')
      .writeAsStringSync('${encoder.convert(sorted(fil, 'fil'))}\n');
  stdout.writeln('${enKeys.length} keys in English and Filipino.');
}
