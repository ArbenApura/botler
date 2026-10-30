// THE PICTURES IN THE CHAT: THE STRIP OF PHOTOS CHOSEN FOR THE NEXT MESSAGE, AND THE GRID UNDER A SENT MESSAGE. TAPPING ONE OPENS THE VIEWER.
// The pictures are files on this phone only. A tile whose file is gone shows a quiet placeholder, never an error.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/photo_viewer.dart';

// -- CONSTANTS -- //

/// The side of a tile in the strip.
const double stripTile = 72;

/// Room above and to the right of a tile for its remove button, which is a 48 dp target centred on the tile's corner.
const double _badgeRoom = 12;

/// The widest a single photo is drawn in a sent message.
const double _singleWidth = 240;

/// The gap between tiles of a sent message.
const double _gap = 6;

// -- TYPES -- //

/// One photo in the strip: where its copy is, how many characters were read from it, or null while it is still being read.
class StripPhoto {
  const StripPhoto(this.path, this.chars);

  final String path;
  final int? chars;
}

/// The picture at [path], cut to the size it is drawn at. A file that is gone shows a quiet placeholder tile.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({required this.path, required this.width, super.key});

  final String path;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      // A wide photo cut to a square is shown larger than its width alone suggests, so it is decoded a little larger
      cacheWidth: (width * dpr * 1.5).round().clamp(1, 1024),
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => ColoredBox(
        color: c.chip,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: c.muted,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// The photos chosen for the next message, in a row that scrolls sideways. Its height never changes with what is in it.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({required this.photos, required this.onRemove, super.key});

  final List<StripPhoto> photos;
  final void Function(int index) onRemove;

  /// The height the strip takes: the tile, the room for the remove buttons, and one line of caption that grows with the text size.
  static double heightFor(BuildContext context) =>
      _badgeRoom +
      stripTile +
      4 +
      MediaQuery.textScalerOf(context).scale(12) * 1.3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final paths = <String>[for (final p in photos) p.path];
    return SizedBox(
      height: heightFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final p = photos[i];
          final reading = p.chars == null;
          return SizedBox(
            key: ValueKey<String>('photo-${p.path}'),
            width: stripTile + _badgeRoom,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: stripTile,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Semantics(
                        button: true,
                        image: true,
                        label: reading
                            ? t.chatPhotoTileReading(i + 1)
                            : t.chatPhotoOpen(i + 1, photos.length),
                        child: GestureDetector(
                          onTap: () => showPhotoViewer(
                            context,
                            paths: paths,
                            initial: i,
                          ),
                          child: Container(
                            width: stripTile,
                            height: stripTile,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.line),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  PhotoThumb(path: p.path, width: stripTile),
                                  if (reading)
                                    ColoredBox(
                                      color: c.scrim.withValues(alpha: 0.5),
                                      child: Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: c.onScrim,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // The number of characters read, short enough for one line at any text size
                      ExcludeSemantics(
                        child: Text(
                          reading ? '…' : '${p.chars}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.muted,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // A 48 dp target around the small round button near the tile's top right corner; it takes that part of the tile's own tap
                Positioned(
                  top: 0,
                  left: stripTile - 36,
                  width: 48,
                  height: 48,
                  child: Semantics(
                    button: true,
                    label: t.chatPhotoRemove(i + 1),
                    child: InkResponse(
                      radius: 24,
                      onTap: () => onRemove(i),
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.line),
                          ),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Icon(Icons.close, size: 16, color: c.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The photos under a sent message: one wide picture, or two columns of squares. Tiles have fixed shapes so the list never jumps as pictures load.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({required this.paths, super.key});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth.isFinite ? box.maxWidth : _singleWidth;
        final single = paths.length == 1;
        final width = single
            ? (room < _singleWidth ? room : _singleWidth)
            : room;
        final tile = single ? width : (width - _gap) / 2;
        Widget one(int i) => Semantics(
          button: true,
          image: true,
          label: t.chatPhotoOpen(i + 1, paths.length),
          child: GestureDetector(
            onTap: () => showPhotoViewer(context, paths: paths, initial: i),
            child: Container(
              width: tile,
              height: single ? tile * 3 / 4 : tile,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: PhotoThumb(path: paths[i], width: tile),
              ),
            ),
          ),
        );
        return SizedBox(
          width: width,
          child: Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: <Widget>[for (var i = 0; i < paths.length; i++) one(i)],
          ),
        );
      },
    );
  }
}
