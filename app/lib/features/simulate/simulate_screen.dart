// TIME TRAVEL: JUMP TO ANY DAY, WEEK, MONTH OR YEAR UP TO 5 YEARS BACK OR AHEAD AND SEE WHAT EVERY ACCOUNT HELD OR WILL HOLD (BTL-20261029-0117).
// Siblings: the calendar (a Today button in the app bar, the offline band, one floating primary action) and the accounts screen (one card with a
// total in the main currency, a warning line for a currency with no rate, each wallet in its own money). The banner at the top always says which
// part of time is shown, in one even box with an info button; recorded numbers are solid, replayed and simulated ones are dashed and tagged.
// Under it one header card holds the zoom, the date and the big total. The one primary action is What if. The previous answer stays on screen
// while the next one loads, so a what-if edit never flashes the page (BTL-20261029-0509).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../calendar/calendar_data.dart';
import 'simulate_data.dart';
import 'simulate_parts.dart';
import 'what_if_sheet.dart';

// -- TYPES -- //

class SimulateScreen extends ConsumerStatefulWidget {
  const SimulateScreen({this.initialDate, super.key});

  /// A day to open on (from the calendar strip), as yyyy-MM-dd; null opens on today.
  final String? initialDate;

  @override
  ConsumerState<SimulateScreen> createState() => _SimulateScreenState();
}

class _SimulateScreenState extends ConsumerState<SimulateScreen> {
  // -- STATES -- //

  /// The last answer shown, kept while the next one loads, with its zoom and how many what-if changes it was asked with. It is shown
  /// only for the same zoom (a year period never reads as a month), and the row counts the what-if of what is on screen.
  ({SimLoad load, Zoom zoom, int changes})? _last;

  // -- FUNCTIONS -- //

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Moves the anchor, and says so when the reach of 5 years stopped it.
  void _go(DateTime day) {
    if (clampDay(day, _today) != DateTime(day.year, day.month, day.day)) {
      say(context, context.t.simReachEdge);
    }
    ref.read(simViewProvider.notifier).go(day);
  }

  Future<void> _pick(DateTime anchor) async {
    final d = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: earliestDay(_today),
      lastDate: latestDay(_today),
    );
    if (d != null && mounted) _go(d);
  }

  /// Brings the plan back as it is, and offers to put the what-if back until the next edit.
  void _reset() {
    final t = context.t;
    final edit = ref.read(whatIfProvider.notifier);
    final previous = ref.read(whatIfProvider);
    edit.reset();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(t.simResetDone),
          action: SnackBarAction(
            label: t.simUndo,
            onPressed: () => edit.set(previous),
          ),
        ),
      );
  }

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    final start = widget.initialDate;
    if (start != null && start.isNotEmpty) {
      // Opened from the calendar: that month, by month
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(simViewProvider.notifier)
          ..setZoom(Zoom.month)
          ..go(parseDay(start));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final view = ref.watch(simViewProvider);
    final whatIf = ref.watch(appliedWhatIfProvider);
    final edited = ref.watch(whatIfProvider);
    final introSeen = ref.watch(simIntroSeenProvider);
    final startsOn = ref.watch(settingsProvider).weekStartsOn;
    // Any edit of the what-if drops the offer to undo a reset
    ref.listen<WhatIf>(whatIfProvider, (_, next) {
      if (!next.isEmpty) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
    final window = windowFor(view.zoom, view.anchor, startsOn, _today);
    final key = window.key(whatIf);
    final value = ref.watch(simOverviewProvider('$key#${view.zoom.name}'));
    final loaded = value.value;
    if (loaded != null) {
      _last = (load: loaded, zoom: view.zoom, changes: whatIf.changes);
    }
    final last = _last;
    final kept = last != null && last.zoom == view.zoom ? last : null;
    final shown = loaded ?? kept?.load;
    final shownChanges = loaded != null ? whatIf.changes : (kept?.changes ?? 0);
    final overview = simOverviewProvider('$key#${view.zoom.name}');
    final day = dayOf(view.anchor);
    // While the answer for a new window loads, the kept one may not hold this day: then no period is shown for it
    final found = shown?.sim.periodOf(day);
    final period = found != null && found.holds(day) ? found : null;
    final part =
        period?.part ??
        (view.anchor.isBefore(_today)
            ? SimPart.past
            : view.anchor.isAfter(_today)
            ? SimPart.future
            : SimPart.mixed);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.simTitle),
        actions: <Widget>[
          PopupMenuButton<int>(
            tooltip: t.simJump,
            icon: const Icon(Icons.event_repeat),
            onSelected: (m) => _go(jumpMonths(view.anchor, m)),
            itemBuilder: (_) => <PopupMenuEntry<int>>[
              for (final (name, months) in <(String, int)>[
                (t.simBack1y, -12),
                (t.simBack1m, -1),
                (t.simAhead1m, 1),
                (t.simAhead1y, 12),
                (t.simAhead5y, 60),
              ])
                PopupMenuItem<int>(value: months, child: Text(name)),
            ],
          ),
          TextButton(
            onPressed: () => ref.read(simViewProvider.notifier).today(),
            child: Text(t.simToday),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showWhatIfSheet(context),
        icon: const Icon(Icons.tune),
        label: Text(t.simWhatIf),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(gapXL, gapL, gapXL, 0),
            child: ModeBand(
              part: part,
              savedAt: shown?.savedAt,
              onInfo: () => showSimInfo(context),
              onRetry: () => ref.invalidate(overview),
            ),
          ),
          // Something newer is on its way: the zoom, the dates or the what-if (still being typed) differ from what is shown
          // The slot is always there, so the page never jumps when the bar comes and goes
          Padding(
            padding: const EdgeInsets.only(top: gapS),
            child: SizedBox(
              height: 2,
              child:
                  (value.isLoading || edited.changes != shownChanges) &&
                      shown != null
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                gapXL,
                gapL,
                gapXL,
                96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gapL,
                  children: <Widget>[
                    if (!introSeen) const _Intro(),
                    _HeaderCard(
                      zoom: view.zoom,
                      label: period == null
                          ? shortDay(context, day)
                          : periodWords(context, period, view.zoom),
                      onBack: () => _go(stepAnchor(view.zoom, view.anchor, -1)),
                      onForward: () =>
                          _go(stepAnchor(view.zoom, view.anchor, 1)),
                      onPick: () => _pick(view.anchor),
                      sim: shown?.sim,
                      period: period,
                    ),
                    if (shownChanges > 0)
                      WhatIfRow(
                        changes: shownChanges,
                        onEdit: () => showWhatIfSheet(context),
                        onReset: _reset,
                      ),
                    if (shown == null)
                      AsyncBody<SimLoad>(
                        value: value,
                        onRetry: () => ref.invalidate(
                          simOverviewProvider('$key#${view.zoom.name}'),
                        ),
                        skeleton: const _Skeleton(),
                        data: (_) => const SizedBox.shrink(),
                      )
                    else ...<Widget>[
                      if (value.hasError && !value.isLoading)
                        AsyncBody<SimLoad>(
                          value: value,
                          onRetry: () => ref.invalidate(
                            simOverviewProvider('$key#${view.zoom.name}'),
                          ),
                          data: (_) => const SizedBox.shrink(),
                        ),
                      _Loaded(
                        load: shown,
                        zoom: view.zoom,
                        day: day,
                        whatIfKey: key,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two-sentence welcome, shown until it is dismissed once. The info button on the banner brings the same words back.
class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapM,
        children: <Widget>[
          Text(t.simIntro),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  ref.read(simIntroSeenProvider.notifier).markSeen(),
              child: Text(t.simIntroGotIt),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card at the top: how far to look (day, week, month, year), which date, and the one big total with what it leaves out.
class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({
    required this.zoom,
    required this.label,
    required this.onBack,
    required this.onForward,
    required this.onPick,
    required this.sim,
    required this.period,
  });

  final Zoom zoom;
  final String label;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onPick;
  final SimResult? sim;
  final SimPeriod? period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final s = sim;
    final p = period;
    Widget? headline;
    List<String> codes = const <String>[];
    if (s != null && p != null) {
      final rates = rateInfoOf(s, p);
      codes = rates.codes;
      if (p.part == SimPart.past) {
        headline = p.beforeFirstRecord || p.recordedEnd == null
            ? Text(t.simNoRecords, style: TextStyle(color: c.muted))
            : HeadlineTotal(
                label: t.simRecordedEnd,
                source: SimSource.recorded,
                amount: rates.noTotal ? null : p.recordedEnd,
              );
      } else if (p.simulatedEnd != null) {
        headline = HeadlineTotal(
          label: t.simSimulatedEnd,
          source: SimSource.simulated,
          amount: rates.noTotal ? null : p.simulatedEnd,
        );
      }
    }
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapM,
        children: <Widget>[
          _ZoomControl(zoom: zoom),
          _Jumper(
            label: label,
            onBack: onBack,
            onForward: onForward,
            onPick: onPick,
          ),
          ?headline,
          if (codes.isNotEmpty) RateWarning(codes),
        ],
      ),
    );
  }
}

/// Everything below the header once an answer is there.
class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.load,
    required this.zoom,
    required this.day,
    required this.whatIfKey,
  });

  final SimLoad load;
  final Zoom zoom;
  final String day;
  final String whatIfKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final sim = load.sim;
    final period = sim.periodOf(day);
    if (period == null) return Note(t.simNoRecords);
    final selected = sim.periods.indexOf(period);
    final first = sim.firstRecord;
    final parts = whatIfKey.split('|');
    final detailKey = <String>[
      period.from,
      period.to,
      parts[2],
      ...parts.sublist(3),
    ].join('|');
    final lines = periodLines(
      context,
      sim,
      period,
      noTotal: rateInfoOf(sim, period).noTotal,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gapL,
      children: <Widget>[
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gapM,
            children: <Widget>[
              SimChart(
                sim: sim,
                selected: selected,
                zoom: zoom,
                onSelect: (i) => ref
                    .read(simViewProvider.notifier)
                    .go(parseDay(sim.periods[i].from)),
              ),
              if (first != null && day.compareTo(first) < 0)
                Text(
                  t.simFirstRecordEdge(shortDay(context, first)),
                  style: TextStyle(color: c.muted),
                ),
            ],
          ),
        ),
        if (lines.isNotEmpty)
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: gapM,
              children: lines,
            ),
          ),
        WalletsCard(period: period, mainCurrency: sim.currency),
        // Entries need the network: the offline copy holds totals only
        if (!load.offline)
          _Entries(detailKey: detailKey, mainCurrency: sim.currency)
        else
          Text(t.simEntriesOffline, style: TextStyle(color: c.muted)),
      ],
    );
  }
}

/// The entries of the selected period, read on their own (every entry of one period, at most a year).
class _Entries extends ConsumerStatefulWidget {
  const _Entries({required this.detailKey, required this.mainCurrency});

  final String detailKey;
  final String mainCurrency;

  @override
  ConsumerState<_Entries> createState() => _EntriesState();
}

class _EntriesState extends ConsumerState<_Entries> {
  // -- STATES -- //

  /// The last entries shown, kept while the next period or what-if loads, so the list never flashes back to a skeleton.
  SimLoad? _last;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final value = ref.watch(simDetailProvider(widget.detailKey));
    final loaded = value.value;
    if (loaded != null) _last = loaded;
    final shown = loaded ?? _last;
    Widget list(SimLoad d) {
      final entries = d.sim.entries;
      if (entries.isEmpty) return Note(t.simNoEntries);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapM,
        children: <Widget>[
          for (final e in entries)
            EntryRow(e, mainCurrency: widget.mainCurrency),
          if (d.sim.entriesOmitted > 0)
            Text(
              t.simEntriesMore(d.sim.entriesOmitted),
              style: TextStyle(color: context.colors.muted),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gapM,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: gapS),
          child: Text(
            t.simEntriesTitle,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: context.colors.muted),
          ),
        ),
        if (shown != null && !(value.hasError && !value.isLoading))
          list(shown)
        else
          AsyncBody<SimLoad>(
            value: value,
            onRetry: () => ref.invalidate(simDetailProvider(widget.detailKey)),
            skeleton: const SkeletonRows(count: 3),
            data: list,
          ),
      ],
    );
  }
}

/// Day, week, month or year as one row of four equal segments. A label that does not fit shrinks, so nothing ever wraps below the row.
class _ZoomControl extends ConsumerWidget {
  const _ZoomControl({required this.zoom});

  final Zoom zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final names = <Zoom, String>{
      Zoom.day: t.simZoomDay,
      Zoom.week: t.simZoomWeek,
      Zoom.month: t.simZoomMonth,
      Zoom.year: t.simZoomYear,
    };
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<Zoom>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: gapS),
          ),
        ),
        segments: <ButtonSegment<Zoom>>[
          for (final z in Zoom.values)
            ButtonSegment<Zoom>(
              value: z,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(names[z] ?? '', maxLines: 1),
              ),
            ),
        ],
        selected: <Zoom>{zoom},
        onSelectionChanged: (s) =>
            ref.read(simViewProvider.notifier).setZoom(s.first),
      ),
    );
  }
}

/// Back, the period (tap to pick a date) and forward: the two arrows are the same size on either side of the date.
class _Jumper extends StatelessWidget {
  const _Jumper({
    required this.label,
    required this.onBack,
    required this.onForward,
    required this.onPick,
  });

  final String label;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: t.simEarlier,
          icon: const Icon(Icons.chevron_left),
          onPressed: onBack,
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: '${t.simPickDate}: $label',
            onTap: onPick,
            child: ExcludeSemantics(
              child: TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: t.simLater,
          icon: const Icon(Icons.chevron_right),
          onPressed: onForward,
        ),
      ],
    );
  }
}

/// The shape of the loaded page: a chart, a totals card and two rows.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const SkeletonGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: gapL,
      children: <Widget>[
        Skeleton(height: 140, radius: 20),
        Skeleton(height: 120, radius: 20),
        SkeletonRows(count: 2),
      ],
    ),
  );
}
