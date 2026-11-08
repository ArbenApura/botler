// THE CONTEXT METER: A SMALL RING IN THE CHAT'S APP BAR THAT FILLS WITH HOW MUCH OF THE MODEL'S WINDOW THE CHAT USES, AND THE QUIET SHEET IT OPENS.
// The sheet says the figure in words, what happens as a chat grows, when it was last summarized, this month's share of the monthly limit, and has one
// action: "Summarize now" (the server folds the older messages into the chat's summary; nothing is lost). The ring is hidden until the chat has an answer
// with a reported size. Accent while there is room, warning from 70 percent, danger from 90 (a status never comes from the accent).

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/clock.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/once.dart';
import 'chat_state.dart';
import 'context_info.dart';
import 'live_parts.dart';

// -- TYPES -- //

/// This month's chat tokens used and the chat allowance, both in charged tokens. Counts only.
class ContextMonth {
  const ContextMonth(this.used, this.cap);

  final int used;
  final int cap;

  /// The whole percent of the allowance used; never 0 once something is used.
  int get percent {
    if (cap <= 0 || used <= 0) return 0;
    return (used * 100 / cap).round().clamp(1, 100);
  }

  double get share => cap <= 0 ? 0 : (used / cap).clamp(0.0, 1.0);
}

enum _Compact { idle, working, done, failed, short, offline }

// -- PROVIDERS -- //

/// This month's share, read when the sheet opens (a plain read: no model call, no tokens).
final FutureProvider<ContextMonth> contextMonthProvider =
    FutureProvider.autoDispose<ContextMonth>((ref) async {
      final answer = await ref.read(apiProvider).verbJson('chat_usage');
      final used = answer['used'];
      final cap = answer['cap'];
      return ContextMonth(used is int ? used : 0, cap is int ? cap : 0);
    });

// -- FUNCTIONS -- //

Color _levelColor(BotlerColors c, ContextLevel level) => switch (level) {
  ContextLevel.calm => c.accent,
  ContextLevel.warning => c.warning,
  ContextLevel.danger => c.danger,
};

const TextStyle _tabular = TextStyle(
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

/// Opens the context sheet from the app bar.
void showContextSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.paper,
    builder: (_) => const _ContextSheet(),
  );
}

// -- CLASSES -- //

/// A ring that fills clockwise with [share] (0 to 1), drawn on a quiet track.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.share,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double share;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (share <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * share, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

/// The app bar action: the ring, 24 dp inside a 48 dp target. Nothing at all until the chat has a reported size.
class ContextRingButton extends ConsumerWidget {
  const ContextRingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(chatProvider.select((s) => s.context));
    if (info == null) return const SizedBox.shrink();
    final c = context.colors;
    final words = context.t.chatContextTooltip(info.percent);
    return IconButton(
      tooltip: words,
      onPressed: () => showContextSheet(context),
      icon: Semantics(
        label: words,
        excludeSemantics: true,
        child: SizedBox(
          width: 24,
          height: 24,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: info.share),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => CustomPaint(
              painter: _RingPainter(
                share: value,
                color: _levelColor(c, info.level),
                track: c.line,
                stroke: 2.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextSheet extends ConsumerStatefulWidget {
  const _ContextSheet();

  @override
  ConsumerState<_ContextSheet> createState() => _ContextSheetState();
}

class _ContextSheetState extends ConsumerState<_ContextSheet> {
  // -- STATES -- //
  // One request key for "summarize this chat" until it succeeds, so a retry after a timeout is the same request
  final Once _once = Once();
  _Compact _compact = _Compact.idle;

  // -- FUNCTIONS -- //

  /// Asks the server to summarize, then reads the chat's summary time every few seconds until it changes (about a minute at most).
  Future<void> _summarize(ContextInfo info) async {
    final chatId = ref.read(chatProvider).chatId;
    if (chatId == null || _compact == _Compact.working) return;
    setState(() => _compact = _Compact.working);
    final before = info.summarizedAt;
    final intent = 'compact:$chatId';
    try {
      final answer = asJson(
        await ref.read(apiProvider).verb('chat_compact', <String, Object?>{
          'chatId': chatId,
        }, _once.key(intent)),
      );
      _once.done(intent);
      if (answer['queued'] == false && answer['reason'] == 'short') {
        if (mounted) setState(() => _compact = _Compact.short);
        return;
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        final now = await ref.read(chatProvider.notifier).refreshContext();
        final at = now?.summarizedAt;
        if (at != null && at != before) {
          if (mounted) setState(() => _compact = _Compact.done);
          return;
        }
      }
      if (mounted) setState(() => _compact = _Compact.failed);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _compact = e.isNetwork ? _Compact.offline : _Compact.failed,
        );
      }
    } on Object {
      if (mounted) setState(() => _compact = _Compact.failed);
    }
  }

  // -- LIFECYCLES -- //

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final info = ref.watch(chatProvider.select((s) => s.context));
    // The figure can vanish while the sheet is open (another chat was opened): the sheet has nothing to say then
    if (info == null) return const SizedBox(height: 120);
    final month = ref.watch(contextMonthProvider).value;
    final color = _levelColor(c, info.level);
    final summarized = info.summarizedAt;
    final status = switch (_compact) {
      _Compact.done => t.chatContextSummarized,
      _Compact.failed => t.chatContextFailed,
      _Compact.short => t.chatContextShort,
      _Compact.offline => t.chatContextOffline,
      _ => null,
    };
    final callout = switch (info.level) {
      ContextLevel.calm => null,
      ContextLevel.warning => (t.chatContextWarn, c.warning),
      ContextLevel.danger => (t.chatContextDanger, c.danger),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                t.chatContextTitle.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: c.muted, letterSpacing: 0.8),
              ),
            ),
            // The figure, in words and in a larger ring
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CustomPaint(
                          size: const Size(76, 76),
                          painter: _RingPainter(
                            share: info.share,
                            color: color,
                            track: c.line,
                            stroke: 6,
                          ),
                        ),
                        Text(
                          '${info.percent}%',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w300)
                              .merge(_tabular),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          t.chatContextFull(info.percent),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w300),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.chatContextUsed(info.tokens, info.window),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: c.muted)
                              .merge(_tabular),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.chatContextAtLast,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(
                t.chatContextExplain,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: c.muted, height: 1.5),
              ),
            ),
            // Only from 70 percent: a quiet outlined line in the status colour, never an alarm before 90
            if (callout != null)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: callout.$2),
                ),
                child: Text(
                  callout.$1,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: callout.$2),
                ),
              ),
            const SizedBox(height: 10),
            _Row(
              label: t.chatContextLastSummary,
              value: summarized == null
                  ? t.chatContextNever
                  : fmtDateTime(manilaWall(summarized), DateKind.monthDay),
            ),
            Container(height: 1, color: c.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          t.chatContextMonth,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      // While it loads or if it cannot be read, the row shows its label only
                      if (month != null) ...<Widget>[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            t.chatContextMonthShare(month.percent),
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: c.muted)
                                .merge(_tabular),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (month != null) ...<Widget>[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: month.share,
                        minHeight: 4,
                        color: c.accent,
                        backgroundColor: c.line,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The one primary action of the sheet
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed:
                  _compact == _Compact.working || _compact == _Compact.short
                  ? null
                  : () => _summarize(info),
              child: _compact == _Compact.working
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(t.chatContextSummarizing),
                        const SizedBox(width: 10),
                        const PulsingDots(),
                      ],
                    )
                  : Text(t.chatContextSummarize),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _compact == _Compact.failed ? c.danger : c.muted,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A label on the left and its value on the right, at least 48 dp tall.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: c.muted)
                    .merge(_tabular),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
