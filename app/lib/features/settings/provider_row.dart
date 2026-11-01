// THE AI SERVER ROW IN SETTINGS: WHICH SERVER ANSWERS THE ASSISTANT (DEEPSEEK TODAY). THE LIST COMES FROM THE SERVER, SO A NEW SERVER NEEDS ONLY A NAME HERE.
// The choice is saved on the server first, like the other shared settings. Nothing here holds a key: the server says which servers are set up.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

/// The names shown for the servers the app knows. A server it does not know is shown by its id. There is one host, so the person sees a plain
/// "AI service" and not its brand.
const Map<String, String> providerNames = <String, String>{
  'deepseek': 'AI service',
};

// -- FUNCTIONS -- //

String providerLabel(String id) => providerNames[id] ?? id;

// -- WIDGETS -- //

class ProviderRow extends StatelessWidget {
  const ProviderRow({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  final Settings settings;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final available = settings.availableProviders;
    // An old server or a first start has no list: the row stays out of the way
    if (available.isEmpty) return const SizedBox.shrink();
    final effective = settings.modelProvider;
    final choice = settings.modelProviderChoice;
    // What the server says will run is always in its own list; a stale phone copy that is not shows nothing selected
    final value = effective != null && available.contains(effective)
        ? effective
        : null;
    final lost = choice != null && !available.contains(choice);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (available.length == 1)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              title: Text(t.settingsAiServer),
              subtitle: Text(
                providerLabel(available.first),
                style: TextStyle(color: c.muted),
              ),
            )
          else
            // The field's own label is the semantic label, like the dropdowns beside it
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.settingsAiServer),
              hint: Text(t.settingsAiServerDefault),
              items: <DropdownMenuItem<String>>[
                for (final id in available)
                  DropdownMenuItem<String>(
                    value: id,
                    child: Text(providerLabel(id)),
                  ),
              ],
              onChanged: (id) => id == null ? null : onChanged(id),
            ),
          const SizedBox(height: 6),
          Text(
            lost
                ? t.settingsAiServerUnavailable(providerLabel(choice))
                : t.settingsAiServerHelp,
            style: TextStyle(color: c.muted),
          ),
        ],
      ),
    );
  }
}
