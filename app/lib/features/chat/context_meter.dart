// THE CONTEXT METER: A SMALL RING IN THE CHAT'S APP BAR THAT FILLS WITH HOW MUCH OF THE MODEL'S WINDOW THE CHAT USES, AND THE QUIET SHEET IT OPENS.
// The sheet says the figure in words, what happens as a chat grows, when it was last summarized, this month's share of the monthly limit, and has one
// action: "Summarize now" (the server folds the older messages into the chat's summary; nothing is lost). The ring is hidden until the chat has an answer
// with a reported size. Accent while there is room, warning from 70 percent, danger from 90 (a status never comes from the accent).
// The sheet is one hero card (ring with the percent inside, the level in words, the token count), a status callout from 70 percent, one grouped card of
// equal rows, the explanation, a reserved status line and the one button. Every text wraps, the content scrolls, and the sheet is height and width capped.

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
    useSafeArea: true,
    // Never wider than a comfortable column on a tablet; the height is the screen's, the content scrolls inside it
    constraints: const BoxConstraints(maxWidth: 560),
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
    final text = Theme.of(context).textTheme;
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
    final levelWords = switch (info.level) {
      ContextLevel.calm => t.chatContextLevelCalm,
      ContextLevel.warning => t.chatContextLevelWarn,
      ContextLevel.danger => t.chatContextLevelDanger,
    };
    final callout = switch (info.level) {
      ContextLevel.calm => null,
      ContextLevel.warning => (t.chatContextWarn, c.warning),
      ContextLevel.danger => (t.chatContextDanger, c.danger),
    };
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Semantics(
                header: true,
                child: Text(
                  t.chatContextTitle,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w400),
                ),
              ),
            ),
            // The figure: the ring says the percent once, the words say the level
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: <Widget>[
                  Semantics(
                    label: t.chatContextFull(info.percent),
                    excludeSemantics: true,
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          CustomPaint(
                            size: const Size(88, 88),
                            painter: _RingPainter(
                              share: info.share,
                              color: color,
                              track: c.line,
                              stroke: 7,
                            ),
                          ),
                          // Scales down inside the ring instead of spilling over it at a large text size
                          SizedBox(
                            width: 56,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${info.percent}%',
                                style: text.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w300)
                                    .merge(_tabular),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          levelWords,
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.chatContextUsed(info.tokens, info.window),
                          style: text.bodyMedium
                              ?.copyWith(color: c.muted)
                              .merge(_tabular),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.chatContextAtLast,
                          style: text.bodySmall?.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Only from 70 percent: a tint of the status colour over the card, never an alarm before 90
            if (callout != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    callout.$2.withValues(alpha: 0.12),
                    c.surface,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: callout.$2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        callout.$1,
                        style: text.bodyMedium?.copyWith(color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
            // One grouped card, rows of the same build, split by a hairline
            Container(
              margin: const EdgeInsets.only(top: 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Row(
                    label: t.chatContextLastSummary,
                    value: summarized == null
                        ? t.chatContextNever
                        : fmtDateTime(
                            manilaWall(summarized),
                            DateKind.monthDay,
                          ),
                  ),
                  Container(height: 1, color: c.line),
                  // While it loads or if it cannot be read, the row shows its label only
                  _Row(
                    label: t.chatContextMonth,
                    value: month == null
                        ? null
                        : t.chatContextMonthShare(month.percent),
                    share: month?.share,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
              child: Text(
                t.chatContextExplain,
                style: text.bodyMedium?.copyWith(color: c.muted, height: 1.5),
              ),
            ),
            // The result of the action has its own line above the button, so the button never moves
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Center(
                  child: status == null
                      ? null
                      : Semantics(
                          liveRegion: true,
                          child: Text(
                            status,
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: _compact == _Compact.failed
                                  ? c.danger
                                  : c.muted,
                              height: 1.45,
                            ),
                          ),
                        ),
                ),
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
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      children: <Widget>[
                        Text(t.chatContextSummarizing),
                        const PulsingDots(),
                      ],
                    )
                  : Text(t.chatContextSummarize, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of the grouped card, at least 56 dp tall: the label, its value beside it when both fit and under it when not, and an optional bar of [share].
class _Row extends StatelessWidget {
  const _Row({required this.label, this.value, this.share});

  final String label;
  final String? value;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final v = value;
    final s = share;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // A Wrap, not two squeezed Flexibles: a long label or value drops to its own line instead of clipping
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                Text(label, style: text.bodyLarge),
                if (v != null)
                  Text(
                    v,
                    style: text.bodyMedium
                        ?.copyWith(color: c.muted)
                        .merge(_tabular),
                  ),
              ],
            ),
            if (s != null) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: s,
                  minHeight: 4,
                  color: c.accent,
                  backgroundColor: c.line,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
