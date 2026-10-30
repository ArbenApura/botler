// THE [[PAGE]] AND [[NOTEBOOK/PAGE]] LINKS: FOUND IN THE TEXT, IGNORED INSIDE CODE SPANS AND FENCED BLOCKS, WITH THEIR OFFSETS.

// -- DEP-MODULES -- //
import 'package:botler/features/notebooks/page_links.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

void main() {
  test('finds a plain link and a link with a notebook', () {
    const text = 'See [[Wi-Fi]] and [[Home manual/Boiler]] now.';
    final links = parsePageLinks(text);
    expect(links, hasLength(2));
    expect(links[0].page, 'Wi-Fi');
    expect(links[0].notebook, isNull);
    expect(links[1].notebook, 'Home manual');
    expect(links[1].page, 'Boiler');
    // The offsets cut the whole link out of the text
    expect(text.substring(links[0].start, links[0].end), '[[Wi-Fi]]');
    expect(
      text.substring(links[1].start, links[1].end),
      '[[Home manual/Boiler]]',
    );
  });

  test('the first slash splits, so a page title may hold a slash', () {
    final link = parsePageLinks('[[Trips/AC/DC tickets]]').single;
    expect(link.notebook, 'Trips');
    expect(link.page, 'AC/DC tickets');
  });

  test('ignores a link inside a code span', () {
    expect(parsePageLinks('Write `[[Page]]` to link.'), isEmpty);
    expect(parsePageLinks('Write ``a ` [[Page]] b`` to link.'), isEmpty);
    // The span closes before the real link
    expect(parsePageLinks('`x` and [[Real]]').single.page, 'Real');
  });

  test('a backtick that never closes is plain text', () {
    expect(parsePageLinks('a ` b [[Page]]').single.page, 'Page');
  });

  test('ignores links inside fenced code blocks, backtick or tilde', () {
    const text =
        'Before [[A]]\n```\n[[B]]\n```\nMiddle [[C]]\n~~~\n[[D]]\n~~~\nEnd [[E]]';
    expect(parsePageLinks(text).map((l) => l.page), <String>['A', 'C', 'E']);
  });

  test('a fence closes only with the same character and at least as long', () {
    const text = '````\n```\n[[Inside]]\n````\n[[Out]]';
    expect(parsePageLinks(text).map((l) => l.page), <String>['Out']);
  });

  test('empty, nested and one-sided brackets are not links', () {
    expect(parsePageLinks('[[]] [[ ]] [[a[b]]] [Page] [[Open'), isEmpty);
    expect(parsePageLinks('[[/Page]] [[Notebook/]]'), isEmpty);
  });

  test('an escaped bracket is not a link', () {
    expect(
      parsePageLinks(r'\[[Page]] but [[Yes]]').map((l) => l.page),
      <String>['Yes'],
    );
  });

  test('keeps the offsets right across lines', () {
    const text = 'first line\n\nsecond [[Here]]\nthird';
    final link = parsePageLinks(text).single;
    expect(text.substring(link.start, link.end), '[[Here]]');
  });

  test('a link cannot span two lines', () {
    expect(parsePageLinks('[[Two\nlines]]'), isEmpty);
  });
}
