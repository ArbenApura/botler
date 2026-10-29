// TIME TRAVEL'S PIECES: THE MODE BAND, THE SOURCE TAGS, THE BALANCE CHART, THE HEADLINE, THE ACCOUNTS AND THE ENTRY ROWS (BTL-20261029-0117,
// BTL-20261029-0509).
// A simulated number must never pass for a real one, and colour is never the only sign: every number has a worded tag beside it, simulated
// and replayed lines are dashed while the recorded line is solid, every entry is the same row shape with an icon and a worded tag, and the
// band at the top says in words which part of time is shown. Every colour comes from the tokens and every gap from gapS, gapM, gapL, gapXL.

// -- DEP-MODULES -- //
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../calendar/calendar_data.dart';
import 'simulate_data.dart';

// -- CONSTANTS -- //

/// The vertical and horizontal rhythm of the screen: every gap is one of these four.
const double gapS = 4;
const double gapM = 8;
const double gapL = 12;
const double gapXL = 16;

// -- FUNCTIONS -- //

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// A short day, such as "Mar 5, 2027".
String shortDay(BuildContext context, String day) =>
    DateFormat.yMMMd(_locale(context)).format(parseDay(day));

/// The words for a period: a day, a month, a year, or "from to".
String periodWords(BuildContext context, SimPeriod p, Zoom zoom) {
  final locale = _locale(context);
  final from = parseDay(p.from);
  return switch (zoom) {
    Zoom.day => DateFormat.yMMMEd(locale).format(from),
    Zoom.month => DateFormat.yMMMM(locale).format(from),
    Zoom.year => DateFormat.y(locale).format(from),
    Zoom.week => context.t.simPeriod(
      DateFormat.MMMd(locale).format(from),
      DateFormat.yMMMd(locale).format(parseDay(p.to)),
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
                    t.simBandOffline(
                      DateFormat.yMMMd(_locale(context)).add_jm().format(saved),
                    ),
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
    super.key,
  });

  final String label;
  final SimSource source;

  /// Null when there is nothing to total: [reason] says why.
  final int? amount;
  final String? reason;

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

// -- PERIOD LINES -- //

/// One labelled number: the words, the amount in tabular figures, and its tag. The tag follows the number, never the period.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    required this.source,
  });

  final String label;
  final int amount;
  final SimSource source;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                style: Theme.of(context).textTheme.titleMedium
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

/// The rest of the selected period under its headline: the plan replay, the gap to the plan, what was missed, its warnings and what was
/// left out. Empty when there is nothing more to say (the card is then not drawn).
List<Widget> periodLines(
  BuildContext context,
  SimResult sim,
  SimPeriod p, {
  bool noTotal = false,
}) {
  final t = context.t;
  final c = context.colors;
  final recordedEnd = p.recordedEnd;
  final replayEnd = p.replayEnd;
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
    // With no rate for anything the period holds, its totals are not zero but unknown, so no total-based line is drawn
    if (!noTotal && p.part == SimPart.past && replayEnd != null)
      _TotalRow(
        label: t.simReplayEnd,
        amount: replayEnd,
        source: SimSource.replay,
      ),
    if (!noTotal && gap != null)
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
    if (!noTotal && p.part == SimPart.mixed && recordedEnd != null)
      _TotalRow(
        label: t.simRecordedToday,
        amount: recordedEnd,
        source: SimSource.recorded,
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

// -- ACCOUNTS -- //

/// The accounts at the end of the period: one block per account, a line per currency in its own money, and the main-currency figure
/// beneath a foreign one. One tag for the whole card, since every line is the same part of time.
class WalletsCard extends StatelessWidget {
  const WalletsCard({
    required this.period,
    required this.mainCurrency,
    super.key,
  });

  final SimPeriod period;
  final String mainCurrency;

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
    required this.source,
    required this.mainCurrency,
    required this.hiddenWord,
    required this.noRateWord,
    required this.aboutOf,
    required this.color,
  });

  final List<SimWallet> wallets;
  final bool past;
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
              // A foreign wallet: what it comes to in the main currency, or that it has no rate
              if (w.currency != mainCurrency && w.mainKnown)
                Text(
                  switch (w.mainFor(past: past)) {
                    final int m => aboutOf(context.moneyMain(m)),
                    null => noRateWord,
                  },
                  style: TextStyle(
                    fontFeatures: tabular,
                    color: w.noRate(past: past) ? c.warning : c.muted,
                  ),
                ),
            ],
          ],
        ),
      ],
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
