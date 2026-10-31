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
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
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

  /// The last entries shown, for the same period and group, kept while a what-if reloads them.
  ({String ident, SimEntries data})? _lastRows;

  final ScrollController _scroll = ScrollController();

  // -- FUNCTIONS -- //

  DateTime get _today => manilaTodayPicker();

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
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
    // A new period, zoom or what-if starts the entries from the top and from every group
    ref.listen<SimView>(simViewProvider, (_, _) {
      ref.read(simGroupProvider.notifier).pick(null);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    ref.listen<WhatIf>(appliedWhatIfProvider, (_, _) {
      ref.read(simGroupProvider.notifier).pick(null);
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
    // The entries are read a page at a time. The unfiltered list also carries the breakdown, so choosing a group never redraws it
    final groupKey = ref.watch(simGroupProvider);
    final canList = shown != null && period != null && !shown.offline;
    String? allKey;
    String? listKey;
    if (canList) {
      final scenario = key.split('|').sublist(3).join('|');
      String detailKey(String group) =>
          '${period.from}|${period.to}|${key.split('|')[2]}|${Uri.encodeComponent(group)}|$scenario';
      allKey = detailKey('');
      listKey = detailKey(groupKey ?? '');
    }
    // Promotable copies for the closures below
    final lk = listKey;
    final allValue = allKey == null
        ? null
        : ref.watch(simEntriesProvider(allKey));
    final listValue = listKey == null
        ? null
        : (listKey == allKey
              ? allValue
              : ref.watch(simEntriesProvider(listKey)));
    // The same period and group keep their rows while a what-if reloads them; a new period starts from a skeleton
    final ident = period == null
        ? ''
        : '${period.from}|${period.to}|${view.zoom.name}|${groupKey ?? ''}';
    final fresh = listValue?.value;
    if (fresh != null) _lastRows = (ident: ident, data: fresh);
    final lastRows = _lastRows;
    // The rows of the same period and group stay only while the new answer is on its way; a failed reload shows its error
    final rows =
        fresh ??
        (lastRows?.ident == ident && (listValue?.isLoading ?? false)
            ? lastRows?.data
            : null);
    final breakdown = _breakdownCard(
      allValue,
      period,
      shown?.sim.currency ?? '',
      groupKey,
      allKey,
    );
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
          // One scroll view for everything: the cards are slivers of one box, the entries a lazy list under them, so only the rows on
          // screen are ever built, however many entries there are
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(gapXL, gapL, gapXL, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: gapL,
                      children: <Widget>[
                        if (!introSeen) const _Intro(),
                        _HeaderCard(
                          zoom: view.zoom,
                          label: period == null
                              ? shortDay(context, day)
                              : periodWords(context, period, view.zoom),
                          onBack: () =>
                              _go(stepAnchor(view.zoom, view.anchor, -1)),
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
                            breakdown: breakdown,
                          ),
                          if (shown.offline)
                            Text(
                              t.simEntriesOffline,
                              style: TextStyle(color: context.colors.muted),
                            )
                          else if (lk != null)
                            _EntriesHeader(
                              groupName: _groupName(allValue, groupKey),
                              value: listValue,
                              rows: rows,
                              onClear: () => ref
                                  .read(simGroupProvider.notifier)
                                  .pick(null),
                              onRetry: () =>
                                  ref.invalidate(simEntriesProvider(lk)),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (rows != null &&
                    lk != null &&
                    shown != null &&
                    !shown.offline)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(gapXL, gapM, gapXL, 0),
                    sliver: SliverList.builder(
                      itemCount: rows.rows.length + 1,
                      itemBuilder: (context, i) {
                        if (i == rows.rows.length) {
                          return _EntriesFooter(
                            data: rows,
                            onRetry: () => ref
                                .read(simEntriesProvider(lk).notifier)
                                .loadMore(),
                          );
                        }
                        // Near the end of what is loaded: ask for the next page (it ignores a repeat while one is on its way, and a
                        // page that failed is only asked again by the retry button, never in a loop)
                        if (i >= rows.rows.length - 10 &&
                            rows.hasMore &&
                            rows.pageError == null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              ref
                                  .read(simEntriesProvider(lk).notifier)
                                  .loadMore();
                            }
                          });
                        }
                        return Padding(
                          key: ValueKey<String>(rows.rows[i].id),
                          padding: const EdgeInsets.only(bottom: gapM),
                          child: EntryRow(
                            rows.rows[i],
                            mainCurrency: shown.sim.currency,
                          ),
                        );
                      },
                    ),
                  ),
                // Room under the last row for the floating button
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: 96 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Where the spending went, as a card; a skeleton while it loads and a retry line if it failed. Null when there is nothing to show.
  Widget? _breakdownCard(
    AsyncValue<SimEntries>? all,
    SimPeriod? period,
    String currency,
    String? groupKey,
    String? allKey,
  ) {
    final p = period;
    if (all == null || p == null || allKey == null) return null;
    final data = all.value;
    if (data == null) {
      if (all.hasError) {
        return PaperCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  errorWords(all.error ?? '', context),
                  style: TextStyle(color: context.colors.muted),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(simEntriesProvider(allKey)),
                child: Text(context.t.retry),
              ),
            ],
          ),
        );
      }
      return const SkeletonGroup(child: Skeleton(height: 140, radius: 20));
    }
    final b = data.sim.breakdown;
    if (b == null) return null;
    final g = spendGroupsFor(b, p.part);
    if (g.groups.isEmpty && g.moreGroups == 0) return null;
    // A group that is no longer listed (the what-if or the period changed under it) clears itself
    if (groupKey != null && !g.groups.any((x) => x.key == groupKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(simGroupProvider.notifier).pick(null);
        say(context, context.t.simGroupGone);
      });
    }
    return BreakdownCard(
      key: ValueKey<String>('${p.from}|${p.to}'),
      groups: g.groups,
      moreAmount: g.moreAmount,
      moreGroups: g.moreGroups,
      mainCurrency: currency,
      selected: groupKey,
      estimate: p.part == SimPart.mixed,
      billMarks: data.sim.billMarks,
      onPick: (k) => ref.read(simGroupProvider.notifier).pick(k),
    );
  }

  /// The name of the group the entries are limited to, from the breakdown.
  String? _groupName(AsyncValue<SimEntries>? all, String? groupKey) {
    final b = all?.value?.sim.breakdown;
    if (groupKey == null || b == null) return null;
    for (final g in <SpendGroup>[...b.recorded.groups, ...b.simulated.groups]) {
      if (g.key == groupKey) {
        return g.kind == 'other' || g.label.isEmpty
            ? context.t.simGroupOther
            : g.label;
      }
    }
    return context.t.simGroupOther;
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

/// Everything below the header once an answer is there: the chart, what was spent, where it went and the accounts.
class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.load,
    required this.zoom,
    required this.day,
    required this.breakdown,
  });

  final SimLoad load;
  final Zoom zoom;
  final String day;

  /// Where the spending went, when there is something to show or it is on its way.
  final Widget? breakdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final sim = load.sim;
    final period = sim.periodOf(day);
    if (period == null) return Note(t.simNoRecords);
    final selected = sim.periods.indexOf(period);
    final first = sim.firstRecord;
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
        SpendCard(sim: sim, period: period),
        SpanCard(period: period),
        ?breakdown,
        WalletsCard(period: period, mainCurrency: sim.currency),
      ],
    );
  }
}

/// The title of the entries, the group they are limited to (with a way back to all of them), and their first states: a skeleton while the
/// first page loads, a retry if it failed, and a line when there are none.
class _EntriesHeader extends StatelessWidget {
  const _EntriesHeader({
    required this.groupName,
    required this.value,
    required this.rows,
    required this.onClear,
    required this.onRetry,
  });

  final String? groupName;
  final AsyncValue<SimEntries>? value;
  final SimEntries? rows;
  final VoidCallback onClear;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final v = value;
    final data = rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gapM,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: gapS),
          child: Text(
            t.simEntriesTitle,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: c.muted),
          ),
        ),
        if (groupName != null)
          Row(
            children: <Widget>[
              const SizedBox(width: gapS),
              Icon(Icons.filter_alt_outlined, size: 18, color: c.info),
              const SizedBox(width: gapM),
              Expanded(
                child: Text(
                  t.simShowingGroup(groupName ?? ''),
                  style: TextStyle(color: c.info),
                ),
              ),
              TextButton(onPressed: onClear, child: Text(t.simShowAll)),
            ],
          ),
        if (data == null && v != null && v.hasError && !v.isLoading)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  errorWords(v.error ?? '', context),
                  style: TextStyle(color: c.muted),
                ),
              ),
              TextButton(onPressed: onRetry, child: Text(t.retry)),
            ],
          )
        else if (data == null)
          const SkeletonRows(count: 3)
        else if (data.rows.isEmpty)
          Note(t.simNoEntries),
      ],
    );
  }
}

/// The end of the entries: how many are shown of how many, a quiet pulse while the next page loads, or a retry if it failed.
class _EntriesFooter extends StatelessWidget {
  const _EntriesFooter({required this.data, required this.onRetry});

  final SimEntries data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    if (data.pageError != null) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(t.simPageFailed, style: TextStyle(color: c.muted)),
          ),
          TextButton(onPressed: onRetry, child: Text(t.retry)),
        ],
      );
    }
    if (data.loadingMore) {
      return const SkeletonGroup(child: Skeleton(height: 56, radius: 14));
    }
    if (data.total <= simPageSize) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: gapM, horizontal: gapS),
      child: Text(
        t.simShownOf(data.rows.length, data.total),
        textAlign: TextAlign.center,
        style: TextStyle(color: c.muted, fontFeatures: tabular),
      ),
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
