// THE SMALL PICTURES OF HEALTH, DRAWN WITH TOKEN COLOURS: THE WEIGHT LINE, ITS TINY VERSION FOR THE HOME TILE, THE BARS AND THE NIGHTS OF SLEEP.

// -- DEP-MODULES -- //
import 'dart:math' as math;

import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../theme/tokens.dart';

// -- TYPES -- //

/// The trend as a line with a soft fill, and the real weigh-ins as faint dots behind it. Two or more points draw it.
class WeightChart extends StatelessWidget {
  const WeightChart({
    required this.trend,
    required this.scale,
    required this.label,
    this.height = 190,
    super.key,
  });

  final List<int> trend;
  final List<int> scale;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      image: true,
      label: label,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            trend: trend,
            scale: scale,
            line: c.accent,
            dot: c.muted,
            grid: c.line,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.trend,
    required this.scale,
    required this.line,
    required this.dot,
    required this.grid,
  });

  final List<int> trend;
  final List<int> scale;
  final Color line;
  final Color dot;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (trend.length < 2) return;
    final all = <int>[...trend, ...scale];
    final low = all.reduce(math.min);
    final high = all.reduce(math.max);
    final span = math.max(high - low, 400);
    const pad = 10.0;
    double x(int i) => pad + (size.width - 2 * pad) * i / (trend.length - 1);
    double y(int v) =>
        pad + (size.height - 2 * pad) * (1 - (v - low) / span.toDouble());
    final rule = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final part in <double>[0, 0.5, 1]) {
      final at = pad + (size.height - 2 * pad) * part;
      canvas.drawLine(Offset(0, at), Offset(size.width, at), rule);
    }
    final dots = Paint()..color = dot.withValues(alpha: 0.45);
    for (var i = 0; i < scale.length && i < trend.length; i++) {
      canvas.drawCircle(Offset(x(i), y(scale[i])), 2.5, dots);
    }
    final path = Path()..moveTo(x(0), y(trend.first));
    for (var i = 1; i < trend.length; i++) {
      path.lineTo(x(i), y(trend[i]));
    }
    final fill = Path.from(path)
      ..lineTo(x(trend.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas
      ..drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              line.withValues(alpha: 0.24),
              line.withValues(alpha: 0),
            ],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawCircle(
        Offset(x(trend.length - 1), y(trend.last)),
        5,
        Paint()..color = line,
      );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.trend != trend || old.line != line || old.scale != scale;
}

/// Seven small bars: the last one in the full accent.
class MiniBars extends StatelessWidget {
  const MiniBars({required this.values, required this.label, super.key});

  final List<int> values;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = values.isEmpty ? 1 : values.reduce(math.max);
    return Semantics(
      image: true,
      label: label,
      child: SizedBox(
        height: 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (var i = 0; i < values.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: 12,
                  height: math.max(6, 56 * values[i] / math.max(top, 1)),
                  decoration: BoxDecoration(
                    color: i == values.length - 1 ? c.accent : c.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One night: when sleep started and ended.
class SleepNight {
  const SleepNight({
    required this.day,
    required this.startMinute,
    required this.endMinute,
  });

  final String day;

  /// Minutes after 21:00 the evening before.
  final int startMinute;
  final int endMinute;
}

/// Each night as a soft bar on a clock from 9 pm to 9 am, with the clock on the left.
class SleepNightsChart extends StatelessWidget {
  const SleepNightsChart({
    required this.nights,
    required this.dayLabels,
    required this.hourLabels,
    required this.label,
    super.key,
  });

  final List<SleepNight> nights;
  final List<String> dayLabels;
  final List<String> hourLabels;
  final String label;

  static const int _span = 12 * 60;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const height = 156.0;
    return Semantics(
      image: true,
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            height: height,
            child: Stack(
              children: <Widget>[
                for (var i = 0; i < hourLabels.length; i++)
                  Positioned(
                    top: i * (height - 14) / math.max(hourLabels.length - 1, 1),
                    child: Text(
                      hourLabels[i],
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                for (var i = 0; i < nights.length; i++)
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: height,
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: <Widget>[
                              Positioned(
                                top:
                                    height *
                                    nights[i].startMinute.clamp(0, _span) /
                                    _span,
                                height: math.max(
                                  4,
                                  height *
                                      (nights[i].endMinute.clamp(0, _span) -
                                          nights[i].startMinute.clamp(
                                            0,
                                            _span,
                                          )) /
                                      _span,
                                ),
                                child: Container(
                                  width: 14,
                                  decoration: BoxDecoration(
                                    color: i == nights.length - 1
                                        ? c.accent
                                        : c.accentSoft,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i < dayLabels.length ? dayLabels[i] : '',
                          style: TextStyle(color: c.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
