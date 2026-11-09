// TIME TRAVEL'S PIECES: THE MODE BAND, THE SOURCE TAGS, THE BALANCE CHART, THE HEADLINE, THE ACCOUNTS AND THE ENTRY ROWS (BTL-20261029-0117,
// BTL-20261029-0509).
// A simulated number must never pass for a real one, and colour is never the only sign: every number has a worded tag beside it, simulated
// and replayed lines are dashed while the recorded line is solid, every entry is the same row shape with an icon and a worded tag, and the
// band at the top says in words which part of time is shown. Every colour comes from the tokens and every gap from gapS, gapM, gapL, gapXL.

// -- DEP-MODULES -- //
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/manila.dart' show manilaToday;
import '../../core/marks.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../calendar/calendar_data.dart';
import '../money/net_parts.dart';
import 'simulate_data.dart';
import '../../core/clock.dart';

// -- CONSTANTS -- //

/// The vertical and horizontal rhythm of the screen: every gap is one of these four.
const double gapS = 4;
const double gapM = 8;
const double gapL = 12;
const double gapXL = 16;

// -- FUNCTIONS -- //

/// A short day, such as "Mar 5, 2027".
String shortDay(BuildContext context, String day) => fmtDate(parseDay(day));

/// The words for a period: a day, a month, a year, or "from to".
String periodWords(BuildContext context, SimPeriod p, Zoom zoom) {
  final from = parseDay(p.from);
  return switch (zoom) {
    Zoom.day => fmtDate(from, DateKind.dateLongWeekday),
    Zoom.month => fmtDate(from, DateKind.monthYear),
    Zoom.year => '${from.year}',
    Zoom.week => context.t.simPeriod(
      fmtDate(from, DateKind.monthDay),
      fmtDate(parseDay(p.to)),
    ),
  };
}

String sourceWord(BuildContext context, SimSource s) => switch (s) {
  SimSource.recorded => context.t.simTagRecorded,
  SimSource.replay => context.t.simTagReplay,
  SimSource.simulated => context.t.simTagSimulated,
  SimSource.missed => context.t.simTagMissed,
};

/// The colour that goes with a source: ink for what is real, info for the future, muted for a replay, warning for a miss.
Color sourceColor(BotlerColors c, SimSource s) => switch (s) {
  SimSource.recorded => c.ink,
  SimSource.replay => c.muted,
  SimSource.simulated => c.info,
  SimSource.missed => c.warning,
};

// -- BAND -- //

/// Which part of time the selected period is in, said in words, with the offline line. One even box with an info button; it stays at the top.
class ModeBand extends StatelessWidget {
  const ModeBand({
    required this.part,
    required this.onInfo,
    required this.onRetry,
    this.savedAt,
    super.key,
  });

  final SimPart part;

  /// Opens the short explanation of what the screen shows.
  final VoidCallback onInfo;

  /// Asks the server again, for an offline copy once the connection is back.
  final VoidCallback onRetry;
  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final saved = savedAt;
    final (
      IconData icon,
      Color tone,
      String title,
      String line,
    ) = switch (part) {
      SimPart.future => (
        Icons.auto_graph,
        c.info,
        t.simBandFuture,
        t.simBandFutureLine,
      ),
      SimPart.past => (
        Icons.history,
        c.muted,
        t.simBandPast,
        t.simBandPastLine,
      ),
      SimPart.mixed => (
        Icons.today_outlined,
        c.info,
        t.simBandMixed,
        t.simBandMixedLine,
      ),
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone),
      ),
      padding: const EdgeInsets.fromLTRB(gapL, gapS, gapS, gapS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: '$title. $line',
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: gapS),
                          child: Icon(icon, size: 20, color: tone),
                        ),
                        const SizedBox(width: gapM),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: gapS),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(color: c.ink),
                                ),
                                Text(line, style: TextStyle(color: c.muted)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: t.simInfoTooltip,
                icon: const Icon(Icons.info_outline),
                onPressed: onInfo,
              ),
            ],
          ),
          if (saved != null)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.simBandOffline(fmtDateTime(zoneWall(saved))),
                    style: TextStyle(color: c.muted),
                  ),
                ),
                TextButton(onPressed: onRetry, child: Text(t.retry)),
              ],
            ),
        ],
      ),
    );
  }
}

/// The what-if as one quiet row under the header: how many changes are on, and Edit and Reset.
class WhatIfRow extends StatelessWidget {
  const WhatIfRow({
    required this.changes,
    required this.onEdit,
    required this.onReset,
    super.key,
  });

  final int changes;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    return Row(
      children: <Widget>[
        const SizedBox(width: gapS),
        Icon(Icons.tune, size: 18, color: c.info),
        const SizedBox(width: gapM),
        Expanded(
          child: Text(t.simWhatIfOn(changes), style: TextStyle(color: c.info)),
        ),
        TextButton(onPressed: onEdit, child: Text(t.simEdit)),
        TextButton(onPressed: onReset, child: Text(t.simReset)),
      ],
    );
  }
}

/// The short explanation: what the screen is for, the chart, every tag, the gap to the plan and the warnings.
Future<void> showSimInfo(BuildContext context) => showFormSheet<void>(
  context,
  title: context.t.simInfoTitle,
  builder: (sheet, close) {
    final t = sheet.t;
    final c = sheet.colors;
    Widget item(String title, String body) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(sheet).textTheme.titleSmall),
        Text(body, style: TextStyle(color: c.muted)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: gapL,
      children: <Widget>[
        Text(t.simInfoIntro),
        item(t.simInfoChartTitle, t.simInfoChart),
        item(t.simInfoNetTitle, t.simInfoNet),
        item(t.simInfoTagsTitle, t.simInfoTags),
        item(t.simInfoGapTitle, t.simInfoGap),
        item(t.simInfoWarnTitle, t.simInfoWarn),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => close(null),
            child: Text(t.simDone),
          ),
        ),
      ],
    );
  },
);

// -- TAGS -- //

/// A worded tag: filled for what was recorded, outlined for a replay or a simulation, warning for a miss.
class SourceTag extends StatelessWidget {
  const SourceTag(this.source, {this.pretend = false, super.key});

  final SimSource source;
  final bool pretend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = sourceColor(c, source);
    final filled = source == SimSource.recorded;
    final text = pretend
        ? '${sourceWord(context, source)} · ${context.t.simTagPretend}'
        : sourceWord(context, source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? c.chip : c.surface,
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: tone),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: filled ? c.ink : tone),
      ),
    );
  }
}

// -- CHART -- //

/// The total of every period as a line: solid where it was recorded, dashed where it is simulated or replayed, with a mark at today.
/// The whole chart is one target: a tap or a drag picks the nearest period, and a screen reader moves period by period.
class SimChart extends StatelessWidget {
  const SimChart({
    required this.sim,
    required this.selected,
    required this.zoom,
    required this.onSelect,
    super.key,
  });

  final SimResult sim;
  final int selected;
  final Zoom zoom;
  final ValueChanged<int> onSelect;

  int _indexAt(double dx, double width) {
    final n = sim.periods.length;
    if (n <= 1 || width <= 0) return 0;
    return (dx / width * (n - 1)).round().clamp(0, n - 1);
  }

  String _value(BuildContext context, int i) {
    final p = sim.periods[i];
    final h = p.headline;
    return context.t.simChartSemantics(
      periodWords(context, p, zoom),
      switch (h.amount) {
        null => '—',
        final a => context.moneyMain(a),
      },
      sourceWord(context, h.source),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = sim.periods.length;
    return Semantics(
      slider: true,
      value: n == 0 ? '' : _value(context, selected),
      increasedValue: selected + 1 < n ? _value(context, selected + 1) : null,
      decreasedValue: selected > 0 ? _value(context, selected - 1) : null,
      onIncrease: selected + 1 < n ? () => onSelect(selected + 1) : null,
      onDecrease: selected > 0 ? () => onSelect(selected - 1) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) =>
                onSelect(_indexAt(d.localPosition.dx, box.maxWidth)),
            onHorizontalDragUpdate: (d) =>
                onSelect(_indexAt(d.localPosition.dx, box.maxWidth)),
            child: CustomPaint(
              size: Size(box.maxWidth, 140),
              painter: _ChartPainter(
                periods: sim.periods,
                selected: selected,
                ink: c.ink,
                info: c.info,
                muted: c.muted,
                grid: c.line,
                warning: c.warning,
                danger: c.danger,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.periods,
    required this.selected,
    required this.ink,
    required this.info,
    required this.muted,
    required this.grid,
    required this.warning,
    required this.danger,
  });

  final List<SimPeriod> periods;
  final int selected;
  final Color ink;
  final Color info;
  final Color muted;
  final Color grid;
  final Color warning;
  final Color danger;

  /// A dashed copy of a path, so a simulated line never looks like a recorded one.
  static Path _dashed(Path source, {double dash = 6, double gap = 5}) {
    final out = Path();
    for (final ui.PathMetric m in source.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, d + dash), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = periods.length;
    if (n == 0) return;
    final values = <int>[
      for (final p in periods)
        ...<int?>[
          p.recordedEnd,
          p.replayEnd,
          p.simulatedEnd,
          p.recordedStart,
        ].whereType<int>(),
    ];
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (lo > 0) lo = 0;
    if (hi == lo) hi = lo + 1;
    const top = 12.0;
    final bottom = size.height - 12;
    double x(int i) => n == 1 ? size.width / 2 : size.width * i / (n - 1);
    double y(int v) => bottom - (bottom - top) * (v - lo) / (hi - lo);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // The zero line, when the balance can go under it
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    // Recorded: solid ink, through the past and up to today
    final recorded = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = periods[i].recordedEnd;
      if (v == null || periods[i].part == SimPart.future) continue;
      started ? recorded.lineTo(x(i), y(v)) : recorded.moveTo(x(i), y(v));
      started = true;
    }
    canvas.drawPath(recorded, stroke..color = ink);

    // Replay: a dashed muted step per past period, from its recorded start to where the plan would have ended it
    for (var i = 0; i < n; i++) {
      final p = periods[i];
      final rs = p.recordedStart;
      final re = p.replayEnd;
      if (rs == null || re == null) continue;
      final from = i == 0
          ? x(i) - (n == 1 ? 12 : size.width / (n - 1) / 2)
          : x(i - 1);
      final seg = Path()
        ..moveTo(from, y(rs))
        ..lineTo(x(i), y(re));
      canvas.drawPath(_dashed(seg), stroke..color = muted);
    }

    // Simulated: dashed info, from today's recorded point on
    final simulated = Path();
    started = false;
    for (var i = 0; i < n; i++) {
      final p = periods[i];
      final v = p.simulatedEnd;
      if (v == null) continue;
      if (!started) {
        final from = p.simulatedStart ?? v;
        simulated.moveTo(i == 0 ? x(i) : x(i - 1), y(from));
        started = true;
      }
      simulated.lineTo(x(i), y(v));
    }
    canvas.drawPath(_dashed(simulated), stroke..color = info);

    // Today: a thin line at the period that holds it
    for (var i = 0; i < n; i++) {
      if (periods[i].part != SimPart.mixed) continue;
      canvas.drawLine(
        Offset(x(i), top - 8),
        Offset(x(i), bottom + 8),
        Paint()
          ..color = info
          ..strokeWidth = 1,
      );
    }

    // Low and below zero: a ring on the period, warning or danger
    for (var i = 0; i < n; i++) {
      final p = periods[i];
      final v = p.headline.amount;
      if (v == null || !(p.low || p.below)) continue;
      canvas.drawCircle(
        Offset(x(i), y(v)),
        5,
        Paint()
          ..color = p.below ? danger : warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // The selected period
    if (selected >= 0 && selected < n) {
      final h = periods[selected].headline.amount;
      canvas.drawLine(
        Offset(x(selected), top - 8),
        Offset(x(selected), bottom + 8),
        Paint()
          ..color = grid
          ..strokeWidth = 2,
      );
      if (h != null) {
        canvas.drawCircle(Offset(x(selected), y(h)), 5, Paint()..color = ink);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.periods != periods ||
      old.selected != selected ||
      old.ink != ink ||
      old.info != info;
}

// -- HEADLINE -- //

/// The one big number of the selected period: the words, the amount in tabular figures (or the reason there is none) and its tag.
class HeadlineTotal extends StatelessWidget {
  const HeadlineTotal({
    required this.label,
    required this.source,
    this.amount,
    this.reason,
    this.sub,
    super.key,
  });

  final String label;
  final SimSource source;

  /// Null when there is nothing to total: [reason] says why.
  final int? amount;
  final String? reason;

  /// A quiet line under the amount (the balance as counted under a net).
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final value = amount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: gapS,
            children: <Widget>[
              Text(label, style: TextStyle(color: c.muted)),
              if (value != null)
                Amount(
                  value,
                  style: theme.headlineMedium?.copyWith(
                    color: source == SimSource.recorded
                        ? c.ink
                        : sourceColor(c, source),
                  ),
                )
              else
                Text(
                  reason ?? context.t.simNoTotal,
                  style: theme.titleMedium?.copyWith(color: c.muted),
                ),
              if (value != null && sub != null)
                Text(
                  sub ?? '',
                  style: TextStyle(color: c.muted, fontFeatures: tabular),
                ),
            ],
          ),
        ),
        SourceTag(source),
      ],
    );
  }
}

/// What the main-currency total leaves out: the currencies with no exchange rate that this period holds, and whether that is all of it.
({List<String> codes, bool noTotal}) rateInfoOf(SimResult sim, SimPeriod p) {
  final past = p.part == SimPart.past;
  final known = p.wallets.where((w) => w.mainKnown).toList();
  // An older saved answer has no main-currency figures: fall back on the whole answer's list
  if (known.isEmpty) {
    return (
      codes: p.wallets.isEmpty ? const <String>[] : sim.missing,
      noTotal: false,
    );
  }
  final held = known.where((w) => w.amountFor(past: past) != null).toList();
  final codes = <String>{
    for (final w in held)
      if (w.noRate(past: past)) w.currency,
  }.toList()..sort();
  return (
    codes: codes,
    noTotal: held.isNotEmpty && held.every((w) => w.noRate(past: past)),
  );
}

/// A visible line naming the currencies with no exchange rate, which are left out of the total (never counted as zero).
class RateWarning extends StatelessWidget {
  const RateWarning(this.codes, {super.key});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
        const SizedBox(width: gapM),
        Expanded(
          child: Text(
            context.t.simMissingRates(codes.join(', ')),
            style: TextStyle(color: c.warning),
          ),
        ),
      ],
    );
  }
}

// -- SPENT AND RECEIVED -- //

/// One labelled number: the words, the amount in tabular figures, and its tag. The tag follows the number, never the period.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    required this.source,
    this.large = false,
  });

  final String label;
  final int amount;
  final SimSource source;

  /// The one number the card is about, drawn bigger than the rows under it.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final dashed = source != SimSource.recorded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: gapS,
            children: <Widget>[
              Text(label, style: TextStyle(color: c.muted)),
              Amount(
                amount,
                style: (large ? text.headlineSmall : text.titleMedium)
                    ?.copyWith(color: dashed ? sourceColor(c, source) : c.ink),
              ),
            ],
          ),
        ),
        SourceTag(source),
      ],
    );
  }
}

/// The lines that always show under the numbers of a period: the gap to the plan, what was missed, its warnings and what was left out.
/// Empty when there is nothing to say.
List<Widget> periodLines(BuildContext context, SimResult sim, SimPeriod p) {
  final t = context.t;
  final c = context.colors;
  final gap = p.gap;
  final warnings = <SimWarning>[
    for (final w in sim.warnings)
      if (p.holds(w.date)) w,
  ];
  final flat =
      p.part != SimPart.past &&
      sim.periods
          .where((x) => x.part == SimPart.future)
          .every((x) => x.simulatedStart == x.simulatedEnd);
  return <Widget>[
    if (gap != null)
      Text(
        gap < 0
            ? t.simGapBelow(context.moneyMain(-gap))
            : gap > 0
            ? t.simGapAbove(context.moneyMain(gap))
            : t.simGapNone,
        style: TextStyle(
          color: gap < 0 ? c.warning : c.muted,
          fontFeatures: tabular,
        ),
      ),
    if (p.missed > 0)
      Text(t.simMissed(p.missed), style: TextStyle(color: c.warning)),
    for (final w in warnings)
      Text(
        w.belowZero
            ? t.simBelowDay(w.accountName, shortDay(context, w.date))
            : t.simLowDay(w.accountName, shortDay(context, w.date)),
        style: TextStyle(color: w.belowZero ? c.danger : c.warning),
      ),
    if (flat) Text(t.simNoPlan, style: TextStyle(color: c.muted)),
    if (sim.unknown.isNotEmpty)
      Text(
        t.simUnknown(sim.unknown.fold(0, (a, u) => a + u.count)),
        style: TextStyle(color: c.muted),
      ),
    if (sim.ratesStale) Text(t.simRatesStale, style: TextStyle(color: c.muted)),
  ];
}

/// How much was spent and received in the selected period, and the lines that belong with it. Spent is the one big number and Received a
/// smaller row under it (hidden when nothing came in); the period of today keeps what is recorded so far apart from what is still to come;
/// the plan replay, the untracked money and the balance rows sit behind one Details row. An older saved answer without these figures
/// shows only the lines, never zeros.
class SpendCard extends StatelessWidget {
  const SpendCard({required this.sim, required this.period, super.key});

  final SimResult sim;
  final SimPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final p = period;
    final lines = periodLines(context, sim, p);
    final rows = <Widget>[];
    final details = <Widget>[];
    if (p.totalsKnown) {
      final past = p.part == SimPart.past;
      final mixed = p.part == SimPart.mixed;
      final source = past || mixed ? SimSource.recorded : SimSource.simulated;
      final spent = past || mixed ? p.recordedSpent : p.simulatedSpent;
      final received = past || mixed ? p.recordedReceived : p.simulatedReceived;
      final coming = mixed ? p.simulatedSpent : null;
      final comingIn = mixed ? p.simulatedReceived : null;
      final nothing =
          (spent ?? 0) == 0 &&
          (received ?? 0) == 0 &&
          (coming ?? 0) == 0 &&
          (comingIn ?? 0) == 0;
      if (spent != null && nothing && p.leftOut.isEmpty) {
        rows.add(Text(t.simNothingSpent, style: TextStyle(color: c.muted)));
      } else if (spent != null) {
        rows.add(
          _TotalRow(
            label: mixed ? t.simSpentSoFar : t.simSpent,
            amount: spent,
            source: source,
            large: true,
          ),
        );
        if ((received ?? 0) != 0) {
          rows.add(
            _TotalRow(
              label: mixed ? t.simReceivedSoFar : t.simReceived,
              amount: received ?? 0,
              source: source,
            ),
          );
        }
        if (coming != null && spent + coming != spent) {
          rows.add(
            _TotalRow(
              label: t.simStillToCome,
              amount: coming,
              source: SimSource.simulated,
            ),
          );
          rows.add(
            Text(
              '${t.simWholePeriod}: ${context.moneyMain(spent + coming)}',
              style: TextStyle(color: c.muted, fontFeatures: tabular),
            ),
          );
        }
      } else if (mixed && coming != null) {
        rows.add(
          _TotalRow(
            label: t.simStillToCome,
            amount: coming,
            source: SimSource.simulated,
          ),
        );
      }
      if (p.leftOut.isNotEmpty) rows.add(RateWarning(p.leftOut));
      // Behind Details: the plan replay of a past period, untracked money, and the balances the header does not show
      final replaySpent = p.replaySpent;
      if (past && replaySpent != null) {
        details.add(
          _TotalRow(
            label: t.simPlanExpected,
            amount: replaySpent,
            source: SimSource.replay,
          ),
        );
      }
      final untracked = p.recordedUntracked;
      if ((past || mixed) && untracked != null && untracked > 0) {
        details.add(
          _TotalRow(
            label: t.simUntracked,
            amount: untracked,
            source: SimSource.recorded,
          ),
        );
      }
      if (mixed && (comingIn ?? 0) != 0) {
        details.add(
          _TotalRow(
            label: t.simStillToReceive,
            amount: comingIn ?? 0,
            source: SimSource.simulated,
          ),
        );
      }
    }
    final replayEnd = p.replayEnd;
    if (p.part == SimPart.past && replayEnd != null) {
      details.add(
        _TotalRow(
          label: t.simReplayEnd,
          amount: replayEnd,
          source: SimSource.replay,
        ),
      );
    }
    final recordedEnd = p.recordedEnd;
    if (p.part == SimPart.mixed && recordedEnd != null) {
      details.add(
        _TotalRow(
          label: t.simRecordedToday,
          amount: recordedEnd,
          source: SimSource.recorded,
        ),
      );
    }
    if (rows.isEmpty && lines.isEmpty && details.isEmpty) {
      return const SizedBox.shrink();
    }
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapM,
        children: <Widget>[
          ...rows,
          ...lines,
          if (details.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: gapM),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                t.simDetails,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gapM,
                  children: details,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// -- OVERALL FLOW -- //

/// True when a day is today in Manila (the answer may be an older saved copy, so "today" is said only when it is). [now] is for tests.
bool _isToday(String day, [DateTime? now]) => day == manilaToday(now);

/// The running total across the span between the selected period and today: from the period to today for a past one, from today to the
/// period for a future one. It is a second card beside the period's own figures (which it includes) and never replaces them. The period
/// that holds today has no span, so it shows one muted line saying where to look. A period without a span (an older saved answer, or
/// before the first record) shows nothing. Net is shown only when it can be trusted: money came in and no currency was left out.
class SpanCard extends StatelessWidget {
  const SpanCard({required this.period, super.key});

  final SimPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final p = period;
    if (!p.spanKnown) {
      if (p.part == SimPart.mixed && p.totalsKnown) {
        return Text(t.simSpanHint, style: TextStyle(color: c.muted));
      }
      return const SizedBox.shrink();
    }
    final from = p.spanFrom ?? p.from;
    final to = p.spanTo ?? p.to;
    final spent = p.spanSpent ?? 0;
    final received = p.spanReceived ?? 0;
    final source = p.spanSimulated ? SimSource.simulated : SimSource.recorded;
    final fromWords = _isToday(from)
        ? t.simSpanTodayCap
        : shortDay(context, from);
    final toWords = _isToday(to) ? t.simSpanToday : shortDay(context, to);
    final partial = p.spanLeftOut.isNotEmpty;
    final nothing = spent == 0 && received == 0 && !partial;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapM,
        children: <Widget>[
          Text(t.simSpanTitle, style: Theme.of(context).textTheme.titleSmall),
          Text(
            t.simSpanRange(fromWords, toWords),
            style: TextStyle(color: c.muted),
          ),
          if (nothing)
            Text(t.simSpanNothing, style: TextStyle(color: c.muted))
          else ...<Widget>[
            _TotalRow(
              label: t.simSpent,
              amount: spent,
              source: source,
              large: true,
            ),
            if (received != 0)
              _TotalRow(label: t.simReceived, amount: received, source: source),
            if (received != 0 && !partial)
              _TotalRow(
                label: t.simSpanNet,
                amount: received - spent,
                source: source,
              ),
          ],
          if (partial) RateWarning(p.spanLeftOut),
          Text(t.simSpanIncludes, style: TextStyle(color: c.muted)),
        ],
      ),
    );
  }
}

// -- WHERE IT WENT -- //

/// The groups of spending to draw: the recorded ones for a past period, the simulated ones for the future, and both added up by group
/// for the period of today (the card then says it includes an estimate).
({List<SpendGroup> groups, int moreAmount, int moreGroups}) spendGroupsFor(
  SimBreakdowns b,
  SimPart part,
) {
  if (part == SimPart.past) {
    return (
      groups: b.recorded.groups,
      moreAmount: b.recorded.moreAmount,
      moreGroups: b.recorded.moreGroups,
    );
  }
  if (part == SimPart.future) {
    return (
      groups: b.simulated.groups,
      moreAmount: b.simulated.moreAmount,
      moreGroups: b.simulated.moreGroups,
    );
  }
  final sums = <String, ({SpendGroup first, int amount, int count})>{};
  for (final g in <SpendGroup>[...b.recorded.groups, ...b.simulated.groups]) {
    final seen = sums[g.key];
    sums[g.key] = (
      first: seen?.first ?? g,
      amount: (seen?.amount ?? 0) + g.amount,
      count: (seen?.count ?? 0) + g.count,
    );
  }
  final merged =
      sums.values
          .map(
            (v) => SpendGroup(<String, Object?>{
              'key': v.first.key,
              'label': v.first.label,
              'kind': v.first.kind,
              'amount': v.amount,
              'count': v.count,
            }),
          )
          .toList()
        ..sort((a, b) {
          final byAmount = b.amount.compareTo(a.amount);
          return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
        });
  return (
    groups: merged,
    moreAmount: b.recorded.moreAmount + b.simulated.moreAmount,
    moreGroups: b.recorded.moreGroups + b.simulated.moreGroups,
  );
}

/// Where the spending of the period went: the biggest bills and categories with their amount and share, and the rest together. A line is
/// one tap away from showing only its entries.
class BreakdownCard extends StatefulWidget {
  const BreakdownCard({
    required this.groups,
    required this.moreAmount,
    required this.moreGroups,
    required this.mainCurrency,
    required this.selected,
    required this.onPick,
    this.estimate = false,
    this.billMarks = const <String, Mark>{},
    super.key,
  });

  /// The mark of each bill by id: a bill group (key bill:ID) shows its own.
  final Map<String, Mark> billMarks;
  final List<SpendGroup> groups;
  final int moreAmount;
  final int moreGroups;
  final String mainCurrency;

  /// The group the entries are limited to.
  final String? selected;
  final ValueChanged<String?> onPick;

  /// The period of today: part of the figures is still to come.
  final bool estimate;

  @override
  State<BreakdownCard> createState() => _BreakdownCardState();
}

/// How many lines show before Show more.
const int _breakdownFirst = 5;

class _BreakdownCardState extends State<BreakdownCard> {
  // -- STATES -- //

  bool _all = false;

  // -- FUNCTIONS -- //

  String _name(BuildContext context, SpendGroup g) =>
      g.kind == 'other' || g.label.isEmpty ? context.t.simGroupOther : g.label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final all = widget.groups;
    final total = all.fold<int>(0, (a, g) => a + g.amount) + widget.moreAmount;
    final shown = _all ? all : all.take(_breakdownFirst).toList();
    final hidden = all.length - shown.length;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapM,
        children: <Widget>[
          Text(t.simWhereTitle, style: Theme.of(context).textTheme.titleSmall),
          Text(
            widget.estimate
                ? '${t.simWhereLine(widget.mainCurrency)} ${t.simIncludesEstimate}'
                : t.simWhereLine(widget.mainCurrency),
            style: TextStyle(color: c.muted),
          ),
          for (final g in shown)
            _GroupLine(
              name: _name(context, g),
              mark: g.kind == 'bill'
                  ? widget.billMarks[g.key.replaceFirst('bill:', '')]
                  : null,
              amount: g.amount,
              total: total,
              selected: widget.selected == g.key,
              onTap: () =>
                  widget.onPick(widget.selected == g.key ? null : g.key),
            ),
          if (_all && widget.moreGroups > 0)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.simEverythingElse(widget.moreGroups),
                    style: TextStyle(color: c.muted),
                  ),
                ),
                Text(
                  context.moneyMain(widget.moreAmount),
                  style: TextStyle(color: c.muted, fontFeatures: tabular),
                ),
              ],
            ),
          if (hidden > 0 || (_all && all.length > _breakdownFirst))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? t.simShowLess : t.simShowMore(hidden)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One group of spending: its name, amount and share, a thin bar, and a tap that limits the entries to it.
class _GroupLine extends StatelessWidget {
  const _GroupLine({
    required this.name,
    required this.mark,
    required this.amount,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final String name;

  /// The bill's icon or picture, when this group is a bill that has one.
  final Mark? mark;
  final int amount;
  final int total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final money = context.moneyMain(amount);
    // Integer maths for the share, rounded to the nearest whole percent; no share for a group below zero or when nothing was spent
    final share = total > 0 && amount > 0
        ? (amount * 100 + total ~/ 2) ~/ total
        : null;
    final fraction = total > 0 && amount > 0 ? amount / total : 0.0;
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: share == null
          ? t.simBreakdownLineNoShare(name, money)
          : t.simBreakdownLine(name, money, share),
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: gapS),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.accent),
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: gapS),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: gapS,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (mark != null && !mark!.isEmpty) ...<Widget>[
                        MarkBadge(name: name, mark: mark!, size: 28),
                        const SizedBox(width: gapM),
                      ],
                      Expanded(
                        flex: 3,
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: gapM),
                      Flexible(
                        flex: 2,
                        child: Text(
                          money,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontFeatures: tabular),
                        ),
                      ),
                    ],
                  ),
                  // The bar, with the share at its end: the bar alone would be a colour with no words
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Stack(
                            children: <Widget>[
                              Container(height: 4, color: c.line),
                              FractionallySizedBox(
                                widthFactor: fraction.clamp(0.0, 1.0),
                                child: Container(height: 4, color: c.info),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (share != null) ...<Widget>[
                        const SizedBox(width: gapM),
                        Text(
                          t.simPercent(share),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: c.muted,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -- ACCOUNTS -- //

/// The accounts at the end of the period: one block per account, a line per currency in its own money, and the main-currency figure
/// beneath a foreign one. One tag for the whole card, since every line is the same part of time.
class WalletsCard extends StatelessWidget {
  const WalletsCard({
    required this.period,
    required this.mainCurrency,
    this.net = false,
    super.key,
  });

  final SimPeriod period;
  final String mainCurrency;

  /// The person chose Show net balance: a simulated wallet that has a net leads with it and shows the balance as counted beneath.
  final bool net;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final past = period.part == SimPart.past;
    final source = past ? SimSource.recorded : SimSource.simulated;
    // Group by account, in the order the server sent them
    final byAccount = <String, List<SimWallet>>{};
    for (final w in period.wallets) {
      if (w.amountFor(past: past) == null) continue;
      byAccount.putIfAbsent(w.accountId, () => <SimWallet>[]).add(w);
    }
    if (byAccount.isEmpty) return const SizedBox.shrink();
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapL,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.simAccountsTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              SourceTag(source),
            ],
          ),
          for (final wallets in byAccount.values)
            _AccountBlock(
              wallets: wallets,
              past: past,
              net: net && !past,
              source: source,
              mainCurrency: mainCurrency,
              hiddenWord: t.simHidden,
              noRateWord: t.simNoRateShort,
              aboutOf: t.simAbout,
              color: c,
            ),
        ],
      ),
    );
  }
}

class _AccountBlock extends StatelessWidget {
  const _AccountBlock({
    required this.wallets,
    required this.past,
    required this.net,
    required this.source,
    required this.mainCurrency,
    required this.hiddenWord,
    required this.noRateWord,
    required this.aboutOf,
    required this.color,
  });

  final List<SimWallet> wallets;
  final bool past;

  /// Net leads for the wallets that have one (never for the past).
  final bool net;
  final SimSource source;
  final String mainCurrency;
  final String hiddenWord;
  final String noRateWord;
  final String Function(String) aboutOf;
  final BotlerColors color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    final first = wallets.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AccountBadge(
          accountId: first.accountId,
          name: first.accountName,
          size: 32,
        ),
        const SizedBox(width: gapM),
        Expanded(
          child: Text(
            first.archived
                ? '${first.accountName} ($hiddenWord)'
                : first.accountName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: gapM),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: gapS,
          children: <Widget>[
            for (final w in wallets) ...<Widget>[
              // A wallet with a net leads with it: the net, the balance as counted when it differs, then what a due bill lacks
              if (net && w.hasNet)
                NetAmount(
                  wallet: w.netJson,
                  currency: w.currency,
                  style: TextStyle(color: c.info),
                )
              else
                Text(
                  context.moneyIn(w.amountFor(past: past) ?? 0, w.currency),
                  style: TextStyle(
                    fontFeatures: tabular,
                    color: (w.amountFor(past: past) ?? 0) < 0
                        ? c.danger
                        : source == SimSource.recorded
                        ? c.ink
                        : c.info,
                  ),
                ),
              // A foreign wallet: what it comes to in the main currency (of the net when that leads), or that it has no rate
              if (w.currency != mainCurrency && w.mainKnown)
                Text(
                  switch (w.mainLead(past: past, net: net)) {
                    final int m => aboutOf(context.moneyMain(m)),
                    null => noRateWord,
                  },
                  style: TextStyle(
                    fontFeatures: tabular,
                    color: w.mainLead(past: past, net: net) == null
                        ? c.warning
                        : c.muted,
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// What is held at the end of a simulated period, wallet by wallet: the bills due before the next payday, what the rules set aside and
/// the goal, in the words and order of the Accounts screen (NetHolds). Only the one-period detail answer carries the holds; nothing is
/// drawn when no wallet holds anything or the setting is off.
class HeldCard extends StatelessWidget {
  const HeldCard({
    required this.period,
    this.billMarks = const <String, Mark>{},
    super.key,
  });

  final SimPeriod period;

  /// The icons of the bills (a bill with none of its own shows its account's, as the server sends them).
  final Map<String, Mark> billMarks;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final held = <SimWallet>[
      for (final w in period.wallets)
        if (w.hasNet && w.holds.isNotEmpty) w,
    ];
    if (period.part == SimPart.past || held.isEmpty) {
      return const SizedBox.shrink();
    }
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(t.simHeldTitle, style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < held.length; i++) ...<Widget>[
            if (i > 0) const Divider(),
            NetHolds(
              wallet: held[i].netJson,
              currency: held[i].currency,
              title: held[i].accountName,
              subtitle: t.simNetEnd,
              // The same badges as the Accounts card above and the entries below: the account, and each bill by its own icon
              leading: AccountBadge(
                accountId: held[i].accountId,
                name: held[i].accountName,
                size: 32,
              ),
              marks: billMarks,
            ),
          ],
        ],
      ),
    );
  }
}

// -- ENTRIES -- //

/// One entry: the same row for every source. Its icon says in, out or a move, a worded tag says recorded, replayed, simulated or missed,
/// and an amount in another currency has its main-currency figure beneath it.
class EntryRow extends StatelessWidget {
  const EntryRow(this.entry, {required this.mainCurrency, super.key});

  final SimEntry entry;
  final String mainCurrency;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final e = entry;
    final real = e.source == SimSource.recorded;
    final tone = sourceColor(c, e.source);
    final sign = switch (e.kind) {
      'in' => '+',
      'out' => '−',
      _ => '',
    };
    final icon = switch (e.kind) {
      'in' => Icons.south_west,
      'out' => Icons.north_east,
      _ => Icons.swap_horiz,
    };
    final amount = switch (e.amount) {
      null => '',
      final a => '$sign${context.moneyIn(a, e.currency)}',
    };
    final foreign = e.amount != null && e.currency != mainCurrency;
    final where = e.kind == 'move' && e.toAccountName.isNotEmpty
        ? '${e.accountName} ${t.simMoveTo(e.toAccountName)}'
        : e.accountName;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.all(gapL),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: gapS),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: gapM),
          AccountBadge(accountId: e.accountId, name: e.accountName, size: 28),
          const SizedBox(width: gapM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: gapS,
              children: <Widget>[
                Text(e.label, overflow: TextOverflow.ellipsis),
                Text(
                  '${shortDay(context, e.date)} · $where'
                  '${foreign ? ' · ${e.currency}' : ''}',
                  style: TextStyle(color: c.muted),
                  overflow: TextOverflow.ellipsis,
                ),
                SourceTag(e.source, pretend: e.pretend),
              ],
            ),
          ),
          const SizedBox(width: gapM),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: gapS,
              children: <Widget>[
                Text(
                  amount,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFeatures: tabular,
                    color: real ? c.ink : tone,
                  ),
                ),
                if (foreign)
                  Text(
                    textAlign: TextAlign.end,
                    switch (e.amountMain) {
                      final int m => t.simAbout(context.moneyMain(m)),
                      null => t.simNoRateShort,
                    },
                    style: TextStyle(
                      fontFeatures: tabular,
                      color: e.amountMain == null ? c.warning : c.muted,
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
