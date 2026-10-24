// THE EXCHANGE RATES ROW IN SETTINGS: WHEN THE RATES WERE FETCHED AND FROM WHERE, AND A TAP TO UPDATE THEM.
// The rates come from the server (one fixed source) and are the same for everyone; this row only shows their date and asks for a refresh.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../money/rates.dart';

// -- FUNCTIONS -- //

class RatesRow extends ConsumerWidget {
  const RatesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.t;
    final rates = asJson(ref.watch(assetsProvider).value?['rates']);
    final asOf = rates['asOf'] is String ? str(rates['asOf']) : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Icon(Icons.currency_exchange, color: c.accentText),
      title: Text(t.settingsRatesTitle),
      subtitle: Text(
        asOf == null
            ? '${t.settingsRatesNone} · ${t.settingsRatesTap}'
            : '${t.settingsRatesLine(ratesDate(context, asOf), str(rates['source'], '-'))} · ${t.settingsRatesTap}',
        style: TextStyle(color: c.muted),
      ),
      onTap: () => unawaited(refreshRates(context, ref)),
    );
  }
}
