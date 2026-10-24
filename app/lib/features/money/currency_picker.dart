// PICK A CURRENCY: A SEARCHABLE LIST OF EVERY CURRENCY, WITH THE ONES ALREADY IN USE FIRST, AND THE SMALL BUTTON THAT OPENS IT.
// Used for the main currency in Settings, the currency of an account or a bill, and "add a currency" on an account.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/money.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// Opens the list and returns the code chosen, or null when it was closed. [first] are shown before the rest (the currencies already in use),
/// and [hide] are left out (a currency the account already has).
Future<String?> pickCurrency(
  BuildContext context, {
  required String current,
  Set<String> first = const <String>{},
  Set<String> hide = const <String>{},
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.colors.paper,
  builder: (sheet) => CurrencySheet(current: current, first: first, hide: hide),
);

// -- TYPES -- //

/// The button that shows a currency and opens the list. At least 48 dp high, and it says what it is for.
class CurrencyButton extends StatelessWidget {
  const CurrencyButton({
    required this.code,
    required this.onPressed,
    this.label,
    super.key,
  });

  final String code;
  final VoidCallback? onPressed;

  /// What the currency is for ("Currency of this bill"). Spoken with the code.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = currencyOf(code);
    return Semantics(
      button: true,
      label: '${label ?? context.t.accountsCurrencyLabel}, ${c.code} ${c.name}',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(c.code, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text(
              c.symbol.trim(),
              style: TextStyle(color: context.colors.muted),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// The list inside the sheet: a search field and every currency with its symbol and an example amount.
class CurrencySheet extends StatefulWidget {
  const CurrencySheet({
    required this.current,
    this.first = const <String>{},
    this.hide = const <String>{},
    super.key,
  });

  final String current;
  final Set<String> first;
  final Set<String> hide;

  @override
  State<CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<CurrencySheet> {
  // -- STATES -- //

  String _query = '';

  // -- FUNCTIONS -- //

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final needle = _query.trim().toLowerCase();
    final all = currencies
        .where((x) => !widget.hide.contains(x.code))
        .where(
          (x) =>
              needle.isEmpty ||
              x.code.toLowerCase().contains(needle) ||
              x.name.toLowerCase().contains(needle),
        );
    // The currencies already in use come first, then the rest in the order of the catalogue
    final shown = <Currency>[
      ...all.where((x) => widget.first.contains(x.code)),
      ...all.where((x) => !widget.first.contains(x.code)),
    ];
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
                    hintText: t.settingsCurrencySearch,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Note(t.settingsCurrencyNone)
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final x = shown[i];
                          final selected = x.code == widget.current;
                          return ListTile(
                            minTileHeight: 56,
                            selected: selected,
                            leading: SizedBox(
                              width: 48,
                              child: Text(
                                x.code,
                                style: TextStyle(
                                  color: c.accentText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(x.name),
                            subtitle: Text(
                              t.settingsCurrencyExample(
                                formatMoney(123456, x.code),
                              ),
                              style: TextStyle(
                                color: c.muted,
                                fontFeatures: tabular,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check, color: c.accent)
                                : null,
                            onTap: () => Navigator.of(context).pop(x.code),
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
