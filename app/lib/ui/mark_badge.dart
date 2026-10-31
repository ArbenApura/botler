// THE MARK OF AN ACCOUNT OR A BILL AS A SMALL ROUNDED SQUARE: ITS PICTURE, ITS ICON, OR THE FIRST LETTER OF ITS NAME.
// Colours come from the tokens only; a person's picture is never tinted. It is drawn at the size it is shown (cacheWidth), so a long list stays light.
// The badge itself is not tappable: a screen that makes it tappable wraps it in a 48 dp target.

// -- DEP-MODULES -- //
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/marks.dart';
import '../l10n/l10n.dart';
import '../state/marks.dart';
import '../theme/tokens.dart';

// -- TYPES -- //

class MarkBadge extends ConsumerWidget {
  const MarkBadge({
    required this.name,
    this.mark = const Mark(),
    this.size = 40,
    this.preview,
    this.announce = false,
    super.key,
  });

  /// The name the mark belongs to: its first letter stands in when there is no mark, and it is the spoken label when [announce] is on.
  final String name;

  /// Say "Icon of {name}" aloud. Off by default: in a row or a chip the name sits beside the badge and would be read twice.
  final bool announce;
  final Mark mark;
  final double size;

  /// A picture the phone holds that is not stored yet (shown in the picker before saving).
  final Uint8List? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final radius = BorderRadius.circular(size * 0.3);
    final Widget inner;
    if (preview != null) {
      inner = _Pixels(preview!, size: size);
    } else if (mark.imageId != null) {
      inner = _Picture(
        key: ValueKey<String>('mark.${mark.imageId}'),
        imageId: mark.imageId!,
        size: size,
        fallback: _glyph(c, mark),
      );
    } else {
      inner = _glyph(c, mark);
    }
    final box = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: radius),
        child: ClipRRect(
          borderRadius: radius,
          child: Center(child: inner),
        ),
      ),
    );
    if (!announce) return ExcludeSemantics(child: box);
    return Semantics(
      label: context.t.markSemantic(name),
      image: true,
      excludeSemantics: true,
      child: box,
    );
  }

  /// The icon, or the first letter of the name when there is no icon.
  Widget _glyph(BotlerColors c, Mark m) {
    final data = m.iconData;
    if (data != null) {
      return Icon(data, size: size * 0.55, color: c.accentText);
    }
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Text(
      letter,
      style: TextStyle(
        color: c.accentText,
        fontSize: size * 0.45,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The badge of an account by its id, read from the accounts list the screens share. A one-liner for a screen that has only the id.
class AccountBadge extends ConsumerWidget {
  const AccountBadge({
    required this.accountId,
    required this.name,
    this.size = 40,
    super.key,
  });

  final String accountId;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = ref.watch(
      accountMarksProvider.select((m) => m[accountId] ?? const Mark()),
    );
    return MarkBadge(name: name, mark: mark, size: size);
  }
}

class _Pixels extends StatelessWidget {
  const _Pixels(this.bytes, {required this.size});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: px,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// A stored picture: shown at once when it is already here, otherwise fetched; the letter or icon shows until it arrives.
class _Picture extends ConsumerStatefulWidget {
  const _Picture({
    required this.imageId,
    required this.size,
    required this.fallback,
    super.key,
  });

  final String imageId;
  final double size;
  final Widget fallback;

  @override
  ConsumerState<_Picture> createState() => _PictureState();
}

class _PictureState extends ConsumerState<_Picture> {
  // -- STATES -- //

  Uint8List? _bytes;

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    final images = ref.read(markImagesProvider);
    _bytes = images.peek(widget.imageId);
    if (_bytes == null) _fetch(images);
  }

  // -- FUNCTIONS -- //

  Future<void> _fetch(MarkImages images) async {
    final got = await images.load(widget.imageId);
    if (got != null && mounted) setState(() => _bytes = got);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return bytes == null ? widget.fallback : _Pixels(bytes, size: widget.size);
  }
}
