// THE DATE AND TIME SECTION OF SETTINGS: THE TIME ZONE, THE 12 OR 24 HOUR CLOCK, THE ORDER OF A DATE AND THE FIRST DAY OF THE WEEK.
// The choices are kept on the server first, like the other shared settings, because the server decides what "today" is and writes the times in its
// own messages. A "Now" line under the title shows the result at once, made by the same formatter every screen uses.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/clock.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'zone_picker.dart';

// -- TYPES -- //

/// Saves one change of the shared choices (the screen's own save, which says so when it cannot).
typedef SaveTimeChoice = Future<void> Function({
  String? timeZone,
  String? timeFormat,
  String? dateStyle,
  int? weekStartsOn,
});

class DateTimeRows extends StatelessWidget {
  const DateTimeRows({required this.settings, required this.onSave, super.key});

  final Settings settings;
  final SaveTimeChoice onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final s = settings;
    // The preview is made from what is saved, so it is the proof that every screen will read the same
    final now = zoneNow();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(t.settingsTimeTitle),
        Text(
          t.settingsTimeNow(fmtDateTime(now, DateKind.monthDayWeekday)),
          style: TextStyle(color: c.muted, fontFeatures: tabular),
        ),
        const SizedBox(height: 8),
        PaperCard(
          onTap: () async {
            final z = await pickZone(context, current: activeZone);
            if (z != null && z != s.timeZone) await onSave(timeZone: z);
          },
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(t.settingsTimeZone, style: TextStyle(color: c.muted)),
                    Text(
                      zoneTitle(activeZone),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Text(
                zoneOffsetLabel(activeZone),
                style: TextStyle(color: c.muted, fontFeatures: tabular),
              ),
              Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(t.settingsTimeZoneHelp, style: TextStyle(color: c.muted)),
        const SizedBox(height: 12),
        Text(t.settingsClockTitle, style: TextStyle(color: c.muted)),
        const SizedBox(height: 6),
        Semantics(
          label: t.settingsClockTitle,
          child: SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'auto',
                label: Text(t.settingsClockAuto),
              ),
              ButtonSegment<String>(
                value: '12',
                label: Text(t.settingsClock12),
              ),
              ButtonSegment<String>(
                value: '24',
                label: Text(t.settingsClock24),
              ),
            ],
            selected: <String>{s.timeFormat},
            onSelectionChanged: (v) => onSave(timeFormat: v.first),
          ),
        ),
        const SizedBox(height: 12),
        Text(t.settingsDateOrderTitle, style: TextStyle(color: c.muted)),
        const SizedBox(height: 6),
        Semantics(
          label: t.settingsDateOrderTitle,
          child: SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'dmy',
                label: Text(t.settingsDateOrderDmy),
              ),
              ButtonSegment<String>(
                value: 'mdy',
                label: Text(t.settingsDateOrderMdy),
              ),
              ButtonSegment<String>(
                value: 'ymd',
                label: Text(t.settingsDateOrderYmd),
              ),
            ],
            // A stored auto is day, month, year
            selected: <String>{s.dateStyle == 'auto' ? 'dmy' : s.dateStyle},
            onSelectionChanged: (v) => onSave(dateStyle: v.first),
          ),
        ),
        const SizedBox(height: 12),
        Text(t.settingsWeekStarts, style: TextStyle(color: c.muted)),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: <ButtonSegment<int>>[
            ButtonSegment<int>(value: 1, label: Text(t.settingsMonday)),
            ButtonSegment<int>(value: 0, label: Text(t.settingsSunday)),
          ],
          selected: <int>{s.weekStartsOn},
          onSelectionChanged: (w) => onSave(weekStartsOn: w.first),
        ),
      ],
    );
  }
}
