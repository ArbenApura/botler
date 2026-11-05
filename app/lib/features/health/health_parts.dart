// THE PIECES HEALTH SCREENS SHARE: THE RING, THE ICON TILE, THE BIG LIGHT NUMBER, THE THIN BAR, THE BOTTOM DOCK AND THE CHOICE ROW.

// -- DEP-MODULES -- //
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';

// -- TYPES -- //

/// A round progress ring with anything in its middle. [label] reads the value in words, so a screen reader gets it too.
class HealthRing extends StatelessWidget {
  const HealthRing({
    required this.size,
    required this.percent,
    required this.label,
    required this.child,
    this.stroke = 14,
    this.color,
    super.key,
  });

  final double size;
  final int percent;
  final String label;
  final Widget child;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            percent: percent.clamp(0, 100),
            stroke: stroke,
            color: color ?? c.accent,
            track: c.line,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.percent,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final int percent;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base..color = track);
    if (percent <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * percent / 100,
      false,
      base
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.color != color || old.track != track;
}

/// An icon on a soft rounded square.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {this.size = 40, this.color, this.fill, super.key});

  final IconData icon;
  final double size;
  final Color? color;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill ?? c.accentSoft,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(icon, size: size * 0.55, color: color ?? c.accentText),
    );
  }
}

/// A large light number, in tabular figures.
class BigNumber extends StatelessWidget {
  const BigNumber(this.text, {this.size = 44, this.color, super.key});

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w300,
      height: 1.1,
      letterSpacing: -size * 0.02,
      color: color ?? context.colors.ink,
      fontFeatures: tabular,
    ),
  );
}

/// A thin progress bar. [percent] is held between 0 and 100.
class ThinBar extends StatelessWidget {
  const ThinBar(this.percent, {this.color, this.height = 6, super.key});

  final int percent;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: percent.clamp(0, 100) / 100,
        minHeight: height,
        color: color ?? c.accent,
        backgroundColor: c.line,
      ),
    );
  }
}

/// The soft sage card that holds what a person should notice.
class SoftCard extends StatelessWidget {
  const SoftCard({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.accentSoft,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

/// The bar at the bottom of a screen that holds its one primary action, and sometimes the way to chat.
class BottomDock extends StatelessWidget {
  const BottomDock({
    required this.primary,
    this.showAsk = false,
    this.below,
    super.key,
  });

  final Widget primary;
  final bool showAsk;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: primary),
              if (showAsk) ...<Widget>[
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: context.t.healthAskBotler,
                  constraints: const BoxConstraints(
                    minWidth: minTap + 4,
                    minHeight: minTap + 4,
                  ),
                  onPressed: () => context.go('/'),
                  icon: Icon(Icons.chat_bubble_outline, color: c.accentText),
                ),
              ],
            ],
          ),
          ?below,
        ],
      ),
    );
  }
}

/// A row of choices: one is on, and each is a real button of at least 48 dp.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    required this.choices,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<(T, String)> choices;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final (v, text) in choices)
          ChoiceChip(
            label: Text(text),
            selected: v == value,
            onSelected: (_) => onChanged(v),
            showCheckmark: v == value,
            checkmarkColor: c.accentText,
            selectedColor: c.accentSoft,
            backgroundColor: c.surface,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            labelStyle: TextStyle(
              color: v == value ? c.accentText : c.ink,
              fontWeight: v == value ? FontWeight.w500 : FontWeight.w400,
            ),
            side: BorderSide(color: v == value ? c.accent : c.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
      ],
    );
  }
}

/// A short row for a stat: a title, a line and something at the end.
class StatRow extends StatelessWidget {
  const StatRow({
    required this.icon,
    required this.title,
    required this.line,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String line;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTap),
        child: Row(
          children: <Widget>[
            IconTile(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  Text(line, style: TextStyle(color: c.muted, fontSize: 13)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
