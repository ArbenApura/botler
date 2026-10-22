// THE LOADING LOOK: QUIET BLOCKS THAT PULSE SOFTLY WHERE THE REAL ROWS WILL BE, SO A SCREEN NEVER JUMPS WHEN ITS DATA ARRIVES.
// One pulse (one controller) drives a whole group of blocks. With animations removed in the phone's settings the blocks stand still.
// Colours come from the tokens only. A group says "Loading" once to a screen reader and hides its blocks.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

// -- TYPES -- //

/// The shapes a loading list can take.
enum SkeletonKind {
  /// Two quiet lines, the height of a list row.
  row,

  /// A card with a title, a large number and a line.
  card,

  /// A list card: two lines on the left, a number on the right (an account, a goal).
  tile,

  /// Three fields and a button.
  form,
}

// -- CONSTANTS -- //

/// One breath of the pulse, in and out.
const Duration skeletonPulse = Duration(milliseconds: 1200);

/// The dimmest the blocks get; they never disappear.
const double _dimmest = 0.6;

/// The height of a list row. Matches a two-line row with its padding, and clears the 48 dp tap size.
const double skeletonRowHeight = 64;

// -- FUNCTIONS -- //

/// The block colour: the line colour a step towards the muted text colour, so it stays visible on the card colour in both modes.
Color _fill(BotlerColors c) => Color.lerp(c.line, c.muted, 0.22) ?? c.line;

// -- SCOPE -- //

/// Hands the group's one pulse to every block below it.
class _PulseScope extends InheritedWidget {
  const _PulseScope({required this.opacity, required super.child});

  final Animation<double> opacity;

  @override
  bool updateShouldNotify(_PulseScope old) => opacity != old.opacity;
}

// -- GROUP -- //

/// Owns the one pulse for the blocks inside it. Stands still when animations are removed, and while its page is not on screen.
class SkeletonGroup extends StatefulWidget {
  const SkeletonGroup({required this.child, super.key});

  final Widget child;

  @override
  State<SkeletonGroup> createState() => _SkeletonGroupState();
}

class _SkeletonGroupState extends State<SkeletonGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: skeletonPulse,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: _dimmest,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  static const Animation<double> _resting = AlwaysStoppedAnimation<double>(0.8);

  bool _standStill = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-read each time the setting changes, so turning animations off stops the pulse at once
    _standStill = MediaQuery.disableAnimationsOf(context);
    if (_standStill) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: context.t.uiLoading,
      child: ExcludeSemantics(
        child: _PulseScope(
          opacity: _standStill ? _resting : _opacity,
          child: widget.child,
        ),
      ),
    );
  }
}

// -- BLOCKS -- //

/// One quiet block in the line colour. Pulses with its group; outside a group it just sits.
class Skeleton extends StatelessWidget {
  const Skeleton({this.width, this.height = 14, this.radius = 8, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _fill(context.colors),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    final scope = context.dependOnInheritedWidgetOfExactType<_PulseScope>();
    if (scope == null) return block;
    return FadeTransition(opacity: scope.opacity, child: block);
  }
}

/// A text-sized block, a share of the width it is given.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({this.widthFactor = 1, this.height = 14, super.key});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Skeleton(height: height),
  );
}

// -- SHAPES -- //

/// A loading list: [count] pieces of one [kind]. It has no padding of its own, so it sits where the loaded content sits.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({this.count = 3, this.kind = SkeletonKind.row, super.key});

  final int count;
  final SkeletonKind kind;

  @override
  Widget build(BuildContext context) {
    return SkeletonGroup(
      child: Column(
        children: <Widget>[
          for (var i = 0; i < count; i++)
            switch (kind) {
              SkeletonKind.row => const _RowShape(),
              SkeletonKind.card => const _CardShape(),
              SkeletonKind.tile => const _TileShape(),
              SkeletonKind.form => const _FormShape(),
            },
        ],
      ),
    );
  }
}

class _RowShape extends StatelessWidget {
  const _RowShape();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: skeletonRowHeight,
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonLine(widthFactor: 0.6),
              SizedBox(height: 8),
              SkeletonLine(widthFactor: 0.35, height: 12),
            ],
          ),
        ),
        SizedBox(width: 16),
        Skeleton(width: 64, height: 16),
      ],
    ),
  );
}

class _CardShape extends StatelessWidget {
  const _CardShape();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 4),
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SkeletonLine(widthFactor: 0.4, height: 12),
            SizedBox(height: 12),
            SkeletonLine(widthFactor: 0.55, height: 28),
            SizedBox(height: 14),
            SkeletonLine(widthFactor: 0.8, height: 12),
          ],
        ),
      ),
    ),
  );
}

class _TileShape extends StatelessWidget {
  const _TileShape();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonLine(widthFactor: 0.5, height: 16),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.35, height: 12),
                ],
              ),
            ),
            SizedBox(width: 16),
            Skeleton(width: 80, height: 20),
          ],
        ),
      ),
    ),
  );
}

class _FormShape extends StatelessWidget {
  const _FormShape();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Skeleton(height: 56, radius: 16),
  );
}
