// FILES A SCRIPT CAN MAKE FOR THE PERSON (BTL-20261031-1334): AN EXCEL SHEET FROM ROWS AND A PDF FROM TEXT. PLAIN FUNCTIONS ON DATA, NO ENGINE AND NO PHONE ACCESS, SO THEY RUN THE SAME IN A TEST.
// The sheet is the smallest valid .xlsx (one sheet, text and numbers, a bold first row, column widths from the content). The PDF is plain text on A4 pages in
// Helvetica, wrapped at a safe width; a character the font cannot show is replaced with "?" (the peso sign is written as PHP).

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// -- MODULES -- //
import 'scratch.dart';

// -- CONSTANTS -- //

const int sheetMaxRows = 20000;
const int sheetMaxColumns = 60;
const int sheetMaxCellChars = 2000;
const int pdfMaxChars = 400000;

/// The widest a line of the PDF is before it wraps, in characters.
const int pdfLineChars = 88;
const int _pdfLinesPerPage = 52;

// -- FUNCTIONS -- //

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Characters XML cannot hold at all are dropped
    .replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]'), '');

String _columnName(int index) {
  var n = index;
  var out = '';
  do {
    out = String.fromCharCode(65 + n % 26) + out;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return out;
}

/// An .xlsx file with one sheet. [rows] is a list of rows; a cell is text, a number, a true or false, or empty. The first row is bold when
/// [header] is on. Throws [ScratchException] for rows that are not a list of lists, or too large.
Uint8List xlsxBytes(
  Object? rows, {
  String sheet = 'Sheet1',
  bool header = true,
}) {
  if (rows is! List<Object?>) {
    throw const ScratchException('rows must be a list of rows.');
  }
  if (rows.length > sheetMaxRows) {
    throw const ScratchException('A sheet has at most 20000 rows.');
  }
  final widths = <int, int>{};
  final body = StringBuffer();
  for (final (r, row) in rows.indexed) {
    if (row is! List<Object?>) {
      throw const ScratchException('Each row must be a list of cells.');
    }
    if (row.length > sheetMaxColumns) {
      throw const ScratchException('A sheet has at most 60 columns.');
    }
    body.write('<row r="${r + 1}">');
    for (final (c, cell) in row.indexed) {
      final ref = '${_columnName(c)}${r + 1}';
      final style = header && r == 0 ? ' s="1"' : '';
      if (cell == null) continue;
      if (cell is num && cell.isFinite) {
        body.write('<c r="$ref"$style><v>$cell</v></c>');
        widths[c] = widths[c] == null || widths[c]! < 10 ? 10 : widths[c]!;
      } else if (cell is bool) {
        body.write('<c r="$ref"$style t="b"><v>${cell ? 1 : 0}</v></c>');
      } else {
        var text = '$cell';
        if (text.length > sheetMaxCellChars) {
          text = text.substring(0, sheetMaxCellChars);
        }
        body.write(
          '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_xml(text)}</t></is></c>',
        );
        final longest = text
            .split('\n')
            .fold<int>(0, (m, l) => l.length > m ? l.length : m);
        if (widths[c] == null || widths[c]! < longest) widths[c] = longest;
      }
    }
    body.write('</row>');
  }
  final cols = StringBuffer();
  if (widths.isNotEmpty) {
    cols.write('<cols>');
    for (final e in widths.entries) {
      final w = (e.value + 2).clamp(8, 60);
      cols.write(
        '<col min="${e.key + 1}" max="${e.key + 1}" width="$w" customWidth="1"/>',
      );
    }
    cols.write('</cols>');
  }
  var name = sheet.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
  if (name.isEmpty) name = 'Sheet1';
  if (name.length > 31) name = name.substring(0, 31);
  const xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  final files = <String, String>{
    '[Content_Types].xml':
        '$xmlHead<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '$xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '$xmlHead<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${_xml(name)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '$xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml':
        '$xmlHead<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml':
        '$xmlHead<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '$cols<sheetData>$body</sheetData></worksheet>',
  };
  final archive = Archive();
  for (final e in files.entries) {
    final data = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, data.length, data));
  }
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}

/// The text as the font can show it: the peso sign as PHP, Latin-1 as it is, anything else as "?".
String _latin(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x20B1) {
      out.write('PHP ');
    } else if (r == 0x20AC) {
      out.write('EUR ');
    } else if (r == 9) {
      out.write('    ');
    } else if (r >= 32 && r < 127 || r >= 160 && r <= 255) {
      out.writeCharCode(r);
    } else if (r == 10) {
      out.write('\n');
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

List<String> _wrap(String text) {
  final lines = <String>[];
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    var line = raw;
    if (line.length <= pdfLineChars) {
      lines.add(line);
      continue;
    }
    while (line.length > pdfLineChars) {
      var cut = line.lastIndexOf(' ', pdfLineChars);
      if (cut < pdfLineChars ~/ 2) cut = pdfLineChars;
      lines.add(line.substring(0, cut).trimRight());
      line = line.substring(cut).trimLeft();
    }
    lines.add(line);
  }
  return lines;
}

String _pdfEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

/// A PDF of plain text on A4 pages, with an optional bold title on the first page.
Uint8List pdfBytes(String text, {String? title}) {
  if (text.length > pdfMaxChars) {
    throw const ScratchException('A PDF holds at most 400000 characters.');
  }
  final lines = _wrap(_latin(text));
  final head = title == null || title.trim().isEmpty
      ? null
      : _latin(title.trim());
  final pages = <List<String>>[];
  for (var i = 0; i < lines.length || pages.isEmpty; i += _pdfLinesPerPage) {
    pages.add(
      lines.isEmpty
          ? <String>[]
          : lines.sublist(
              i,
              i + _pdfLinesPerPage > lines.length
                  ? lines.length
                  : i + _pdfLinesPerPage,
            ),
    );
  }
  // Objects: 1 catalog, 2 pages, 3 Helvetica, 4 Helvetica-Bold, then a page and its stream for each page
  final objects = <String>[];
  final kids = <String>[];
  for (var p = 0; p < pages.length; p++) {
    final pageObj = 5 + p * 2;
    kids.add('$pageObj 0 R');
  }
  objects
    ..add('<< /Type /Catalog /Pages 2 0 R >>')
    ..add('<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>')
    ..add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    )
    ..add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    );
  for (var p = 0; p < pages.length; p++) {
    final content = StringBuffer('BT\n50 790 Td\n');
    if (p == 0 && head != null) {
      content.write('/F2 14 Tf\n(${_pdfEscape(head)}) Tj\n0 -26 Td\n');
    }
    content.write('/F1 10 Tf\n14 TL\n');
    for (final line in pages[p]) {
      content.write('(${_pdfEscape(line)}) Tj\nT*\n');
    }
    content.write('ET\n');
    final stream = content.toString();
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${6 + p * 2} 0 R >>',
      )
      ..add(
        '<< /Length ${latin1.encode(stream).length} >>\nstream\n$stream\nendstream',
      );
  }
  final out = BytesBuilder();
  final offsets = <int>[];
  void add(List<int> b) => out.add(b);
  add(latin1.encode('%PDF-1.4\n'));
  for (final (i, obj) in objects.indexed) {
    offsets.add(out.length);
    add(latin1.encode('${i + 1} 0 obj\n$obj\nendobj\n'));
  }
  final xref = out.length;
  final table = StringBuffer(
    'xref\n0 ${objects.length + 1}\n0000000000 65535 f \n',
  );
  for (final o in offsets) {
    table.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  table.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  add(latin1.encode(table.toString()));
  return out.toBytes();
}
