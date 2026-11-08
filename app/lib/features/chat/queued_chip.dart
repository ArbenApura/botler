// A MESSAGE WAITING ITS TURN, AND THE ONE QUIET LINE OF A PAUSED QUEUE. THE CHIP IS THE PERSON'S OWN CHIP IN A MUTED STATE (DASHED LINE, A SMALL
// CLOCK AND THE WORD WAITING); THE LINE IS PLAIN MUTED TEXT WITH TWO TEXT BUTTONS. NO PANEL, NO SHEET, NO MODAL.

// -- DEP-MODULES -- //
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

/// The length of a dash and of the gap after it, in logical pixels.
const double _dash = 5;
const double _gap = 4;

// -- PAINTERS -- //

/// A rounded rectangle drawn with a dashed line in [color].
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final PathMetric metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        final end = at + _dash < metric.length ? at + _dash : metric.length;
        canvas.drawPath(metric.extractPath(at, end), paint);
        at += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

// -- WIDGETS -- //

/// One waiting message. The text edits it (when it has no photos), the cross takes it off the queue.
class QueuedChip extends StatelessWidget {
  const QueuedChip({
    required this.text,
    required this.photos,
    required this.onRemove,
    required this.onEdit,
    super.key,
  });

  final String text;

  /// How many photos go with it.
  final int photos;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final shown = photos > 0 ? t.chatWithPhotos(text, photos) : text;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        child: CustomPaint(
          painter: _DashedBorder(color: c.line, radius: 18),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, top: 2, bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Semantics(
                        button: photos == 0,
                        label: photos == 0 ? t.chatQueueEdit : null,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: photos == 0 ? onEdit : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              shown,
                              style: TextStyle(
                                color: c.ink.withValues(alpha: 0.88),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: t.chatQueueRemove,
                      onPressed: onRemove,
                      icon: Icon(Icons.close, size: 18, color: c.muted),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.schedule, size: 12, color: c.muted),
                      const SizedBox(width: 4),
                      Text(
                        t.chatQueueWaiting,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// After a Stop or a failed message: how many are waiting, and two plain buttons. Nothing is sent unasked.
class PausedQueueLine extends StatelessWidget {
  const PausedQueueLine({
    required this.count,
    required this.onSendNow,
    required this.onClear,
    super.key,
  });

  final int count;
  final VoidCallback onSendNow;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    return Row(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              t.chatQueuePaused(count),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.muted),
            ),
          ),
        ),
        TextButton(onPressed: onSendNow, child: Text(t.chatQueueSendNow)),
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: Text(t.chatQueueClear),
        ),
      ],
    );
  }
}
