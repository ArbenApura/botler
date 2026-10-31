// THE MARK OF AN ACCOUNT OR A BILL: A BUILT-IN ICON OR THE PERSON'S OWN SMALL PICTURE, SHOWN BESIDE ITS NAME WHEREVER IT APPEARS.
// The server stores either one (never both) and sends only the icon key and the picture's id; the picture itself is fetched once by id and kept
// (a picture never changes under its id). A row with no mark, or an older server that sends none, simply shows the first letter of its name.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

// -- MODULES -- //
import 'json.dart';
import 'photo_upload.dart';

// -- CONSTANTS -- //

/// The most a stored picture may weigh (the server refuses more), and the side of its square.
const int markMaxBytes = 24000;
const int markEdge = 192;

/// The qualities tried in turn until the picture fits [markMaxBytes].
const List<int> _markQualities = <int>[85, 75, 65, 55, 45, 35];

/// The icons the server accepts (server/src/lib/finance/visual.ts), in the order they are offered.
const List<String> kIconKeys = <String>[
  'bank',
  'wallet',
  'cash',
  'card',
  'piggy',
  'savings',
  'home',
  'rent',
  'bolt',
  'water',
  'wifi',
  'phone',
  'cart',
  'food',
  'fuel',
  'car',
  'bus',
  'health',
  'school',
  'family',
  'gift',
  'travel',
  'shopping',
  'subscription',
  'tv',
  'game',
  'insurance',
  'tax',
  'loan',
  'invest',
  'crypto',
  'work',
  'pet',
  'baby',
  'tools',
  'gym',
  'coffee',
  'heart',
  'star',
  'flag',
];

const Map<String, IconData> _icons = <String, IconData>{
  'bank': Icons.account_balance,
  'wallet': Icons.account_balance_wallet,
  'cash': Icons.payments,
  'card': Icons.credit_card,
  'piggy': Icons.savings,
  'savings': Icons.paid,
  'home': Icons.home,
  'rent': Icons.apartment,
  'bolt': Icons.bolt,
  'water': Icons.water_drop,
  'wifi': Icons.wifi,
  'phone': Icons.smartphone,
  'cart': Icons.shopping_cart,
  'food': Icons.restaurant,
  'fuel': Icons.local_gas_station,
  'car': Icons.directions_car,
  'bus': Icons.directions_bus,
  'health': Icons.medical_services,
  'school': Icons.school,
  'family': Icons.family_restroom,
  'gift': Icons.card_giftcard,
  'travel': Icons.flight,
  'shopping': Icons.shopping_bag,
  'subscription': Icons.autorenew,
  'tv': Icons.tv,
  'game': Icons.sports_esports,
  'insurance': Icons.shield,
  'tax': Icons.receipt_long,
  'loan': Icons.request_quote,
  'invest': Icons.trending_up,
  'crypto': Icons.currency_bitcoin,
  'work': Icons.work,
  'pet': Icons.pets,
  'baby': Icons.child_care,
  'tools': Icons.build,
  'gym': Icons.fitness_center,
  'coffee': Icons.coffee,
  'heart': Icons.favorite,
  'star': Icons.star,
  'flag': Icons.flag,
};

// -- TYPES -- //

/// What a row shows beside its name: an icon key, a picture id, or nothing.
class Mark {
  const Mark({this.icon, this.imageId});

  final String? icon;
  final String? imageId;

  bool get isEmpty => iconData == null && imageId == null;

  /// The glyph of the icon, or null for no icon or a key this app does not know (a newer server).
  IconData? get iconData => icon == null ? null : _icons[icon];

  @override
  bool operator ==(Object other) =>
      other is Mark && other.icon == icon && other.imageId == imageId;

  @override
  int get hashCode => Object.hash(icon, imageId);
}

/// What the person chose in the picker: leave it, an icon, a new picture, or no mark.
enum MarkKind { unchanged, icon, picture, none }

class MarkChoice {
  const MarkChoice.unchanged()
    : kind = MarkKind.unchanged,
      icon = null,
      bytes = null;
  const MarkChoice.icon(String this.icon) : kind = MarkKind.icon, bytes = null;
  const MarkChoice.picture(Uint8List this.bytes)
    : kind = MarkKind.picture,
      icon = null;
  const MarkChoice.none() : kind = MarkKind.none, icon = null, bytes = null;

  final MarkKind kind;
  final String? icon;
  final Uint8List? bytes;

  bool get changed => kind != MarkKind.unchanged;
}

// -- FUNCTIONS -- //

/// The mark of a row (an account, a bill, a calendar item). An older server sends neither key.
Mark markOf(Json? row) {
  final icon = row?['icon'];
  final id = row?['imageId'];
  return Mark(
    icon: icon is String && icon.isNotEmpty ? icon : null,
    imageId: id is String && id.isNotEmpty ? id : null,
  );
}

/// The arguments that make [choice] the mark of a row that has [current] now. Only what changes is sent: setting one clears the other on the
/// server, and removing sends a clear for whatever is there. Empty when nothing changes.
Json markArgs(MarkChoice choice, Mark current) {
  switch (choice.kind) {
    case MarkKind.unchanged:
      return <String, Object?>{};
    case MarkKind.icon:
      return <String, Object?>{'icon': choice.icon};
    case MarkKind.picture:
      return <String, Object?>{'imageData': base64Encode(choice.bytes!)};
    case MarkKind.none:
      return <String, Object?>{
        if (current.icon != null) 'icon': null,
        if (current.imageId != null) 'clearImage': true,
      };
  }
}

/// A square JPEG of [markEdge] pixels (the middle of the picture) under [markMaxBytes], or null when the bytes are not a picture this phone can
/// open or stay too large at the smallest try. Runs in the calling isolate; [prepareMarkPicture] puts it in another.
Uint8List? encodeMarkPicture(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) return null;
    final info = decoder.startDecode(bytes);
    if (info == null || info.width * info.height > uploadMaxPixels) return null;
    final decoded = decoder.decode(bytes);
    if (decoded == null) return null;
    final upright = img.bakeOrientation(decoded)..exif.clear();
    final side = upright.width < upright.height
        ? upright.width
        : upright.height;
    final square = img.copyCrop(
      upright,
      x: (upright.width - side) ~/ 2,
      y: (upright.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final edge = side < markEdge ? side : markEdge;
    final small = edge == side
        ? square
        : img.copyResize(
            square,
            width: edge,
            height: edge,
            interpolation: img.Interpolation.average,
          );
    for (final quality in _markQualities) {
      final out = img.encodeJpg(small, quality: quality);
      if (out.length <= markMaxBytes) return out;
    }
    return null;
  } on Object {
    // A file that is cut short is not a picture it can use
    return null;
  }
}

Uint8List? _fromFile(String path) =>
    encodeMarkPicture(File(path).readAsBytesSync());

/// Reads the file at [path] and makes its mark picture, off the main isolate. Null when it cannot be made.
Future<Uint8List?> prepareMarkPicture(String path) async {
  try {
    return await Isolate.run(() => _fromFile(path));
  } on Object {
    return null;
  }
}

/// The mark a bill shows: its own, otherwise the mark of the account it is paid from, otherwise none.
Mark billMarkOf(Json? bill, Map<String, Mark> accounts) {
  final own = markOf(bill);
  if (!own.isEmpty) return own;
  return accounts[str(bill?['accountId'])] ?? const Mark();
}
