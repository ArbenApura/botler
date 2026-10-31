// FINDING A LOGO ON THE WEB FOR AN ACCOUNT OR BILL (BTL-20261031-1334): THE PHONE BUILDS THE CANDIDATE LIST, DOWNLOADS EACH ONE BEHIND ITS OWN ADDRESS GUARD,
// TRIMS PLAIN BORDERS AND FITS IT TO A SQUARE. The server never fetches a picture: the card only carries a domain and a few https addresses.
// The guard: https only, the standard port, no login in the address, no local name, and the host must resolve to public addresses only (checked again
// at every redirect, which is followed by hand, at most three times). A download is cut at 3 MB and 8 seconds and must decode as a picture.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// -- MODULES -- //
import 'photo_crop.dart';

// -- CONSTANTS -- //

const int logoMaxBytes = 3000000;
const int logoMaxPageBytes = 300000;
const Duration logoTimeout = Duration(seconds: 8);
const int logoMaxRedirects = 3;
const int logoMaxCandidates = 6;

/// A picture with a side shorter than this is too small to be a usable mark.
const int logoMinEdge = 16;

/// A picture this large (its shorter side) is preferred over a smaller one.
const int logoGoodEdge = 96;

/// What the pictures are asked with: many sites turn away an unknown agent.
const String _agent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36 Botler';

/// The most pictures tried for one request, and how many are downloaded at the same time.
const int _maxTried = 14;
const int _parallel = 2;

/// A logo with more pixels than this is not opened (decoded it is four bytes a pixel, and several are open at once).
const int logoMaxPixels = 4000000;

/// The longest side kept for the working copy.
const int _logoWorkingEdge = 1024;

/// How different a pixel must be from the border colour (sum of the three channels) to count as part of the logo.
const int _inkThreshold = 48;

/// Breathing room around the trimmed logo, as a share of its longer side.
const double _trimPad = 0.08;

// -- TYPES -- //

/// Turns a host name into addresses. A test replaces it; the phone uses the system lookup.
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

/// One picture that could be the logo: where it came from, a working copy to cut from, and the box chosen for it automatically.
class WebLogoCandidate {
  const WebLogoCandidate({
    required this.url,
    required this.source,
    required this.plan,
  });

  final Uri url;
  final CropSource source;
  final CropPlan plan;
}

// -- FUNCTIONS -- //

Future<List<InternetAddress>> _systemLookup(String host) =>
    InternetAddress.lookup(host);

bool _blockedV4(List<int> b) {
  final a = b[0];
  final c = b[1];
  return a == 0 ||
      a == 10 ||
      a == 127 ||
      a >= 224 ||
      (a == 100 && c >= 64 && c <= 127) ||
      (a == 169 && c == 254) ||
      (a == 172 && c >= 16 && c <= 31) ||
      (a == 192 && c == 168) ||
      (a == 192 && c == 0 && b[2] == 0) ||
      (a == 198 && (c == 18 || c == 19));
}

/// True when the address is one this phone must never fetch from: loopback, private, link-local, carrier NAT, multicast, unspecified.
bool isBlockedAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 4) return _blockedV4(b);
  if (b.length != 16) return true;
  final zeros10 = b.sublist(0, 10).every((x) => x == 0);
  // An IPv4 address inside an IPv6 one is judged as IPv4
  if (zeros10 && b[10] == 0xff && b[11] == 0xff)
    return _blockedV4(b.sublist(12));
  // IPv4 inside an IPv6 address by other routes: the old compatible form ::a.b.c.d, NAT64 64:ff9b::/96 and 6to4 2002::/16
  if (zeros10 && b[10] == 0 && b[11] == 0 && b.any((x) => x != 0)) {
    return b.sublist(0, 15).every((x) => x == 0) && b[15] == 1
        ? true
        : _blockedV4(b.sublist(12));
  }
  // NAT64 (64:ff9b::/96, what a phone network that has no IPv4 gives for an IPv4-only site) carries the real address in its last four bytes
  if (b[0] == 0x00 &&
      b[1] == 0x64 &&
      b[2] == 0xff &&
      b[3] == 0x9b &&
      b.sublist(4, 12).every((x) => x == 0)) {
    return _blockedV4(b.sublist(12));
  }
  // 6to4 (2002::/16) carries it in bytes 2 to 5
  if (b[0] == 0x20 && b[1] == 0x02) return _blockedV4(b.sublist(2, 6));
  if (b.every((x) => x == 0)) return true;
  if (b.sublist(0, 15).every((x) => x == 0) && b[15] == 1) return true;
  if ((b[0] & 0xfe) == 0xfc) return true;
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true;
  if (b[0] == 0xff) return true;
  return false;
}

final RegExp _localName = RegExp(
  r'^(localhost|.+\.(localhost|local|internal|lan|home|corp))$',
  caseSensitive: false,
);

/// Why an address must not be fetched, or null when it may be. Checks the text only; [hostIsPublic] checks what the name resolves to.
String? urlRefusal(Uri u) {
  if (u.scheme != 'https') return 'Only https addresses are fetched.';
  if (u.userInfo.isNotEmpty) return 'Addresses with a login are not fetched.';
  if (u.hasPort && u.port != 443) return 'Only the standard port is used.';
  final host = u.host.replaceAll(RegExp(r'\.+$'), '');
  if (host.isEmpty) return 'The address has no host.';
  if (_localName.hasMatch(host)) return 'That address is private.';
  final ip = InternetAddress.tryParse(host);
  if (ip != null && isBlockedAddress(ip)) return 'That address is private.';
  return null;
}

/// True when every address the host resolves to is public. A name that does not resolve is not public.
Future<bool> hostIsPublic(String host, HostResolver resolve) async {
  final bare = host.replaceAll(RegExp(r'\.+$'), '');
  final literal = InternetAddress.tryParse(bare);
  if (literal != null) return !isBlockedAddress(literal);
  try {
    final found = await resolve(bare);
    return found.isNotEmpty && !found.any(isBlockedAddress);
  } on Object {
    return false;
  }
}

/// The bytes at [start], or null: the address and every redirect target pass the guard, the answer is a plain 200 and fits [maxBytes].
Future<Uint8List?> fetchGuarded(
  Uri start, {
  required http.Client client,
  required int maxBytes,
  String accept = 'image/*,*/*;q=0.5',
  HostResolver resolver = _systemLookup,
  Duration timeout = logoTimeout,
}) async {
  try {
    return await _fetch(
      start,
      client,
      maxBytes,
      accept,
      resolver,
    ).timeout(timeout);
  } on Object {
    return null;
  }
}

Future<Uint8List?> _fetch(
  Uri start,
  http.Client client,
  int maxBytes,
  String accept,
  HostResolver resolver,
) async {
  var url = start;
  for (var hop = 0; hop <= logoMaxRedirects; hop++) {
    if (urlRefusal(url) != null) return null;
    if (!await hostIsPublic(url.host, resolver)) return null;
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers['accept'] = accept
      ..headers['user-agent'] = _agent;
    final response = await client.send(request);
    if (<int>{301, 302, 303, 307, 308}.contains(response.statusCode)) {
      final where = response.headers['location'];
      await response.stream.drain<void>();
      if (where == null || where.isEmpty) return null;
      url = url.resolve(where);
      continue;
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      return null;
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      await response.stream.drain<void>();
      return null;
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      out.add(chunk);
      if (out.length > maxBytes) return null;
    }
    return out.takeBytes();
  }
  return null;
}

final RegExp _tag = RegExp(r'<(link|meta)\b[^>]*>', caseSensitive: false);
final RegExp _attr = RegExp(
  r'''([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);

/// The icon and logo addresses a home page names: apple-touch-icon first, then the other icons, then the sharing picture. Resolved against [base].
List<Uri> iconLinksIn(String html, Uri base) {
  final touch = <Uri>[];
  final icons = <Uri>[];
  final shared = <Uri>[];
  for (final m in _tag.allMatches(html)) {
    final tag = m.group(0) ?? '';
    final attrs = <String, String>{
      for (final a in _attr.allMatches(tag))
        (a.group(1) ?? '').toLowerCase(): a.group(2) ?? a.group(3) ?? '',
    };
    final isLink = tag.toLowerCase().startsWith('<link');
    final target = isLink ? attrs['href'] : attrs['content'];
    if (target == null || target.isEmpty || target.startsWith('data:'))
      continue;
    final uri = base.resolve(target);
    if (isLink) {
      final rel = (attrs['rel'] ?? '').toLowerCase();
      if (rel.contains('apple-touch-icon')) {
        touch.add(uri);
      } else if (rel.contains('icon')) {
        icons.add(uri);
      }
    } else {
      final key = (attrs['property'] ?? attrs['name'] ?? '').toLowerCase();
      if (key == 'og:image' || key == 'og:logo') shared.add(uri);
    }
  }
  return <Uri>[...touch, ...icons, ...shared];
}

/// The names a site answers to: the domain as given and the same with www (or without it).
List<String> siteHosts(String domain) {
  final d = domain.trim().toLowerCase();
  return d.startsWith('www.')
      ? <String>[d, d.substring(4)]
      : <String>[d, 'www.$d'];
}

/// The addresses to try for a request, best guess first and without repeats: the addresses the assistant found, the pictures the home page
/// names, then fixed places (the site's own touch icon and favicon, two public favicon services).
List<Uri> logoSources({
  String? domain,
  List<String> urls = const <String>[],
  List<Uri> fromPage = const <Uri>[],
}) {
  final out = <Uri>[];
  final seen = <String>{};
  void add(Uri? u) {
    if (u == null || u.scheme != 'https') return;
    if (seen.add(u.toString())) out.add(u);
  }

  urls.map(Uri.tryParse).forEach(add);
  fromPage.forEach(add);
  final d = domain?.trim().toLowerCase();
  if (d != null && d.isNotEmpty) {
    // Some organisations have no address without www (and some only without it), so both are tried
    final hosts = siteHosts(d);
    for (final h in hosts) {
      add(Uri.tryParse('https://$h/apple-touch-icon.png'));
    }
    for (final h in hosts) {
      add(
        Uri.https('www.google.com', '/s2/favicons', <String, String>{
          'domain': h,
          'sz': '256',
        }),
      );
    }
    add(Uri.tryParse('https://icons.duckduckgo.com/ip3/$d.ico'));
    for (final h in hosts) {
      add(Uri.tryParse('https://$h/favicon.ico'));
    }
  }
  return out.take(_maxTried).toList();
}

/// A picture made ready off the main isolate: flattened on white, shrunk if large, with the box that trims its plain border.
typedef PreparedLogo = ({int width, int height, Uint8List rgba, CropPlan plan});

/// Decodes [bytes], lays any transparency on white, and finds the box around the logo itself. Null when it is not a usable picture
/// (unreadable, too many pixels, too small, or blank).
PreparedLogo? prepareLogo(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) return null;
    final info = decoder.startDecode(bytes);
    if (info == null || info.width * info.height > logoMaxPixels) return null;
    final decoded = decoder.decode(bytes);
    if (decoded == null) return null;
    // A picture that already has an alpha channel keeps it (convert would make it opaque); it is laid on white below
    var image = decoded.numChannels == 4 && decoded.format == img.Format.uint8
        ? decoded
        : decoded.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
    final shortest = image.width < image.height ? image.width : image.height;
    if (shortest < logoMinEdge) return null;
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > _logoWorkingEdge) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: _logoWorkingEdge,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: _logoWorkingEdge,
              interpolation: img.Interpolation.average,
            );
    }
    _flattenOnWhite(image);
    final plan = trimPlan(image);
    if (plan == null) return null;
    return (
      width: image.width,
      height: image.height,
      rgba: image.getBytes(order: img.ChannelOrder.rgba),
      plan: plan,
    );
  } on Object {
    return null;
  }
}

/// Lays every partly transparent pixel on white and makes it opaque, so a transparent logo is not shown on black.
void _flattenOnWhite(img.Image image) {
  for (final p in image) {
    final a = p.a.toInt();
    if (a >= 255) continue;
    final k = a / 255;
    p
      ..r = (p.r * k + 255 * (1 - k)).round()
      ..g = (p.g * k + 255 * (1 - k)).round()
      ..b = (p.b * k + 255 * (1 - k)).round()
      ..a = 255;
  }
}

/// The box around everything that differs from the border colour (the average of the four corners), with a little room, kept to the picture
/// and shown whole ("contain"). Null when the picture is one plain colour. A logo that fills its picture keeps the whole picture.
CropPlan? trimPlan(img.Image image) {
  final w = image.width;
  final h = image.height;
  final corners = <img.Pixel>[
    image.getPixel(0, 0),
    image.getPixel(w - 1, 0),
    image.getPixel(0, h - 1),
    image.getPixel(w - 1, h - 1),
  ];
  final bg = <int>[
    for (var c = 0; c < 3; c++)
      (corners.map((p) => p[c].toInt()).reduce((a, b) => a + b) / 4).round(),
  ];
  var minX = w;
  var minY = h;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      final d =
          (p.r.toInt() - bg[0]).abs() +
          (p.g.toInt() - bg[1]).abs() +
          (p.b.toInt() - bg[2]).abs();
      if (d <= _inkThreshold) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  final bw = maxX - minX + 1;
  final bh = maxY - minY + 1;
  final pad = ((bw > bh ? bw : bh) * _trimPad).round() + 1;
  final left = (minX - pad).clamp(0, w - 1);
  final top = (minY - pad).clamp(0, h - 1);
  final right = (maxX + pad).clamp(0, w - 1);
  final bottom = (maxY + pad).clamp(0, h - 1);
  return CropPlan(
    x: left / w,
    y: top / h,
    width: (right - left + 1) / w,
    height: (bottom - top + 1) / h,
    fit: CropFit.contain,
  );
}

/// Prepares a picture in another isolate. A top-level function, so the closure it sends holds the bytes only: a closure made inside
/// [findLogoCandidates] would carry the HTTP client with it, which holds open sockets and cannot be sent (the card then showed "no logo").
Future<PreparedLogo?> _prepareOffThread(Uint8List bytes) =>
    Isolate.run(() => prepareLogo(bytes));

/// Every usable logo for the request, best first (large before small, then in the order the sources were tried). Never throws: a source that
/// is refused, slow or not a picture is left out. An empty list means nothing was found.
Future<List<WebLogoCandidate>> findLogoCandidates({
  String? domain,
  List<String> urls = const <String>[],
  required http.Client client,
  HostResolver resolver = _systemLookup,
  int max = logoMaxCandidates,
  Duration timeout = logoTimeout,
}) async {
  var fromPage = const <Uri>[];
  final d = domain?.trim().toLowerCase();
  if (d != null && d.isNotEmpty) {
    // Both names at once; the first page that answers names the icons (its own address is the base for relative links)
    final homes = siteHosts(d).map((h) => Uri.https(h, '/')).toList();
    final pages = await Future.wait(
      homes.map(
        (home) => fetchGuarded(
          home,
          client: client,
          maxBytes: logoMaxPageBytes,
          accept: 'text/html,*/*;q=0.5',
          resolver: resolver,
          timeout: timeout,
        ),
      ),
    );
    final links = <Uri>[];
    for (final (i, page) in pages.indexed) {
      if (page != null) {
        links.addAll(iconLinksIn(String.fromCharCodes(page), homes[i]));
      }
    }
    fromPage = links;
  }
  final sources = logoSources(domain: d, urls: urls, fromPage: fromPage);
  final found = <({int order, Uri url, PreparedLogo logo})>[];
  final seen = <int>{};
  for (var i = 0; i < sources.length; i += _parallel) {
    final batch = sources.skip(i).take(_parallel).toList();
    final results = await Future.wait(
      batch.map((url) async {
        final bytes = await fetchGuarded(
          url,
          client: client,
          maxBytes: logoMaxBytes,
          resolver: resolver,
          timeout: timeout,
        );
        if (bytes == null) return null;
        final logo = await _prepareOffThread(bytes);
        return logo == null ? null : (url: url, logo: logo);
      }),
    );
    for (final (j, r) in results.indexed) {
      if (r == null) continue;
      // The same picture from two places (the touch icon and the page's own link) is shown once
      if (!seen.add(Object.hashAll(r.logo.rgba))) continue;
      found.add((order: i + j, url: r.url, logo: r.logo));
    }
  }
  bool good(PreparedLogo l) =>
      (l.width < l.height ? l.width : l.height) >= logoGoodEdge;
  found.sort((a, b) {
    final ga = good(a.logo) ? 0 : 1;
    final gb = good(b.logo) ? 0 : 1;
    return ga != gb ? ga - gb : a.order - b.order;
  });
  return <WebLogoCandidate>[
    for (final f in found.take(max))
      WebLogoCandidate(
        url: f.url,
        source: cropSourceFromRaw(f.logo.width, f.logo.height, f.logo.rgba),
        plan: f.logo.plan,
      ),
  ];
}
