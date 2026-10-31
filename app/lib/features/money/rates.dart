// EXCHANGE RATES ON THE PHONE: THE DATE THEY ARE FROM, AND THE "UPDATE RATES" ACTION USED BY THE ACCOUNTS SCREEN AND SETTINGS.
// The rates themselves live on the server (fetched from one fixed source). The phone only asks for the total and for a refresh, and says
// plainly when the rates are old, missing, or could not be updated: the total is then the last one that worked, never a guess.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// A moment from the server as a short date in the app's language ("Oct 23"). Text that is not a date is empty.
String ratesDate(BuildContext context, String? iso) {
  final at = dateOf(iso);
  if (at == null) return '';
  return DateFormat.MMMd(Localizations.localeOf(context).toString())
      .format(manilaWall(at));
}

/// How old the rates are, in whole days, or null when there are none.
int? ratesAgeDays(String? iso) {
  final d = dateOf(iso);
  return d == null ? null : calendarDaysBetween(manilaWall(d), manilaNow());
}

/// The guard and key of the rates refresh.
final Once _refreshOnce = Once();

/// Rates older than this many days are said to be old out loud.
const int staleDays = 3;

/// Asks the server for fresh rates and says how it went. Does nothing with the screen after it was closed. Offline, it says so.
Future<void> refreshRates(BuildContext context, WidgetRef ref) async {
  final t = context.t;
  try {
    // One refresh at a time: a second tap while it runs does nothing
    final raw = await _refreshOnce.run(
      (key) => ref
          .read(apiProvider)
          .verb('fx_rates_refresh', const <String, Object?>{}, key),
      intent: 'refresh',
    );
    if (raw == null) return;
    final answer = asJson(raw);
    final status = str(asJson(answer['outcome'])['status']);
    final reason = str(asJson(answer['outcome'])['reason']);
    if (context.mounted) {
      say(
        context,
        status == 'refreshed'
            ? t.accountsRatesUpdated
            : status == 'skipped' && reason == 'recent'
            ? t.accountsRatesTooSoon
            : t.accountsRatesFailed,
      );
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      say(
        context,
        e.isNetwork ? t.accountsRatesOffline : errorWords(e, context),
      );
    }
  }
  ref
    ..invalidate(assetsProvider)
    ..invalidate(syncProvider);
}
