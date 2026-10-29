// TIME TRAVEL: JUMP TO ANY DAY, WEEK, MONTH OR YEAR UP TO 5 YEARS BACK OR AHEAD AND SEE WHAT EVERY ACCOUNT HELD OR WILL HOLD (BTL-20261029-0117).
// Siblings: the calendar (chips, a Today button in the app bar, the offline band, one floating primary action) and the agenda (the date
// picker). The band at the top always says which part of time is shown; recorded numbers are solid and filled, replayed and simulated ones
// are dashed, outlined and tagged. Back and forward move the selected period; the chart and the quick jumps move it too. The one primary
// action is What if. The previous answer stays on screen while the next one loads, so a what-if edit never flashes the page.

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
  /// only for the same zoom (a year period never reads as a month), and the band counts the what-if of what is on screen.
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
    final startsOn = ref.watch(settingsProvider).weekStartsOn;
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
    final period = shown?.sim.periodOf(day);
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
          ModeBand(
            part: part,
            changes: shownChanges,
            savedAt: shown?.savedAt,
            onReset: () => ref.read(whatIfProvider.notifier).reset(),
            onRetry: () => ref.invalidate(overview),
          ),
          // Something newer is on its way: the zoom, the dates or the what-if (still being typed) differ from what is shown
          if ((value.isLoading || edited.changes != shownChanges) &&
              shown != null)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: pagePadding(context).copyWith(bottom: 96),
              children: <Widget>[
                _ZoomChips(zoom: view.zoom),
                _Jumper(
                  label: period == null
                      ? shortDay(context, day)
                      : periodWords(context, period, view.zoom),
                  onBack: () => _go(stepAnchor(view.zoom, view.anchor, -1)),
                  onForward: () => _go(stepAnchor(view.zoom, view.anchor, 1)),
                  onPick: () => _pick(view.anchor),
                ),
                _QuickJumps(onJump: (m) => _go(jumpMonths(view.anchor, m))),
                const SizedBox(height: 8),
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
          ),
        ],
      ),
    );
  }
}

/// Everything below the jumper once an answer is there.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PaperCard(
          child: SimChart(
            sim: sim,
            selected: selected,
            zoom: zoom,
            onSelect: (i) => ref
                .read(simViewProvider.notifier)
                .go(parseDay(sim.periods[i].from)),
          ),
        ),
        if (first != null && day.compareTo(first) < 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t.simFirstRecordEdge(shortDay(context, first)),
              style: TextStyle(color: c.muted),
            ),
          ),
        const SizedBox(height: 12),
        PeriodCard(sim: sim, period: period, zoom: zoom),
        const SizedBox(height: 12),
        WalletsCard(period: period),
        const SizedBox(height: 12),
        // Entries need the network: the offline copy holds totals only
        if (!load.offline) _Entries(detailKey: detailKey),
      ],
    );
  }
}

/// The entries of the selected period, read on their own (every entry of one period, at most a year).
class _Entries extends ConsumerStatefulWidget {
  const _Entries({required this.detailKey});

  final String detailKey;

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
        children: <Widget>[
          for (final e in entries) EntryRow(e),
          if (d.sim.entriesOmitted > 0)
            Text(
              t.simEntriesMore(d.sim.entriesOmitted),
              style: TextStyle(color: context.colors.muted),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(t.simEntriesTitle),
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

class _ZoomChips extends ConsumerWidget {
  const _ZoomChips({required this.zoom});

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
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final z in Zoom.values)
          ChoiceChip(
            label: Text(names[z] ?? ''),
            selected: z == zoom,
            onSelected: (_) => ref.read(simViewProvider.notifier).setZoom(z),
          ),
      ],
    );
  }
}

/// Back, the period (tap to pick a date) and forward.
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
              child: TextButton(
                onPressed: onPick,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
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

class _QuickJumps extends StatelessWidget {
  const _QuickJumps({required this.onJump});

  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final jumps = <(String, int)>[
      (t.simBack1y, -12),
      (t.simBack1m, -1),
      (t.simAhead1m, 1),
      (t.simAhead1y, 12),
      (t.simAhead5y, 60),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (final (label, months) in jumps)
          ActionChip(label: Text(label), onPressed: () => onJump(months)),
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
      children: <Widget>[
        Skeleton(height: 140, radius: 20),
        SizedBox(height: 12),
        Skeleton(height: 120, radius: 20),
        SizedBox(height: 12),
        SkeletonRows(count: 2),
      ],
    ),
  );
}
