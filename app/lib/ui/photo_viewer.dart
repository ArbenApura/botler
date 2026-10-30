// A FULL SCREEN VIEW OF PHOTOS KEPT ON THE PHONE: PINCH TO ZOOM, DRAG TO MOVE, DOUBLE TAP TO ZOOM IN AND BACK, SWIPE SIDEWAYS FOR THE NEXT PHOTO,
// SWIPE DOWN OR PRESS BACK TO CLOSE. One tap hides or shows the bar. Every colour comes from the tokens.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

// -- MODULES -- //
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

// -- CONSTANTS -- //

/// The most a photo can be zoomed.
const double photoMaxScale = 5;

/// What a double tap zooms to.
const double photoDoubleTapScale = 2.5;

/// A photo is decoded no wider than this, so three full camera pictures never sit in memory at once.
const int photoDecodeWidth = 2048;

/// A swipe down longer than this closes the viewer.
const double _dismissDistance = 110;

// -- FUNCTIONS -- //

/// Opens the viewer over everything (the root navigator) at photo [initial] of [paths].
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<String> paths,
  int initial = 0,
}) {
  if (paths.isEmpty) return Future<void>.value();
  final still = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: still
          ? Duration.zero
          : const Duration(milliseconds: 180),
      reverseTransitionDuration: still
          ? Duration.zero
          : const Duration(milliseconds: 140),
      pageBuilder: (_, _, _) => PhotoViewer(
        paths: paths,
        initial: initial.clamp(0, paths.length - 1),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The matrix that shows the point [at] (in the viewer) [scale] times larger without moving it, kept inside the picture's edges.
Matrix4 zoomAbout(Offset at, double scale, Size size) {
  final tx = (at.dx * (1 - scale)).clamp(size.width * (1 - scale), 0.0);
  final ty = (at.dy * (1 - scale)).clamp(size.height * (1 - scale), 0.0);
  return Matrix4.identity()
    ..translateByDouble(tx, ty, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}

// -- TYPES -- //

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({required this.paths, this.initial = 0, super.key});

  final List<String> paths;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _page = widget.initial;

  /// The photo on screen is zoomed: sideways drags move the picture, not the page.
  final ValueNotifier<bool> _zoomed = ValueNotifier<bool>(false);

  /// The bar is showing.
  final ValueNotifier<bool> _bar = ValueNotifier<bool>(true);

  /// How far the photo has been pulled down to close it.
  final ValueNotifier<double> _pull = ValueNotifier<double>(0);

  // Raw pointers, outside the gesture arena, so the pull works whatever the picture's own gestures claim
  final Set<int> _down = <int>{};
  Offset _moved = Offset.zero;
  bool _pulling = false;

  /// More than one finger has been down since the last time all were up.
  bool _multi = false;

  @override
  void dispose() {
    _pages.dispose();
    _zoomed.dispose();
    _bar.dispose();
    _pull.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    _down.add(e.pointer);
    if (_down.length > 1) {
      // A pinch: the finger left after it is not the start of a pull
      _multi = true;
      _cancelPull();
    }
    _moved = Offset.zero;
  }

  void _onMove(PointerMoveEvent e) {
    if (_down.length != 1 || _zoomed.value || _multi) return;
    _moved += e.delta;
    if (!_pulling) {
      // Mostly downwards, and past the touch slop, before it counts as a pull
      if (_moved.dy > 18 && _moved.dy > _moved.dx.abs() * 1.5) _pulling = true;
    }
    if (_pulling) _pull.value = _moved.dy.clamp(0, 600);
  }

  void _onUp(PointerEvent e) {
    _down.remove(e.pointer);
    if (_down.isNotEmpty) return;
    _multi = false;
    if (_pulling && _pull.value > _dismissDistance) {
      Navigator.of(context).maybePop();
      return;
    }
    _cancelPull();
  }

  void _cancelPull() {
    _pulling = false;
    _pull.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final total = widget.paths.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: c.scrim.withValues(alpha: 0),
        systemNavigationBarColor: c.scrim,
      ),
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: ValueListenableBuilder<double>(
          valueListenable: _pull,
          builder: (context, pull, child) => ColoredBox(
            color: c.scrim.withValues(alpha: (1 - pull / 450).clamp(0.0, 1.0)),
            child: Transform.translate(offset: Offset(0, pull), child: child),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: _zoomed,
                builder: (context, zoomed, _) => ValueListenableBuilder<double>(
                  valueListenable: _pull,
                  builder: (context, pull, _) => PageView.builder(
                    controller: _pages,
                    itemCount: total,
                    // A zoomed photo keeps its drags for moving the picture, and a photo being pulled down does not turn the page
                    physics: zoomed || pull > 0
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: (i) => setState(() {
                      _page = i;
                      _zoomed.value = false;
                    }),
                    itemBuilder: (context, i) => _ZoomPage(
                      path: widget.paths[i],
                      active: i == _page,
                      onZoomed: (z) {
                        if (i == _page) _zoomed.value = z;
                      },
                      onTap: () => _bar.value = !_bar.value,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _bar,
                  builder: (context, shown, child) => ExcludeSemantics(
                    excluding: !shown,
                    child: IgnorePointer(
                      ignoring: !shown,
                      child: AnimatedOpacity(
                        opacity: shown ? 1 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        child: child,
                      ),
                    ),
                  ),
                  // A soft dark band behind the bar so it reads over a white receipt too
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          c.scrim.withValues(alpha: 0.7),
                          c.scrim.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          children: <Widget>[
                            IconButton(
                              tooltip: t.chatPhotoClose,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: Icon(Icons.close, color: c.onScrim),
                            ),
                            const Spacer(),
                            if (total > 1)
                              Semantics(
                                liveRegion: true,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 16,
                                  ),
                                  child: Text(
                                    t.chatPhotoCount(_page + 1, total),
                                    style: TextStyle(
                                      color: c.onScrim,
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One photo that can be zoomed and moved. [active] turns false when another page is in front, which puts the picture back to fit.
class _ZoomPage extends StatefulWidget {
  const _ZoomPage({
    required this.path,
    required this.active,
    required this.onZoomed,
    required this.onTap,
  });

  final String path;
  final bool active;
  final ValueChanged<bool> onZoomed;
  final VoidCallback onTap;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _view = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  final ValueNotifier<bool> _zoomed = ValueNotifier<bool>(false);
  Matrix4Tween? _tween;
  Offset _tapAt = Offset.zero;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _view.addListener(_changed);
    _anim.addListener(() {
      final tween = _tween;
      if (tween != null) _view.value = tween.evaluate(_anim);
    });
  }

  @override
  void didUpdateWidget(_ZoomPage old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _reset();
  }

  @override
  void dispose() {
    _view.removeListener(_changed);
    _view.dispose();
    _anim.dispose();
    _zoomed.dispose();
    super.dispose();
  }

  double get _scale => _view.value.getMaxScaleOnAxis();

  void _changed() {
    final z = _scale > 1.02;
    if (z != _zoomed.value) {
      _zoomed.value = z;
      widget.onZoomed(z);
    }
  }

  void _reset() {
    _anim.stop();
    _view.value = Matrix4.identity();
  }

  /// Moves the picture to [target] over a moment (at once when the phone asks for no animation).
  void _goTo(Matrix4 target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _view.value = target;
      return;
    }
    _tween = Matrix4Tween(begin: _view.value, end: target);
    _anim
      ..reset()
      ..forward();
  }

  void _doubleTap() {
    _goTo(
      _scale > 1.02
          ? Matrix4.identity()
          : zoomAbout(_tapAt, photoDoubleTapScale, _size),
    );
  }

  /// A step of the zoom for someone who cannot pinch (screen reader actions).
  void _step(double factor) {
    final next = (_scale * factor).clamp(1.0, photoMaxScale);
    _goTo(
      next <= 1.02
          ? Matrix4.identity()
          : zoomAbout(_size.center(Offset.zero), next, _size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        return Semantics(
          customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
            CustomSemanticsAction(label: t.chatPhotoZoomIn): () => _step(2),
            CustomSemanticsAction(label: t.chatPhotoZoomOut): () => _step(0.5),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            onDoubleTapDown: (d) => _tapAt = d.localPosition,
            onDoubleTap: _doubleTap,
            child: ValueListenableBuilder<bool>(
              valueListenable: _zoomed,
              builder: (context, zoomed, child) => InteractiveViewer(
                transformationController: _view,
                minScale: 1,
                maxScale: photoMaxScale,
                // Unzoomed, a one finger drag belongs to the page and to closing; pinching still works
                panEnabled: zoomed,
                // A new gesture takes over from a double tap still animating
                onInteractionStart: (_) => _anim.stop(),
                // The builder is always given the child below
                child: child!,
              ),
              child: Center(
                child: Image.file(
                  File(widget.path),
                  fit: BoxFit.contain,
                  width: box.maxWidth,
                  height: box.maxHeight,
                  cacheWidth: (box.maxWidth * dpr * photoMaxScale / 2)
                      .round()
                      .clamp(1, photoDecodeWidth),
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  errorBuilder: (context, _, _) => Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.image_not_supported_outlined,
                          color: c.onScrim,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.chatPhotoMissing,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.onScrim),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
