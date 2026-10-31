// FINDING A LOGO ON THE WEB (BTL-20261031-1334): THE ADDRESS GUARD, THE CANDIDATE LIST, THE DOWNLOAD AND THE AUTOMATIC TRIM

// -- DEP-MODULES -- //
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:botler/core/photo_crop.dart';
import 'package:botler/core/web_logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

// -- FUNCTIONS -- //

/// A logo: a red disc on white, [size] pixels square, with a wide plain border.
Uint8List logoPng({int size = 200, bool transparent = false}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(
    image,
    color: transparent
        ? img.ColorRgba8(0, 0, 0, 0)
        : img.ColorRgba8(255, 255, 255, 255),
  );
  img.fillCircle(
    image,
    x: size ~/ 2,
    y: size ~/ 2,
    radius: size ~/ 5,
    color: img.ColorRgba8(220, 20, 20, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Future<List<InternetAddress>> publicHost(String host) async =>
    <InternetAddress>[InternetAddress('93.184.216.34')];

http.Response png(Uint8List bytes) => http.Response.bytes(
  bytes,
  200,
  headers: <String, String>{'content-type': 'image/png'},
);

// -- TESTS -- //

void main() {
  group('the address guard', () {
    test('allows a plain public https address', () {
      expect(urlRefusal(Uri.parse('https://rcbc.com/logo.png')), isNull);
      expect(urlRefusal(Uri.parse('https://rcbc.com:443/logo.png')), isNull);
    });

    test('refuses http, other ports, logins and local names', () {
      for (final u in <String>[
        'http://rcbc.com/logo.png',
        'https://rcbc.com:8443/logo.png',
        'https://user:pw@rcbc.com/logo.png',
        'https://localhost/logo.png',
        'https://bank.internal/logo.png',
        'https://printer.local/logo.png',
        'ftp://rcbc.com/logo.png',
      ]) {
        expect(urlRefusal(Uri.parse(u)), isNotNull, reason: u);
      }
    });

    test('refuses private and loopback addresses written as numbers', () {
      for (final u in <String>[
        'https://127.0.0.1/a.png',
        'https://10.0.0.5/a.png',
        'https://192.168.1.1/a.png',
        'https://172.16.0.1/a.png',
        'https://169.254.169.254/a.png',
        'https://100.64.0.1/a.png',
        'https://[::1]/a.png',
        'https://[fe80::1]/a.png',
        'https://[fd00::1]/a.png',
        'https://[::ffff:127.0.0.1]/a.png',
        'https://[64:ff9b::7f00:1]/a.png',
        'https://[2002:7f00:1::]/a.png',
        'https://[::127.0.0.1]/a.png',
      ]) {
        expect(urlRefusal(Uri.parse(u)), isNotNull, reason: u);
      }
      expect(urlRefusal(Uri.parse('https://93.184.216.34/a.png')), isNull);
      // A public address behind NAT64 (what a phone network with no IPv4 gives for an IPv4-only site) is allowed; a private one behind it is not
      expect(isBlockedAddress(InternetAddress('64:ff9b::5db8:d822')), isFalse);
      expect(isBlockedAddress(InternetAddress('64:ff9b::a00:1')), isTrue);
      expect(isBlockedAddress(InternetAddress('2002:5db8:d822::1')), isFalse);
    });

    test('a name that resolves to a private address is refused', () async {
      Future<List<InternetAddress>> inside(String h) async => <InternetAddress>[
        InternetAddress('10.1.2.3'),
      ];
      Future<List<InternetAddress>> mixed(String h) async => <InternetAddress>[
        InternetAddress('93.184.216.34'),
        InternetAddress('127.0.0.1'),
      ];
      Future<List<InternetAddress>> none(String h) async => <InternetAddress>[];
      Future<List<InternetAddress>> broken(String h) async =>
          throw const SocketException('no such host');
      expect(await hostIsPublic('evil.example', inside), isFalse);
      expect(await hostIsPublic('evil.example', mixed), isFalse);
      expect(await hostIsPublic('evil.example', none), isFalse);
      expect(await hostIsPublic('evil.example', broken), isFalse);
      expect(await hostIsPublic('rcbc.com', publicHost), isTrue);
    });
  });

  group('the download', () {
    test('returns the bytes of a plain answer', () async {
      final client = MockClient((r) async => png(logoPng()));
      final got = await fetchGuarded(
        Uri.parse('https://rcbc.com/a.png'),
        client: client,
        maxBytes: logoMaxBytes,
        resolver: publicHost,
      );
      expect(got, isNotNull);
    });

    test('follows a redirect by hand and checks every hop', () async {
      var hits = 0;
      final client = MockClient((r) async {
        hits++;
        if (r.url.host == 'rcbc.com') {
          return http.Response(
            '',
            302,
            headers: <String, String>{'location': 'https://cdn.rcbc.com/a.png'},
          );
        }
        return png(logoPng());
      });
      final got = await fetchGuarded(
        Uri.parse('https://rcbc.com/a.png'),
        client: client,
        maxBytes: logoMaxBytes,
        resolver: publicHost,
      );
      expect(got, isNotNull);
      expect(hits, 2);
    });

    test('refuses a redirect into the inside, or to http', () async {
      for (final to in <String>[
        'https://127.0.0.1/a.png',
        'http://rcbc.com/a.png',
        'https://10.0.0.1/a.png',
      ]) {
        final client = MockClient(
          (r) async =>
              http.Response('', 302, headers: <String, String>{'location': to}),
        );
        final got = await fetchGuarded(
          Uri.parse('https://rcbc.com/a.png'),
          client: client,
          maxBytes: logoMaxBytes,
          resolver: publicHost,
        );
        expect(got, isNull, reason: to);
      }
    });

    test('gives up after too many redirects', () async {
      final client = MockClient(
        (r) async => http.Response(
          '',
          302,
          headers: <String, String>{'location': 'https://rcbc.com/again'},
        ),
      );
      final got = await fetchGuarded(
        Uri.parse('https://rcbc.com/a.png'),
        client: client,
        maxBytes: logoMaxBytes,
        resolver: publicHost,
      );
      expect(got, isNull);
    });

    test(
      'refuses a picture that is too large, an error answer and a slow host',
      () async {
        final big = MockClient(
          (r) async => http.Response.bytes(Uint8List(logoMaxBytes + 10), 200),
        );
        expect(
          await fetchGuarded(
            Uri.parse('https://rcbc.com/a.png'),
            client: big,
            maxBytes: logoMaxBytes,
            resolver: publicHost,
          ),
          isNull,
        );
        final missing = MockClient((r) async => http.Response('no', 404));
        expect(
          await fetchGuarded(
            Uri.parse('https://rcbc.com/a.png'),
            client: missing,
            maxBytes: logoMaxBytes,
            resolver: publicHost,
          ),
          isNull,
        );
        final slow = MockClient((r) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return png(logoPng());
        });
        expect(
          await fetchGuarded(
            Uri.parse('https://rcbc.com/a.png'),
            client: slow,
            maxBytes: logoMaxBytes,
            resolver: publicHost,
            timeout: const Duration(milliseconds: 100),
          ),
          isNull,
        );
      },
    );
  });

  group('the candidate list', () {
    test('reads icons and the sharing picture from a home page, resolved against it', () {
      const html = '''
<html><head>
<link rel="icon" href="/favicon-32.png">
<link rel="apple-touch-icon" sizes="180x180" href="/touch.png">
<meta property="og:image" content="https://cdn.rcbc.com/share.jpg">
<link rel="stylesheet" href="/site.css">
<link rel="icon" href="data:image/png;base64,AAAA">
</head></html>''';
      final links = iconLinksIn(html, Uri.parse('https://www.rcbc.com/'));
      expect(links.map((u) => u.toString()).toList(), <String>[
        'https://www.rcbc.com/touch.png',
        'https://www.rcbc.com/favicon-32.png',
        'https://cdn.rcbc.com/share.jpg',
      ]);
    });

    test('lists the given addresses, the page icons, then the fixed places, without repeats or http', () {
      final list = logoSources(
        domain: 'rcbc.com',
        urls: <String>[
          'https://upload.wikimedia.org/a.png',
          'http://bad.example/a.png',
        ],
        fromPage: <Uri>[Uri.parse('https://rcbc.com/apple-touch-icon.png')],
      ).map((u) => u.toString()).toList();
      expect(list.first, 'https://upload.wikimedia.org/a.png');
      expect(list, isNot(contains('http://bad.example/a.png')));
      expect(
        list.where((u) => u == 'https://rcbc.com/apple-touch-icon.png'),
        hasLength(1),
      );
      expect(list.any((u) => u.contains('google.com/s2/favicons')), isTrue);
      expect(list.last, 'https://www.rcbc.com/favicon.ico');
      expect(list, contains('https://rcbc.com/favicon.ico'));
      expect(list.any((u) => u.contains('domain=www.rcbc.com')), isTrue);
    });
  });

  group('the automatic trim', () {
    test('finds the logo inside a wide plain border and shows it whole', () {
      final prepared = prepareLogo(logoPng());
      expect(prepared, isNotNull);
      final plan = prepared!.plan;
      expect(plan.fit, CropFit.contain);
      // The disc is 80 of 200 pixels wide: the box is much smaller than the picture and still holds the disc
      expect(plan.width, lessThan(0.6));
      expect(plan.width, greaterThan(0.4));
      expect(plan.x, lessThan(0.3));
      expect(plan.x + plan.width, greaterThan(0.7));
    });

    test('a transparent logo is laid on white, not black', () {
      final prepared = prepareLogo(logoPng(transparent: true));
      expect(prepared, isNotNull);
      expect(prepared!.rgba[0], 255);
      expect(prepared.rgba[1], 255);
      expect(prepared.rgba[2], 255);
    });

    test('a blank, a tiny and a broken picture are not candidates', () {
      final blank = img.Image(width: 100, height: 100);
      img.fill(blank, color: img.ColorRgb8(10, 10, 10));
      expect(prepareLogo(Uint8List.fromList(img.encodePng(blank))), isNull);
      expect(prepareLogo(logoPng(size: 12)), isNull);
      expect(prepareLogo(logoPng(size: 16)), isNotNull);
      expect(prepareLogo(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    });
  });

  group('finding candidates', () {
    test('collects the pictures that load, best first, and leaves out the ones that fail', () async {
      final big = logoPng(size: 256);
      final small = logoPng(size: 64);
      final client = MockClient((r) async {
        final path = r.url.path;
        if (path == '/') {
          return http.Response(
            '<link rel="icon" href="/small.png"><link rel="apple-touch-icon" href="/big.png">',
            200,
          );
        }
        if (path == '/big.png') return png(big);
        if (path == '/small.png') return png(small);
        return http.Response('no', 404);
      });
      final found = await findLogoCandidates(
        domain: 'rcbc.com',
        client: client,
        resolver: publicHost,
      );
      expect(found, isNotEmpty);
      // Large before small, whatever order they were tried in
      expect(found.first.url.path, '/big.png');
      expect(found.first.source.width, 256);
      expect(found.first.source.cut(found.first.plan), isNotNull);
    });

    test(
      'works with a client that holds things an isolate cannot receive',
      () async {
        // The real HTTP client holds open sockets (futures, ports). Anything the picture work captures from this function would fail to send
        final client = _HeavyClient(logoPng(size: 128));
        final found = await findLogoCandidates(
          domain: 'rcbc.com',
          client: client,
          resolver: publicHost,
        );
        expect(found, isNotEmpty);
        client.close();
      },
    );

    test(
      'tries the www name too, for a site that has no address without it',
      () async {
        final asked = <String>[];
        final client = MockClient((r) async {
          asked.add(r.url.host);
          // Only the www name exists
          if (r.url.host == 'www.gotyme.com' && r.url.path == '/favicon.ico') {
            return png(logoPng(size: 64));
          }
          return http.Response('no', 404);
        });
        final found = await findLogoCandidates(
          domain: 'gotyme.com',
          client: client,
          resolver: publicHost,
        );
        expect(found, hasLength(1));
        expect(found.single.url.host, 'www.gotyme.com');
        expect(asked, contains('www.gotyme.com'));
      },
    );

    test(
      'returns an empty list when nothing is found or the host is private',
      () async {
        final nothing = MockClient((r) async => http.Response('no', 404));
        expect(
          await findLogoCandidates(
            domain: 'rcbc.com',
            client: nothing,
            resolver: publicHost,
          ),
          isEmpty,
        );
        final inside = await findLogoCandidates(
          domain: 'rcbc.com',
          client: MockClient((r) async => png(logoPng())),
          resolver: (h) async => <InternetAddress>[InternetAddress('10.0.0.9')],
        );
        expect(inside, isEmpty);
      },
    );

    test('the same picture from two places appears once', () async {
      final same = logoPng(size: 128);
      final client = MockClient(
        (r) async => r.url.path == '/' ? http.Response('', 200) : png(same),
      );
      final found = await findLogoCandidates(
        domain: 'rcbc.com',
        urls: <String>['https://cdn.example.com/a.png'],
        client: client,
        resolver: publicHost,
      );
      expect(found, hasLength(1));
    });
  });
}

/// A client that answers every picture request with the same picture and keeps a pending future and a port, like a real one keeps sockets.
class _HeavyClient extends http.BaseClient {
  _HeavyClient(this._png);

  final Uint8List _png;
  final ReceivePort _port = ReceivePort();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/') {
      return http.StreamedResponse(Stream<List<int>>.value(<int>[]), 404);
    }
    return http.StreamedResponse(Stream<List<int>>.value(_png), 200);
  }

  @override
  void close() {
    _port.close();
    super.close();
  }
}
