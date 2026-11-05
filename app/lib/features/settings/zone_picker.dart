// PICK A TIME ZONE: A SEARCHABLE LIST OF CITIES AND ZONES WITH THEIR OFFSET RIGHT NOW. THE SAME SHAPE AS THE CURRENCY LIST.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/clock.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// Opens the list and returns the zone chosen, or null when it was closed.
Future<String?> pickZone(BuildContext context, {required String current}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colors.paper,
      builder: (sheet) => ZoneSheet(current: current),
    );

/// "Asia/Manila" as "Manila · Asia", the way a person looks for it.
String zoneTitle(String zone) {
  final i = zone.lastIndexOf('/');
  if (i < 0) return zone;
  return '${zone.substring(i + 1).replaceAll('_', ' ')} · ${zone.substring(0, i).replaceAll('_', ' ')}';
}

// -- TYPES -- //

class ZoneSheet extends StatefulWidget {
  const ZoneSheet({required this.current, super.key});

  final String current;

  @override
  State<ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<ZoneSheet> {
  // -- STATES -- //

  String _query = '';
  late final List<String> _all = zoneNames();

  // -- FUNCTIONS -- //

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final needle = _query.trim().toLowerCase().replaceAll(' ', '_');
    final shown = <String>[
      for (final z in _all)
        if (needle.isEmpty || z.toLowerCase().contains(needle)) z,
    ];
    final now = DateTime.now();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    hintText: t.settingsTimeZoneSearch,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Note(t.settingsTimeZoneNone)
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final z = shown[i];
                          final selected = z == widget.current;
                          return ListTile(
                            minTileHeight: 56,
                            selected: selected,
                            title: Text(zoneTitle(z)),
                            subtitle: Text(z, style: TextStyle(color: c.muted)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  zoneOffsetLabel(z, now),
                                  style: TextStyle(
                                    color: c.muted,
                                    fontFeatures: tabular,
                                  ),
                                ),
                                if (selected) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Icon(Icons.check, color: c.accent),
                                ],
                              ],
                            ),
                            onTap: () => Navigator.of(context).pop(z),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
